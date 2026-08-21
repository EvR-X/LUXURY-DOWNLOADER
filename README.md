# Luxury Downloader

> **A simple, modern CLI application installer and Linux setup utility.**

Luxury Downloader is a lightweight Bash-based CLI designed to make common Linux installation and setup tasks easier from one terminal interface.

Instead of remembering separate `apt`, `pacman`, AUR, repository, Flatpak, driver, firmware, and utility commands, Luxury detects the Linux family and presents the appropriate actions through a structured menu.

The project follows one main idea:

**Keep the main screen simple, and move secondary tools into organized categories.**

---

## ✨ What is Luxury Downloader?

Luxury Downloader is an interactive terminal application that can:

- Detect supported Debian/Ubuntu-based and Arch-based distributions.
- Detect the system architecture.
- Use the appropriate package manager automatically.
- Ask for administrator privileges only when a system-level operation needs them.
- Install a selected application or several applications in one session.
- Detect applications that are already installed.
- Update the Linux system.
- Check whether a newer Luxury Downloader version is available.
- Install Luxury as the `luxury` command.
- Update or uninstall the installed `luxury` command.
- Organize additional tools into separate categories.

Everything is controlled from an English-language terminal interface.

---

# 🖥️ Main Menu

The main screen is intentionally kept focused on the most commonly installed applications and the most important actions.

Example:

```text
╔══════════════════════════════════════════════════╗
║                 LUXURY DOWNLOADER                ║
║                                                  ║
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

### Main applications

- **Brave Origin**
- **Thunderbird**
- **LibreWolf**
- **VLC**
- **LibreOffice**
- **MPV**

---

# 📦 Supported Applications

| Application | Debian / Ubuntu | Arch |
|---|---|---|
| Brave Origin | Official Brave installer | AUR (`brave-origin-bin`) |
| Thunderbird | APT | Pacman |
| LibreWolf | Official LibreWolf repository via `extrepo` | Pacman |
| VLC | APT | Pacman |
| LibreOffice | APT | `libreoffice-still` |
| MPV | APT | Pacman |


---

# 📂 Categories

The main menu contains a single **Categories** option. Secondary functionality is moved into separate pages so the main screen remains clean.

```text
=== CATEGORIES ===

  [1] AUR Helpers
  [2] Drivers & Firmware
  [3] Terminal Utilities
  [0] Back
```

---

# 🧩 AUR Helpers

The AUR is an Arch Linux ecosystem, so this section is available only on **Arch-based systems**.

```text
=== AUR HELPERS ===

  Current helper: None

  [1] Install / use Yay
  [2] Install / use Paru
  [3] Back
```

Luxury explicitly checks the detected Linux family before starting an AUR workflow. On Debian/Ubuntu-based systems it refuses to run AUR commands instead of attempting to use `pacman`.

### Yay

Luxury installs the required Arch build tools, clones `yay-bin` from the AUR, and builds it using `makepkg` as the normal user.

### Paru

Luxury installs the required Arch build tools, clones `paru-bin` from the AUR, and builds it using `makepkg` as the normal user.

AUR packages are **not built as root**.

---

# 🖥️ Drivers & Firmware

Luxury provides different driver choices depending on whether the detected system is Arch-based or Debian/Ubuntu-based.

## Arch-based systems

```text
[1] NVIDIA Open
[2] NVIDIA Open + DKMS
[3] AMD GPU
[4] AMD CPU Microcode
[5] Intel GPU
[6] Intel CPU Microcode
[7] Firmware
[0] Back
```

### NVIDIA Open

```bash
sudo pacman -S --needed nvidia-open
```

### NVIDIA Open + DKMS

```bash
sudo pacman -S --needed nvidia-open-dkms
```

### AMD GPU

Installs:

```text
mesa
vulkan-radeon
linux-firmware
```

### AMD CPU Microcode

```bash
sudo pacman -S --needed amd-ucode
```

### Intel GPU

Installs:

```text
mesa
vulkan-intel
linux-firmware
```

### Intel CPU Microcode

```bash
sudo pacman -S --needed intel-ucode
```

### Firmware

```bash
sudo pacman -S --needed linux-firmware
```

## Debian/Ubuntu-based systems

```text
[1] NVIDIA (recommended Ubuntu driver)
[2] AMD GPU
[3] AMD CPU Microcode
[4] Intel GPU
[5] Intel CPU Microcode
[6] Firmware
[0] Back
```

### NVIDIA

Luxury uses `ubuntu-drivers` when available. If it is missing, Luxury installs `ubuntu-drivers-common` first and then requests the recommended driver.

### AMD GPU

Installs:

```text
mesa-vulkan-drivers
linux-firmware
```

### AMD CPU Microcode

```text
amd64-microcode
```

### Intel GPU

Installs:

```text
mesa-vulkan-drivers
linux-firmware
```

### Intel CPU Microcode

```text
intel-microcode
```

### Firmware

```text
linux-firmware
```

---

# 🧰 Terminal Utilities

Terminal-focused programs are kept in their own category.

```text
=== TERMINAL UTILITIES ===

  [1] CMatrix
  [2] CAVA
  [3] lavat
  [4] Peaclock
  [5] Fastfetch
  [6] Neofetch / Neowofetch
  [7] HyFetch
  [8] btop
  [9] htop
  [0] Back
