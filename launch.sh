#!/bin/sh
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
[ -f "$USERDATA_PATH/$PAK_NAME/debug" ] && set -x

rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1

echo "$0" "$@"
cd "$PAK_DIR" || exit 1
mkdir -p "$USERDATA_PATH/$PAK_NAME"

ARCHITECTURE=arm
case "$(uname -m)" in
    *64*) ARCHITECTURE=arm64 ;;
esac

export HOME="$USERDATA_PATH/$PAK_NAME"
export LD_LIBRARY_PATH="$PAK_DIR/lib:$LD_LIBRARY_PATH"
export PATH="$PAK_DIR/bin/$ARCHITECTURE:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"

COLLECTIONS_PATH="$SDCARD_PATH/Collections"
FAVORITES_LABEL="Favorites"
FAVORITES_PATH="$COLLECTIONS_PATH/1) $FAVORITES_LABEL.txt"
RECENTS_PATH="$SDCARD_PATH/.userdata/shared/.minui/recent.txt"

load_settings() {
    config_file="$PAK_DIR/config.json"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    if jq -e '.settings.favorites_label' "$config_file" >/dev/null 2>&1; then
        FAVORITES_LABEL=$(jq -r '.settings.favorites_label' "$config_file")
        FAVORITES_PATH="$COLLECTIONS_PATH/1) $FAVORITES_LABEL.txt"
    fi
}

add_game_to_recents() {
    filepath="$1" game_alias="$2"

    filepath="${filepath#"$SDCARD_PATH/"}"
    if [ -f "$RECENTS_PATH" ]; then
        sed -i "\#/$filepath$(printf '\t')$game_alias#d" "$RECENTS_PATH"
    fi

    rm -f "/tmp/recent.txt"
    printf "%s\t%s\n" "/$filepath" "$game_alias" >"/tmp/recent.txt"
    cat "$RECENTS_PATH" >>"/tmp/recent.txt"
    mv "/tmp/recent.txt" "$RECENTS_PATH"
}

# Filter out non-ROM file extensions (saves, states, configs, media, metadata, playlists)
# Only passes through actual game/ROM files
filter_game_files() {
    grep -Eiv '\.(txt|log|sav|srm|state|fsstate|rtc|nv|cfg|conf|png|jpe?g|bmp|gif|tif|webp|xml|dat|lst|pdf)$'
}

escape_glob() {
    # Escape glob metacharacters so find -iname treats them literally
    # Escapes: [ ] * ?
    printf '%s' "$1" | sed 's/\[/\\[/g; s/\]/\\]/g; s/\*/\\*/g; s/?/\\?/g'
}

get_rom_alias() {
    filepath="$1"
    filename="$(basename "$filepath")"
    filename="${filename%.*}"
    filename="$(echo "$filename" | sed 's/([^)]*)//g' | sed 's/\[[^]]*\]//g' | sed 's/[[:space:]]*$//')"
    echo "$filename"
}

get_emu_folder() {
    filepath="$1"
    roms="$SDCARD_PATH/Roms"

    echo "${filepath#"$roms/"}" | cut -d'/' -f1
}

get_emu_name() {
    emu_folder="$1"

    echo "$emu_folder" | sed 's/.*(\([^)]*\)).*/\1/'
}

get_emu_path() {
    emu_name="$1"
    platform_emu="$SDCARD_PATH/Emus/$PLATFORM/${emu_name}.pak/launch.sh"
    if [ -f "$platform_emu" ]; then
        echo "$platform_emu"
        return
    fi

    pak_emu="$SDCARD_PATH/.system/$PLATFORM/paks/Emus/${emu_name}.pak/launch.sh"
    if [ -f "$pak_emu" ]; then
        echo "$pak_emu"
        return
    fi

    return 1
}

show_message() {
    message="$1"
    seconds="$2"

    if [ -z "$seconds" ]; then
        seconds="forever"
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$message" 1>&2
    if [ "$seconds" = "forever" ]; then
        minui-presenter --message "$message" --timeout -1 &
    else
        minui-presenter --message "$message" --timeout "$seconds"
    fi
}

show_confirm() {
    message="$1"

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$message" 1>&2

    if ! minui-presenter --message "$message" \
        --confirm-show \
        --cancel-show \
        --confirm-text "YES" \
        --cancel-text "NO" \
        --timeout 0; then
        return 1
    fi

    return 0
}

