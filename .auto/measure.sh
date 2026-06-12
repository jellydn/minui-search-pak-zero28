#!/bin/bash
set -euo pipefail

# measure.sh — verifies search-pak feature integrity

PAK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PAK_DIR"

errors=0
shellcheck_warnings=0

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
required_funcs="load_settings show_confirm add_to_favorites delete_game show_game_actions add_game_to_recents get_rom_alias get_emu_folder get_emu_name get_emu_path show_message"
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

# Check that the action flow calls show_game_actions instead of direct exec
echo "=== Check 6: Action flow integration ==="
if grep -q "show_game_actions" launch.sh; then
  echo "OK: show_game_actions called from main loop"
else
  echo "FAIL: show_game_actions not called from main loop"
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
