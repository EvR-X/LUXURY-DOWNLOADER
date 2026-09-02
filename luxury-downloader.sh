#!/usr/bin/env bash

# ============================================================
#                       LUXURY DOWNLOADER
#        Lightweight CLI installer for Debian/Ubuntu + Arch
# ============================================================

# Public repository:
# https://github.com/EvR-X/LUXURY-DOWNLOADER
#
# Install (first-time setup):
#   curl -fsSL https://raw.githubusercontent.com/EvR-X/LUXURY-DOWNLOADER/main/luxury-downloader.sh | bash
#
# Then run:
#   luxury
#
# Update Luxury itself:
#   luxury update
#
# Uninstall:
#   luxury uninstall
#
# NOTE:
# The updater reads VERSION from the script hosted at UPDATE_URL.
# Keep this file in the repository root as "luxury-downloader.sh".

set -u

VERSION="2.3.5"
LUXURY_TITLE="Luxury Downloader"
INSTALL_PATH="/usr/local/bin/luxury"
REPO="EvR-X/LUXURY-DOWNLOADER"
UPDATE_URL="https://raw.githubusercontent.com/${REPO}/main/luxury-downloader.sh"
BAZAAR_FLATPAK_ID="io.github.kolunmi.Bazaar"

DISTRO_FAMILY=""
DISTRO_ID=""
DISTRO_NAME=""
SUDO="sudo"
APT_SYNCED=false
AUR_HELPER=""

# ============================================================
#                         UI
# ============================================================

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    GREEN=$'\033[32m'
    RED=$'\033[31m'
    YELLOW=$'\033[33m'
    CYAN=$'\033[36m'
    BLUE=$'\033[34m'
    MAGENTA=$'\033[35m'
    RESET=$'\033[0m'
else
    BOLD=''
    DIM=''
    GREEN=''
    RED=''
    YELLOW=''
    CYAN=''
    BLUE=''
    MAGENTA=''
    RESET=''
fi

print_ok()   { printf '%b✓%b %s\n' "$GREEN" "$RESET" "$1"; }
print_warn() { printf '%b!%b %s\n' "$YELLOW" "$RESET" "$1"; }
print_err()  { printf '%b✗%b %s\n' "$RED" "$RESET" "$1"; }
print_info() { printf '%b→%b %s\n' "$CYAN" "$RESET" "$1"; }

press_enter() {
    read -r -p "Press Enter to continue..." _ || true
}

repeat_char() {
    local out
    printf -v out '%*s' "$2" ''
    printf '%s' "${out// /$1}"
}

print_box() {
    local width=50
    local line pad_l pad_r

    printf '%b╔%s╗%b\n' "$CYAN$BOLD" "$(repeat_char '═' "$width")" "$RESET"

    for line in "$@"; do
        pad_l=$(( (width - ${#line}) / 2 ))
        pad_r=$(( width - ${#line} - pad_l ))
        (( pad_l < 0 )) && pad_l=0
        (( pad_r < 0 )) && pad_r=0

        printf '%b║%b' "$CYAN$BOLD" "$RESET"
        printf '%*s' "$pad_l" ''
        printf '%b%s%b' "$BOLD" "$line" "$RESET"
        printf '%*s' "$pad_r" ''
        printf '%b║%b\n' "$CYAN$BOLD" "$RESET"
    done

    printf '%b╚%s╝%b\n' "$CYAN$BOLD" "$(repeat_char '═' "$width")" "$RESET"
}

section_title() {
    echo
    printf '%b=== %s ===%b\n\n' "$BOLD$BLUE" "$1" "$RESET"
}

# ============================================================
#                    BASIC REQUIREMENTS
# ============================================================

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_err "Required command not found: $1"
        return 1
    fi
    return 0
}

check_sudo() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        SUDO=""
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        print_err "sudo is required for system-wide installation."
        return 1
    fi

    if ! sudo -v; then
        print_err "Administrator privileges could not be obtained."
        return 1
    fi
}

check_architecture() {
    case "$(uname -m)" in
        x86_64|amd64|aarch64|arm64)
            return 0
            ;;
        *)
            print_err "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac
}

version_is_newer() {
    local candidate="$1"
    local current="$2"

    [[ "$candidate" =~ ^[0-9]+([.][0-9]+)*$ ]] || return 1
    [[ "$current" =~ ^[0-9]+([.][0-9]+)*$ ]] || return 1

    [[ "$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n1)" == "$candidate" ]] \
        && [[ "$candidate" != "$current" ]]
}

# ============================================================
#                 DISTRIBUTION DETECTION
# ============================================================

detect_distro() {
    if [[ ! -r /etc/os-release ]]; then
        print_err "Could not read /etc/os-release."
        return 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    DISTRO_ID="${ID:-unknown}"
    DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
    local like="${ID_LIKE:-}"

    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop|neon|zorin|elementary|lubuntu|kubuntu|xubuntu|ubuntu-mate|budgie-remix)
            DISTRO_FAMILY="debian"
            ;;
        arch|manjaro|endeavouros|garuda|cachyos|arcolinux|artix)
            DISTRO_FAMILY="arch"
            ;;
        *)
            if [[ "$like" == *debian* || "$like" == *ubuntu* ]]; then
                DISTRO_FAMILY="debian"
            elif [[ "$like" == *arch* ]]; then
                DISTRO_FAMILY="arch"
            else
                print_err "Unsupported distribution: $DISTRO_ID"
                print_info "Supported families: Debian/Ubuntu-based and Arch-based."
                return 1
            fi
            ;;
    esac

    return 0
}

# ============================================================
#                       PACKAGE HELPERS
# ============================================================

is_installed() {
    local package="$1"

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
            | grep -q 'install ok installed'
    else
        pacman -Q "$package" >/dev/null 2>&1
    fi
}

apt_has_package() {
    apt-cache show "$1" >/dev/null 2>&1
}

pacman_has_package() {
    pacman -Si "$1" >/dev/null 2>&1
}

apt_update() {
    print_info "Refreshing APT package indexes..."

    if $SUDO apt update; then
        APT_SYNCED=true
        return 0
    fi

    print_err "APT failed to refresh its package indexes."
    return 1
}

ensure_apt_synced() {
    [[ "$DISTRO_FAMILY" == "debian" ]] || return 0
    [[ "$APT_SYNCED" == true ]] && return 0
    apt_update
}

install_apt_package() {
    local package="$1"
    local name="${2:-$package}"

    check_sudo || return 1

    [[ -n "$package" ]] || {
        print_err "No APT package was defined for $name."
        return 1
    }

    if is_installed "$package"; then
        print_ok "$name is already installed."
        return 0
    fi

    ensure_apt_synced || return 1

    if ! apt_has_package "$package"; then
        print_err "APT package not available: $package"
        return 1
    fi

    print_info "Installing $name..."

    if $SUDO apt install -y "$package"; then
        print_ok "$name installed."
        return 0
    fi

    print_err "Could not install $name."
    return 1
}