is_favorited() {
    file="$1"
    rel_path="${file#"$SDCARD_PATH/"}"

    [ -f "$FAVORITES_PATH" ] && grep -Fxq "$rel_path" "$FAVORITES_PATH"
}

add_to_favorites() {
    file="$1"

    rel_path="${file#"$SDCARD_PATH/"}"

    mkdir -p "$COLLECTIONS_PATH"
    touch "$FAVORITES_PATH"

    if ! grep -Fxq "$rel_path" "$FAVORITES_PATH"; then
        echo "$rel_path" >> "$FAVORITES_PATH"
        awk -F'/' '{print $NF "|" $0}' "$FAVORITES_PATH" | sort -t'|' -k1,1 | cut -d'|' -f2- > "${FAVORITES_PATH}.tmp"
        mv "${FAVORITES_PATH}.tmp" "$FAVORITES_PATH"

        pretty_name=$(basename "$file" | sed -e 's/([^()]*)//g' -e 's/\[[^]]*\]//g')
        show_message "$pretty_name added to $FAVORITES_LABEL." 3
    fi
}

remove_from_favorites() {
    file="$1"

    rel_path="${file#"$SDCARD_PATH/"}"

    if [ -f "$FAVORITES_PATH" ] && grep -Fxq "$rel_path" "$FAVORITES_PATH"; then
        grep -Fxv "$rel_path" "$FAVORITES_PATH" > "${FAVORITES_PATH}.tmp" 2>/dev/null
        mv "${FAVORITES_PATH}.tmp" "$FAVORITES_PATH"
        if [ ! -s "$FAVORITES_PATH" ]; then
            rm -f "$FAVORITES_PATH"
        fi

        pretty_name=$(basename "$file" | sed -e 's/([^()]*)//g' -e 's/\[[^]]*\]//g')
        show_message "$pretty_name removed from $FAVORITES_LABEL." 3
    fi
}

delete_game() {
    file="$1"

    rel_path="${file#"$SDCARD_PATH/"}"

    if ! show_confirm "Delete $(basename "$file")?"; then
        return 0
    fi

    rm -f "$file"

    # Remove from favorites if present
    if [ -f "$FAVORITES_PATH" ]; then
        grep -Fxv "$rel_path" "$FAVORITES_PATH" > "${FAVORITES_PATH}.tmp" 2>/dev/null
        mv "${FAVORITES_PATH}.tmp" "$FAVORITES_PATH"
        if [ ! -s "$FAVORITES_PATH" ]; then
            rm -f "$FAVORITES_PATH"
        fi
    fi

    pretty_name=$(basename "$file" | sed -e 's/([^()]*)//g' -e 's/\[[^]]*\]//g')
    show_message "$pretty_name deleted." 3

    # Clear search results so we go back to search
    : >"$search_list_file"
    : >"$results_list_file"
}

show_game_actions() {
    file="$1"
    rom_alias="$2"
    emu_path="$3"

    actions_file="/tmp/game-actions"
    : >"$actions_file"
    echo "Launch" >>"$actions_file"
    if is_favorited "$file"; then
        echo "Remove from Favorites" >>"$actions_file"
    else
        echo "Add to Favorites" >>"$actions_file"
    fi
    echo "Delete Game" >>"$actions_file"
    echo "Cancel" >>"$actions_file"

    killall minui-presenter >/dev/null 2>&1 || true
    action=$(minui-list --file "$actions_file" --format text --title "$rom_alias")
    exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        return 0
    fi

    case "$action" in
        "Launch")
            rm -f /tmp/stay_awake
            add_game_to_recents "$file" "$rom_alias"
            killall minui-presenter >/dev/null 2>&1 || true
            if [ -n "$emu_path" ] && [ -f "$emu_path" ]; then
                exec "$emu_path" "$file"
            else
                show_message "Emulator not found for $rom_alias" 2
            fi
            ;;
        "Add to Favorites")
            add_to_favorites "$file"
            ;;
        "Remove from Favorites")
            remove_from_favorites "$file"
            ;;
        "Delete Game")
            delete_game "$file"
            ;;
        *)
            # Cancel - do nothing
            ;;
    esac
}

cleanup() {
    rm -f /tmp/stay_awake
    killall minui-presenter >/dev/null 2>&1 || true
}

