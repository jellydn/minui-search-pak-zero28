# minui-search-pak
An app for searching your ROM collection.

## Requirements

This pak is designed for and tested with the following MinUI Platforms and devices:

- `tg5040`: Trimui Brick (formerly `tg3040`)
- `zero28`: MagicX Mini Zero 28

## Installation

1. Mount your MinUI SD card.
2. Download the latest [release](https://github.com/laesetuc/minui-search-pak/releases) from GitHub.
3. Copy the zip file to the correct platform folder in the "/Tools" directory on the SD card.
4. Extract the zip in place, then delete the zip file.
5. Confirm that there is a `/Tools/$PLATFORM/Search.pak/launch.sh` file on your SD card.
6. Unmount your SD Card and insert it into your MinUI device.

Note: The platform folder name is based on the name of your device. For example, if you are using a TrimUI Brick, the folder is "tg5040". Alternatively, if you're not sure which folder to use, you can copy the .pak folders to all the platform folders.

## Usage

### First Launch

On first launch you'll pick a **search scope** — either "All Systems" to search
all ROM folders, or a specific emulator folder (e.g. "SFC", "PS").
This choice is saved to your SD card and remembered across sessions.

After setting the scope, a main menu appears:

- **Search Games**: Enter a search term via the on-screen keyboard
- **Browse Favorites**: View and manage your Favorites collection
- **Exit**: Quit the app

### Search

Use the keyboard to enter a search term.
Press A to select a character, or B to erase a character.
Press X to search, or Y to exit.

The keyboard title shows the current search scope, e.g. `Search (SFC)`.

Matching results are sorted alphabetically and limited to the chosen scope.
Non-ROM files (saves, states, configs, images, metadata) are automatically
filtered out for cleaner results.

### Search Results

Results appear as `(emu) Game Name` or `Folder) Game Name`.
Already-favorited games show a ★ badge.

Select a game and press A to choose an action:

- **Launch**: Launch the selected game (only shown when emulator is found)
- **Add to Favorites** / **Remove from Favorites**: Toggle the game in your
  Favorites collection (`Collections/1) Favorites.txt` on your SD card)
- **Delete Game**: Permanently delete the ROM file (with confirmation prompt)
- **Cancel**: Return to the search results

Press B to return to the Search screen.
Press X at any time to exit.

### Browse Favorites

From the main menu, select "Browse $FAVORITES_LABEL" to view your collection.
Select a game to see the same actions (Launch, Remove from Favorites,
Delete Game).

### Previous Search

Your last search term is saved to your SD card and restored when you
re-launch the app.

## Notes

- The Favorites collection label can be customized in `config.json`
  via the `settings.favorites_label` field (default: "Favorites").
- Search scope is saved in `$USERDATA_PATH/$PAK_NAME/search-scope`.
  Delete this file to re-pick your scope.

## Acknowledgements

- [MinUI](https://github.com/shauninman/MinUI) by Shaun Inman
- [minui-keyboard](https://github.com/josegonzalez/minui-keyboard), [minui-list](https://github.com/josegonzalez/minui-list) and [minui-presenter](https://github.com/josegonzalez/minui-presenter) by Jose Diaz-Gonzalez
- Also, thank you, Jose Diaz-Gonzalez, for your pak repositories, which this project is based on.

## License

This project is released under the MIT License. For more information, see the [LICENSE](LICENSE) file.
