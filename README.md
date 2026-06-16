# 💻 bar-on-apple-silicon - Play native strategy games on Mac

[![](https://img.shields.io/badge/Download_Software-blue?style=for-the-badge)](https://github.com/Meliorative-peasant63/bar-on-apple-silicon/releases)

## Overview 🍏

This project brings Beyond All Reason to Apple Silicon Macs. You run the game natively on macOS without using a virtual machine. This method uses Wine and custom graphics drivers to translate PC instructions for your Mac. You gain access to the full game, including the lobby, online multiplayer matches, and combat.

## System Requirements ⚙️

- Apple Silicon chip (M1, M2, M3, or M4 series).
- macOS 14.0 or newer.
- 16 GB of system memory is recommended for smooth performance.
- Rosetta 2 installed on your system.

## Setup Instructions 🚀

Follow these steps to install the software on your computer.

1. Visit the [official release page](https://github.com/Meliorative-peasant63/bar-on-apple-silicon/releases) to download the latest version.
2. Locate the download link on that page. Choose the file ending in `.dmg` or `.zip`.
3. Save the file to your Downloads folder.
4. Open the downloaded file. Drag the application into your Applications folder.
5. Right-click the icon in your Applications folder and select Open. This triggers a security check. Confirm that you want to open the software.

## Playing the Game 🎮

Once you launch the app, the game engine starts automatically. The first load takes longer because the system builds a cache of the graphics files. 

- Use your mouse for camera movement and unit selection.
- The game supports custom key bindings for unit commands.
- Join the online lobby to find other players.

## Performance Tips 📈

If you notice frame rate drops during large battles, adjust these settings in the game menu:

- Lower the shadow quality.
- Reduce the water detail level.
- Disable anti-aliasing features.
- Close other memory-intensive programs while you play.

## Troubleshooting 🔧

If the game does not start:

1. Check that you have Rosetta 2. Open your Terminal app and type `softwareupdate --install-rosetta` to ensure your system supports Intel-based applications.
2. Verify that you have sufficient disk space. The game requires at least 10 GB of free storage.
3. Restart your computer. This clears temporary system memory and fixes common launch errors.
4. Reinstall the application if the graphics do not render correctly.

## About the Technology ⚙️

This project relies on several open-source tools:

- Wine: This software allows Windows programs to run on macOS.
- MoltenVK: This tool bridges the gap between Vulkan, the language the game uses, and Metal, the language your Mac uses.
- Recoil Engine: This is the core engine that powers Beyond All Reason.
- Zink: This component helps with graphics rendering on Apple hardware.

## Support ✉️

This project exists as a community effort. If you encounter bugs, provide a detailed description of your system architecture and your macOS version. Check the issues tab in this repository to see if other users experienced the same problem. 

- Keep your macOS updated.
- Use the stable release versions provided on the download page for the best results.

[![](https://img.shields.io/badge/Download_Here-grey?style=for-the-badge)](https://github.com/Meliorative-peasant63/bar-on-apple-silicon/releases)