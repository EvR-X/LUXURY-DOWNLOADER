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

VERSION="2.6.0"
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
# Drivers & Firmware, AUR Helpers, Uninstall [Apps/Utilities]) was opened, so
# main()'s loop skips its own "Press Enter to return..." pause: those
# pages already pause after each individual action, so this avoids
# stacking a second, redundant confirmation on top of those.
SKIP_MAIN_PAUSE=false

# Debian-family sub-flavor, set by detect_distro: "ubuntu" for Ubuntu and
# anything Ubuntu-based, "debian" for Debian itself and its non-Ubuntu
# derivatives (LMDE, MX...). Empty on Arch. Only used where the two really
# behave differently (NVIDIA drivers).
DISTRO_FLAVOR=""

# What the install code actually did, so the caller records exactly the
# method + target that were used instead of guessing later (see INSTALL
# TRACKING). Empty means "Luxury did not install anything new".
INSTALL_RESULT_METHOD=""
INSTALL_RESULT_TARGET=""

# True only when the last install_apt_package / install_pacman_package /
# install_aur_package call really ran an install (false when the package
# was already there, or the install failed).
PKG_INSTALLED_NOW=false

# Temp files/dirs removed on the way out of the script (see CLEANUP).
TMP_CLEANUP=()

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
# Helpers, Uninstall [Apps/Utilities]). Width auto-adjusts to fit longer titles.
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

    DISTRO_FLAVOR=""
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        case "$DISTRO_ID" in
            ubuntu|pop|neon|zorin|elementary|lubuntu|kubuntu|xubuntu|ubuntu-mate|budgie-remix)
                DISTRO_FLAVOR="ubuntu"
                ;;
            *)
                # ID_LIKE is what tells Ubuntu-based Linux Mint
                # ("ubuntu debian") apart from LMDE ("debian").
                if [[ " ${like} " == *" ubuntu "* ]]; then
                    DISTRO_FLAVOR="ubuntu"
                else
                    DISTRO_FLAVOR="debian"
                fi
                ;;
        esac
    fi

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

    PKG_INSTALLED_NOW=false

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
        PKG_INSTALLED_NOW=true
        print_ok "$name installed."
        return 0
    fi

    print_err "Could not install $name."
    return 1
}

install_pacman_package() {
    local package="$1"
    local name="${2:-$package}"

    PKG_INSTALLED_NOW=false

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
        PKG_INSTALLED_NOW=true
        print_ok "$name installed."
        return 0
    fi

    print_err "Could not install $name."
    return 1
}