install_pacman_package() {
    local package="$1"
    local name="${2:-$package}"

    check_sudo || return 1

    [[ -n "$package" ]] || {
        print_err "No pacman package was defined for $name."
        return 1
    }

    if is_installed "$package"; then
        print_ok "$name is already installed."
        return 0
    fi

    if ! pacman_has_package "$package"; then
        print_err "Arch package not available: $package"
        return 1
    fi

    print_info "Installing $name..."

    if $SUDO pacman -S --needed --noconfirm "$package"; then
        print_ok "$name installed."
        return 0
    fi

    print_err "Could not install $name."
    return 1
}

install_aur_package() {
    local package="$1"
    local name="${2:-$package}"

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        print_err "Do not build or install AUR packages as root."
        print_info "Run Luxury as your normal user."
        return 1
    fi

    local helper
    helper="$(detect_aur_helper)" || {
        print_err "No AUR helper is installed."
        print_info "Open Categories -> AUR Helpers first."
        return 1
    }

    if "$helper" -Q "$package" >/dev/null 2>&1; then
        print_ok "$name is already installed."
        return 0
    fi

    print_info "Installing $name from AUR..."

    if "$helper" -S --needed --noconfirm "$package"; then
        print_ok "$name installed."
        return 0
    fi

    print_err "Could not install $name from AUR."
    return 1
}

detect_aur_helper() {
    if command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
    elif command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
    else
        AUR_HELPER=""
    fi

    [[ -n "$AUR_HELPER" ]] || return 1
    printf '%s' "$AUR_HELPER"
}

# ============================================================
#                    SELF INSTALL / UPDATE
# ============================================================

get_local_script_path() {
    if [[ -f "$0" ]]; then
        printf '%s' "$0"
        return 0
    fi
    return 1
}

download_remote_script() {
    local destination="$1"

    require_command curl || return 1

    # raw.githubusercontent.com sits behind a CDN that caches each exact
    # URL for a few minutes. A unique query string on every call forces a
    # cache miss so a version bump just pushed to the repo is picked up
    # immediately instead of possibly serving a stale copy.
    local cache_bust="$(date +%s)-$$-${RANDOM}"

    if curl -fLsS --connect-timeout 5 --max-time 15 \
        -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
        "${UPDATE_URL}?cb=${cache_bust}" -o "$destination"; then
        return 0
    fi

    print_err "Could not download Luxury Downloader from GitHub."
    return 1
}

extract_version_from_file() {
    local file="$1"
    sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$file" | head -n1
}

bootstrap_install() {
    require_command install || return 1
    check_sudo || return 1

    local source=""
    local temp=""
    local cleanup_temp=false

    if source="$(get_local_script_path 2>/dev/null)"; then
        :
    else
        temp="$(mktemp)"
        cleanup_temp=true
        download_remote_script "$temp" || {
            rm -f "$temp"
            return 1
        }
        source="$temp"
    fi

    local candidate_version
    candidate_version="$(extract_version_from_file "$source")"

    if [[ -z "$candidate_version" ]]; then
        print_err "The source script does not contain a valid VERSION."
        [[ "$cleanup_temp" == true ]] && rm -f "$temp"
        return 1
    fi

    if [[ -f "$INSTALL_PATH" ]]; then
        local installed_version
        installed_version="$(extract_version_from_file "$INSTALL_PATH")"

        if [[ "$installed_version" == "$candidate_version" && -n "$installed_version" ]]; then
            print_ok "Luxury Downloader v${installed_version} is already installed and up to date."
            [[ "$cleanup_temp" == true ]] && rm -f "$temp"
            return 0
        fi

        if [[ -n "$installed_version" ]] && ! version_is_newer "$candidate_version" "$installed_version"; then
            print_warn "Installed Luxury Downloader v${installed_version} is newer than the source v${candidate_version}."
            print_info "Nothing was changed."
            [[ "$cleanup_temp" == true ]] && rm -f "$temp"
            return 0
        fi

        if [[ -n "$installed_version" ]]; then
            print_info "Updating installed Luxury Downloader from v${installed_version} to v${candidate_version}..."
        else
            print_info "Replacing the existing Luxury Downloader installation with v${candidate_version}..."
        fi
    else
        print_info "Installing Luxury Downloader v${candidate_version} to ${INSTALL_PATH}..."
    fi

    if $SUDO install -m 0755 "$source" "$INSTALL_PATH"; then
        print_ok "Luxury Downloader v${candidate_version} installed."
        printf '\n'
        print_info "To start Luxury Downloader, type: luxury"
    else
        print_err "Could not install Luxury Downloader."
        [[ "$cleanup_temp" == true ]] && rm -f "$temp"
        return 1
    fi

    [[ "$cleanup_temp" == true ]] && rm -f "$temp"
    return 0
}

uninstall_self() {
    check_sudo || return 1

    if [[ ! -e "$INSTALL_PATH" ]]; then
        print_warn "Luxury Downloader is not installed at ${INSTALL_PATH}."
        return 0
    fi

    printf 'Remove Luxury Downloader from %s? [y/N]: ' "$INSTALL_PATH"
    local answer
    read -r answer || answer=""

    case "${answer,,}" in
        y|yes)
            if $SUDO rm -f "$INSTALL_PATH"; then
                print_ok "Luxury Downloader has been uninstalled."
                return 0
            fi
            print_err "Could not remove $INSTALL_PATH."
            return 1
            ;;
        *)
            print_info "Uninstall cancelled."
            ;;
    esac
}

apply_update() {
    local source="$1"
    local version="$2"

    check_sudo || return 1
    require_command install || return 1

    if $SUDO install -m 0755 "$source" "$INSTALL_PATH"; then
        print_ok "Luxury Downloader updated to v${version}."
        return 0
    fi

    print_err "Could not install the updated script."
    return 1
}

update_self() {
    if [[ ! -f "$INSTALL_PATH" ]]; then
        print_warn "Luxury Downloader is not installed."
        print_info "Install Luxury with the official one-line setup command from the README."
        return 1
    fi

    require_command curl || return 1

    local temp
    temp="$(mktemp)"

    if ! download_remote_script "$temp"; then
        rm -f "$temp"
        return 1
    fi

    local remote_version
    remote_version="$(extract_version_from_file "$temp")"

    if [[ -z "$remote_version" ]]; then
        print_err "Remote VERSION could not be read."
        rm -f "$temp"
        return 1
    fi

    local installed_version
    installed_version="$(extract_version_from_file "$INSTALL_PATH")"

    if [[ -n "$installed_version" ]]; then
        if [[ "$remote_version" == "$installed_version" ]]; then
            print_ok "Luxury Downloader is already up to date (v${installed_version})."
            rm -f "$temp"
            return 0
        fi

        if ! version_is_newer "$remote_version" "$installed_version"; then
            print_warn "Repository version v${remote_version} is not newer than the installed v${installed_version}."
            print_info "Downgrade skipped."
            rm -f "$temp"
            return 0
        fi

        print_info "Updating from v${installed_version} to v${remote_version}..."
    else
        print_warn "The installed script has no readable VERSION. Replacing it with v${remote_version}."
    fi

    apply_update "$temp" "$remote_version"
    local result=$?
    rm -f "$temp"
    return "$result"
}

