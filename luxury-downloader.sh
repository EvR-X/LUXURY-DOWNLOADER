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

VERSION="2.5.4"
LUXURY_TITLE="Luxury Downloader"
INSTALL_PATH="/usr/local/bin/luxury"
REPO="EvR-X/LUXURY-DOWNLOADER"
UPDATE_URL="https://raw.githubusercontent.com/${REPO}/main/luxury-downloader.sh"

DISTRO_FAMILY=""
DISTRO_ID=""
DISTRO_NAME=""
# Real distro label for display only (e.g. "Lubuntu (Racoon)"), built
# from /etc/os-release's own NAME + VERSION_CODENAME. Kept separate
# from DISTRO_NAME (PRETTY_NAME, used elsewhere) so nothing that
# already reads DISTRO_NAME changes behavior.
DISTRO_REAL_LABEL=""
SUDO="sudo"
APT_SYNCED=false
AUR_HELPER=""
# Set by process_selection when a sub-page (Apps, Terminal Utilities,
# Drivers & Firmware, AUR Helpers, Uninstall Apps) was opened, so
# main()'s loop skips its own "Press Enter to return..." pause: those
# pages already pause after each individual action, so this avoids
# stacking a second, redundant confirmation on top of those.
SKIP_MAIN_PAUSE=false

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

