# Luxury Downloader

[![License](https://img.shields.io/github/license/EvR-X/LUXURY-DOWNLOADER?style=flat-square)](https://github.com/EvR-X/LUXURY-DOWNLOADER/blob/main/LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/EvR-X/LUXURY-DOWNLOADER?style=flat-square)](https://github.com/EvR-X/LUXURY-DOWNLOADER/commits/main)

> A CLI that installs apps, drivers, and utilities on Debian/Ubuntu and Arch Linux from a single menu.

## Features

- Detects your distro, family, and architecture
- Includes Brave Origin, Thunderbird, LibreWolf, VLC, LibreOffice, MPV, ETC
- Installs GPU/CPU drivers and firmware
- Sets up AUR helpers (Yay, Paru) on Arch
- Adds terminal utilities: btop, htop, Fastfetch, and more
- Opens Bazaar, a Flatpak app store
- Updates your system or itself

The main screen is intentionally kept focused on the most commonly installed applications and the most important actions.

Example:

```text
╔══════════════════════════════════════════════════╗
║                 LUXURY DOWNLOADER                ║
║                     v2.1.2                       ║
╚══════════════════════════════════════════════════╝

  System:       Ubuntu 26.04 LTS
  Family:       debian
  Architecture: x86_64

  [1] Brave Origin
  [2] Thunderbird
  [3] LibreWolf
  [4] VLC
  [5] LibreOffice
  [6] MPV

  [7] Categories
  [8] Bazaar (Flatpak App Store)
  [9] Update System
  [10] Install ALL Apps
  [0] Exit
```
The option numbers are generated automatically from the application's registry, so the menu stays synchronized with the actual application list.

## Install

```sh
$ curl -fsSL https://raw.githubusercontent.com/EvR-X/LUXURY-DOWNLOADER/main/luxury-downloader.sh | bash
```

## Usage

```sh
$ luxury            # open the menu
$ luxury update     # update Luxury
$ luxury uninstall  # remove Luxury
$ luxury --version  # show version
```
