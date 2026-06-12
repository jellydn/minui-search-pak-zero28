#!/bin/bash
set -euo pipefail

# measure.sh — verifies search-pak feature integrity

PAK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PAK_DIR"

errors=0
shellcheck_warnings=0
noise_gaps=0

# Check shellcheck
echo "=== Check 1: Shellcheck ==="
if command -v shellcheck >/dev/null 2>&1; then
  count=$(shellcheck --severity=warning launch.sh 2>/dev/null | grep -c "^In " || true)
  shellcheck_warnings=$count
  echo "Shellcheck warnings: $shellcheck_warnings"
  if [ "$shellcheck_warnings" -gt 0 ]; then
    errors=$((errors + shellcheck_warnings))
  fi
else
  echo "shellcheck not found, skipping"
fi

# Check that required functions exist
echo "=== Check 2: Required functions ==="
required_funcs="load_settings show_confirm is_favorited add_to_favorites remove_from_favorites delete_game show_game_actions filter_game_files escape_glob format_results add_game_to_recents get_rom_alias get_emu_folder get_emu_name get_emu_path show_message"
for func in $required_funcs; do
  if grep -q "^${func}()" launch.sh; then
    echo "OK: $func found"
  else
    echo "FAIL: $func not found"
    errors=$((errors + 1))
  fi
done

# Check zero28 in config.json
echo "=== Check 3: zero28 platform support ==="
if grep -q '"zero28"' config.json; then
  echo "OK: zero28 in config.json"
else
  echo "FAIL: zero28 missing from config.json"
  errors=$((errors + 1))
fi

if [ -f pak.json ]; then
  if grep -q '"zero28"' pak.json; then
    echo "OK: zero28 in pak.json"
  else
    echo "FAIL: zero28 missing from pak.json"
    errors=$((errors + 1))
  fi
fi

if [ -d bin/zero28 ]; then
  echo "OK: bin/zero28 directory exists"
else
  echo "FAIL: bin/zero28 directory missing"
  errors=$((errors + 1))
fi

# Check favorites_label in config.json
echo "=== Check 4: Config settings ==="
if grep -q '"favorites_label"' config.json; then
  echo "OK: favorites_label in config.json"
else
  echo "FAIL: favorites_label missing from config.json"
  errors=$((errors + 1))
fi

# Check favorites variables
echo "=== Check 5: Favorites variables ==="
for var in COLLECTIONS_PATH RECENTS_PATH FAVORITES_LABEL FAVORITES_PATH; do
  if grep -q "${var}=" launch.sh; then
    echo "OK: $var defined"
  else
    echo "FAIL: $var not defined"
    errors=$((errors + 1))
  fi
done

# Check action flow
echo "=== Check 6: Action flow integration ==="
if grep -q "is_favorited" launch.sh; then
  echo "OK: is_favorited helper used for dynamic menu"
else
  echo "FAIL: is_favorited not used"
  errors=$((errors + 1))
fi
if grep -q "show_game_actions" launch.sh; then
  echo "OK: show_game_actions called from main loop"
else
  echo "FAIL: show_game_actions not called from main loop"
  errors=$((errors + 1))
fi
if grep -q "Remove from Favorites" launch.sh; then
  echo "OK: Remove from Favorites action available in menu"
else
  echo "FAIL: Remove from Favorites action missing"
  errors=$((errors + 1))
fi

# Check search pipeline
echo "=== Check 7: Search pipeline uses filter_game_files + sort ==="
if grep -q "filter_game_files" launch.sh; then
  echo "OK: search pipeline pipes through filter_game_files"
else
  echo "FAIL: filter_game_files not used in search pipeline"
  errors=$((errors + 1))
fi
if grep -q "filter_game_files.*sort -f" launch.sh; then
  echo "OK: find piped through filter_game_files then sorted"
else
  echo "FAIL: find pipeline missing sort after filter_game_files"
  errors=$((errors + 1))
fi

# Check wc -l usage
echo "=== Check 9: Efficient wc -l usage ==="
wc_anti=$(grep -c 'cat.*|.*wc -l' launch.sh || true)
wc_good=$(grep -c 'wc -l <' launch.sh || true)
if [ "$wc_anti" -eq 0 ] && [ "$wc_good" -ge 3 ]; then
  echo "OK: no cat | wc -l anti-patterns, $wc_good wc -l < usages"
else
  echo "FAIL: $wc_anti cat | wc -l anti-patterns remain"
  errors=$((errors + wc_anti))
fi

# Check glob escaping
echo "=== Check 10: Glob metacharacter escaping ==="
if grep -q "^escape_glob()" launch.sh; then
  echo "OK: escape_glob function defined"
else
  echo "FAIL: escape_glob function missing"
  errors=$((errors + 1))
fi
if grep -q "escape_glob.*search_term" launch.sh; then
  echo "OK: search_term escaped via escape_glob before find"
else
  echo "FAIL: search_term not escaped before find"
  errors=$((errors + 1))
fi

# Check format_results function
echo "=== Check 11: Display formatting via format_results() ==="
if grep -q "^format_results()" launch.sh; then
  echo "OK: format_results() function defined"
