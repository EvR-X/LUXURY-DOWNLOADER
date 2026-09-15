# Luxury Downloader

[![License](https://img.shields.io/github/license/EvR-X/LUXURY-DOWNLOADER?style=flat-square)](https://github.com/EvR-X/LUXURY-DOWNLOADER/blob/main/LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/EvR-X/LUXURY-DOWNLOADER?style=flat-square)](https://github.com/EvR-X/LUXURY-DOWNLOADER/commits/main)

> A CLI that installs apps, drivers, and utilities on Debian/Ubuntu and Arch Linux from a single menu.

## Features

- Detects your distro, family, and architecture
- Includes Brave Origin, Thunderbird, LibreWolf, VLC, LibreOffice, MPV, etc.
- Installs GPU/CPU drivers and firmware
- Sets up AUR helpers (Yay, Paru) on Arch
- Adds terminal utilities: btop, htop, Fastfetch, and more
- Installs Bazaar, an app store for your system
- Lets you cleanly uninstall anything Luxury installed
- Updates your system or itself

The main menu stays short on purpose — everything else (apps, drivers,
utilities, uninstalling) lives one level down, in its own page.

Example:

```text
╭──────────────────────────────────────────────────╮
│          ✦ Luxury Downloader  v2.5.0           │
╰──────────────────────────────────────────────────╯
Ubuntu 26.04 LTS · debian · x86_64

  [1] Apps
  [2] Terminal Utilities
  [3] Drivers & Firmware
  [4] AUR Helpers
  [5] Install Bazaar
  [6] Update System
  [7] Install ALL Apps
  [8] Uninstall Apps

  [Q] Exit
```

Numbers inside the Apps and Terminal Utilities pages come from the same
registry the script installs from, so they always stay in sync with
what's actually available.

## Install

```sh
 curl -fsSL https://raw.githubusercontent.com/EvR-X/LUXURY-DOWNLOADER/main/luxury-downloader.sh | bash
```

## Usage

```sh
$ luxury            # open the menu
$ luxury update     # update Luxury
$ luxury uninstall  # remove Luxury
$ luxury --version  # show version
```