check_for_updates() {
    [[ -f "$INSTALL_PATH" ]] || return 0

    require_command curl >/dev/null 2>&1 || {
        print_warn "curl is not installed. Update check skipped."
        return 0
    }

    local installed_version
    installed_version="$(extract_version_from_file "$INSTALL_PATH")"

    if [[ -z "$installed_version" ]]; then
        installed_version="$VERSION"
    fi

    print_info "Checking for Luxury Downloader updates..."

    # Downloaded once here and reused below if the user picks [U], so the
    # version we compare against is exactly the file we'd install — no
    # second fetch that could land on a different CDN cache state.
    local temp
    temp="$(mktemp)"

    if ! download_remote_script "$temp" 2>/dev/null; then
        print_warn "Could not check for Luxury Downloader updates right now. Continuing."
        rm -f "$temp"
        return 0
    fi

    local remote_version
    remote_version="$(extract_version_from_file "$temp")"

    if [[ -z "$remote_version" ]]; then
        print_warn "Could not check for Luxury Downloader updates right now. Continuing."
        rm -f "$temp"
        return 0
    fi

    if [[ "$remote_version" == "$installed_version" ]]; then
        print_ok "Luxury Downloader is up to date (v${installed_version})."
        rm -f "$temp"
        return 0
    fi

    if ! version_is_newer "$remote_version" "$installed_version"; then
        print_ok "Installed Luxury Downloader v${installed_version} is newer than the repository version v${remote_version}."
        rm -f "$temp"
        return 0
    fi

    printf '\n%bNew update found: v%s%b\n' "$YELLOW$BOLD" "$remote_version" "$RESET"
    printf 'Current version: v%s\n\n' "$installed_version"
    printf '[U] Update\n'
    printf '[S] Skip\n\n'
    printf 'Choose an option: '

    local answer
    read -r answer || answer=""

    case "${answer,,}" in
        u|update)
            if apply_update "$temp" "$remote_version"; then
                rm -f "$temp"
                print_info "Restarting Luxury Downloader..."
                if [[ -x "$INSTALL_PATH" ]]; then
                    exec "$INSTALL_PATH"
                fi
            else
                rm -f "$temp"
            fi
            ;;
        *)
            print_info "Update skipped."
            rm -f "$temp"
            ;;
    esac
}

# ============================================================
#                     BRAVE ORIGIN
# ============================================================

install_brave_origin_debian() {
    if command -v brave-origin >/dev/null 2>&1; then
        print_ok "Brave Origin is already installed."
        return 0
    fi

    require_command curl || return 1

    print_info "Installing Brave Origin using Brave's official installer..."

    # Official Brave Origin Linux installer.
    if curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh; then
        print_ok "Brave Origin installed."
        return 0
    fi

    print_err "Brave Origin installation failed."
    return 1
}

install_brave_origin_arch() {
    install_aur_package "brave-origin-bin" "Brave Origin"
}

# ============================================================
#                         LIBREWOLF
# ============================================================

install_librewolf_debian() {
    if command -v librewolf >/dev/null 2>&1; then
        print_ok "LibreWolf is already installed."
        return 0
    fi

    install_apt_package "extrepo" "extrepo" || return 1

    print_info "Enabling the official LibreWolf repository..."

    if ! $SUDO extrepo enable librewolf; then
        # extrepo returns non-zero if it is already enabled on some setups.
        if ! grep -Rqs 'repo.librewolf.net' \
            /etc/apt/sources.list /etc/apt/sources.list.d /etc/extrepo \
            2>/dev/null; then
            print_err "Could not enable the LibreWolf repository."
            return 1
        fi
    fi

    $SUDO extrepo update librewolf >/dev/null 2>&1 || true

    apt_update || return 1
    install_apt_package "librewolf" "LibreWolf"
}

install_librewolf_arch() {
    install_pacman_package "librewolf" "LibreWolf"
}

# ============================================================
#                   LOCALSEND + RETROARCH
# ============================================================

install_localsend_debian() {
    # Official source: https://localsend.org/download
    # LocalSend's official Linux download page currently lists Flathub as the
    # distro-independent package-manager route, including the official app ID.
    if command -v flatpak >/dev/null 2>&1 && flatpak info "org.localsend.localsend_app" >/dev/null 2>&1; then
        print_ok "LocalSend is already installed."
        return 0
    fi

    install_flatpak || return 1
    ensure_flathub || return 1

    print_info "Installing LocalSend from the official Flathub package..."
    if flatpak install -y flathub "org.localsend.localsend_app"; then
        print_ok "LocalSend installed."
        return 0
    fi

    print_err "LocalSend installation failed."
    return 1
}

install_localsend_arch() {
    if ! detect_aur_helper >/dev/null 2>&1; then
        print_info "No AUR helper detected. Installing Yay automatically..."
        install_aur_helper yay || return 1
    fi

    install_aur_package "localsend-bin" "LocalSend"
}

add_libretro_ppa() {
    # Official RetroArch Linux docs: https://docs.libretro.com/guides/install-gnu/
    # Libretro Stable PPA: https://launchpad.net/~libretro/+archive/ubuntu/stable
    [[ "$DISTRO_FAMILY" == "debian" ]] || return 1

    # The Libretro Team documents this PPA for Ubuntu and Ubuntu-based systems.
    # Plain Debian falls back to its normal APT repositories below.
    case "$DISTRO_ID" in
        ubuntu|linuxmint|pop|neon|zorin|elementary|lubuntu|kubuntu|xubuntu|ubuntu-mate|budgie-remix)
            ;;
        *)
            return 0
            ;;
    esac

    install_apt_package "software-properties-common" "Software properties" || return 1
    require_command add-apt-repository || return 1

    if ! grep -Rqs '^deb .*ppa\.launchpadcontent\.net/libretro/stable\|^deb .*ppa:libretro/stable' \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        print_info "Adding the official Libretro Stable PPA..."
        if ! $SUDO add-apt-repository --yes --no-update ppa:libretro/stable; then
            print_err "Could not add the Libretro Stable PPA."
            return 1
        fi
    fi

    apt_update
}

configure_retroarch_system_core_dir() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/retroarch/retroarch.cfg"
    mkdir -p "$(dirname "$cfg")" 2>/dev/null || return 0

    if [[ -f "$cfg" ]]; then
        if grep -qE '^core_directory[[:space:]]*=' "$cfg"; then
            sed -i 's|^core_directory[[:space:]]*=.*|core_directory = "/usr/lib/libretro"|' "$cfg" || true
        else
            printf '\ncore_directory = "/usr/lib/libretro"\n' >> "$cfg"
        fi
    else
        printf 'core_directory = "/usr/lib/libretro"\n' > "$cfg"
    fi
}