```

### Included utilities

- **CMatrix** — Matrix-style terminal animation.
- **CAVA** — Console audio visualizer.
- **lavat** — Terminal lava-lamp simulation.
- **Peaclock** — Terminal clock utility.
- **Fastfetch** — Fast system-information display.
- **Neofetch / Neowofetch** — Neofetch-style system-information utility. Debian/Ubuntu uses the available `neowofetch` package entry.
- **HyFetch** — System-information fetch-style utility.
- **btop** — Interactive terminal resource monitor.
- **htop** — Interactive process viewer.

### Special installation handling

Not every utility is installed through a simple package name.

#### lavat

Luxury prepares the build environment, clones the upstream repository, and installs `lavat` with `make install`.

#### Peaclock on Debian/Ubuntu

Luxury does not assume a standard Ubuntu repository package is available. It prepares the build environment and builds the current upstream project from source.

#### Peaclock on Arch

Luxury first checks the configured Arch repositories. If the package is not available there, it falls back to the AUR using the installed AUR helper.

#### Neofetch on Arch

If `neofetch` is not available from the configured official repositories, Luxury warns the user and can use the AUR helper. 

---

# 🛍️ Bazaar

**Bazaar** is available directly from the main menu:


When Bazaar is selected, Luxury automatically checks the Flatpak environment.

The process is:

1. Check whether Flatpak is installed.
2. Install Flatpak if it is missing.
3. Check whether the Flathub remote exists.
4. Add Flathub if needed.
5. Check whether Bazaar is already installed.
6. Install Bazaar if necessary.
7. Launch Bazaar.

Bazaar's Flatpak application ID is:

```text
io.github.kolunmi.Bazaar
```

The menu therefore does not require the user to configure Flatpak manually first.

---

# 🔄 Luxury Downloader Update Check

Before opening the main menu, Luxury checks whether a newer version of Luxury Downloader is available from the project's GitHub repository.

When the installed version is current:

```text
✓ Luxury Downloader is up to date (v2.1.2).
```

When a newer version exists:

```text
New update found: v2.2.0
Current version: v2.1.2
[U] Update  [S] Skip:
```

### Update

Press `U` to replace the installed Luxury command with the newer version and restart Luxury.

### Skip

Press `S` to continue using the current version.

### Failed update check

If GitHub cannot be reached or the version cannot be read, Luxury warns the user and continues instead of blocking the application.

---

# 🔄 Update Your Linux System

The main menu contains:

```text
[9] Update System
```

Luxury automatically chooses the correct system-update workflow.

### Debian/Ubuntu-based

```bash
sudo apt update
sudo apt upgrade -y
```

### Arch-based

```bash
sudo pacman -Syu --noconfirm
```

On Arch, synchronization and upgrading are performed together to avoid a partial system upgrade.

---

# 📦 Install ALL Apps

The main menu contains:

```text
[10] Install ALL Apps
```

This option installs **only the applications from the main application registry**:

1. Brave Origin
2. Thunderbird
3. LibreWolf
4. VLC
5. LibreOffice
6. MPV

It does **not** install:

- AUR Helpers
- Drivers & Firmware
- Terminal Utilities
- Bazaar

Luxury continues through the application list and reports when one or more installations fail instead of silently treating every result as successful.

---

# 🐧 Supported Linux Families

Luxury reads `/etc/os-release` and detects the Linux family before performing package operations.

### Debian/Ubuntu-based

The script recognizes explicit IDs including:

- Ubuntu
- Debian
- Linux Mint
- Pop!_OS
- KDE neon
- Zorin OS
- elementary OS
- Lubuntu
- Kubuntu
- Xubuntu
- Ubuntu MATE
- Budgie Remix

It can also use `ID_LIKE` to recognize compatible derivatives that identify themselves as Debian/Ubuntu based.

### Arch-based

The script recognizes explicit IDs including:

- Arch Linux
- Manjaro
- EndeavourOS
- Garuda Linux
- CachyOS
- ArcoLinux
- Artix

It can also use `ID_LIKE` to recognize compatible Arch derivatives.

Unsupported distributions are rejected instead of blindly running the wrong package manager.

---

# 🏗️ Architecture Support

Luxury currently accepts:

```text
x86_64
amd64
aarch64
arm64
```

Other architectures are rejected with an explanatory message.

---

# 🔐 Permissions & Safety

Luxury does not require administrator privileges merely to display its interface.

Administrator privileges are requested when a system-level operation actually requires them, for example:

- Installing system packages.
- Installing Luxury to `/usr/local/bin/luxury`.
- Updating the installed Luxury command.
- Removing the installed Luxury command.
- Installing drivers or firmware.
- Installing source-built software system-wide.

AUR helpers are built as the normal user. Luxury explicitly refuses to build AUR packages as root.

---

# 💾 Installation

Install the `luxury` command system-wide with:

```bash
curl -fsSL https://raw.githubusercontent.com/EvR-X/LUXURY-DOWNLOADER/main/luxury-downloader.sh | bash
```

Luxury installs the command to:

```text
/usr/local/bin/luxury
```

After installation, simply run:

```bash
luxury
```

---


# 🔧 Luxury Commands

## Open Luxury

```bash
luxury
```

Opens the interactive menu.

## Force an Update

```bash
luxury update
```

Downloads the current script from the GitHub repository and replaces the installed command.

## Uninstall Luxury

```bash
luxury uninstall
```

or:

```bash
luxury remove
```

Luxury asks for confirmation before removing `/usr/local/bin/luxury`.

## Show Version

```bash
luxury --version
```

or:

```bash
luxury -v
```

## Show Help

```bash
luxury --help
```

or:

```bash
luxury -h
```

---

# 📖 Command Summary

| Command | What it does |
|---|---|
| `luxury` | Opens the interactive menu |
| `luxury update` | Force-updates the installed Luxury command |
| `luxury uninstall` | Removes the installed Luxury command |
| `luxury remove` | Alias for `luxury uninstall` |
| `luxury --version` | Shows the current Luxury version |
| `luxury --help` | Shows command help |

---

# 🛠️ Application Registry

Luxury uses centralized registries instead of duplicating menu logic for every program.

The main application registry uses:

```text
APP_ORDER
APP_NAME
APP_PKG_DEBIAN
APP_PKG_ARCH
APP_CUSTOM_DEBIAN
APP_CUSTOM_ARCH
```

Terminal utilities use:

```text
UTIL_ORDER
UTIL_NAME
UTIL_APT
UTIL_PACMAN
```

This means the main menu, numbered selection, and **Install ALL Apps** can use the same application definitions.

For applications that need special setup, Luxury can call a custom installation function instead of a normal package-manager command.

---

# 🎯 Design Goals

Luxury Downloader is designed around a few simple principles:

- **Simple main screen** — keep common applications visible.
- **Organized categories** — move secondary functionality to separate pages.
- **Correct package manager** — detect Debian/Ubuntu versus Arch before installation.
- **Arch-specific tooling** — keep AUR helpers and AUR workflows isolated to Arch-based systems.
- **No unnecessary root access** — request administrator privileges only when required.
- **Safe Arch updates** — use `pacman -Syu` instead of a standalone package database sync.
- **Automatic update awareness** — check for a newer Luxury version before the menu opens.
- **Centralized application management** — keep installation definitions in registries.
- **English interface** — all user-facing program text is written in English.

---

# 📌 Current Version

**Luxury Downloader v2.1.9**

---

# ⚠️ Notes

Luxury Downloader is a convenience layer over the package managers and upstream installation systems already used by Linux distributions and individual projects.

Package availability can depend on the enabled repositories and the exact distribution release.

AUR operations require an Arch-based system, a network connection, and a normal non-root user.

Source builds such as `lavat` and Peaclock require network access to their upstream repositories and the appropriate build environment.

---
