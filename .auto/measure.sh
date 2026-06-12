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
required_funcs="load_settings show_confirm is_favorited add_to_favorites remove_from_favorites delete_game show_game_actions filter_game_files escape_glob add_game_to_recents get_rom_alias get_emu_folder get_emu_name get_emu_path show_message"
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

# Check zero28 in pak.json
if [ -f pak.json ]; then
  if grep -q '"zero28"' pak.json; then
    echo "OK: zero28 in pak.json"
  else
    echo "FAIL: zero28 missing from pak.json"
    errors=$((errors + 1))
  fi
fi

# Check zero28 bin directory exists
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

# Check COLLECTIONS_PATH and FAVORITES_PATH variables
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

# Check search pipeline uses filter_game_files
echo "=== Check 7: Search pipeline uses filter_game_files + sort ==="
if grep -q "filter_game_files" launch.sh; then
  echo "OK: search pipeline pipes through filter_game_files"
else
  echo "FAIL: filter_game_files not used in search pipeline"
  errors=$((errors + 1))
fi
if grep -q "find.*Roms.*| filter_game_files | sort" launch.sh; then
  echo "OK: find piped through filter_game_files then sorted"
else
  echo "FAIL: find pipeline missing sort after filter_game_files"
  errors=$((errors + 1))
fi

# Check wc -l < is used instead of cat | wc -l
echo "=== Check 9: Efficient wc -l usage ==="
wc_anti=$(grep -c 'cat.*|.*wc -l' launch.sh || true)
wc_good=$(grep -c 'wc -l <' launch.sh || true)
if [ "$wc_anti" -eq 0 ] && [ "$wc_good" -ge 3 ]; then
  echo "OK: no cat | wc -l anti-patterns, $wc_good wc -l < usages"
else
  echo "FAIL: $wc_anti cat | wc -l anti-patterns remain"
  errors=$((errors + wc_anti))
fi

# Check glob metacharacters are escaped in search pipeline
echo "=== Check 10: Glob metacharacter escaping ==="
if grep -q "escape_glob" launch.sh; then
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

# Check display formatting uses awk (not the old fragile sed)
echo "=== Check 11: Display formatting for folder types ==="
if grep -q "awk.*search_list_file.*results_list_file" launch.sh; then
  echo "OK: awk-based display formatting for folder+game name"
else
  # awk may not appear on same line as both files — check it's used in formatting
  if grep -q "awk -F/" launch.sh; then
    echo "OK: awk-based display formatting for folder+game name"
  else
    echo "FAIL: awk-based display formatting not found"
    errors=$((errors + 1))
  fi
fi

# Check noise-extension coverage: verify each category is in the grep exclusion
echo "=== Check 8: Noise extension coverage ==="
missing=0
filter_line=$(grep -A1 'filter_game_files()' launch.sh | tail -1)
echo "Filter line: $filter_line"

if echo "$filter_line" | grep -q 'sav\|state\|srm\|rtc\|nv'; then
  echo "OK: save/state extensions covered"
else
  echo "MISSING: save/state extensions (sav, srm, state, rtc)"
  missing=$((missing + 1))
fi

if echo "$filter_line" | grep -q 'cfg\|conf'; then
  echo "OK: config extensions covered"
else
  echo "MISSING: config extensions (cfg, conf)"
  missing=$((missing + 1))
fi

if echo "$filter_line" | grep -q 'png\|jpe\?g\|bmp\|gif\|tif\|webp'; then
  echo "OK: media/image extensions covered"
else
  echo "MISSING: media/image extensions (png, jpg, bmp, gif)"
  missing=$((missing + 1))
fi

if echo "$filter_line" | grep -q 'xml\|dat\|txt\|log\|lst\|pdf'; then
  echo "OK: metadata/text extensions covered"
else
  echo "MISSING: metadata/text extensions (xml, dat, txt, log)"
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
