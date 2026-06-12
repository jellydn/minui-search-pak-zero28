#!/bin/bash
set -euo pipefail

PAK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PAK_DIR"

errors=0
shellcheck_warnings=0

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

echo "=== Check 3: zero28 platform support ==="
if grep -q '"zero28"' config.json; then
  echo "OK: zero28 in config.json"
else
  echo "FAIL: zero28 missing from config.json"
  errors=$((errors + 1))
fi
if [ -f pak.json ] && grep -q '"zero28"' pak.json; then
  echo "OK: zero28 in pak.json"
fi
if [ -d bin/zero28 ]; then
  echo "OK: bin/zero28 directory exists"
fi

echo "=== Check 4: Config settings ==="
if grep -q '"favorites_label"' config.json; then
  echo "OK: favorites_label in config.json"
fi

echo "=== Check 5: Favorites variables ==="
for var in COLLECTIONS_PATH FAVORITES_LABEL FAVORITES_PATH; do
  if grep -q "${var}=" launch.sh; then
    echo "OK: $var defined"
  else
    echo "FAIL: $var not defined"
    errors=$((errors + 1))
  fi
done

echo "=== Check 6: Action flow ==="
if grep -q "show_game_actions" launch.sh; then
  echo "OK: show_game_actions called from main loop"
fi
if grep -q "Remove from Favorites" launch.sh; then
  echo "OK: Remove from Favorites action available"
fi

echo "=== Check 7: Search pipeline ==="
if grep -q "filter_game_files" launch.sh; then
  echo "OK: search pipeline uses filter_game_files"
fi
if grep -q "sort -f" launch.sh; then
  echo "OK: results sorted"
fi

echo "=== Check 8: wc -l usage ==="
wc_anti=$(grep -c 'cat.*|.*wc -l' launch.sh || true)
if [ "$wc_anti" -eq 0 ]; then
  echo "OK: no cat | wc -l anti-patterns"
fi

echo "=== Check 9: Glob escaping ==="
if grep -q "^escape_glob()" launch.sh; then
  echo "OK: escape_glob function defined"
fi

echo "=== Check 10: Stay-awake lifecycle ==="
rm_total=$(grep -c 'rm -f /tmp/stay_awake' launch.sh || true)
echo_now=$(grep -c 'echo "1" >/tmp/stay_awake' launch.sh || true)
if [ "$rm_total" -eq 2 ] && [ "$echo_now" -eq 2 ]; then
  echo "OK: stay_awake lifecycle correct ($rm_total rm, $echo_now echo)"
else
  echo "FAIL: stay_awake ($rm_total rm, $echo_now echo)"
  errors=$((errors + 1))
fi

echo ""
echo "METRIC shellcheck_warnings=$shellcheck_warnings"
echo "METRIC coverage_gaps=$errors"
if [ "$errors" -gt 0 ]; then
  echo "FAILED: $errors issues found"
  exit 1
fi
echo "PASSED: All checks passed"
exit 0