install_aur_package() {
    local package="$1"
    local name="${2:-$package}"

    PKG_INSTALLED_NOW=false

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
        PKG_INSTALLED_NOW=true
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
#                   INSTALL RESULTS + CLEANUP
# ============================================================

# The install code reports what it really did through these, so the
# caller (see finalize_install) records the exact method + target that
# were used, and only for things Luxury itself installed.
reset_install_result() {
    INSTALL_RESULT_METHOD=""
    INSTALL_RESULT_TARGET=""
}

set_install_result() {
    INSTALL_RESULT_METHOD="$1"
    INSTALL_RESULT_TARGET="$2"
}

# track_pkg_install <method> <package> -> call right after an
# install_*_package call succeeded. Remembers the package as this
# install's result, but only if that call really installed it: a
# package that was already on the system is not Luxury's to remove.
track_pkg_install() {
    if [[ "$PKG_INSTALLED_NOW" == true ]]; then
        set_install_result "$1" "$2"
    fi
    return 0
}

# track_pkg_install_multi <method> <package> -> like track_pkg_install,
# but APPENDS to INSTALL_RESULT_TARGET as a comma-separated list instead
# of replacing it, so one install made of several packages (RetroArch
# plus each Libretro core it pulled in) ends up as a single record that
# covers all of them, instead of only the last one tracked. Only ever
# called for a package install_*_package really installed just now.
track_pkg_install_multi() {
    local method="$1"
    local package="$2"

    [[ "$PKG_INSTALLED_NOW" == true ]] || return 0

    if [[ -z "$INSTALL_RESULT_METHOD" ]]; then
        set_install_result "$method" "$package"
    elif [[ "$INSTALL_RESULT_METHOD" == "$method" ]]; then
        INSTALL_RESULT_TARGET="${INSTALL_RESULT_TARGET},${package}"
    fi
    return 0
}

install_tracked_apt() {
    install_apt_package "$@" || return 1
    track_pkg_install "apt" "$1"
}

install_tracked_pacman() {
    install_pacman_package "$@" || return 1
    track_pkg_install "pacman" "$1"
}

# AUR packages end up in pacman's database, so they are tracked (and
# later removed) as pacman packages.
install_tracked_aur() {
    install_aur_package "$@" || return 1
    track_pkg_install "pacman" "$1"
}

# register_cleanup <path> -> deleted by cleanup_temp_paths, including
# when the script is interrupted. Call it from the function that made
# the temp path (not from inside $(...), which would lose the entry).
register_cleanup() {
    TMP_CLEANUP+=("$1")
}

cleanup_temp_paths() {
    local path
    for path in "${TMP_CLEANUP[@]}"; do
        [[ -n "$path" ]] && rm -rf -- "$path"
    done
    TMP_CLEANUP=()
}

# Runs on every way out of the script (normal exit, Ctrl-C, SIGTERM):
# rolls back a half-finished source install, removes build-only
# dependencies Luxury pulled in for a build that never got to clean up
# after itself, and deletes leftover temp files.
cleanup_on_exit() {
    rollback_compiled_in_progress
    remove_build_only_deps
    cleanup_temp_paths
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

    if [[ ! "$candidate_version" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
        print_err "The source script contains an invalid VERSION: ${candidate_version}"
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

    if [[ ! "$remote_version" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
        print_err "The remote script contains an invalid VERSION: ${remote_version}"
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
    register_cleanup "$temp"

    if ! download_remote_script "$temp" 2>/dev/null; then
        print_warn "Could not check for Luxury Downloader updates right now. Continuing."
        rm -f "$temp"
        return 0
    fi

    local remote_version
    remote_version="$(extract_version_from_file "$temp")"

    if [[ -z "$remote_version" ]] || [[ ! "$remote_version" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
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

    # Official Brave Origin Linux installer. pipefail matters here: without
    # it a failed download leaves `sh` reading an empty script, which exits
    # 0 and would be reported as a successful install.
    if ( set -o pipefail; curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh ); then
        if is_installed "brave-origin"; then
            set_install_result "apt" "brave-origin"
            print_ok "Brave Origin installed."
            return 0
        fi

        if command -v brave-origin >/dev/null 2>&1; then
            print_warn "Brave Origin is installed, but not as the 'brave-origin' APT package, so Luxury cannot track it for uninstalling."
            print_ok "Brave Origin installed."
            return 0
        fi

        print_err "Brave's installer finished, but Brave Origin was not found afterwards."
        return 1
    fi

    print_err "Brave Origin installation failed."
    return 1
}

install_brave_origin_arch() {
    install_tracked_aur "brave-origin-bin" "Brave Origin"
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
    install_tracked_apt "librewolf" "LibreWolf"
}

install_librewolf_arch() {
    install_tracked_pacman "librewolf" "LibreWolf"
}

# ============================================================
#                       THUNDERBIRD
# ============================================================
# Ubuntu ships "thunderbird" in APT as a transitional package that only
# pulls in the Snap (24.04 and later, including 26.04), while Debian and
# Ubuntu-based distros that build their own (Linux Mint) have a real .deb
# under the same name. dpkg alone can therefore say "installed" for a shim
# whose Snap is missing, so detection looks at what the package really
# is, and installation picks Snap or APT accordingly.

# deb_is_snap_shim <package> -> is the INSTALLED .deb just a transitional
# shim that pulls in a Snap?
deb_is_snap_shim() {
    local info
    info="$(dpkg-query -W -f='${Depends}\n${binary:Summary}\n' "$1" 2>/dev/null)" || return 1
    [[ "$info" =~ [Tt]ransitional && "$info" =~ [Ss]nap ]]
}

# apt_candidate_is_snap_shim <package> -> would APT install a transitional
# shim that pulls in a Snap, instead of the real application?
apt_candidate_is_snap_shim() {
    apt-cache show "$1" 2>/dev/null \
        | awk 'BEGIN { RS = "" } NR == 1 { print; exit }' \
        | grep -qiE '^Description(-[A-Za-z_]+)?:.*transitional.*snap|^Depends:.*snapd'
}

# thunderbird_target_debian -> "method:target" of the Thunderbird that is
# installed right now. When there is none it prints the Snap, which is
# what a fresh install uses on Ubuntu and is reported as absent.
thunderbird_target_debian() {
    if command -v snap >/dev/null 2>&1 && snap list thunderbird >/dev/null 2>&1; then
        printf 'snap:thunderbird'
    elif is_installed thunderbird && ! deb_is_snap_shim thunderbird; then
        printf 'apt:thunderbird'
    else
        printf 'snap:thunderbird'
    fi
}

is_thunderbird_installed_debian() {
    local method_target
    method_target="$(thunderbird_target_debian)"
    is_target_present "${method_target%%:*}" "${method_target#*:}"
}

install_thunderbird_debian() {
    if is_thunderbird_installed_debian; then
        print_ok "Thunderbird is already installed."
        return 0
    fi

    # The route depends on what APT would really install, so its package
    # index has to be fresh.
    ensure_apt_synced || return 1

    if apt_candidate_is_snap_shim "thunderbird"; then
        print_info "This system's Thunderbird package only installs the Snap. Installing the Snap directly..."
        check_sudo || return 1

        if ! command -v snap >/dev/null 2>&1; then
            install_apt_package "snapd" "snapd" || return 1
        fi

        if $SUDO snap install thunderbird; then
            set_install_result "snap" "thunderbird"
            print_ok "Thunderbird installed."
            return 0
        fi

        print_err "Could not install Thunderbird via Snap."
        return 1
    fi

    # Debian, Linux Mint and any distro where the APT package is the real
    # application rather than a Snap shim.
    install_tracked_apt "thunderbird" "Thunderbird"
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
        set_install_result "flatpak" "org.localsend.localsend_app"
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

    install_tracked_aur "localsend-bin" "LocalSend"
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

# RetroArch's setting for the folder its cores live in is
# "libretro_directory" (docs.libretro.com -> Directory Configuration).
# There is no "core_directory": v2.6.0 wrote that key, and RetroArch
# ignored it. The file is rewritten line by line in plain bash so paths
# with characters that are special to sed can't corrupt it.
configure_retroarch_system_core_dir() {
    local core_dir="${1:-/usr/lib/libretro}"
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/retroarch/retroarch.cfg"
    local tmp line found=false

    mkdir -p "$(dirname "$cfg")" 2>/dev/null || return 0
    tmp="$(mktemp)" || return 0

    if [[ -f "$cfg" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^libretro_directory[[:space:]]*= ]]; then
                printf 'libretro_directory = "%s"\n' "$core_dir" >> "$tmp"
                found=true
            else
                printf '%s\n' "$line" >> "$tmp"
            fi
        done < "$cfg"
    fi

    if [[ "$found" == false ]]; then
        printf 'libretro_directory = "%s"\n' "$core_dir" >> "$tmp"
    fi

    # Writing through the existing file keeps its owner and permissions
    # (and a new file gets the normal umask, not mktemp's 0600).
    cat "$tmp" > "$cfg" 2>/dev/null || true
    rm -f "$tmp"
    return 0
}

# detect_libretro_core_dir_debian <package...> -> prints the real
# directory dpkg placed the *_libretro.so files in for the first
# package in the list it actually has installed. Debian/Ubuntu use
# multiarch paths (e.g. /usr/lib/x86_64-linux-gnu/libretro) that
# vary by architecture, so this is detected rather than assumed.
detect_libretro_core_dir_debian() {
    local pkg core_file
    for pkg in "$@"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || continue
        core_file="$(dpkg -L "$pkg" 2>/dev/null | grep '_libretro\.so$' | head -n1)"
        if [[ -n "$core_file" ]]; then
            dirname "$core_file"
            return 0
        fi
    done
    return 1
}

# detect_libretro_core_dir_arch <package...> -> the pacman equivalent
# of the detector above, for the same reason: don't assume the path,
# read it from whichever core package is actually installed.
detect_libretro_core_dir_arch() {
    local pkg core_file
    for pkg in "$@"; do
        pacman -Qi "$pkg" >/dev/null 2>&1 || continue
        core_file="$(pacman -Ql "$pkg" 2>/dev/null | awk '{print $2}' | grep '_libretro\.so$' | head -n1)"
        if [[ -n "$core_file" ]]; then
            dirname "$core_file"
            return 0
        fi
    done
    return 1
}

install_retroarch_debian() {
    local installed_cores=0
    local package

    add_libretro_ppa || return 1

    install_tracked_apt "retroarch" "RetroArch" || return 1

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
                track_pkg_install_multi "apt" "$package"
            fi
        else
            print_warn "Core package not available in this APT source: $package (skipped)."
        fi
    done

    local core_dir
    if core_dir="$(detect_libretro_core_dir_debian "${cores[@]}")"; then
        print_info "Detected Libretro core directory: ${core_dir}"
    else
        core_dir="/usr/lib/libretro"
        print_warn "Could not detect the Libretro core directory; defaulting to ${core_dir}."
    fi
    configure_retroarch_system_core_dir "$core_dir"

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

    install_tracked_pacman "retroarch" "RetroArch" || return 1

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
                track_pkg_install_multi "pacman" "$package"
            fi
        else
            print_warn "Core package not available in the configured Arch repositories: $package (skipped)."
        fi
    done

    configure_retroarch_system_core_dir "$(detect_libretro_core_dir_arch "${cores[@]}" || printf '/usr/lib/libretro')"

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
# installed, so "Uninstall [Apps/Utilities]" can never remove something the
# user installed by other means.
#
# One line per entry: category|slug|method|target, for example
#
#   app|thunderbird|snap|thunderbird
#   util|lavat|compiled|lavat
#
# method + target are what the install code ACTUALLY used at the time
# (see INSTALL_RESULT_METHOD / INSTALL_RESULT_TARGET), so uninstalling
# months later removes exactly that -- never whatever happens to be on
# the system by then. method is one of:
#   apt, pacman   a package (AUR packages are pacman packages too)
#   flatpak, snap an app ID / snap name
#   path          an absolute file under /usr/local put there by an
#                 installer script (never a file a package owns)
#   compiled      built from source; target is the slug of its file
#                 manifest (see the compiled-program section)
#
# v2.6.0 and older wrote "category:slug" with no method. Those lines
# are converted once, at startup, by migrate_install_records().

INSTALL_RECORD_FILE="/var/lib/luxury-downloader/installed.list"

# record_fields_are_safe <category> <slug> <method> <target>
record_fields_are_safe() {
    local field
    for field in "$@"; do
        [[ -n "$field" && "$field" != *"|"* && "$field" != *$'\n'* ]] || return 1
    done

    case "$3" in
        apt|pacman|flatpak|snap|path|compiled) return 0 ;;
        *) return 1 ;;
    esac
}

# record_target_is_safe <method> <target> -> is this target something
# that is fine to hand to a package manager or rm? Checked again when
# an entry is read back, since the file is plain text.
record_target_is_safe() {
    local method="$1"
    local target="$2"

    case "$method" in
        path)     [[ "$target" =~ ^/usr/local/[A-Za-z0-9._+@/-]+$ && "$target" != *".."* ]] ;;
        compiled) [[ "$target" =~ ^[a-z0-9][a-z0-9._-]*$ ]] ;;
        # apt/pacman/flatpak/snap: normally a single package, but apt and
        # pacman targets may also be a comma-separated list (e.g. RetroArch
        # plus each Libretro core installed alongside it under one record).
        *)        [[ "$target" =~ ^[A-Za-z0-9][A-Za-z0-9._+:@-]*(,[A-Za-z0-9][A-Za-z0-9._+:@-]*)*$ ]] ;;
    esac
}

# merge_target_list <old> <new> -> prints the union of two comma-separated
# package lists, in order, without duplicates. old's own items are also
# deduplicated the same way, so a caller never needs to pre-clean it.
merge_target_list() {
    local old="$1" new="$2"
    local -a items
    local -A seen=()
    local -a out=()
    local pkg
    IFS=',' read -r -a items <<< "${old},${new}"
    for pkg in "${items[@]}"; do
        [[ -n "$pkg" ]] || continue
        if [[ -z "${seen[$pkg]:-}" ]]; then
            seen[$pkg]=1
            out+=("$pkg")
        fi
    done
    local IFS=','
    printf '%s' "${out[*]}"
}

# record_install <category> <slug> <method> <target> -> saves (or
# replaces) the entry for that item.
#
# For apt/pacman, target may be a comma-separated package list (see
# track_pkg_install_multi): merged with whatever that item's existing
# record already lists, rather than replacing it, so a later run that
# adds one more package (e.g. a Libretro core that only became available
# in a newer repository snapshot) doesn't make Luxury forget the ones
# a previous run already tracked.
record_install() {
    local category="$1"
    local slug="$2"
    local method="$3"
    local target="$4"

    if ! record_fields_are_safe "$category" "$slug" "$method" "$target"; then
        print_warn "Could not track ${slug}: unexpected value in its install record."
        return 1
    fi

    if [[ "$method" == "apt" || "$method" == "pacman" ]]; then
        local existing
        if existing="$(get_record "$category" "$slug")" && [[ "${existing%%|*}" == "$method" ]]; then
            target="$(merge_target_list "${existing#*|}" "$target")"
        fi
    fi

    if ! $SUDO mkdir -p "$(dirname "$INSTALL_RECORD_FILE")" 2>/dev/null; then
        print_warn "Could not save the install record for ${slug}; Uninstall [Apps/Utilities] will not be able to remove it."
        return 1
    fi

    forget_install "$category" "$slug"

    if printf '%s|%s|%s|%s\n' "$category" "$slug" "$method" "$target" \
        | $SUDO tee -a "$INSTALL_RECORD_FILE" >/dev/null 2>&1; then
        return 0
    fi

    print_warn "Could not save the install record for ${slug}; Uninstall [Apps/Utilities] will not be able to remove it."
    return 1
}

# get_record <category> <slug> -> prints "method|target" for that item
# (the last matching line wins) or returns 1 when there is none. An
# old-format line comes back as "legacy|".
get_record() {
    local category="$1"
    local slug="$2"
    local line c s m t found=""

    [[ -f "$INSTALL_RECORD_FILE" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *"|"* ]]; then
            IFS='|' read -r c s m t <<< "$line"
            if [[ "$c" == "$category" && "$s" == "$slug" ]]; then
                found="${m}|${t}"
            fi
        elif [[ "$line" == "${category}:${slug}" ]]; then
            found="legacy|"
        fi
    done < "$INSTALL_RECORD_FILE"

    [[ -n "$found" ]] || return 1
    printf '%s' "$found"
}

is_recorded() {
    get_record "$1" "$2" >/dev/null
}

forget_install() {
    local category="$1"
    local slug="$2"
    local tmp line c s

    [[ -f "$INSTALL_RECORD_FILE" ]] || return 0
    tmp="$(mktemp)" || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue

        if [[ "$line" == *"|"* ]]; then
            IFS='|' read -r c s _ <<< "$line"
        else
            c="${line%%:*}"
            s="${line#*:}"
        fi

        [[ "$c" == "$category" && "$s" == "$slug" ]] && continue
        printf '%s\n' "$line" >> "$tmp"
    done < "$INSTALL_RECORD_FILE"

    $SUDO cp "$tmp" "$INSTALL_RECORD_FILE" 2>/dev/null
    rm -f "$tmp"
}

# legacy_record_to_entry <category> <slug> -> prints the v2 line for an
# old "category:slug" entry, or returns 1 when it can't be verified. This
# is the one place that still works out "how was it installed" from the
# current state of the system, and it only converts what it can confirm;
# anything doubtful is dropped, which only means Luxury won't offer to
# remove it -- it never causes something to be removed.
legacy_record_to_entry() {
    local category="$1"
    local slug="$2"
    local method_target method target resolved

    # Built-from-source programs keep a manifest of their files.
    if [[ "$category" == "util" ]]; then
        case "$slug" in
            lavat|peaclock)
                if [[ -s "${COMPILED_RECORD_DIR}/${slug}.list" ]]; then
                    printf '%s|%s|compiled|%s' "$category" "$slug" "$slug"
                    return 0
                fi
                # lavat is always built from source; peaclock only on
                # Debian. Without a manifest there is nothing safe to do.
                if [[ "$slug" == "lavat" || "$DISTRO_FAMILY" == "debian" ]]; then
                    return 1
                fi
                ;;
        esac
    fi

    method_target="$(resolve_default_target "$category" "$slug")"
    method="${method_target%%:*}"
    target="${method_target#*:}"

    case "$method" in
        apt|pacman|flatpak|snap)
            is_target_present "$method" "$target" || return 1
            ;;
        command)
            # Only a binary that sits in /usr/local/bin (where the
            # official installer scripts put it) can be Luxury's, and
            # never one that a package owns.
            resolved="$(command -v "$target" 2>/dev/null)" || return 1
            [[ "$resolved" == /usr/local/bin/* ]] || return 1
            path_is_package_owned "$resolved" && return 1
            method="path"
            target="$resolved"
            ;;
        *)
            return 1
            ;;
    esac

    record_target_is_safe "$method" "$target" || return 1
    printf '%s|%s|%s|%s' "$category" "$slug" "$method" "$target"
}

# migrate_install_records -> one-time upgrade of "category:slug" lines.
migrate_install_records() {
    [[ -f "$INSTALL_RECORD_FILE" ]] || return 0
    grep -qE '^[a-z]+:[^|:]+$' "$INSTALL_RECORD_FILE" 2>/dev/null || return 0

    check_sudo || return 0

    local tmp line category slug entry
    local -a dropped=()
    tmp="$(mktemp)" || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue

        if [[ "$line" == *"|"* ]]; then
            printf '%s\n' "$line" >> "$tmp"
        elif [[ "$line" =~ ^([a-z]+):([^|:]+)$ ]]; then
            category="${BASH_REMATCH[1]}"
            slug="${BASH_REMATCH[2]}"
            if entry="$(legacy_record_to_entry "$category" "$slug")"; then
                printf '%s\n' "$entry" >> "$tmp"
            else
                dropped+=("$slug")
            fi
        fi
    done < "$INSTALL_RECORD_FILE"

    if $SUDO cp "$tmp" "$INSTALL_RECORD_FILE" 2>/dev/null; then
        if (( ${#dropped[@]} > 0 )); then
            print_warn "Upgraded Luxury's install records. Could not confirm how these were installed, so Luxury will not offer to remove them: ${dropped[*]}"
        fi
    fi

    rm -f "$tmp"
    return 0
}

# was_already_present <category> <slug> -> is this software on the
# system right now? Only used for the ✓ marks in the menus and by the
# migration above; it is never used to decide what to uninstall. Reuses
# resolve_default_target/is_target_present (defined later, in the SAFE
# UNINSTALL SYSTEM section -- fine in bash, since nothing here runs until
# main() is reached at the bottom of the script).
was_already_present() {
    local category="$1"
    local slug="$2"
    local method_target method target

    method_target="$(resolve_default_target "$category" "$slug")"
    method="${method_target%%:*}"
    target="${method_target#*:}"

    [[ "$method" != "unknown" && -n "$target" ]] || return 1
    is_target_present "$method" "$target"
}

# finalize_install <category> <slug> <status> <name> -> the single place
# where an install is recorded, verified and announced.
#
# - What the install code reported (INSTALL_RESULT_*) is recorded when it
#   is really on the system, even if a LATER step of a multi-step install
#   failed, so what Luxury did put there is never left untracked.
# - A "success" whose target is missing afterwards is reported as a
#   failure instead of being trusted.
# - Nothing is recorded when nothing was reported: the software was
#   already there and is not Luxury's to remove.
finalize_install() {
    local category="$1"
    local slug="$2"
    local status="$3"
    local name="$4"

    if [[ -n "$INSTALL_RESULT_METHOD" ]]; then
        if is_target_present "$INSTALL_RESULT_METHOD" "$INSTALL_RESULT_TARGET"; then
            record_install "$category" "$slug" "$INSTALL_RESULT_METHOD" "$INSTALL_RESULT_TARGET" || true
        elif [[ "$status" -eq 0 ]]; then
            print_err "${name}: the installer reported success, but ${INSTALL_RESULT_TARGET} (${INSTALL_RESULT_METHOD}) was not found afterwards."
            return 1
        fi
    fi

    [[ "$status" -eq 0 ]] || return "$status"

    announce_installed "$category" "$slug"
    return 0
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
    [tty-clock]="tty-clock -c"
)

declare -A HELP_CMD=(
    [7zip]="7z --help"
    [unrar]="unrar"
)

# announce_installed <category> <slug> -> the install functions
# already print their own "✓ X installed." line via print_ok, so
# this only adds a hint right after it, avoiding a duplicate
# message.
#
# - Anything in RUN_CMD gets "Type [x] to run it." (terminal
#   utilities launched by typing their own command).
# - Anything in HELP_CMD gets "Run it with: [x]" (terminal-only
#   apps invoked with arguments, like 7-Zip/unrar).
# - Apps with a real launcher icon (Brave, Thunderbird, LibreWolf,
#   VLC, LibreOffice, MPV, LocalSend, RetroArch, Bazaar, the
#   terminal emulators) match none of the above and get no hint,
#   since they're opened from the system's app menu.
announce_installed() {
    local category="$1"
    local slug="$2"

    local cmd="${RUN_CMD[$slug]:-}"
    if [[ -n "$cmd" ]]; then
        print_info "Type [${cmd}] to run it."
        return 0
    fi

    local help_cmd="${HELP_CMD[$slug]:-}"
    [[ -n "$help_cmd" ]] && print_info "Run it with: ${help_cmd}"
}

# ============================================================
#                       MAIN APP REGISTRY
# ============================================================

APP_ORDER=(brave thunderbird librewolf vlc libreoffice mpv localsend retroarch 7zip unrar alacritty kitty konsole)

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
    [alacritty]="Alacritty"
    [kitty]="Kitty"
    [konsole]="Konsole"
)

declare -A APP_PKG_DEBIAN=(
    [thunderbird]="thunderbird"
    [vlc]="vlc"
    [libreoffice]="libreoffice"
    [mpv]="mpv"
    [7zip]="7zip"
    [unrar]="unrar"
    [alacritty]="alacritty"
    [kitty]="kitty"
    [konsole]="konsole"
)

declare -A APP_PKG_ARCH=(
    [thunderbird]="thunderbird"
    [vlc]="vlc"
    [libreoffice]="libreoffice-still"
    [mpv]="mpv"
    [7zip]="7zip"
    [unrar]="unrar"
    [alacritty]="alacritty"
    [kitty]="kitty"
    [konsole]="konsole"
)

declare -A APP_CUSTOM_DEBIAN=(
    [brave]="install_brave_origin_debian"
    [librewolf]="install_librewolf_debian"
    [localsend]="install_localsend_debian"
    [retroarch]="install_retroarch_debian"
    [thunderbird]="install_thunderbird_debian"
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
    local result=0

    reset_install_result

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        custom_fn="${APP_CUSTOM_DEBIAN[$slug]:-}"
        if [[ -n "$custom_fn" ]]; then
            "$custom_fn" || result=$?
        else
            install_tracked_apt "${APP_PKG_DEBIAN[$slug]:-}" "$name" || result=$?
        fi
    else
        custom_fn="${APP_CUSTOM_ARCH[$slug]:-}"
        if [[ -n "$custom_fn" ]]; then
            "$custom_fn" || result=$?
        else
            install_tracked_pacman "${APP_PKG_ARCH[$slug]:-}" "$name" || result=$?
        fi
    fi

    finalize_install "app" "$slug" "$result" "$name"
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
        read -r -p "Select: " choice || return 0

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

# detect_kernel_package -> prints the package base (pkgbase) of the kernel
# that is RUNNING right now: linux, linux-lts, linux-zen, linux-cachyos...
# Returns 1 when it can't be identified with confidence. Callers must ask
# or abort instead of assuming "linux": DKMS needs the headers of the
# real kernel, and custom kernels (CachyOS, Xanmod, Manjaro's linuxNNN...)
# have package names that `uname -r` alone can't tell apart.
detect_kernel_package() {
    local krel moddir pkgbase="" owner=""

    krel="$(uname -r 2>/dev/null)" || return 1
    [[ -n "$krel" ]] || return 1
    moddir="/usr/lib/modules/${krel}"

    # 1. Every packaged Arch kernel ships its own pkgbase next to its modules.
    if [[ -r "${moddir}/pkgbase" ]]; then
        IFS= read -r pkgbase < "${moddir}/pkgbase" || true
        pkgbase="${pkgbase//[[:space:]]/}"
        if [[ "$pkgbase" =~ ^[a-z0-9][a-z0-9._+-]*$ ]]; then
            printf '%s' "$pkgbase"
            return 0
        fi
    fi

    # 2. Ask pacman which package owns the running kernel image.
    if [[ -e "${moddir}/vmlinuz" ]]; then
        owner="$(pacman -Qqo "${moddir}/vmlinuz" 2>/dev/null | head -n1)"
        if [[ "$owner" =~ ^[a-z0-9][a-z0-9._+-]*$ ]]; then
            printf '%s' "$owner"
            return 0
        fi
    fi

    # 3. The modules directory is gone (kernel upgraded but not rebooted
    #    yet): fall back to the version suffix of the official kernels
    #    only. -rt-lts has to be tested before -lts, which it also matches.
    case "$krel" in
        *-rt-lts)   printf 'linux-rt-lts' ;;
        *-lts)      printf 'linux-lts' ;;
        *-zen)      printf 'linux-zen' ;;
        *-hardened) printf 'linux-hardened' ;;
        *-rt)       printf 'linux-rt' ;;
        *-arch*)    printf 'linux' ;;
        *)          return 1 ;;
    esac
}

# nvidia_family_from_lspci_line <one line of `lspci -nn`> -> prints the
# driver family that GPU needs:
#   turing+      Turing, Ampere, Ada, Hopper, Blackwell -> open kernel modules
#   580xx        Maxwell, Pascal, Volta                 -> nvidia-580xx (AUR)
#   470xx        Kepler                                 -> nvidia-470xx (AUR)
#   390xx        Fermi                                  -> nvidia-390xx (AUR)
#   340xx        Tesla (G80-G200)                       -> nvidia-340xx (AUR)
#   unsupported  Curie and older (NV3x/NV4x and earlier)
#   unknown      anything that can't be matched with confidence
#
# The family comes from the GPU's chip codename, which pci.ids puts in front
# of the marketing name ("GP104 [GeForce GTX 1070]"), not from a pattern
# over marketing names: the same name can hide different generations (the
# GeForce MX line spans Maxwell, Pascal and Turing). The PCI device id is
# only used as a cross-check: Turing and newer start at 0x1E00 and nothing
# older reaches it, so a codename that disagrees with the id is rejected.
nvidia_family_from_lspci_line() {
    local line="$1"
    local codename="" family="" id=0

    if [[ "$line" =~ \[10de:([0-9A-Fa-f]{4})\] ]]; then
        id=$((16#${BASH_REMATCH[1]}))
    else
        printf 'unknown'
        return
    fi

    if [[ "$line" =~ NVIDIA[[:space:]]+Corporation[[:space:]]+([A-Za-z0-9]+) ]]; then
        codename="${BASH_REMATCH[1]^^}"
    fi

    case "$codename" in
        TU[0-9][0-9][0-9]*|GA[0-9][0-9][0-9]*|AD[0-9][0-9][0-9]*|GH[0-9][0-9][0-9]*|GB[0-9][0-9][0-9]*)
            family="turing+"
            ;;
        GV[0-9][0-9][0-9]*|GP[0-9][0-9][0-9]*|GM[0-9][0-9][0-9]*)
            family="580xx"
            ;;
        GK[0-9][0-9][0-9]*)
            family="470xx"
            ;;
        GF[0-9][0-9][0-9]*)
            family="390xx"
            ;;
        G[89][0-9]|G[89][0-9][A-Z]*|GT[0-9][0-9][0-9]*)
            family="340xx"
            ;;
        G[0-9][0-9]|G[0-9][0-9][A-Z]*|NV[0-9][0-9]*|MCP[0-9]*)
            family="unsupported"
            ;;
        *)
            printf 'unknown'
            return
            ;;
    esac

    if [[ "$family" == "turing+" ]]; then
        (( id >= 0x1E00 )) || { printf 'unknown'; return; }
    else
        (( id < 0x1E00 )) || { printf 'unknown'; return; }
    fi

    printf '%s' "$family"
}

# detect_nvidia_generation -> the family (see above) of the NVIDIA GPU(s)
# in this machine. "unknown" when lspci is missing, there is no NVIDIA
# GPU, or the GPUs belong to different families.
detect_nvidia_generation() {
    command -v lspci >/dev/null 2>&1 || { printf 'unknown'; return; }

    local line family result=""

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        family="$(nvidia_family_from_lspci_line "$line")"

        if [[ -z "$result" ]]; then
            result="$family"
        elif [[ "$result" != "$family" ]]; then
            printf 'unknown'
            return
        fi
    done < <(lspci -nn 2>/dev/null \
        | grep -iE 'vga compatible|3d controller|display controller' \
        | grep -iE '\[10de:')

    printf '%s' "${result:-unknown}"
}

nvidia_family_label() {
    case "$1" in
        turing+)     printf 'Turing (RTX / GTX 16xx) or newer' ;;
        580xx)       printf 'Maxwell / Pascal / Volta (GTX 750, 9xx, 10xx, Titan V)' ;;
        470xx)       printf 'Kepler (GTX 6xx / 7xx)' ;;
        390xx)       printf 'Fermi (GTX 4xx / 5xx)' ;;
        340xx)       printf 'Tesla (GeForce 8, 9, 100-300 series)' ;;
        unsupported) printf 'older than Tesla (Curie or earlier)' ;;
        *)           printf 'unknown' ;;
    esac
}

# open_driver_blocked_for_gpu -> returns 0 (after saying why) when the
# detected GPU can't run the open kernel modules, so a Pascal or older
# card is never handed nvidia-open by mistake.
open_driver_blocked_for_gpu() {
    local detected
    detected="$(detect_nvidia_generation)"

    case "$detected" in
        580xx|470xx|390xx|340xx)
            print_err "Your NVIDIA GPU ($(nvidia_family_label "$detected")) cannot use the open kernel modules."
            print_info "Use the NVIDIA Legacy option (branch ${detected}) instead."
            return 0
            ;;
        unsupported)
            print_err "Your NVIDIA GPU is older than Tesla; no packaged NVIDIA driver supports it."
            print_info "The open-source nouveau driver (part of Mesa) is the option for it."
            return 0
            ;;
    esac

    return 1
}

# install_kernel_headers_arch -> installs the headers of the RUNNING
# kernel, which DKMS needs to build a module for it. The headers package
# is "<pkgbase>-headers" for every packaged Arch kernel.
install_kernel_headers_arch() {
    local kernel_pkg headers_pkg

    if ! kernel_pkg="$(detect_kernel_package)"; then
        print_err "Could not identify the package of the running kernel, so its headers can't be chosen automatically."
        print_info "Install the headers that match your kernel (usually <kernel package>-headers) and try again."
        return 1
    fi

    headers_pkg="${kernel_pkg}-headers"
    print_info "Detected kernel: ${kernel_pkg}"

    if is_installed "$headers_pkg"; then
        print_ok "Kernel headers (${kernel_pkg}) are already installed."
        return 0
    fi

    if ! pacman_has_package "$headers_pkg"; then
        print_err "Headers package not found in the configured repositories: ${headers_pkg}"
        print_info "DKMS needs the headers of the running kernel. Install them manually first."
        return 1
    fi

    install_pacman_package "$headers_pkg" "Kernel headers (${kernel_pkg})"
}

# install_nvidia_auto_arch -> reads the GPU's family and installs the
# matching driver without requiring the user to already know which
# branch their card needs. Falls back to asking for a manual choice when
# detection can't be made with confidence, rather than risking the wrong
# driver.
install_nvidia_auto_arch() {
    local generation

    command -v lspci >/dev/null 2>&1 \
        || print_info "Tip: install pciutils so Luxury can read your GPU model."

    generation="$(detect_nvidia_generation)"

    case "$generation" in
        turing+)
            print_info "Detected GPU: $(nvidia_family_label "$generation")."
            install_nvidia_arch
            ;;
        580xx|470xx|390xx|340xx)
            print_info "Detected GPU: $(nvidia_family_label "$generation")."
            install_nvidia_legacy_arch "$generation"
            ;;
        unsupported)
            print_err "Detected GPU: older than Tesla. No NVIDIA driver Luxury can install supports it."
            print_info "The open-source nouveau driver (part of Mesa) is the option for this GPU."
            return 1
            ;;
        *)
            print_warn "Could not confidently detect the NVIDIA GPU generation."
            print_info "Please pick manually: NVIDIA Open, NVIDIA Open + DKMS, or NVIDIA Legacy."
            return 1
            ;;
    esac
}

# install_nvidia_arch -> the open driver for the running kernel:
# linux -> nvidia-open, linux-lts -> nvidia-open-lts, any other kernel ->
# nvidia-open-dkms (rebuilt for whatever kernel is installed).
install_nvidia_arch() {
    local kernel_pkg

    if open_driver_blocked_for_gpu; then
        return 1
    fi

    if ! kernel_pkg="$(detect_kernel_package)"; then
        print_err "Could not identify the package of the running kernel."
        print_info "Install nvidia-open-dkms and the headers of your kernel manually."
        return 1
    fi

    case "$kernel_pkg" in
        linux)
            install_pacman_package "nvidia-open" "NVIDIA Open Driver"
            ;;
        linux-lts)
            if pacman_has_package "nvidia-open-lts"; then
                install_pacman_package "nvidia-open-lts" "NVIDIA Open Driver (LTS)"
            else
                print_warn "nvidia-open-lts is not available in the configured repositories. Using DKMS instead."
                install_nvidia_dkms_arch
            fi
            ;;
        *)
            print_warn "Running kernel package: ${kernel_pkg}. Arch only ships prebuilt open modules for 'linux' and 'linux-lts'."
            print_info "Installing the DKMS variant instead, which rebuilds for any kernel."
            install_nvidia_dkms_arch
            ;;
    esac
}

install_nvidia_dkms_arch() {
    if open_driver_blocked_for_gpu; then
        return 1
    fi

    install_kernel_headers_arch || return 1
    install_pacman_package "nvidia-open-dkms" "NVIDIA Open DKMS Driver"
}

# Since 2025-12-20 Arch's official nvidia/nvidia-dkms packages were replaced
# by nvidia-open/nvidia-open-dkms. The open kernel modules require the GPU
# System Processor (GSP), introduced with Turing, so they cannot run on
# Volta, Pascal, Maxwell or older cards. Those need one of the community
# maintained legacy branches from the AUR, and WHICH one depends on the
# generation:
#   Maxwell / Pascal / Volta -> nvidia-580xx-dkms
#   Kepler                   -> nvidia-470xx-dkms
#   Fermi                    -> nvidia-390xx-dkms
#   Tesla (G80-G200)         -> nvidia-340xx-dkms

# prompt_nvidia_legacy_branch -> asks which branch (menus go to stderr so
# the answer can be captured with $(...)).
prompt_nvidia_legacy_branch() {
    {
        echo
        echo "  Which legacy branch does your GPU need?"
        echo "  [1] 580xx - Maxwell / Pascal / Volta (GTX 750, 9xx, 10xx, Titan V)"
        echo "  [2] 470xx - Kepler (GTX 6xx / 7xx)"
        echo "  [3] 390xx - Fermi (GTX 4xx / 5xx)"
        echo "  [4] 340xx - Tesla (GeForce 8, 9, 100-300 series)"
        echo
    } >&2

    local choice
    read -r -p "Select (Enter to cancel): " choice || choice=""

    case "$choice" in
        1) printf '580xx' ;;
        2) printf '470xx' ;;
        3) printf '390xx' ;;
        4) printf '340xx' ;;
        *)
            print_info "Cancelled." >&2
            return 1
            ;;
    esac
}

# install_nvidia_legacy_arch [branch] -> branch is 580xx, 470xx, 390xx or
# 340xx; it is asked for when omitted. A branch that contradicts the
# detected GPU is refused.
install_nvidia_legacy_arch() {
    local branch="${1:-}"
    local detected answer

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        print_err "Do not build AUR packages as root."
        print_info "Run Luxury as your normal user."
        return 1
    fi

    if [[ -z "$branch" ]]; then
        branch="$(prompt_nvidia_legacy_branch)" || return 1
    fi

    case "$branch" in
        580xx|470xx|390xx|340xx) ;;
        *)
            print_err "Unknown NVIDIA legacy branch: ${branch}"
            return 1
            ;;
    esac

    detected="$(detect_nvidia_generation)"
    case "$detected" in
        turing+)
            print_err "Your NVIDIA GPU is Turing or newer. Legacy drivers are not for it; use the NVIDIA Open option."
            return 1
            ;;
        unsupported)
            print_err "Your NVIDIA GPU is older than Tesla; no packaged NVIDIA driver supports it."
            print_info "The open-source nouveau driver (part of Mesa) is the option for it."
            return 1
            ;;
        580xx|470xx|390xx|340xx)
            if [[ "$detected" != "$branch" ]]; then
                print_err "Your NVIDIA GPU is $(nvidia_family_label "$detected"): it needs the ${detected} branch, not ${branch}."
                return 1
            fi
            ;;
        *)
            print_warn "Could not verify your GPU's generation; trusting your choice of the ${branch} branch."
            ;;
    esac

    if [[ "$branch" != "580xx" ]]; then
        print_warn "The ${branch} branch is a community-maintained AUR package and NVIDIA no longer supports it."
        print_info "It may not work with your current kernel or Xorg; the open-source nouveau driver is often easier for these GPUs."
        read -r -p "Continue anyway? [y/N]: " answer || answer=""
        case "${answer,,}" in
            y|yes) ;;
            *)
                print_info "Cancelled."
                return 1
                ;;
        esac
    fi

    print_info "If the official nvidia, nvidia-lts, nvidia-dkms or nvidia-open* packages are installed, remove them first to avoid conflicts."

    install_kernel_headers_arch || return 1

    if ! detect_aur_helper >/dev/null 2>&1; then
        print_info "No AUR helper detected. Installing Yay automatically..."
        install_aur_helper yay || return 1
    fi

    install_aur_package "nvidia-${branch}-dkms" "NVIDIA Legacy Driver (${branch})"
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

# Ubuntu and Ubuntu-based distros: ubuntu-drivers picks the driver that
# suits the GPU (and the Ubuntu release) by itself.
install_nvidia_ubuntu() {
    if ! ubuntu_has_ubuntu_drivers; then
        if ! install_apt_package "ubuntu-drivers-common" "Ubuntu Drivers"; then
            print_err "Automatic NVIDIA driver support is not available on this distribution."
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

# install_kernel_headers_debian -> the headers DKMS needs to build the
# NVIDIA module: those of the running kernel when the archive has them,
# otherwise the architecture's meta package.
install_kernel_headers_debian() {
    local krel arch exact meta

    krel="$(uname -r 2>/dev/null)"
    arch="$(dpkg --print-architecture 2>/dev/null)"
    exact="linux-headers-${krel}"
    meta="linux-headers-${arch}"

    if [[ -n "$krel" ]] && is_installed "$exact"; then
        print_ok "Kernel headers (${krel}) are already installed."
        return 0
    fi

    if [[ -n "$krel" ]] && apt_has_package "$exact"; then
        install_apt_package "$exact" "Kernel headers (${krel})"
        return $?
    fi

    if [[ -n "$arch" ]] && apt_has_package "$meta"; then
        install_apt_package "$meta" "Kernel headers (${meta})"
        return $?
    fi

    print_warn "Could not find a kernel headers package for ${krel:-this kernel}; DKMS may fail to build the NVIDIA module."
    return 0
}

# Plain Debian (and Debian-based distros that are not Ubuntu-based):
# ubuntu-drivers is an Ubuntu tool and does not know Debian's package
# names. Debian's own route is nvidia-detect, which recommends the right
# driver metapackage (nvidia-driver, or a legacy/tesla one) for the GPU.
# Those packages live in the "non-free" component.
install_nvidia_debian_pure() {
    local report package

    check_sudo || return 1
    ensure_apt_synced || return 1

    if ! apt_has_package "nvidia-detect"; then
        print_err "Debian's NVIDIA packages are in the 'non-free' component, which is not enabled on this system."
        print_info "Enable 'non-free' and 'non-free-firmware' in your APT sources, run 'sudo apt update', then try again."
        print_info "Guide: https://wiki.debian.org/NvidiaGraphicsDrivers"
        return 1
    fi

    install_apt_package "nvidia-detect" "NVIDIA detection tool" || return 1

    report="$(nvidia-detect 2>&1)" || true
    package="$(printf '%s\n' "$report" \
        | grep -oE 'nvidia-(driver|legacy-[0-9]+xx-driver|tesla-[0-9]+-driver)' \
        | head -n1)"

    if [[ -z "$package" ]]; then
        print_err "nvidia-detect did not recommend a driver package for this system:"
        printf '%s\n' "$report"
        return 1
    fi

    print_info "nvidia-detect recommends: ${package}"

    if ! apt_has_package "$package"; then
        print_err "The recommended package is not available in the configured APT sources: ${package}"
        return 1
    fi

    install_kernel_headers_debian || return 1
    install_apt_package "$package" "NVIDIA driver (${package})" || return 1

    if apt_has_package "firmware-misc-nonfree"; then
        install_apt_package "firmware-misc-nonfree" "Non-free firmware" || return 1
    fi

    print_info "Reboot to start using the NVIDIA driver."
    return 0
}

install_nvidia_debian() {
    if [[ "$DISTRO_FLAVOR" == "ubuntu" ]]; then
        install_nvidia_ubuntu
    else
        install_nvidia_debian_pure
    fi
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
            printf '  [1] %bNVIDIA (auto-detect GPU + kernel)%b\n' "$CYAN" "$RESET"
            echo "  [2] NVIDIA Open (Turing / RTX, GTX 16xx and newer)"
            echo "  [3] NVIDIA Open + DKMS (Turing / RTX, GTX 16xx and newer)"
            echo "  [4] NVIDIA Legacy (pick branch: 580xx / 470xx / 390xx / 340xx)"
            echo "  [5] AMD GPU"
            echo "  [6] AMD CPU Microcode"
            echo "  [7] Intel GPU"
            echo "  [8] Intel CPU Microcode"
            echo "  [9] Firmware"
        else
            if [[ "$DISTRO_FLAVOR" == "ubuntu" ]]; then
                echo "  [1] NVIDIA (recommended Ubuntu driver)"
            else
                echo "  [1] NVIDIA (Debian driver, needs non-free)"
            fi
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
        read -r -p "Select: " choice || return 0

        if [[ "${choice,,}" == "b" ]]; then
            return 0
        fi

        if [[ "$DISTRO_FAMILY" == "arch" ]]; then
            case "$choice" in
                1) install_nvidia_auto_arch || true; press_enter ;;
                2) install_nvidia_arch || true; press_enter ;;
                3) install_nvidia_dkms_arch || true; press_enter ;;
                4) install_nvidia_legacy_arch || true; press_enter ;;
                5) install_amd_gpu_arch || true; press_enter ;;
                6) install_amd_cpu_arch || true; press_enter ;;
                7) install_intel_gpu_arch || true; press_enter ;;
                8) install_intel_cpu_arch || true; press_enter ;;
                9) install_firmware_arch || true; press_enter ;;
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

# ------------------------------------------------------------
# Programs built from source (Peaclock on Debian/Ubuntu, lavat).
#
# These two have no package to track. Each one is built as a normal user
# and installed into a scratch "stage" directory first (DESTDIR-style), so
# the real system is not touched until the whole install is known to have
# worked. Only then are the staged files copied into place, and exactly
# those paths are written to a manifest that "Uninstall [Apps/Utilities]" uses later:
#
#   <slug>.list   every file and symlink that was installed
#   <slug>.dirs   directories that did not exist before and were created
#
# Nothing outside /usr/local is ever installed or removed, and an install
# that would overwrite a file that already exists is refused. If the build
# or the copy fails, or Luxury is interrupted, whatever was copied is
# rolled back. Build-only dependencies (a compiler, headers, build
# systems) are removed again once the build is over -- whether it worked
# or not -- but only the ones Luxury itself had to install.
# ------------------------------------------------------------

COMPILED_RECORD_DIR="/var/lib/luxury-downloader/compiled"
COMPILED_ALLOWED_PREFIX="/usr/local/"

# Slug of the source install whose files are being copied right now, so an
# interruption can roll it back (see cleanup_on_exit).
COMPILED_IN_PROGRESS_SLUG=""

# compiled_path_is_safe <path> -> strictly inside /usr/local, no "..", no
# newlines. Applied both when installing and when removing.
compiled_path_is_safe() {
    local path="$1"

    [[ "$path" == "${COMPILED_ALLOWED_PREFIX}"?* ]] || return 1
    [[ "$path" != *"/../"* && "$path" != */.. && "$path" != *$'\n'* ]] || return 1
    return 0
}

# uninstall_compiled <slug> -> removes exactly the files recorded for this
# slug's source install, then the directories it created (only if they
# are empty by now), then the manifests themselves.
uninstall_compiled() {
    local slug="$1"
    local manifest="${COMPILED_RECORD_DIR}/${slug}.list"
    local dirs_manifest="${COMPILED_RECORD_DIR}/${slug}.dirs"
    local path

    [[ -s "$manifest" ]] || return 1
    check_sudo || return 1

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue

        if ! compiled_path_is_safe "$path"; then
            print_warn "Skipping an unexpected path in the manifest: ${path}"
            continue
        fi

        if path_is_package_owned "$path"; then
            print_warn "Skipping package-owned path: $path"
            continue
        fi

        if [[ -e "$path" || -L "$path" ]]; then
            $SUDO rm -f -- "$path"
        fi
    done < "$manifest"

    if [[ -s "$dirs_manifest" ]]; then
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue

            case "$path" in
                "${COMPILED_ALLOWED_PREFIX}"?*)
                    $SUDO rmdir -- "$path" 2>/dev/null || true
                    ;;
            esac
        done < <(LC_ALL=C sort -r "$dirs_manifest")
    fi

    $SUDO rm -f -- "$manifest" "$dirs_manifest"
    return 0
}

# abort_compiled_install <slug> -> undoes a source install that failed
# while its files were being copied.
abort_compiled_install() {
    local slug="$1"

    COMPILED_IN_PROGRESS_SLUG=""
    uninstall_compiled "$slug" >/dev/null 2>&1 || true
    $SUDO rm -f -- "${COMPILED_RECORD_DIR}/${slug}.list" "${COMPILED_RECORD_DIR}/${slug}.dirs" 2>/dev/null || true
}

# Called on the way out of the script: if it is interrupted while the
# files of a source install are being copied, roll that install back.
rollback_compiled_in_progress() {
    [[ -n "$COMPILED_IN_PROGRESS_SLUG" ]] || return 0

    local slug="$COMPILED_IN_PROGRESS_SLUG"
    print_warn "Interrupted while installing ${slug}. Rolling back the files it had copied..."
    abort_compiled_install "$slug"
}

# install_staged_tree <slug> <stage_dir> -> checks what the build put in
# the stage directory, copies it into the real system and writes the
# manifests. On success it reports ("compiled", slug) as the install's
# result; on any failure the real system is left as it was.
install_staged_tree() {
    local slug="$1"
    local stage="$2"
    local manifest="${COMPILED_RECORD_DIR}/${slug}.list"
    local dirs_manifest="${COMPILED_RECORD_DIR}/${slug}.dirs"
    local -a files=() dirs=() new_dirs=() collisions=()
    local rel path

    # 1. Everything the build wants to install, as absolute paths.
    while IFS= read -r -d '' rel; do
        path="/${rel}"
        if ! compiled_path_is_safe "$path"; then
            print_err "The build wants to install outside ${COMPILED_ALLOWED_PREFIX}: ${path}"
            return 1
        fi
        files+=("$path")
    done < <(cd "$stage" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\0' | LC_ALL=C sort -z)

    while IFS= read -r -d '' rel; do
        path="/${rel}"
        if [[ "$path" == *$'\n'* ]]; then
            print_err "The build created a directory with an unsupported name."
            return 1
        fi
        case "$path" in
            /usr|/usr/local|"${COMPILED_ALLOWED_PREFIX}"*)
                dirs+=("$path")
                ;;
            *)
                print_err "The build wants to create a directory outside ${COMPILED_ALLOWED_PREFIX}: ${path}"
                return 1
                ;;
        esac
    done < <(cd "$stage" && find . -mindepth 1 -type d -printf '%P\0' | LC_ALL=C sort -z)

    if [[ -n "$(cd "$stage" && find . -mindepth 1 ! -type f ! -type l ! -type d -print -quit)" ]]; then
        print_err "The build produced special files (devices, sockets...), which Luxury will not install."
        return 1
    fi

    if (( ${#files[@]} == 0 )); then
        print_err "The build did not install any files."
        return 1
    fi

    # 2. Refuse to overwrite anything that already exists.
    for path in "${files[@]}"; do
        if [[ -e "$path" || -L "$path" ]]; then
            collisions+=("$path")
        fi
    done

    if (( ${#collisions[@]} > 0 )); then
        print_err "Refusing to overwrite files that already exist:"
        printf '    %s\n' "${collisions[@]}"
        return 1
    fi

    for path in "${dirs[@]}"; do
        if [[ -e "$path" || -L "$path" ]]; then
            if [[ ! -d "$path" ]]; then
                print_err "Cannot create the directory ${path}: something else is already there."
                return 1
            fi
        else
            new_dirs+=("$path")
        fi
    done

    # 3. The manifests go first, so an install that fails or is
    #    interrupted halfway can still be rolled back exactly.
    check_sudo || return 1

    if ! $SUDO mkdir -p "$COMPILED_RECORD_DIR"; then
        print_err "Could not create ${COMPILED_RECORD_DIR}."
        return 1
    fi

    if ! printf '%s\n' "${files[@]}" | $SUDO tee "$manifest" >/dev/null; then
        print_err "Could not write the install manifest."
        abort_compiled_install "$slug"
        return 1
    fi

    if (( ${#new_dirs[@]} > 0 )); then
        if ! printf '%s\n' "${new_dirs[@]}" | $SUDO tee "$dirs_manifest" >/dev/null; then
            print_err "Could not write the install manifest."
            abort_compiled_install "$slug"
            return 1
        fi
    else
        $SUDO rm -f -- "$dirs_manifest"
    fi

    # 4. Copy: directories first (parents before children), then files.
    COMPILED_IN_PROGRESS_SLUG="$slug"

    for path in "${new_dirs[@]}"; do
        if ! $SUDO mkdir -m 0755 -- "$path"; then
            print_err "Could not create ${path}."
            abort_compiled_install "$slug"
            return 1
        fi
    done

    for path in "${files[@]}"; do
        if ! $SUDO cp -P --preserve=mode,timestamps -- "${stage}${path}" "$path"; then
            print_err "Could not copy ${path}."
            abort_compiled_install "$slug"
            return 1
        fi
    done

    COMPILED_IN_PROGRESS_SLUG=""
    set_install_result "compiled" "$slug"
    return 0
}

# install_build_deps <pkg...> -> installs each with the current
# distro's package manager, remembering (in BUILD_ONLY_DEPS) only
# the ones that were not already on the system, so remove_build_
# only_deps can clean up precisely the ones this build needed. A
# package is remembered BEFORE its install is attempted, so one that
# fails halfway is still cleaned up.
BUILD_ONLY_DEPS=()

install_build_deps() {
    BUILD_ONLY_DEPS=()
    local pkg
    for pkg in "$@"; do
        is_installed "$pkg" || BUILD_ONLY_DEPS+=("$pkg")

        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            install_apt_package "$pkg" "$pkg" || return 1
        else
            install_pacman_package "$pkg" "$pkg" || return 1
        fi
    done
}

# remove_build_only_deps -> uninstalls whatever install_build_deps
# had to add for the build that just finished (or failed). Never touches
# a package that was already present before that build started.
remove_build_only_deps() {
    local pkg
    for pkg in "${BUILD_ONLY_DEPS[@]}"; do
        print_info "Removing build-only dependency: ${pkg}..."
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            $SUDO apt remove -y "$pkg" >/dev/null 2>&1
        else
            $SUDO pacman -R --noconfirm "$pkg" >/dev/null 2>&1
        fi
    done
    BUILD_ONLY_DEPS=()
}

# _build_in_workdir ... -> the body of compile_and_install_from_source;
# split out so the work directory is deleted on every way out of it.
_build_in_workdir() {
    local slug="$1"
    local name="$2"
    local repo="$3"
    local stage_fn="$4"
    local workdir="$5"
    local src="${workdir}/src"
    local stage="${workdir}/stage"
    local shim="${workdir}/nosudo"
    local tool

    mkdir -p "$stage" "$shim" || return 1

    if ! git clone --depth 1 "$repo" "$src"; then
        print_err "Could not clone ${name}."
        return 1
    fi

    # Some upstream install scripts fall back to `sudo make install` when
    # a plain install fails. Sudo would drop DESTDIR and install straight
    # into the system, bypassing the stage and the tracking, so during
    # the build sudo and doas are replaced by stubs that just fail.
    for tool in sudo doas; do
        printf '#!/bin/sh\necho "Luxury: privilege escalation is disabled while building %s." >&2\nexit 1\n' "$name" > "${shim}/${tool}"
        chmod +x "${shim}/${tool}"
    done

    print_info "Building ${name}..."
    if ! ( cd "$src" && export PATH="${shim}:${PATH}" && "$stage_fn" "$stage" ); then
        print_err "${name} build failed. Nothing was installed."
        return 1
    fi

    print_info "Installing ${name}..."
    if ! install_staged_tree "$slug" "$stage"; then
        print_err "${name} installation failed. Nothing was left behind."
        return 1
    fi

    return 0
}

# compile_and_install_from_source <slug> <name> <repo_url> <stage_fn>
# -> clones, builds and installs into a stage directory (stage_fn does the
# building and must install ONLY into the directory it is given, without
# needing root), then installs the staged files with install_staged_tree.
compile_and_install_from_source() {
    local slug="$1"
    local name="$2"
    local repo="$3"
    local stage_fn="$4"
    local workdir rc=0

    workdir="$(mktemp -d)" || {
        print_err "Could not create a temporary directory."
        return 1
    }
    register_cleanup "$workdir"

    _build_in_workdir "$slug" "$name" "$repo" "$stage_fn" "$workdir" || rc=$?

    rm -rf -- "$workdir"
    return "$rc"
}

# build_compiled_program <slug> <name> <repo_url> <stage_fn> <build_dep>...
# -> the whole flow, including the build dependencies: they are removed
# again whether the build worked or not.
build_compiled_program() {
    local slug="$1"
    local name="$2"
    local repo="$3"
    local stage_fn="$4"
    local rc=0
    shift 4

    check_sudo || return 1

    install_build_deps "$@" || rc=1

    if (( rc == 0 )); then
        compile_and_install_from_source "$slug" "$name" "$repo" "$stage_fn" || rc=1
    fi

    remove_build_only_deps
    return "$rc"
}

# Run inside the cloned source tree; each installs ONLY into the stage
# directory it is given (no root needed).
stage_install_peaclock() {
    local stage="$1"

    # RUNME.sh installs with a plain `make install`, which honors DESTDIR.
    ./RUNME.sh build && DESTDIR="$stage" ./RUNME.sh install
}

stage_install_lavat() {
    local stage="$1"

    # lavat's makefile has no DESTDIR support, but it does install under
    # $(PREFIX), and a PREFIX given on the command line overrides it.
    make install PREFIX="${stage}/usr/local"
}

install_peaclock_debian() {
    if command -v peaclock >/dev/null 2>&1; then
        print_ok "Peaclock is already installed."
        return 0
    fi

    print_info "Peaclock is not provided by the standard Ubuntu 26.04 repositories."
    print_info "Building the current upstream release from source..."

    build_compiled_program "peaclock" "Peaclock" \
        "https://github.com/octobanana/peaclock.git" stage_install_peaclock \
        git cmake build-essential libicu-dev libpthread-stubs0-dev || return 1

    print_ok "Peaclock installed."
    return 0
}

install_peaclock_arch() {
    if pacman_has_package "peaclock"; then
        install_tracked_pacman "peaclock" "Peaclock"
    else
        install_tracked_aur "peaclock" "Peaclock"
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

    local -a deps
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        deps=(git build-essential)
    else
        deps=(git base-devel)
    fi

    build_compiled_program "lavat" "lavat" \
        "https://github.com/AngelJumbo/lavat" stage_install_lavat \
        "${deps[@]}" || return 1

    print_ok "lavat installed."
    return 0
}

UTIL_ORDER=(cmatrix cava lavat peaclock fastfetch sl pipes sptlrx btop htop tty-clock)

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
    [tty-clock]="tty-clock"
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
    local result=0
    local pkg

    reset_install_result

    if [[ "$slug" == "lavat" ]]; then
        install_lavat || result=$?

    elif [[ "$slug" == "peaclock" ]]; then
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            install_peaclock_debian || result=$?
        else
            install_peaclock_arch || result=$?
        fi

    # pipes.sh, sptlrx and tty-clock have no official Arch repo package
    # (AUR only), and pipes.sh's APT binary package is named differently
    # (pipes-sh) from its AUR name (pipes.sh), so these get a small
    # special case instead of living in the generic UTIL_APT/UTIL_PACMAN
    # tables.
    elif [[ "$slug" == "pipes" ]]; then
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            install_tracked_apt "pipes-sh" "$name" || result=$?
        else
            install_tracked_aur "pipes.sh" "$name" || result=$?
        fi

    elif [[ "$slug" == "sptlrx" ]]; then
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            install_tracked_apt "sptlrx" "$name" || result=$?
        else
            install_tracked_aur "sptlrx" "$name" || result=$?
        fi

    elif [[ "$slug" == "tty-clock" ]]; then
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            install_tracked_apt "tty-clock" "$name" || result=$?
        else
            install_tracked_aur "tty-clock" "$name" || result=$?
        fi

    elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
        install_tracked_apt "${UTIL_APT[$slug]:-}" "$name" || result=$?

    else
        pkg="${UTIL_PACMAN[$slug]:-}"
        if pacman_has_package "$pkg"; then
            install_tracked_pacman "$pkg" "$name" || result=$?
        else
            print_err "Package not available in the configured Arch repositories: ${pkg:-$slug}"
            result=1
        fi
    fi

    finalize_install "util" "$slug" "$result" "$name"
}

# ============================================================
#                    SAFE UNINSTALL SYSTEM
# ============================================================
# Only ever acts on entries in INSTALL_RECORD_FILE (things Luxury
# itself installed) -- see record_install() above -- and only with
# the exact method and target that were recorded when it installed
# them. Never touches software the user installed some other way.

# resolve_default_target <category> <slug> -> prints "method:target" for
# where this software normally lives on the CURRENT distro family. It is
# only used to draw the menus' ✓ marks and by migrate_install_records();
# it is NEVER used to decide what to uninstall, because the state of the
# system can change between an install and an uninstall. method is one
# of: apt, pacman, flatpak, snap, command (any program of that name on
# PATH), unknown.
resolve_default_target() {
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
            thunderbird)
                # See the THUNDERBIRD section: on Ubuntu the APT package
                # is only a shim for the Snap.
                if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                    thunderbird_target_debian
                else
                    printf 'pacman:thunderbird'
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
            # Always built from source with "make install" on every
            # distro family -- see install_lavat.
            printf 'command:lavat'
            return
            ;;
        peaclock)
            if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                printf 'command:peaclock'
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
        tty-clock)
            if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                printf 'apt:tty-clock'
            else
                printf 'pacman:tty-clock'
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

# present_targets_from_list <comma-separated packages> -> prints, one per
# line, the ones from the list that are currently installed. A plain
# single package (no comma) works the same as before: either one line
# or none. Used so a multi-package record (RetroArch + its cores) can be
# checked and uninstalled package by package instead of as one string.
present_targets_from_list() {
    local list="$1" pkg
    local -a pkgs
    IFS=',' read -r -a pkgs <<< "$list"
    for pkg in "${pkgs[@]}"; do
        [[ -n "$pkg" ]] || continue
        is_installed "$pkg" && printf '%s\n' "$pkg"
    done
}

# any_of_list_installed <comma-separated packages> -> true if at least
# one package in the list is currently installed.
any_of_list_installed() {
    [[ -n "$(present_targets_from_list "$1")" ]]
}

# is_target_present <method> <target> -> is it actually installed
# right now, regardless of what the tracking file says?
is_target_present() {
    local method="$1"
    local target="$2"

    case "$method" in
        apt|pacman) any_of_list_installed "$target" ;;
        flatpak)    command -v flatpak >/dev/null 2>&1 && flatpak info "$target" >/dev/null 2>&1 ;;
        snap)       command -v snap >/dev/null 2>&1 && snap list "$target" >/dev/null 2>&1 ;;
        path)       [[ -e "$target" || -L "$target" ]] ;;
        compiled)   [[ -s "${COMPILED_RECORD_DIR}/${target}.list" ]] ;;
        command)    command -v "$target" >/dev/null 2>&1 ;;
        *)          return 1 ;;
    esac
}

