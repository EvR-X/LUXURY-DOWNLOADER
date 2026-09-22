Luxury Downloader

""License" (https://img.shields.io/github/license/EvR-X/LUXURY-DOWNLOADER?style=flat-square)" (https://github.com/EvR-X/LUXURY-DOWNLOADER/blob/main/LICENSE)
""Version" (https://img.shields.io/badge/version-2.6.0-blue?style=flat-square)" (https://github.com/EvR-X/LUXURY-DOWNLOADER/releases)

«A CLI that installs apps, drivers, and terminal utilities on Debian/Ubuntu and Arch Linux from a single menu.»

Features

- Detects distribution, family, and architecture
- Installs apps such as Brave Origin, Thunderbird, LibreWolf, VLC, LibreOffice, MPV, RetroArch, and more
- Installs GPU/CPU drivers and firmware
- Supports NVIDIA Open, DKMS, and legacy drivers on Arch
- Sets up AUR helpers such as Yay and Paru
- Includes terminal utilities like btop, htop, Fastfetch, Cava, and more
- Installs and configures Bazaar on supported Ubuntu systems
- Safely tracks and uninstalls software installed by Luxury
- Supports tracked source builds with rollback and cleanup
- Updates the system or Luxury Downloader itself

The main menu stays intentionally short. Apps, utilities, drivers, AUR helpers, and uninstall options are organized into separate pages.

Example

╭──────────────────────────────────────────────────╮
│              ✦ Luxury Downloader                 │
╰──────────────────────────────────────────────────╯
X.Y.Z · Ubuntu 26.04.1 LTS · debian · x86_64

  [1] Apps
  [2] Terminal Utilities
  [3] Drivers & Firmware
  [4] AUR Helpers
  [5] Install Bazaar
  [6] Update System
  [7] Uninstall [Apps/Utilities]

  [Q] Exit

App and utility menus use the same internal registries as the installer, keeping the available options synchronized with the software Luxury actually supports.

Install

curl -fsSL https://raw.githubusercontent.com/EvR-X/LUXURY-DOWNLOADER/main/luxury-downloader.sh | bash

Usage

luxury            # open the menu
luxury update     # update Luxury
luxury uninstall  # remove Luxury
luxury --version  # show version
luxury --help     # show help