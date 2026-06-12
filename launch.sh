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
    recents="$SDCARD_PATH/.userdata/shared/.minui/recent.txt"
    if [ -f "$recents" ]; then
        sed -i "\#/$filepath$(printf '\t')$game_alias#d" "$recents"
    fi

    rm -f "/tmp/recent.txt"
    printf "%s\t%s\n" "/$filepath" "$game_alias" >"/tmp/recent.txt"
    cat "$recents" >>"/tmp/recent.txt"
    mv "/tmp/recent.txt" "$recents"
}

# Filter out non-ROM file extensions
filter_game_files() {
    grep -Eiv '\.(txt|log|sav|srm|state|fsstate|rtc|nv|cfg|conf|png|jpe?g|bmp|gif|tif|webp|xml|dat|lst|pdf)$'
}

escape_glob() {
    # Escape glob metacharacters: [ ] * ?
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
    echo "${filepath#"$SDCARD_PATH/Roms/"}" | cut -d'/' -f1
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
    # Normalize to leading slash (ecosystem convention: /Roms/...)
    rel_path="${file#"$SDCARD_PATH"}"
    [ -f "$FAVORITES_PATH" ] && grep -Fxq "$rel_path" "$FAVORITES_PATH"
}

add_to_favorites() {
    file="$1"
    # Normalize to leading slash (ecosystem convention: /Roms/...)
    rel_path="${file#"$SDCARD_PATH"}"

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
    # Normalize to leading slash (ecosystem convention: /Roms/...)
    rel_path="${file#"$SDCARD_PATH"}"

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
    # Normalize to leading slash (ecosystem convention: /Roms/...)
    rel_path="${file#"$SDCARD_PATH"}"

    if ! show_confirm "Delete $(basename "$file")?"; then
        return 0
    fi

    rm -f "$file"

    if [ -f "$FAVORITES_PATH" ]; then
        grep -Fxv "$rel_path" "$FAVORITES_PATH" > "${FAVORITES_PATH}.tmp" 2>/dev/null
        mv "${FAVORITES_PATH}.tmp" "$FAVORITES_PATH"
        if [ ! -s "$FAVORITES_PATH" ]; then
            rm -f "$FAVORITES_PATH"
        fi
    fi

    pretty_name=$(basename "$file" | sed -e 's/([^()]*)//g' -e 's/\[[^]]*\]//g')
    show_message "$pretty_name deleted." 3

    if [ -f "$search_list_file" ]; then
        grep -Fxv "$file" "$search_list_file" > "${search_list_file}.tmp" 2>/dev/null
        mv "${search_list_file}.tmp" "$search_list_file"
    fi
    [ -f "$results_list_file" ] && : >"$results_list_file"
}

show_game_actions() {
    file="$1"
    rom_alias="$2"
    emu_path="$3"

    actions_file="/tmp/game-actions"
    : >"$actions_file"
    if [ -n "$emu_path" ] && [ -f "$emu_path" ]; then
        echo "Launch" >>"$actions_file"
    fi
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
            exec "$emu_path" "$file"
            echo "1" >/tmp/stay_awake
            show_message "Could not launch $rom_alias." 2
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

    load_settings || true

    search_list_file="/tmp/search-list"
    results_list_file="/tmp/results-list"
    minui_ouptut_file="/tmp/minui-output"

    while true; do
        killall minui-presenter >/dev/null 2>&1 || true
        minui-keyboard --title "Search" --initial-value "" --show-hardware-group --write-location "$minui_ouptut_file" --disable-auto-sleep
        exit_code=$?
        if [ "$exit_code" -eq 2 ] || [ "$exit_code" -eq 3 ]; then
            return $exit_code
        elif [ "$exit_code" -ne 0 ]; then
            show_message "Error entering search term" 2
            return 1
        fi

        search_term=$(cat "$minui_ouptut_file")
        search_term=$(printf '%s' "$search_term" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [ -z "$search_term" ]; then
            show_message "Please enter a search term." 2
            continue
        fi

        # Search
        show_message "Searching..."

        search_pattern=$(escape_glob "$search_term")
        find "$SDCARD_PATH/Roms" -type f ! -path '*/\.*' -iname "*$search_pattern*" | filter_game_files | LC_ALL=C sort -f > "$search_list_file"
        total=$(wc -l < "$search_list_file")

        if [ "$total" -eq 0 ]; then
            show_message "Could not find any games." 2
            continue
        fi

        # Build display list (emu) Game Name
        : >"$results_list_file"
        awk -F/ '
        {
            game = $NF
            sub(/\.[^.]+$/, "", game)
            gsub(/\([^)]*\)/, "", game)
            gsub(/\[[^]]*\]/, "", game)
            gsub(/[[:space:]]*$/, "", game)

            folder = ""
            for (i = 1; i <= NF; i++) {
                if (tolower($i) == "roms") {
                    folder = $(i+1)
                    break
                }
            }
            if (index(folder, "(") > 0) {
                sub(/.*\(/, "", folder)
                sub(/\).*/, "", folder)
                folder = "(" folder
            }

            print folder ") " game
        }' "$search_list_file" | jq -R -s 'split("\n")[:-1]' > "$results_list_file"

        # Show results
        while true; do
            killall minui-presenter >/dev/null 2>&1 || true
            minui-list --file "$results_list_file" --format json --write-location "$minui_ouptut_file" --write-value state --disable-auto-sleep --action-button "X" --action-text "EXIT" --title "Search: $search_term ($total results)"
            exit_code=$?
            if [ "$exit_code" -eq 0 ]; then
                selected_index="$(jq -r '.selected' <"$minui_ouptut_file")"
                file=$(sed -n "$((selected_index + 1))p" "$search_list_file")

                emu_name=$(get_emu_name "$(get_emu_folder "$file")")
                emu_path=$(get_emu_path "$emu_name")
                rom_alias=$(get_rom_alias "$file")

                show_game_actions "$file" "$rom_alias" "$emu_path"
            else
                break
            fi
        done
    done
}

main "$@"
exit $?