install_retroarch_debian() {
    local installed_cores=0
    local package

    add_libretro_ppa || return 1

    install_apt_package "retroarch" "RetroArch" || return 1

    # Ubuntu/Libretro use these package names for the core variants currently
    # available through APT. We test availability before installation so a
    # distro snapshot missing one optional variant does not abort the whole job.
    local -a cores=(
        "libretro-nestopia"
        "libretro-mesen"
        "libretro-snes9x"
        "libretro-bsnes-mercury-accuracy"
        "libretro-bsnes-mercury-balanced"
        "libretro-bsnes-mercury-performance"
        "libretro-mgba"
        "libretro-gambatte"
        "libretro-sameboy"
        "libretro-desmume"
        "libretro-melonds"
        "libretro-mupen64plus-next"
        "libretro-parallel-n64"
        "libretro-genesisplusgx"
        "libretro-picodrive"
    )

    print_info "Installing the main Libretro cores and variants..."
    for package in "${cores[@]}"; do
        if apt_has_package "$package"; then
            if install_apt_package "$package" "$package"; then
                installed_cores=$((installed_cores + 1))
            fi
        else
            print_warn "Core package not available in this APT source: $package (skipped)."
        fi
    done

    configure_retroarch_system_core_dir

    if (( installed_cores == 0 )); then
        print_err "RetroArch was installed, but no requested Libretro core package was available."
        print_info "Open RetroArch -> Online Updater -> Core Downloader to add cores supported by this build."
        return 1
    fi

    print_ok "RetroArch and $installed_cores core package(s) installed."
    return 0
}

install_retroarch_arch() {
    # Official Arch package group: https://archlinux.org/groups/x86_64/libretro/
    local package
    local installed_cores=0

    install_pacman_package "retroarch" "RetroArch" || return 1

    # Arch Linux ships these cores in the official Extra/libretro group.
    local -a cores=(
        "libretro-nestopia"
        "libretro-mesen"
        "libretro-snes9x"
        "libretro-mesen-s"
        "libretro-bsnes"
        "libretro-bsnes-hd"
        "libretro-mgba"
        "libretro-gambatte"
        "libretro-sameboy"
        "libretro-desmume"
        "libretro-melonds"
        "libretro-mupen64plus-next"
        "libretro-parallel-n64"
        "libretro-genesis-plus-gx"
        "libretro-picodrive"
        "libretro-blastem"
    )

    print_info "Installing the main Libretro cores and variants..."
    for package in "${cores[@]}"; do
        if pacman_has_package "$package"; then
            if install_pacman_package "$package" "$package"; then
                installed_cores=$((installed_cores + 1))
            fi
        else
            print_warn "Core package not available in the configured Arch repositories: $package (skipped)."
        fi
    done

    configure_retroarch_system_core_dir

    if (( installed_cores == 0 )); then
        print_err "RetroArch was installed, but no requested Libretro core package was available."
        return 1
    fi

    print_ok "RetroArch and $installed_cores core package(s) installed."
    return 0
}

# ============================================================
#                         VENTOY
# ============================================================
# Multiboot USB creation tool. Has no APT package anywhere (not
# in Debian, Ubuntu, or any PPA); on Arch it's AUR-only. Note:
# the ArchWiki flags that upstream has stayed unresponsive about
# the toolchain behind its precompiled bits, which is why this
# uses the AUR's source-build "ventoy" package rather than the
# prebuilt "ventoy-bin" one.

install_ventoy_arch() {
    install_aur_package "ventoy" "Ventoy"
}