# path_is_package_owned <absolute path> -> does dpkg / pacman own it?
path_is_package_owned() {
    local path="$1"

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        dpkg -S "$path" >/dev/null 2>&1
    else
        pacman -Qo "$path" >/dev/null 2>&1
    fi
}

# uninstall_path_target <absolute path> -> removes one file that an
# installer script put in /usr/local, and only that: never a path outside
# /usr/local, and never a file a package manager has claimed since.
uninstall_path_target() {
    local target="$1"

    if ! compiled_path_is_safe "$target"; then
        print_err "Refusing to remove a path outside ${COMPILED_ALLOWED_PREFIX}: ${target}"
        return 1
    fi

    if path_is_package_owned "$target"; then
        print_err "${target} now belongs to an installed package; not removing it."
        return 1
    fi

    check_sudo || return 1
    $SUDO rm -f -- "$target"
}

# perform_uninstall <method> <target> -> does the actual removal.
perform_uninstall() {
    local method="$1"
    local target="$2"

    case "$method" in
        apt)
            check_sudo || return 1
            # target may be several comma-separated packages (RetroArch +
            # its cores); only ask apt to remove the ones still present,
            # since asking it to remove even one missing package fails
            # the whole command and leaves the rest untouched.
            local -a present=()
            mapfile -t present < <(present_targets_from_list "$target")
            (( ${#present[@]} > 0 )) || return 0
            $SUDO apt remove -y "${present[@]}"
            ;;
        pacman)
            check_sudo || return 1
            local -a present=()
            mapfile -t present < <(present_targets_from_list "$target")
            (( ${#present[@]} > 0 )) || return 0
            $SUDO pacman -R --noconfirm "${present[@]}"
            ;;
        flatpak)
            command -v flatpak >/dev/null 2>&1 || return 1
            flatpak uninstall -y "$target"
            ;;
        snap)
            command -v snap >/dev/null 2>&1 || return 1
            check_sudo || return 1
            $SUDO snap remove "$target"
            ;;
        path)
            uninstall_path_target "$target"
            ;;
        compiled)
            # target is the slug here (e.g. "lavat"): removes exactly the
            # files its manifest lists -- see uninstall_compiled.
            uninstall_compiled "$target"
            ;;
        *)
            return 1
            ;;
    esac
}

