
## Completed ✓

### Add Delete Game and Add to Favorites to search-pak
Extended `launch.sh` with:
- `show_confirm()` — Y/N confirmation dialog via minui-presenter (used before deleting)
- `add_to_favorites()` — adds game to `Collections/1) Favorites.txt` with dedup + name sorting (mirrors Favorites pak pattern)
- `delete_game()` — permanently removes a ROM file with confirm, also cleans up from Favorites if present
- `show_game_actions()` — action menu (Launch / Add to Favorites / Delete Game / Cancel) shown on game selection instead of immediate Launch
- `load_settings()` — reads `favorites_label` from `config.json`
- Refactored `add_game_to_recents()` to use global `RECENTS_PATH`
- Fixed all shellcheck warnings (SC3010→case, SC2188→: >, SC2034→use RECENTS_PATH)
- Updated `config.json` with `settings.favorites_label` and `zero28` platform
- Updated `README.md` with new features and zero28 support

### Dynamic Favorites in action menu
- Added `is_favorited()` to check favorite state
- Action menu conditionally shows "Add to Favorites" vs "Remove from Favorites"
- Added `remove_from_favorites()` function

### Sorted results + no cat | wc -l
- `sort -f` in search pipeline for alphabetical results
- All `cat | wc -l` replaced with `wc -l <`

### Deferred / Future ideas
- **Search history**: Persist recent searches so users can pick from past terms
- **Regex search**: Support `-iregex` instead of `-iname` for pattern matching
- **Search within emulator folders**: Allow user to scope search to a specific emu folder
- **Batch delete**: From search results, allow multi-select delete cycle
- **Collections browser**: From search, let user open and browse their Favorites collection
- **Favorites badge in results**: Show a ★ or icon next to already-favorited games in results list
- **Case-insensitive sort locale**: Consider `LC_ALL=C.UTF-8 sort -f` if CJK characters are present

### Display formatting for all folder types
- Replaced fragile sed pipeline with awk that handles:
  - Folders with parens (e.g., `FC (Japan)` → `(Japan) game`)
  - Flat folders (e.g., `SFC` → `SFC) game`)
  - Strips extension and region tags from game name

### Stay-awake lifecycle fix
- Removed premature `rm -f /tmp/stay_awake` from main loop (broke wake lock for non-Launch actions)
- Added `echo "1" >/tmp/stay_awake` restore on emulator launch failure
- Now only Launch + exec path removes stay_awake

### Search term persistence
- Moved `previous_search_file` from `/tmp/search-term` to `$USERDATA_PATH/$PAK_NAME/search-term`
- Users see their last search term on relaunch

### Results preserved after delete
- `format_results()` extracted as reusable function
- After deleting a game, remaining results are regenerated instead of blank
- grep -Fxv removes single entry from search_list_file

### Temp file initialization
- `[ -f ... ] || : > ...` guards for search_list_file, results_list_file,
  previous_search_file to prevent cat errors on first launch

### Dead code cleanup
- Removed commented-out `#echo hi`, `#return` lines from keyboard/list exit branches
- All shellcheck levels (warning + info) pass at zero

### Deferred ideas still open
- **Search within emulator folders**: Allow user to scope search to a specific emu folder
- **Favorites badge in results**: Show a ★ next to already-favorited games
- **Batch delete / multi-select**: From search results
- **Collections browser**: From search, let user open and browse Favorites