# print_header -> the one big title bar, shown only on the main menu.
print_header() {
    local width=50
    local label=" ✦ ${LUXURY_TITLE} "
    (( ${#label} + 2 > width )) && width=$(( ${#label} + 2 ))
    local pad=$(( width - ${#label} ))
    local left=$(( pad / 2 ))
    local right=$(( pad - left ))

    printf '%b╭%s╮%b\n' "$CYAN$BOLD" "$(repeat_char '─' "$width")" "$RESET"
    printf '%b│%b%*s%b%s%b%*s%b│%b\n' \
        "$CYAN$BOLD" "$RESET" "$left" '' \
        "$CYAN$BOLD" "$label" "$RESET" \
        "$right" '' "$CYAN$BOLD" "$RESET"
    printf '%b╰%s╯%b\n' "$CYAN$BOLD" "$(repeat_char '─' "$width")" "$RESET"
}

# print_sysline -> Luxury's own version plus the compact
# "distro · family · arch" info, all on the one line below the header.
# Ends with the real distro name/codename in brackets (e.g.
# "[Lubuntu (Racoon)]") when detect_distro has populated it.
print_sysline() {
    printf '%bv%s · %s · %s · %s' \
        "$DIM" "$VERSION" "$DISTRO_NAME" "$DISTRO_FAMILY" "$(uname -m)"

    if [[ -n "$DISTRO_REAL_LABEL" ]]; then
        printf ' [%s]' "$DISTRO_REAL_LABEL"
    fi

    printf '%b\n' "$RESET"
}

# box_top/box_bottom -> compact rounded section frame used by every
# inner page (Apps, Terminal Utilities, Drivers & Firmware, AUR
# Helpers, Uninstall Apps). Width auto-adjusts to fit longer titles.
box_top() {
    local title="$1"
    local width=42
    local label=" ${title} "
    (( ${#label} + 4 > width )) && width=$(( ${#label} + 4 ))
    local pad=$(( width - ${#label} ))
    local left=$(( pad / 2 ))
    local right=$(( pad - left ))

    printf '%b╭%s' "$CYAN" "$(repeat_char '─' "$left")"
    printf '%b%s%b' "$BOLD$BLUE" "$label" "$RESET$CYAN"
    printf '%s╮%b\n' "$(repeat_char '─' "$right")" "$RESET"
}

box_bottom() {
    local title="$1"
    local width=42
    local label=" ${title} "
    (( ${#label} + 4 > width )) && width=$(( ${#label} + 4 ))

    printf '%b╰%s╯%b\n' "$CYAN" "$(repeat_char '─' "$width")" "$RESET"
}

# Lighter-weight heading for one-shot actions (Update System, Install
# ALL) that aren't navigable pages, so they don't need a full box.
section_title() {
    printf '\n%b%s%b\n\n' "$BOLD$BLUE" "$1" "$RESET"
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

    # /etc/os-release defines its own VERSION, NAME, ID... fields. Sourcing
    # it directly into this script used to overwrite Luxury's own $VERSION
    # with the distro's version string. Reading it inside a subshell keeps
    # those fields fully isolated — only the lines this prints ever
    # reach the script.
    local -a os_fields
    mapfile -t os_fields < <(
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '%s\n' "${ID:-}" "${ID_LIKE:-}" "${PRETTY_NAME:-${NAME:-Unknown Linux}}" \
            "${NAME:-}" "${VERSION_CODENAME:-}"
    )

    DISTRO_ID="${os_fields[0]:-unknown}"
    local like="${os_fields[1]:-}"
    DISTRO_NAME="${os_fields[2]:-Unknown Linux}"

    # Real distro label for display: "NAME (Codename)" when a codename
    # is present (e.g. "Lubuntu (Racoon)"), otherwise just NAME. Falls
    # back to DISTRO_NAME (PRETTY_NAME) if the plain NAME field is
    # missing, so this is never left empty. VERSION_CODENAME is always
    # lowercase by os-release convention (e.g. "racoon"), so its first
    # letter is capitalized here to match the desired display format.
    local real_name="${os_fields[3]:-}"
    local codename="${os_fields[4]:-}"
    [[ -z "$real_name" ]] && real_name="$DISTRO_NAME"
    if [[ -n "$codename" ]]; then
        codename="${codename^}"
        DISTRO_REAL_LABEL="${real_name} (${codename})"
    else
        DISTRO_REAL_LABEL="$real_name"
    fi

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
        print_info "Open AUR Helpers from the main menu first."
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
#              INSTALL TRACKING (for safe uninstalls)
# ============================================================
# A small persistent record of exactly what Luxury itself has
# installed, so "Uninstall Apps" can never remove something the
# user installed by other means. One line per entry, formatted
# as "category:slug" (e.g. "app:vlc", "util:btop").

INSTALL_RECORD_FILE="/var/lib/luxury-downloader/installed.list"

record_install() {
    local category="$1"
    local slug="$2"
    local entry="${category}:${slug}"

    $SUDO mkdir -p "$(dirname "$INSTALL_RECORD_FILE")" 2>/dev/null || return 0

    if [[ -f "$INSTALL_RECORD_FILE" ]] && grep -Fxq "$entry" "$INSTALL_RECORD_FILE" 2>/dev/null; then
        return 0
    fi

    printf '%s\n' "$entry" | $SUDO tee -a "$INSTALL_RECORD_FILE" >/dev/null 2>&1
}

is_recorded() {
    local category="$1"
    local slug="$2"
    [[ -f "$INSTALL_RECORD_FILE" ]] || return 1
    grep -Fxq "${category}:${slug}" "$INSTALL_RECORD_FILE" 2>/dev/null
}

forget_install() {
    local category="$1"
    local slug="$2"
    [[ -f "$INSTALL_RECORD_FILE" ]] || return 0

    local tmp
    tmp="$(mktemp)" || return 0
    grep -Fxv "${category}:${slug}" "$INSTALL_RECORD_FILE" > "$tmp" 2>/dev/null
    $SUDO cp "$tmp" "$INSTALL_RECORD_FILE" 2>/dev/null
    rm -f "$tmp"
}

# ============================================================
#                    REAL RUN COMMANDS
# ============================================================
# Two separate hints after a successful install. Only entries
# Luxury actually knows for certain are listed; anything absent
# simply gets no hint (better to say nothing than to invent a
# command that might be wrong).
#
# RUN_CMD -> "Type [x] to run it." Terminal utilities that are
# launched by typing their own command (cmatrix, btop, etc).
# Confirmed apps with their own launcher icon (Brave, Thunderbird,
# LibreWolf, VLC, LibreOffice, MPV, LocalSend, RetroArch, Bazaar)
# are opened from the system's app menu, so they intentionally
# have no entry here.
#
# HELP_CMD -> "Run it with: [x]" for terminal-only apps that don't
# get opened directly, just invoked with arguments (7-Zip, unrar).

declare -A RUN_CMD=(
    [cmatrix]="cmatrix"
    [cava]="cava"
    [lavat]="lavat"
    [peaclock]="peaclock"
    [fastfetch]="fastfetch"
    [sl]="sl"
    [pipes]="pipes.sh"
    [sptlrx]="sptlrx"
    [btop]="btop"
    [htop]="htop"
)

declare -A HELP_CMD=(
    [7zip]="7z --help"
    [unrar]="unrar"
)

# announce_installed <category> <slug> -> the install functions
# already print their own "✓ X installed." line via print_ok, so
# this only adds a hint right after it, avoiding a duplicate
# message. category is "app" or "util" (the same value already
# passed to record_install right before this is called).
#
# - Terminal utilities (category "util") get the RUN_CMD hint.
# - Apps (category "app") only get a hint if they're a
#   terminal-only tool with no launcher icon (HELP_CMD); apps with
#   a real launcher icon get no hint at all, since they're opened
#   from the system's app menu, not by typing a command.
announce_installed() {
    local category="$1"
    local slug="$2"

    if [[ "$category" == "util" ]]; then
        local cmd="${RUN_CMD[$slug]:-}"
        [[ -n "$cmd" ]] && print_info "Type [${cmd}] to run it."
        return 0
    fi

    local help_cmd="${HELP_CMD[$slug]:-}"
    [[ -n "$help_cmd" ]] && print_info "Run it with: ${help_cmd}"
}

# ============================================================
#                       MAIN APP REGISTRY
# ============================================================

APP_ORDER=(brave thunderbird librewolf vlc libreoffice mpv localsend retroarch 7zip unrar)

declare -A APP_NAME=(
    [brave]="Brave Origin"
    [thunderbird]="Thunderbird"
    [librewolf]="LibreWolf"
    [vlc]="VLC"
    [libreoffice]="LibreOffice"
    [mpv]="MPV"
    [localsend]="LocalSend"
    [retroarch]="RetroArch + Cores"
    [7zip]="7-Zip"
    [unrar]="unrar (RAR extractor)"
    [bazaar]="Bazaar"
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
)

declare -A APP_CUSTOM_ARCH=(
    [brave]="install_brave_origin_arch"
    [librewolf]="install_librewolf_arch"
    [localsend]="install_localsend_arch"
    [retroarch]="install_retroarch_arch"
)

install_app_by_slug() {
    local slug="$1"
    local name="${APP_NAME[$slug]:-$slug}"
    local custom_fn=""
    local result

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
    result=$?

    if [[ $result -eq 0 ]]; then
        record_install "app" "$slug"
        announce_installed "app" "$slug"
    fi

    return "$result"
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
        echo
        box_top "AUR HELPERS"
        echo

        local current="None"
        if detect_aur_helper >/dev/null 2>&1; then
            current="$AUR_HELPER"
        fi

        printf '  Current helper: %b%s%b\n\n' "$CYAN" "$current" "$RESET"
        echo "  [1] Install / use Yay"
        echo "  [2] Install / use Paru"
        echo
        printf '  %b[B]%b Back\n' "$CYAN" "$RESET"
        echo
        box_bottom "AUR HELPERS"
        echo

        local choice
        read -r -p "Select: " choice || choice=""

        case "${choice,,}" in
            1)
                install_aur_helper yay || true
                press_enter
                ;;
            2)
                install_aur_helper paru || true
                press_enter
                ;;
            b)
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
        echo
        box_top "DRIVERS & FIRMWARE"
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

        echo
        printf '  %b[B]%b Back\n' "$CYAN" "$RESET"
        echo
        box_bottom "DRIVERS & FIRMWARE"
        echo

        local choice
        read -r -p "Select: " choice || choice=""

        if [[ "${choice,,}" == "b" ]]; then
            return 0
        fi

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

UTIL_ORDER=(cmatrix cava lavat peaclock fastfetch sl pipes sptlrx btop htop)

declare -A UTIL_NAME=(
    [cmatrix]="CMatrix"
    [cava]="CAVA"
    [lavat]="lavat"
    [peaclock]="Peaclock"
    [fastfetch]="Fastfetch"
    [sl]="sl (Steam Locomotive)"
    [pipes]="pipes.sh"
    [sptlrx]="sptlrx (Spotify lyrics)"
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
    local result

    if [[ "$slug" == "lavat" ]]; then
        install_lavat
        result=$?

    elif [[ "$slug" == "peaclock" ]]; then
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            install_peaclock_debian
        else
            install_peaclock_arch
        fi
        result=$?

    # pipes.sh and sptlrx have no official Arch repo package (AUR only),
    # and pipes.sh's APT binary package is named differently (pipes-sh)
    # from its AUR name (pipes.sh), so both get a small special case
    # instead of living in the generic UTIL_APT/UTIL_PACMAN tables.
    elif [[ "$slug" == "pipes" ]]; then
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            install_apt_package "pipes-sh" "$name"
        else
            install_aur_package "pipes.sh" "$name"
        fi
        result=$?

    elif [[ "$slug" == "sptlrx" ]]; then
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            install_apt_package "sptlrx" "$name"
        else
            install_aur_package "sptlrx" "$name"
        fi
        result=$?

    elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
        install_apt_package "${UTIL_APT[$slug]:-}" "$name"
        result=$?

    else
        if pacman_has_package "${UTIL_PACMAN[$slug]:-}"; then
            install_pacman_package "${UTIL_PACMAN[$slug]:-}" "$name"
            result=$?
        else
            print_err "Package not available in the configured Arch repositories: ${UTIL_PACMAN[$slug]:-$slug}"
            result=1
        fi
    fi

    if [[ $result -eq 0 ]]; then
        record_install "util" "$slug"
        announce_installed "util" "$slug"
    fi

    return "$result"
}

# ============================================================
#                    SAFE UNINSTALL SYSTEM
# ============================================================
# Only ever acts on entries in INSTALL_RECORD_FILE (things Luxury
# itself installed) — see record_install() above. Never touches
# software the user installed some other way.

# resolve_uninstall_target <category> <slug> -> prints "method:target"
# for the CURRENT distro family. method is one of: apt, pacman,
# flatpak, path, unknown. "unknown" means there's no safe automated
# way to remove it, and the caller must warn instead of acting.
resolve_uninstall_target() {
    local category="$1"
    local slug="$2"

    if [[ "$category" == "app" ]]; then
        case "$slug" in
            brave)
                if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                    printf 'apt:brave-origin'
                else
                    printf 'pacman:brave-origin-bin'
                fi
                return
                ;;
            librewolf)
                if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                    printf 'apt:librewolf'
                else
                    printf 'pacman:librewolf'
                fi
                return
                ;;
            localsend)
                if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                    printf 'flatpak:org.localsend.localsend_app'
                else
                    printf 'pacman:localsend-bin'
                fi
                return
                ;;
            retroarch)
                if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                    printf 'apt:retroarch'
                else
                    printf 'pacman:retroarch'
                fi
                return
                ;;
            bazaar)
                # Bazaar is only offered here through APT on Ubuntu-based
                # systems (see install_bazaar); it has no Arch package.
                # Uninstalling it removes only the bazaar package itself,
                # never the shared Flatpak/Flathub runtime it depends on.
                if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                    printf 'apt:bazaar'
                else
                    printf 'unknown:'
                fi
                return
                ;;
        esac

        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            local pkg="${APP_PKG_DEBIAN[$slug]:-}"
            [[ -n "$pkg" ]] && printf 'apt:%s' "$pkg" || printf 'unknown:'
        else
            local pkg="${APP_PKG_ARCH[$slug]:-}"
            [[ -n "$pkg" ]] && printf 'pacman:%s' "$pkg" || printf 'unknown:'
        fi
        return
    fi

    # category == util
    case "$slug" in
        lavat)
            if [[ "$DISTRO_FAMILY" == "arch" ]]; then
                printf 'pacman:lavat'
            else
                # Built from source with "make install"; no package
                # manager tracks it. Removing the resolved binary path
                # is as far as this can safely go.
                printf 'path:lavat'
            fi
            return
            ;;
        peaclock)
            if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                printf 'path:peaclock'
            else
                printf 'pacman:peaclock'
            fi
            return
            ;;
        pipes)
            if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                printf 'apt:pipes-sh'
            else
                printf 'pacman:pipes.sh'
            fi
            return
            ;;
        sptlrx)
            if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                printf 'apt:sptlrx'
            else
                printf 'pacman:sptlrx'
            fi
            return
            ;;
    esac

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        local pkg="${UTIL_APT[$slug]:-}"
        [[ -n "$pkg" ]] && printf 'apt:%s' "$pkg" || printf 'unknown:'
    else
        local pkg="${UTIL_PACMAN[$slug]:-}"
        [[ -n "$pkg" ]] && printf 'pacman:%s' "$pkg" || printf 'unknown:'
    fi
}

# is_target_present <method> <target> -> is it actually installed
# right now, regardless of what the tracking file says?
is_target_present() {
    local method="$1"
    local target="$2"

    case "$method" in
        apt|pacman) is_installed "$target" ;;
        flatpak)    command -v flatpak >/dev/null 2>&1 && flatpak info "$target" >/dev/null 2>&1 ;;
        path)       command -v "$target" >/dev/null 2>&1 ;;
        *)          return 1 ;;
    esac
}

# perform_uninstall <method> <target> -> does the actual removal.
perform_uninstall() {
    local method="$1"
    local target="$2"

    case "$method" in
        apt)
            check_sudo || return 1
            $SUDO apt remove -y "$target"
            ;;
        pacman)
            check_sudo || return 1
            $SUDO pacman -R --noconfirm "$target"
            ;;
        flatpak)
            command -v flatpak >/dev/null 2>&1 || return 1
            flatpak uninstall -y "$target"
            ;;
        path)
            local resolved
            resolved="$(command -v "$target" 2>/dev/null)"
            [[ -n "$resolved" ]] || return 1
            check_sudo || return 1
            $SUDO rm -f "$resolved"
            ;;
        *)
            return 1
            ;;
    esac
}