# uninstall_entry <category> <slug> -> the full safe flow: was it
# Luxury that installed this, with what method, is it still there,
# then remove exactly that.
uninstall_entry() {
    local category="$1"
    local slug="$2"
    local name

    if [[ "$category" == "app" ]]; then
        name="${APP_NAME[$slug]:-$slug}"
    else
        name="${UTIL_NAME[$slug]:-$slug}"
    fi

    local record method target
    if ! record="$(get_record "$category" "$slug")"; then
        print_warn "${name} wasn't installed with Luxury, or wasn't found."
        return 0
    fi

    method="${record%%|*}"
    target="${record#*|}"

    case "$method" in
        apt|pacman|flatpak|snap|path|compiled)
            ;;
        legacy)
            print_warn "The install record for ${name} is in an old format. Restart Luxury so it can be upgraded, then try again."
            return 1
            ;;
        *)
            print_warn "Not enough information to safely remove ${name}. Please remove it manually."
            return 1
            ;;
    esac

    if [[ -z "$target" ]] || ! record_target_is_safe "$method" "$target"; then
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
        local slug mark
        for slug in "${UTIL_ORDER[@]}"; do
            if was_already_present "util" "$slug"; then
                mark="${GREEN}✓${RESET}"
            else
                mark=" "
            fi
            printf '  [%d] [%b] %s\n' "$i" "$mark" "${UTIL_NAME[$slug]:-$slug}"
            ((i++))
        done

        echo
        printf '  %b[B]%b Back\n' "$CYAN" "$RESET"
        echo
        box_bottom "TERMINAL UTILITIES"
        echo

        local choice
        read -r -p "Select: " choice || return 0

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
    reset_install_result

    if is_installed "bazaar" || command -v bazaar >/dev/null 2>&1; then
        if ! ensure_bazaar_runtime; then
            print_err "Bazaar is installed, but its Flatpak/Flathub runtime is not ready."
            return 1
        fi
        print_ok "Bazaar is already installed."
        return 0
    fi

    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        print_err "Bazaar is only offered here through APT on Ubuntu-based systems."
        return 1
    fi

    ensure_apt_synced || return 1

    if ! apt_has_package "bazaar"; then
        print_err "The 'bazaar' APT package is not available on this system."
        print_info "It currently ships on Ubuntu 26.04 and newer (universe)."
        return 1
    fi

    if ! install_tracked_apt "bazaar" "Bazaar"; then
        return 1
    fi

    # Bazaar itself is on the system from here on, so it gets recorded
    # even if the runtime setup below fails.
    if ! ensure_bazaar_runtime; then
        finalize_install "app" "bazaar" 1 "Bazaar" || true
        print_err "Bazaar was installed, but its Flatpak/Flathub runtime could not be set up, so it cannot browse apps yet."
        print_info "Fix the problem above and run Install Bazaar again."
        return 1
    fi

    finalize_install "app" "bazaar" 0 "Bazaar"
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
#                       MENUS / PAGES
# ============================================================