install_ventoy_debian() {
    if [[ -x /opt/ventoy/Ventoy2Disk.sh ]] || command -v ventoy2disk >/dev/null 2>&1; then
        print_ok "Ventoy is already installed."
        return 0
    fi

    case "$(uname -m)" in
        x86_64|amd64|aarch64|arm64|mips64) ;;
        *)
            print_err "No official Ventoy Linux build for this architecture: $(uname -m)"
            return 1
            ;;
    esac

    require_command curl || return 1
    require_command tar || return 1
    check_sudo || return 1

    print_info "Ventoy has no APT package; downloading the official release from GitHub..."

    local tag version download_url tmpdir extracted
    tag="$(curl -fsSL --connect-timeout 5 --max-time 10 \
        "https://api.github.com/repos/ventoy/Ventoy/releases/latest" 2>/dev/null \
        | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
        | sed -E 's/.*"([^"]+)"$/\1/')"

    if [[ -z "$tag" ]]; then
        print_err "Could not determine the latest Ventoy release from GitHub."
        return 1
    fi

    version="${tag#v}"
    # A single "linux" tarball covers x86_64/i386/aarch64/mips64; Ventoy
    # does not publish separate per-architecture Linux archives.
    download_url="https://github.com/ventoy/Ventoy/releases/download/${tag}/ventoy-${version}-linux.tar.gz"

    tmpdir="$(mktemp -d)" || { print_err "Could not create a temporary directory."; return 1; }

    print_info "Downloading Ventoy ${version}..."
    if ! curl -fLsS --connect-timeout 5 --max-time 60 "$download_url" -o "$tmpdir/ventoy.tar.gz"; then
        print_err "Could not download Ventoy ${version}."
        rm -rf "$tmpdir"
        return 1
    fi

    if ! tar -xzf "$tmpdir/ventoy.tar.gz" -C "$tmpdir"; then
        print_err "Could not extract the Ventoy archive."
        rm -rf "$tmpdir"
        return 1
    fi

    extracted="$(find "$tmpdir" -maxdepth 1 -type d -name 'ventoy-*' | head -n1)"

    if [[ -z "$extracted" ]]; then
        print_err "Unexpected Ventoy archive layout."
        rm -rf "$tmpdir"
        return 1
    fi

    $SUDO rm -rf /opt/ventoy
    if ! $SUDO mkdir -p /opt/ventoy || ! $SUDO cp -r "$extracted"/. /opt/ventoy/; then
        print_err "Could not install Ventoy to /opt/ventoy."
        rm -rf "$tmpdir"
        return 1
    fi

    $SUDO chmod +x /opt/ventoy/*.sh 2>/dev/null || true
    [[ -f /opt/ventoy/Ventoy2Disk.sh ]] && $SUDO ln -sf /opt/ventoy/Ventoy2Disk.sh /usr/local/bin/ventoy2disk
    [[ -f /opt/ventoy/VentoyGUI.sh ]] && $SUDO ln -sf /opt/ventoy/VentoyGUI.sh /usr/local/bin/ventoygui

    rm -rf "$tmpdir"
    print_ok "Ventoy ${version} installed to /opt/ventoy."
    print_info "Run 'sudo ventoy2disk' (CLI) or 'ventoygui' (GUI) to write it to a USB drive."
    return 0
}

# ============================================================
#                      TASK MANAGER OG (TMOG)
# ============================================================
# Native cross-platform task manager by David Plummer (creator
# of the original Windows Task Manager). Currently in beta; the
# Linux build is a Qt 6 app. Upstream does not permit
# redistributing the binary, so both paths below always fetch
# it straight from tmog.org, same as its AUR packaging does.

install_tmog_debian() {
    if command -v tmog-task-manager >/dev/null 2>&1 || command -v tmog >/dev/null 2>&1; then
        print_ok "Task Manager OG is already installed."
        return 0
    fi

    if [[ "$(uname -m)" != "x86_64" && "$(uname -m)" != "amd64" ]]; then
        print_err "Task Manager OG's Linux build is x86_64-only."
        return 1
    fi

    require_command curl || return 1
    check_sudo || return 1

    print_info "Downloading Task Manager OG (beta) from tmog.org..."

    local tmpdeb
    tmpdeb="$(mktemp --suffix=.deb)" || { print_err "Could not create a temporary file."; return 1; }

    if ! curl -fLsS --connect-timeout 5 --max-time 60 \
        "https://tmog.org/downloads/TMOG-Task-Manager-Linux-x86_64.deb" -o "$tmpdeb"; then
        print_err "Could not download Task Manager OG."
        rm -f "$tmpdeb"
        return 1
    fi

    ensure_apt_synced
    print_info "Installing Task Manager OG (this pulls in Qt 6 if it's missing)..."

    if $SUDO apt install -y "$tmpdeb"; then
        print_ok "Task Manager OG installed."
        rm -f "$tmpdeb"
        return 0
    fi

    print_err "Could not install Task Manager OG."
    rm -f "$tmpdeb"
    return 1
}

install_tmog_arch() {
    install_aur_package "tmog-bin" "Task Manager OG"
}

# ============================================================
#                       MAIN APP REGISTRY
# ============================================================

APP_ORDER=(brave thunderbird librewolf vlc libreoffice mpv localsend retroarch ventoy 7zip unrar tmog)

declare -A APP_NAME=(
    [brave]="Brave Origin"
    [thunderbird]="Thunderbird"
    [librewolf]="LibreWolf"
    [vlc]="VLC"
    [libreoffice]="LibreOffice"
    [mpv]="MPV"
    [localsend]="LocalSend"
    [retroarch]="RetroArch + Cores"
    [ventoy]="Ventoy"
    [7zip]="7-Zip"
    [unrar]="unrar (RAR extractor)"
    [tmog]="Task Manager OG (beta)"
)

declare -A APP_PKG_DEBIAN=(
    [thunderbird]="thunderbird"
    [vlc]="vlc"
    [libreoffice]="libreoffice"
    [mpv]="mpv"
    [7zip]="7zip"
    [unrar]="unrar"
)

declare -A APP_PKG_ARCH=(
    [thunderbird]="thunderbird"
    [vlc]="vlc"
    [libreoffice]="libreoffice-still"
    [mpv]="mpv"
    [7zip]="7zip"
    [unrar]="unrar"
)

declare -A APP_CUSTOM_DEBIAN=(
    [brave]="install_brave_origin_debian"
    [librewolf]="install_librewolf_debian"
    [localsend]="install_localsend_debian"
    [retroarch]="install_retroarch_debian"
    [ventoy]="install_ventoy_debian"
    [tmog]="install_tmog_debian"
)

declare -A APP_CUSTOM_ARCH=(
    [brave]="install_brave_origin_arch"
    [librewolf]="install_librewolf_arch"
    [localsend]="install_localsend_arch"
    [retroarch]="install_retroarch_arch"
    [ventoy]="install_ventoy_arch"
    [tmog]="install_tmog_arch"
)

install_app_by_slug() {
    local slug="$1"
    local name="${APP_NAME[$slug]:-$slug}"
    local custom_fn=""

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        custom_fn="${APP_CUSTOM_DEBIAN[$slug]:-}"
        if [[ -n "$custom_fn" ]]; then
            "$custom_fn"
        else
            install_apt_package "${APP_PKG_DEBIAN[$slug]:-}" "$name"
        fi
    else
        custom_fn="${APP_CUSTOM_ARCH[$slug]:-}"
        if [[ -n "$custom_fn" ]]; then
            "$custom_fn"
        else
            install_pacman_package "${APP_PKG_ARCH[$slug]:-}" "$name"
        fi
    fi
}

# ============================================================
#                      AUR HELPERS
# ============================================================

install_aur_helper() {
    local helper="$1"

    [[ "$DISTRO_FAMILY" == "arch" ]] || {
        print_warn "AUR helpers are available only on Arch-based systems."
        return 1
    }

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        print_err "Do not build AUR packages as root."
        print_info "Run Luxury as your normal user."
        return 1
    fi

    check_sudo || return 1

    if command -v "$helper" >/dev/null 2>&1; then
        print_ok "$helper is already installed."
        AUR_HELPER="$helper"
        return 0
    fi

    print_info "Installing build requirements..."
    $SUDO pacman -S --needed --noconfirm git base-devel || {
        print_err "Could not install AUR build requirements."
        return 1
    }

    local tmpdir
    tmpdir="$(mktemp -d)"

    case "$helper" in
        yay)
            git clone https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin" || {
                rm -rf "$tmpdir"
                print_err "Could not clone yay-bin from AUR."
                return 1
            }
            ;;
        paru)
            git clone https://aur.archlinux.org/paru-bin.git "$tmpdir/paru-bin" || {
                rm -rf "$tmpdir"
                print_err "Could not clone paru-bin from AUR."
                return 1
            }
            ;;
        *)
            rm -rf "$tmpdir"
            print_err "Unsupported AUR helper: $helper"
            return 1
            ;;
    esac

    # makepkg should run as the invoking normal user, not root. id -un is
    # used as the fallback (not a bare $USER) because $USER isn't always
    # exported — e.g. some non-interactive invocations — and referencing
    # an unset $USER here would crash the whole script under `set -u`.
    local build_user="${SUDO_USER:-$(id -un)}"
    chown -R "$build_user" "$tmpdir" 2>/dev/null || true

    print_info "Building $helper..."

    if sudo -u "$build_user" bash -lc \
        "cd '$tmpdir/${helper}-bin' && makepkg -si --noconfirm"; then
        print_ok "$helper installed."
        AUR_HELPER="$helper"
        rm -rf "$tmpdir"
        return 0
    fi

    rm -rf "$tmpdir"
    print_err "Could not build/install $helper."
    return 1
}

show_aur_helpers_page() {
    while true; do
        clear 2>/dev/null || true
        print_box "AUR HELPERS"
        echo

        local current="None"
        if detect_aur_helper >/dev/null 2>&1; then
            current="$AUR_HELPER"
        fi

        printf '  Current helper: %s\n\n' "$current"
        echo "  [1] Install / use Yay"
        echo "  [2] Install / use Paru"
        echo "  [3] Back"
        echo

        local choice
        read -r -p "Choose an option: " choice || choice=""

        case "$choice" in
            1)
                install_aur_helper yay || true
                press_enter
                ;;
            2)
                install_aur_helper paru || true
                press_enter
                ;;
            3)
                return 0
                ;;
            *)
                print_warn "Invalid option."
                ;;
        esac
    done
}

# ============================================================
#                       DRIVERS
# ============================================================

install_nvidia_arch() {
    install_pacman_package "nvidia-open" "NVIDIA Open Driver"
}

install_nvidia_dkms_arch() {
    install_pacman_package "nvidia-open-dkms" "NVIDIA Open DKMS Driver"
}

# Since 2025-12-20 Arch's official nvidia/nvidia-dkms packages were replaced
# by nvidia-open/nvidia-open-dkms. The open kernel modules require the GPU
# System Processor (GSP), introduced with Turing, so they cannot run on
# Maxwell (GTX 900) or Pascal (GTX 10xx) or older cards. Those cards need
# the community-maintained legacy branch from the AUR instead.
install_nvidia_legacy_arch() {
    print_warn "For GTX 900 (Maxwell) / GTX 10xx (Pascal) and older cards only."
    print_info "If the official nvidia, nvidia-lts or nvidia-dkms packages are installed, remove them first to avoid conflicts."

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        print_err "Do not build AUR packages as root."
        print_info "Run Luxury as your normal user."
        return 1
    fi

    if ! detect_aur_helper >/dev/null 2>&1; then
        print_info "No AUR helper detected. Installing Yay automatically..."
        install_aur_helper yay || return 1
    fi

    install_aur_package "nvidia-580xx-dkms" "NVIDIA Legacy Driver (580xx)"
}

install_amd_gpu_arch() {
    ensure_arch_packages mesa vulkan-radeon linux-firmware
}

install_amd_cpu_arch() {
    if [[ "$(uname -m)" != "x86_64" ]]; then
        print_warn "AMD CPU microcode package is only applicable to x86_64 systems."
        return 0
    fi
    install_pacman_package "amd-ucode" "AMD CPU Microcode"
}

install_intel_gpu_arch() {
    ensure_arch_packages mesa vulkan-intel linux-firmware
}

install_intel_cpu_arch() {
    if [[ "$(uname -m)" != "x86_64" ]]; then
        print_warn "Intel CPU microcode package is only applicable to x86_64 systems."
        return 0
    fi
    install_pacman_package "intel-ucode" "Intel CPU Microcode"
}

ensure_arch_packages() {
    local package
    for package in "$@"; do
        install_pacman_package "$package" "$package" || return 1
    done
}

ubuntu_has_ubuntu_drivers() {
    command -v ubuntu-drivers >/dev/null 2>&1
}

install_nvidia_debian() {
    if ! ubuntu_has_ubuntu_drivers; then
        if ! install_apt_package "ubuntu-drivers-common" "Ubuntu Drivers"; then
            print_err "Automatic NVIDIA driver support is not available on this Debian-based distribution."
            return 1
        fi
    fi

    print_info "Installing the recommended NVIDIA driver..."
    if $SUDO ubuntu-drivers install; then
        print_ok "Recommended NVIDIA driver installed."
        return 0
    fi

    print_err "NVIDIA driver installation failed."
    return 1
}

install_amd_gpu_debian() {
    install_apt_package "mesa-vulkan-drivers" "Mesa Vulkan Drivers" || return 1
    install_apt_package "linux-firmware" "Linux Firmware"
}

install_amd_cpu_debian() {
    if [[ "$(uname -m)" != "x86_64" ]]; then
        print_warn "AMD CPU microcode package is only applicable to x86_64 systems."
        return 0
    fi
    install_apt_package "amd64-microcode" "AMD CPU Microcode"
}

install_intel_gpu_debian() {
    install_apt_package "mesa-vulkan-drivers" "Mesa Vulkan Drivers" || return 1
    install_apt_package "linux-firmware" "Linux Firmware"
}

install_intel_cpu_debian() {
    if [[ "$(uname -m)" != "x86_64" ]]; then
        print_warn "Intel CPU microcode package is only applicable to x86_64 systems."
        return 0
    fi
    install_apt_package "intel-microcode" "Intel CPU Microcode"
}

install_firmware_debian() {
    install_apt_package "linux-firmware" "Linux Firmware"
}

install_firmware_arch() {
    install_pacman_package "linux-firmware" "Linux Firmware"
}

show_drivers_page() {
    while true; do
        clear 2>/dev/null || true
        print_box "DRIVERS & FIRMWARE"
        echo

        if [[ "$DISTRO_FAMILY" == "arch" ]]; then
            echo "  [1] NVIDIA Open (Turing / RTX, GTX 16xx and newer)"
            echo "  [2] NVIDIA Open + DKMS (Turing / RTX, GTX 16xx and newer)"
            echo "  [3] NVIDIA Legacy (GTX 900 Maxwell / GTX 10xx Pascal and older)"
            echo "  [4] AMD GPU"
            echo "  [5] AMD CPU Microcode"
            echo "  [6] Intel GPU"
            echo "  [7] Intel CPU Microcode"
            echo "  [8] Firmware"
        else
            echo "  [1] NVIDIA (recommended Ubuntu driver)"
            echo "  [2] AMD GPU"
            echo "  [3] AMD CPU Microcode"
            echo "  [4] Intel GPU"
            echo "  [5] Intel CPU Microcode"
            echo "  [6] Firmware"
        fi

        echo "  [0] Back"
        echo

        local choice
        read -r -p "Choose an option: " choice || choice=""

        if [[ "$DISTRO_FAMILY" == "arch" ]]; then
            case "$choice" in
                1) install_nvidia_arch || true; press_enter ;;
                2) install_nvidia_dkms_arch || true; press_enter ;;
                3) install_nvidia_legacy_arch || true; press_enter ;;
                4) install_amd_gpu_arch || true; press_enter ;;
                5) install_amd_cpu_arch || true; press_enter ;;
                6) install_intel_gpu_arch || true; press_enter ;;
                7) install_intel_cpu_arch || true; press_enter ;;
                8) install_firmware_arch || true; press_enter ;;
                0) return 0 ;;
                *) print_warn "Invalid option." ;;
            esac
        else
            case "$choice" in
                1) install_nvidia_debian || true; press_enter ;;
                2) install_amd_gpu_debian || true; press_enter ;;
                3) install_amd_cpu_debian || true; press_enter ;;
                4) install_intel_gpu_debian || true; press_enter ;;
                5) install_intel_cpu_debian || true; press_enter ;;
                6) install_firmware_debian || true; press_enter ;;
                0) return 0 ;;
                *) print_warn "Invalid option." ;;
            esac
        fi
    done
}

# ============================================================
#                   TERMINAL UTILITIES
# ============================================================

install_peaclock_debian() {
    if command -v peaclock >/dev/null 2>&1; then
        print_ok "Peaclock is already installed."
        return 0
    fi

    print_info "Peaclock is not provided by the standard Ubuntu 26.04 repositories."
    print_info "Building the current upstream release from source..."

    install_apt_package "git" "Git" || return 1
    install_apt_package "cmake" "CMake" || return 1
    install_apt_package "build-essential" "Build tools" || return 1
    install_apt_package "libicu-dev" "ICU development files" || return 1
    install_apt_package "libpthread-stubs0-dev" "POSIX thread stubs" || return 1

    local tmpdir
    tmpdir="$(mktemp -d)"

    if ! git clone --depth 1 https://github.com/octobanana/peaclock.git "$tmpdir/peaclock"; then
        rm -rf "$tmpdir"
        print_err "Could not clone Peaclock."
        return 1
    fi

    if ! (
        cd "$tmpdir/peaclock" &&
        ./RUNME.sh build &&
        ./RUNME.sh install
    ); then
        rm -rf "$tmpdir"
        print_err "Peaclock build/install failed."
        return 1
    fi

    rm -rf "$tmpdir"
    print_ok "Peaclock installed."
    return 0
}

install_peaclock_arch() {
    if pacman_has_package "peaclock"; then
        install_pacman_package "peaclock" "Peaclock"
    else
        install_aur_package "peaclock" "Peaclock"
    fi
}

# lavat: terminal lava-lamp simulation.
# Upstream documents a Unix-like system, a C compiler and make,
# and installs with "sudo make install".
install_lavat() {
    if command -v lavat >/dev/null 2>&1; then
        print_ok "lavat is already installed."
        return 0
    fi

    check_sudo || return 1

    print_info "Installing lavat from the official upstream repository..."

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        install_apt_package "git" "Git" || return 1
        install_apt_package "build-essential" "Build tools" || return 1
    else
        install_pacman_package "git" "Git" || return 1
        install_pacman_package "base-devel" "Build tools" || return 1
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"

    if ! git clone --depth 1 https://github.com/AngelJumbo/lavat "$tmpdir/lavat"; then
        rm -rf "$tmpdir"
        print_err "Could not clone lavat."
        return 1
    fi

    if ! (cd "$tmpdir/lavat" && $SUDO make install); then
        rm -rf "$tmpdir"
        print_err "lavat installation failed."
        return 1
    fi

    rm -rf "$tmpdir"
    print_ok "lavat installed."
    return 0
}

UTIL_ORDER=(cmatrix cava lavat peaclock fastfetch sl btop htop)

declare -A UTIL_NAME=(
    [cmatrix]="CMatrix"
    [cava]="CAVA"
    [lavat]="lavat"
    [peaclock]="Peaclock"
    [fastfetch]="Fastfetch"
    [sl]="sl (Steam Locomotive)"
    [btop]="btop"
    [htop]="htop"
)

declare -A UTIL_APT=(
    [cmatrix]="cmatrix"
    [cava]="cava"
    [fastfetch]="fastfetch"
    [sl]="sl"
    [btop]="btop"
    [htop]="htop"
)

declare -A UTIL_PACMAN=(
    [cmatrix]="cmatrix"
    [cava]="cava"
    [fastfetch]="fastfetch"
    [sl]="sl"
    [btop]="btop"
    [htop]="htop"
)

install_utility() {
    local slug="$1"
    local name="${UTIL_NAME[$slug]:-$slug}"

    if [[ "$slug" == "lavat" ]]; then
        install_lavat
        return $?
    fi

    if [[ "$slug" == "peaclock" ]]; then
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            install_peaclock_debian
        else
            install_peaclock_arch
        fi
        return $?
    fi

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        install_apt_package "${UTIL_APT[$slug]}" "$name"
    else
        if pacman_has_package "${UTIL_PACMAN[$slug]}"; then
            install_pacman_package "${UTIL_PACMAN[$slug]}" "$name"
        else
            print_err "Package not available in the configured Arch repositories: ${UTIL_PACMAN[$slug]}"
            return 1
        fi
    fi
}

show_utilities_page() {
    while true; do
        clear 2>/dev/null || true
        print_box "TERMINAL UTILITIES"
        echo

        local i=1
        local slug
        for slug in "${UTIL_ORDER[@]}"; do
            printf '  [%d] %s\n' "$i" "${UTIL_NAME[$slug]}"
            ((i++))
        done

        echo "  [0] Back"
        echo

        local choice
        read -r -p "Choose an option: " choice || choice=""

        if [[ "$choice" == "0" ]]; then
            return 0
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#UTIL_ORDER[@]} )); then
            local selected="${UTIL_ORDER[$((choice - 1))]}"
            install_utility "$selected" || true
            press_enter
        else
            print_warn "Invalid option."
        fi
    done
}

# ============================================================
#                         BAZAAR
# ============================================================

install_flatpak() {
    if command -v flatpak >/dev/null 2>&1; then
        return 0
    fi

    print_info "Flatpak is not installed. Installing it..."

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        install_apt_package "flatpak" "Flatpak"
    else
        install_pacman_package "flatpak" "Flatpak"
    fi
}

ensure_flathub() {
    command -v flatpak >/dev/null 2>&1 || return 1

    if flatpak remote-list --columns=name 2>/dev/null | grep -Fxq "flathub"; then
        return 0
    fi

    print_info "Adding the official Flathub remote..."

    if flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
        return 0
    fi

    print_err "Could not add Flathub."
    return 1
}

install_bazaar_native() {
    if command -v bazaar >/dev/null 2>&1; then
        print_ok "Bazaar is already installed."
        return 0
    fi

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        ensure_apt_synced
        apt_has_package "bazaar" || return 1

        # Ubuntu 26.04+ ships a native APT package (universe) and Bazaar's
        # own developers now recommend it over the Flatpak build on that
        # release: recent Ubuntu tightened the sandboxing rules that
        # Bazaar's Flatpak needs (the fusermount wrapper), which broke
        # Flatpak installs from within it. Older Ubuntu/Debian/Mint don't
        # have this package yet, so this simply falls through to Flatpak.
        print_info "Using the native APT package (recommended by Bazaar upstream on this Ubuntu release)."
        install_apt_package "bazaar" "Bazaar (App Store)"
    else
        pacman_has_package "bazaar" || return 1
        install_pacman_package "bazaar" "Bazaar (App Store)"
    fi
}

install_bazaar() {
    if install_bazaar_native; then
        return 0
    fi

    if ! install_flatpak; then
        return 1
    fi

    ensure_flathub || return 1

    if flatpak info "$BAZAAR_FLATPAK_ID" >/dev/null 2>&1; then
        print_ok "Bazaar is already installed."
        return 0
    fi

    print_info "Installing Bazaar from Flathub..."

    if flatpak install -y flathub "$BAZAAR_FLATPAK_ID"; then
        print_ok "Bazaar installed."
        return 0
    fi

    print_err "Could not install Bazaar."
    return 1
}

launch_bazaar() {
    if command -v bazaar >/dev/null 2>&1; then
        print_info "Launching Bazaar..."
        bazaar >/dev/null 2>&1 &
        return 0
    fi

    if ! command -v flatpak >/dev/null 2>&1; then
        print_warn "Flatpak is not installed."
        install_bazaar || return 1
    elif ! flatpak info "$BAZAAR_FLATPAK_ID" >/dev/null 2>&1; then
        install_bazaar || return 1
    fi

    if command -v bazaar >/dev/null 2>&1; then
        print_info "Launching Bazaar..."
        bazaar >/dev/null 2>&1 &
        return 0
    fi

    print_info "Launching Bazaar..."
    flatpak run "$BAZAAR_FLATPAK_ID" >/dev/null 2>&1 &
}

# ============================================================
#                    SYSTEM UPDATE
# ============================================================

update_system() {
    section_title "SYSTEM UPDATE"
    check_sudo || return 1

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        apt_update || return 1

        if $SUDO apt upgrade -y; then
            print_ok "System updated."
            return 0
        fi

        print_err "System update finished with errors."
        return 1
    fi

    # Always synchronize and upgrade together on Arch.
    if $SUDO pacman -Syu --noconfirm; then
        print_ok "System updated."
        return 0
    fi

    print_err "System update finished with errors."
    return 1
}

# ============================================================
#                      INSTALL ALL
# ============================================================

install_all() {
    section_title "INSTALL ALL APPS"

    local failed=0
    local slug

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        ensure_apt_synced || return 1
    fi

    for slug in "${APP_ORDER[@]}"; do
        echo
        if ! install_app_by_slug "$slug"; then
            failed=1
        fi
    done

    echo
    if (( failed == 0 )); then
        print_ok "All applications completed successfully."
        return 0
    fi

    print_warn "One or more applications failed."
    return 1
}

# ============================================================
#                       MENUS / PAGES
# ============================================================

show_categories_page() {
    while true; do
        clear 2>/dev/null || true
        print_box "CATEGORIES"
        echo
        echo "  [1] AUR Helpers"
        echo "  [2] Drivers & Firmware"
        echo "  [3] Terminal Utilities"
        echo "  [0] Back"
        echo

        local choice
        read -r -p "Choose a category: " choice || choice=""

        case "$choice" in
            1) show_aur_helpers_page ;;
            2) show_drivers_page ;;
            3) show_utilities_page ;;
            0) return 0 ;;
            *) print_warn "Invalid option." ;;
        esac
    done
}

show_main_menu() {
    clear 2>/dev/null || true
    echo

    print_box "$LUXURY_TITLE" "v${VERSION}"
    echo

    printf '  %bSystem:%b       %s\n' "$BOLD" "$RESET" "$DISTRO_NAME"
    printf '  %bFamily:%b       %s\n' "$BOLD" "$RESET" "$DISTRO_FAMILY"
    printf '  %bArchitecture:%b %s\n\n' "$BOLD" "$RESET" "$(uname -m)"

    local i=1
    local slug

    for slug in "${APP_ORDER[@]}"; do
        printf '  [%d] %s\n' "$i" "${APP_NAME[$slug]}"
        ((i++))
    done

    local n=${#APP_ORDER[@]}
    local opt_categories=$((n + 1))
    local opt_bazaar=$((n + 2))
    local opt_update=$((n + 3))
    local opt_all=$((n + 4))

    echo
    printf '  [%d] Categories\n' "$opt_categories"
    printf '  [%d] Bazaar (App Store)\n' "$opt_bazaar"
    printf '  [%d] Update System\n' "$opt_update"
    printf '  [%d] Install ALL Apps\n' "$opt_all"
    echo "  [0] Exit"
    echo
}

process_selection() {
    local input="$1"
    local item
    local slug
    local -a items

    local n=${#APP_ORDER[@]}
    local opt_categories=$((n + 1))
    local opt_bazaar=$((n + 2))
    local opt_update=$((n + 3))
    local opt_all=$((n + 4))

    input="${input//;/,}"
    IFS=',' read -r -a items <<< "$input"

    for item in "${items[@]}"; do
        item="${item//[[:space:]]/}"
        [[ -z "$item" ]] && continue

        case "$item" in
            0)
                print_info "Goodbye."
                exit 0
                ;;
            "$opt_categories")
                show_categories_page
                ;;
            "$opt_bazaar")
                launch_bazaar || true
                ;;
            "$opt_update")
                update_system || true
                ;;
            "$opt_all")
                install_all || true
                ;;
            *)
                if slug="$(app_slug_by_number "$item" 2>/dev/null)"; then
                    install_app_by_slug "$slug" || true
                else
                    print_err "Invalid option: $item"
                fi
                ;;
        esac

        echo
    done
}

app_slug_by_number() {
    local n="$1"
    local idx

    [[ "$n" =~ ^[0-9]+$ ]] || return 1
    idx=$((n - 1))

    if (( idx < 0 || idx >= ${#APP_ORDER[@]} )); then
        return 1
    fi

    printf '%s' "${APP_ORDER[$idx]}"
}

# ============================================================
#                           HELP
# ============================================================

show_help() {
    cat <<EOF
${LUXURY_TITLE} v${VERSION}

Usage:
  luxury                  Open the interactive menu
  luxury update          Update the installed Luxury command
  luxury uninstall       Remove Luxury Downloader
  luxury --version       Show version
  luxury --help          Show this help

First-time installation:
  curl -fsSL ${UPDATE_URL} | bash
EOF
}

# ============================================================
#                           MAIN
# ============================================================

main() {
    local command="${1:-menu}"

    case "$command" in
        --help|-h|help)
            show_help
            return 0
            ;;
        --version|-v|version)
            printf '%s v%s\n' "$LUXURY_TITLE" "$VERSION"
            return 0
            ;;
        uninstall|remove)
            uninstall_self
            return $?
            ;;
        update)
            update_self
            return $?
            ;;
        menu|"")
            ;;
        *)
            print_err "Unknown command: $command"
            show_help
            return 2
            ;;
    esac

    # The only way to install Luxury is the official first-time setup
    # command (curl | bash). Once installed, plain `luxury` opens the UI.
    if [[ ! -f "$INSTALL_PATH" ]]; then
        bootstrap_install || return $?
        return 0
    fi

    # Always check for a Luxury Downloader update first.
    # Only after this check do we detect the system and open the menu.
    check_for_updates

    require_command bash || return 1
    require_command uname || return 1
    require_command grep || return 1
    require_command sed || return 1

    detect_distro || return 1
    check_architecture || return 1

    while true; do
        show_main_menu

        local input
        read -r -p "Choose one or more options (example: 1,3,5): " input || {
            echo
            return 0
        }

        process_selection "$input"

        echo
        read -r -p "Press Enter to return to the main menu..." _ || true
    done
}

if (return 0 2>/dev/null); then
    : # Sourced: do not start the interactive menu.
else
    main "$@"
fi