else
  echo "FAIL: format_results() not found"
  errors=$((errors + 1))
fi

# Check stay_awake lifecycle
echo "=== Check 12: Stay-awake lifecycle ==="
rm_total=$(grep -c 'rm -f /tmp/stay_awake' launch.sh || true)
echo_now=$(grep -c 'echo "1" >/tmp/stay_awake' launch.sh || true)
if [ "$rm_total" -eq 2 ] && [ "$echo_now" -eq 1 ]; then
  echo "OK: stay_awake lifecycle correct ($rm_total rm, $echo_now echo)"
else
  echo "FAIL: stay_awake lifecycle wrong ($rm_total rm, $echo_now echo, expected 2 rm, 1 echo)"
  errors=$((errors + 1))
fi

# Check search term persistence
echo "=== Check 13: Search term persistence ==="
if grep -q 'previous_search_file.*USERDATA_PATH' launch.sh; then
  echo "OK: search term persists in userdata across sessions"
else
  echo "FAIL: search term uses /tmp, lost across sessions"
  errors=$((errors + 1))
fi

# Check preserved results after delete
echo "=== Check 14: Preserved results after delete ==="
if grep -q "grep -Fxv.*search_list_file" launch.sh; then
  echo "OK: remaining results preserved after game delete"
else
  echo "FAIL: deleted game not removed from search list"
  errors=$((errors + 1))
fi
if grep -q "format_results.*results_list_file.*search_list_file" launch.sh; then
  echo "OK: results display regenerated after delete"
else
  echo "FAIL: results not regenerated after delete"
  errors=$((errors + 1))
fi

# Check search scope
echo "=== Check 15: Search scope feature ==="
if grep -q "search_scope_file" launch.sh; then
  echo "OK: search scope persisted in USERDATA_PATH"
else
  echo "FAIL: search scope not persisted"
  errors=$((errors + 1))
fi
if grep -q 'find "\$search_root"' launch.sh || grep -q 'find "\$search_root' launch.sh; then
  echo "OK: find uses scoped search_root"
else
  echo "FAIL: find not using search_root"
  errors=$((errors + 1))
fi
if grep -q "Search (\$scope)" launch.sh || grep -q "Search (\(\$scope\)" launch.sh; then
  echo "OK: scope shown in search keyboard title"
else
  echo "FAIL: scope not in keyboard title"
  errors=$((errors + 1))
fi
if grep -q "CURRENT_SCOPE" launch.sh; then
  echo "OK: CURRENT_SCOPE global variable defined"
else
  echo "FAIL: CURRENT_SCOPE not defined"
  errors=$((errors + 1))
fi
if grep -q "tolower(raw_folder)" launch.sh; then
  echo "OK: redundant folder prefix suppressed when scoped to single system"
else
  echo "FAIL: redundant folder prefix not suppressed"
  errors=$((errors + 1))
fi

# Check favorites browser
echo "=== Check 16: Favorites browser ==="
if grep -q "^format_favorite_line()" launch.sh; then
  echo "OK: format_favorite_line helper defined"
else
  echo "FAIL: format_favorite_line helper missing"
  errors=$((errors + 1))
fi
if grep -q "^browse_favorites()" launch.sh; then
  echo "OK: browse_favorites function defined"
else
  echo "FAIL: browse_favorites function missing"
  errors=$((errors + 1))
fi
if grep -q "Browse.*FAVORITES_LABEL" launch.sh; then
  echo "OK: Browse Favorites option in main menu"
else
  echo "FAIL: Browse Favorites option missing"
  errors=$((errors + 1))
fi

# Check noise-extension coverage
echo "=== Check 8: Noise extension coverage ==="
missing=0
filter_line=$(grep -A1 'filter_game_files()' launch.sh | tail -1)
echo "Filter line: $filter_line"

if echo "$filter_line" | grep -qE 'sav|state|srm|rtc|nv'; then
  echo "OK: save/state extensions covered"
else
  echo "MISSING: save/state extensions"
  missing=$((missing + 1))
fi

if echo "$filter_line" | grep -qE 'cfg|conf'; then
  echo "OK: config extensions covered"
else
  echo "MISSING: config extensions"
  missing=$((missing + 1))
fi

if echo "$filter_line" | grep -qE 'jpe|png|bmp|gif|tif|webp'; then
  echo "OK: media/image extensions covered"
else
  echo "MISSING: media/image extensions"
  missing=$((missing + 1))
fi

if echo "$filter_line" | grep -qE 'xml|dat|txt|log|lst|pdf'; then
  echo "OK: metadata/text extensions covered"
else
  echo "MISSING: metadata/text extensions"
  missing=$((missing + 1))
fi

noise_gaps=$missing
echo "Noise extension gaps: $noise_gaps"

echo ""
echo "METRIC shellcheck_warnings=$shellcheck_warnings"
echo "METRIC search_noise_gaps=$noise_gaps"
echo "METRIC coverage_gaps=$((errors + noise_gaps))"
if [ "$errors" -gt 0 ] || [ "$noise_gaps" -gt 0 ]; then
  echo "FAILED: $errors errors, $noise_gaps noise gaps found"
  exit 1
fi
echo "PASSED: All checks passed"
exit 0