show_apps_page() {
    while true; do
        clear 2>/dev/null || true
        echo
        box_top "APPS"
        echo

        local i=1
        local slug mark
        for slug in "${APP_ORDER[@]}"; do
            if was_already_present "app" "$slug"; then
                mark="${GREEN}✓${RESET}"
            else
                mark=" "
            fi
            printf '  [%d] [%b] %s\n' "$i" "$mark" "${APP_NAME[$slug]:-$slug}"
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
    # the number right after Terminal Utilities, so the existing "app"
    # (1..n_apps) and "util" (n_apps+1..n_apps+n_utils) ranges below
    # stay untouched.
    local bazaar_index=$((n_apps + n_utils + 1))

    while true; do
        clear 2>/dev/null || true
        echo
        box_top "UNINSTALL [APPS/UTILITIES]"
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
        box_bottom "UNINSTALL [APPS/UTILITIES]"
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
    echo "  [7] Uninstall [Apps/Utilities]"
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

    # From here on Luxury can be interrupted in the middle of an install
    # (Ctrl-C, closed terminal): whatever is half done -- copied files,
    # build-only dependencies, temp directories -- is cleaned up on the way out.
    trap cleanup_on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP

    # Always check for a Luxury Downloader update first.
    # Only after this check do we detect the system and open the menu.
    check_for_updates

    require_command bash || return 1
    require_command uname || return 1
    require_command grep || return 1
    require_command sed || return 1

    detect_distro || return 1
    check_architecture || return 1

    # Upgrades install records written by older versions (one-time).
    migrate_install_records

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