# uninstall_entry <category> <slug> -> the full safe flow: was it
# Luxury that installed this, is it still there, then remove it.
uninstall_entry() {
    local category="$1"
    local slug="$2"
    local name

    if [[ "$category" == "app" ]]; then
        name="${APP_NAME[$slug]:-$slug}"
    else
        name="${UTIL_NAME[$slug]:-$slug}"
    fi

    if ! is_recorded "$category" "$slug"; then
        print_warn "${name} wasn't installed with Luxury, or wasn't found."
        return 0
    fi

    local method_target method target
    method_target="$(resolve_uninstall_target "$category" "$slug")"
    method="${method_target%%:*}"
    target="${method_target#*:}"

    if [[ "$method" == "unknown" || -z "$target" ]]; then
        print_warn "Not enough information to safely remove ${name}. Please remove it manually."
        return 1
    fi

    if ! is_target_present "$method" "$target"; then
        print_warn "${name} was already removed."
        forget_install "$category" "$slug"
        return 0
    fi

    print_info "Removing ${name}..."

    if perform_uninstall "$method" "$target"; then
        print_ok "${name} was uninstalled."
        forget_install "$category" "$slug"
    else
        print_err "Could not uninstall ${name}."
        return 1
    fi
}

show_utilities_page() {
    while true; do
        clear 2>/dev/null || true
        echo
        box_top "TERMINAL UTILITIES"
        echo

        local i=1
        local slug
        for slug in "${UTIL_ORDER[@]}"; do
            printf '  [%d] %s\n' "$i" "${UTIL_NAME[$slug]:-$slug}"
            ((i++))
        done

        echo
        printf '  %b[B]%b Back\n' "$CYAN" "$RESET"
        echo
        box_bottom "TERMINAL UTILITIES"
        echo

        local choice
        read -r -p "Select: " choice || choice=""

        if [[ "${choice,,}" == "b" ]]; then
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
# APT-only, Ubuntu-based only: the "bazaar" package currently
# ships on Ubuntu 26.04+ (universe). No Flatpak fallback and no
# Arch path on purpose.

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

install_bazaar() {
    if command -v bazaar >/dev/null 2>&1; then
        print_ok "Bazaar is already installed."
        ensure_bazaar_runtime
        return 0
    fi

    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        print_err "Bazaar is only offered here through APT on Ubuntu-based systems."
        return 1
    fi

    ensure_apt_synced

    if ! apt_has_package "bazaar"; then
        print_err "The 'bazaar' APT package is not available on this system."
        print_info "It currently ships on Ubuntu 26.04 and newer (universe)."
        return 1
    fi

    if ! install_apt_package "bazaar" "Bazaar"; then
        return 1
    fi

    ensure_bazaar_runtime
    record_install "app" "bazaar"
    announce_installed "app" "bazaar"
}

# Bazaar's entire purpose is browsing/installing apps from Flathub, so
# even though the app itself is installed via APT here, it still
# needs Flatpak plus the Flathub remote configured to actually work.
ensure_bazaar_runtime() {
    if ! install_flatpak; then
        print_warn "Flatpak could not be set up automatically; Bazaar needs it to browse apps."
        return 1
    fi

    if ! ensure_flathub; then
        print_warn "The Flathub remote could not be added automatically."
        return 1
    fi

    print_ok "Flathub is ready."
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

show_apps_page() {
    while true; do
        clear 2>/dev/null || true
        echo
        box_top "APPS"
        echo

        local i=1
        local slug
        for slug in "${APP_ORDER[@]}"; do
            printf '  [%d] %s\n' "$i" "${APP_NAME[$slug]:-$slug}"
            ((i++))
        done

        echo
        printf '  %b[B]%b Back\n' "$CYAN" "$RESET"
        echo
        box_bottom "APPS"
        echo

        local input
        read -r -p "Select one or more (e.g: 1,3,5): " input || return

        if [[ "${input,,}" == "b" ]]; then
            return
        fi

        input="${input//;/,}"
        local -a items
        IFS=',' read -r -a items <<< "$input"

        local item any=false
        for item in "${items[@]}"; do
            item="${item//[[:space:]]/}"
            [[ -z "$item" ]] && continue
            any=true

            if [[ "${item,,}" == "b" ]]; then
                return
            elif slug="$(app_slug_by_number "$item" 2>/dev/null)"; then
                install_app_by_slug "$slug" || true
            else
                print_err "Invalid option: $item"
            fi
            echo
        done

        if [[ "$any" == false ]]; then
            print_warn "No option was entered."
        fi

        echo
        read -r -p "Press Enter to continue..." _
    done
}

show_uninstall_page() {
    local n_apps=${#APP_ORDER[@]}
    local n_utils=${#UTIL_ORDER[@]}
    # Bazaar has its own dedicated install button (not part of APP_ORDER,
    # see install_bazaar), but it can still be uninstalled here. It gets
    # the number right after the terminal utilities, so the existing
    # "app" (1..n_apps) and "util" (n_apps+1..n_apps+n_utils) ranges
    # below stay untouched.
    local bazaar_index=$((n_apps + n_utils + 1))

    while true; do
        clear 2>/dev/null || true
        echo
        box_top "UNINSTALL APPS"
        echo

        printf '  %bAPPS%b\n' "$BOLD$BLUE" "$RESET"
        local i=1
        local slug
        for slug in "${APP_ORDER[@]}"; do
            printf '  [%d] %s\n' "$i" "${APP_NAME[$slug]:-$slug}"
            ((i++))
        done
        printf '  [%d] %s\n' "$bazaar_index" "${APP_NAME[bazaar]:-Bazaar}"

        echo
        printf '  %bTERMINAL UTILITIES%b\n' "$BOLD$BLUE" "$RESET"
        i=$((n_apps + 1))
        for slug in "${UTIL_ORDER[@]}"; do
            printf '  [%d] %s\n' "$i" "${UTIL_NAME[$slug]:-$slug}"
            ((i++))
        done

        echo
        printf '  %b[B]%b Back\n' "$CYAN" "$RESET"
        echo
        box_bottom "UNINSTALL APPS"
        echo

        local input
        read -r -p "Select one or more to uninstall: " input || return

        if [[ "${input,,}" == "b" ]]; then
            return
        fi

        input="${input//;/,}"
        local -a items
        IFS=',' read -r -a items <<< "$input"

        local item any=false
        for item in "${items[@]}"; do
            item="${item//[[:space:]]/}"
            [[ -z "$item" ]] && continue
            any=true

            if [[ "${item,,}" == "b" ]]; then
                return
            fi

            if [[ "$item" =~ ^[0-9]+$ ]] && (( item >= 1 && item <= n_apps )); then
                uninstall_entry "app" "${APP_ORDER[$((item - 1))]}"
            elif [[ "$item" =~ ^[0-9]+$ ]] && (( item > n_apps && item <= n_apps + n_utils )); then
                uninstall_entry "util" "${UTIL_ORDER[$((item - 1 - n_apps))]}"
            elif [[ "$item" =~ ^[0-9]+$ ]] && (( item == bazaar_index )); then
                uninstall_entry "app" "bazaar"
            else
                print_err "Invalid option: $item"
            fi
            echo
        done

        if [[ "$any" == false ]]; then
            print_warn "No option was entered."
        fi

        echo
        read -r -p "Press Enter to continue..." _
    done
}

show_main_menu() {
    clear 2>/dev/null || true
    echo
    print_header
    print_sysline
    echo

    echo "  [1] Apps"
    echo "  [2] Terminal Utilities"
    echo "  [3] Drivers & Firmware"
    echo "  [4] AUR Helpers"
    printf '  [5] %bInstall Bazaar%b\n' "$CYAN" "$RESET"
    printf '  [6] %bUpdate System%b\n' "$YELLOW" "$RESET"
    printf '  [7] %bInstall ALL Apps%b\n' "$GREEN" "$RESET"
    echo "  [8] Uninstall Apps"
    echo
    printf '  %b[Q] Exit%b\n' "$RED" "$RESET"
    echo
}

process_selection() {
    local input="$1"
    local item
    local -a items

    input="${input//;/,}"
    IFS=',' read -r -a items <<< "$input"

    for item in "${items[@]}"; do
        item="${item//[[:space:]]/}"
        [[ -z "$item" ]] && continue

        case "${item,,}" in
            q)
                print_info "Goodbye."
                sleep 1
                clear 2>/dev/null || true
                exit 0
                ;;
            1)
                show_apps_page
                SKIP_MAIN_PAUSE=true
                ;;
            2)
                show_utilities_page
                SKIP_MAIN_PAUSE=true
                ;;
            3)
                show_drivers_page
                SKIP_MAIN_PAUSE=true
                ;;
            4)
                show_aur_helpers_page
                SKIP_MAIN_PAUSE=true
                ;;
            5)
                install_bazaar || true
                ;;
            6)
                update_system || true
                ;;
            7)
                install_all || true
                ;;
            8)
                show_uninstall_page
                SKIP_MAIN_PAUSE=true
                ;;
            *)
                print_err "Invalid option: $item"
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
        read -r -p "Select: " input || {
            echo
            return 0
        }

        SKIP_MAIN_PAUSE=false
        process_selection "$input"

        if [[ "$SKIP_MAIN_PAUSE" == true ]]; then
            continue
        fi

        echo
        read -r -p "Press Enter to return to the main menu..." _ || true
    done
}

if (return 0 2>/dev/null); then
    : # Sourced: do not start the interactive menu.
else
    main "$@"
fi
