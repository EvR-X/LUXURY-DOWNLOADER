# Luxury Downloader

[![Release](https://img.shields.io/github/v/release/EvR-X/LUXURY-DOWNLOADER?style=flat-square)](https://github.com/EvR-X/LUXURY-DOWNLOADER/releases)
[![License](https://img.shields.io/github/license/EvR-X/LUXURY-DOWNLOADER?style=flat-square)](https://github.com/EvR-X/LUXURY-DOWNLOADER/blob/main/LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/EvR-X/LUXURY-DOWNLOADER?style=flat-square)](https://github.com/EvR-X/LUXURY-DOWNLOADER/commits/main)

> A CLI that installs apps, drivers, and utilities on Debian/Ubuntu and Arch Linux from a single menu.

## Features

- Detects your distro, family, and architecture
- Installs Brave Origin, Thunderbird, LibreWolf, VLC, LibreOffice, MPV, ETC
- Installs GPU/CPU drivers and firmware
- Sets up AUR helpers (Yay, Paru) on Arch
- Adds terminal utilities: btop, htop, Fastfetch, and more
- Opens Bazaar, a Flatpak app store
- Updates your system or itself

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