main() {
    echo "1" >/tmp/stay_awake
    trap "cleanup" EXIT INT TERM HUP QUIT

    if ! command -v minui-presenter >/dev/null 2>&1; then
        show_message "minui-presenter not found" 2
        return 1
    fi
    if ! command -v minui-keyboard >/dev/null 2>&1; then
        show_message "minui-keyboard not found" 2
        return 1
    fi
    if ! command -v minui-list >/dev/null 2>&1; then
        show_message "minui-list not found" 2
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        show_message "jq not found" 2
        return 1
    fi

    if ! load_settings; then
        show_message "Could not load settings" 2
        return 1
    fi

    search_list_file="/tmp/search-list"
    results_list_file="/tmp/results-list"
    previous_search_file="/tmp/search-term"
    minui_ouptut_file="/tmp/minui-output"

    while true; do
        search_term=$(cat "$previous_search_file")

        total=$(wc -l < "$search_list_file")
        if [ "$total" -eq 0 ]; then

            # Get search term
            killall minui-presenter >/dev/null 2>&1 || true
            minui-keyboard --title "Search" --initial-value "$search_term" --show-hardware-group --write-location "$minui_ouptut_file" --disable-auto-sleep 
            exit_code=$?
            if [ "$exit_code" -eq 2 ] || [ "$exit_code" -eq 3 ]; then
                #>"$previous_search_file"
                return $exit_code
                #echo hi
            elif [ "$exit_code" -ne 0 ]; then
                show_message "Error entering search term" 2
                return 1
            fi
            search_term=$(cat "$minui_ouptut_file")
            # Trim whitespace
            search_term=$(printf '%s' "$search_term" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            echo "$search_term" > "$previous_search_file"

            # Perform search
            if [ -z "$search_term" ]; then
                show_message "Please enter a search term." 2
                : >"$search_list_file"
                : >"$results_list_file"
            else
                show_message "Searching..."

                search_pattern=$(escape_glob "$search_term")
                find "$SDCARD_PATH/Roms" -type f ! -path '*/\.*' -iname "*$search_pattern*" | filter_game_files | sort -f > "$search_list_file"
                total=$(wc -l < "$search_list_file")

                if [ "$total" -eq 0 ]; then
                    show_message "Could not find any games." 2
                else
                    : >"$results_list_file"
                    awk -F/ '
                    {
                        # Extract game filename (last field)
                        game = $NF
                        # Strip extension
                        sub(/\.[^.]+$/, "", game)
                        # Strip region/tags from game name
                        gsub(/\([^)]*\)/, "", game)
                        gsub(/\[[^]]*\]/, "", game)
                        sub(/[[:space:]]*$/, "", game)

                        # Find the emu folder (field after Roms)
                        for (i = 1; i <= NF; i++) {
                            if (tolower($i) == "roms") {
                                folder = $(i+1)
                                break
                            }
                        }

                        if (folder ~ /\(/) {
                            # Folder has parens: "(emu) game"
                            sub(/.*\(/, "(", folder)
                            sub(/\).*/, ")", folder)
                            print folder " " game
                        } else {
                            # No parens: "folder) game"
                            print folder ") " game
                        }
                    }' "$search_list_file" \
                        | jq -R -s 'split("\n")[:-1]' > "$results_list_file"
                fi
            fi
        fi

        # Display Results

        total=$(wc -l < "$search_list_file")
        if [ "$total" -gt 0 ]; then
            killall minui-presenter >/dev/null 2>&1 || true
            minui-list --file "$results_list_file" --format json --write-location "$minui_ouptut_file" --write-value state --disable-auto-sleep --action-button "X" --action-text "EXIT"  --title "Search: $search_term ($total results)"
            exit_code=$?
            if [ "$exit_code" -eq 0 ]; then
                output=$(cat "$minui_ouptut_file")
                selected_index="$(echo "$output" | jq -r '.selected')"
                file=$(sed -n "$((selected_index + 1))p" "$search_list_file")

                emu_folder=$(get_emu_folder "$file")
                emu_name=$(get_emu_name "$emu_folder")
                emu_path=$(get_emu_path "$emu_name")
                rom_alias=$(get_rom_alias "$file")
                rm -f /tmp/stay_awake

                show_game_actions "$file" "$rom_alias" "$emu_path"
            elif [ "$exit_code" -eq 4 ] || [ "$exit_code" -eq 3 ]; then
                return $exit_code
                #echo hi
            else
                : >"$results_list_file"
                : >"$search_list_file"
                #return $exit_code
            fi
        fi
    done
}

main "$@"
