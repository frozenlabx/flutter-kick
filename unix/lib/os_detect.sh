#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: OS and Environment Detection Library
# Detects OS, CPU arch, active shell, disk space, and installs base prerequisites
# ==============================================================================

if [[ -n "${_OS_DETECT_LIB_LOADED:-}" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
_OS_DETECT_LIB_LOADED=1

# Ensure UI library is loaded for logging
SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_LIB_DIR}/ui.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/ui.sh"
fi

# ------------------------------------------------------------------------------
# Global Detection Variables
# ------------------------------------------------------------------------------
OS_TYPE=""            # "macos", "linux", "unsupported"
OS_FAMILY=""          # "macos", "debian", "fedora", "arch", "unknown"
OS_NAME=""            # Human-readable OS name
OS_VERSION=""         # OS version string
CPU_ARCH=""           # "x86_64", "arm64", "unsupported"
ACTIVE_SHELL=""       # "bash", "zsh", "fish", "unknown"
TARGET_SHELL_RC=""    # Primary RC file to inject environment into
# shellcheck disable=SC2034
ALL_CANDIDATE_RCS=()  # All candidate RC files for thorough cleanup/inspection

# ------------------------------------------------------------------------------
# OS Detection
# ------------------------------------------------------------------------------
detect_os() {
    local kernel_name
    kernel_name="$(uname -s 2>/dev/null || echo "Unknown")"

    case "$kernel_name" in
        Darwin)
            OS_TYPE="macos"
            OS_FAMILY="macos"
            if command -v sw_vers >/dev/null 2>&1; then
                OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo "")"
                OS_NAME="macOS ${OS_VERSION}"
            else
                OS_VERSION="$(uname -r)"
                OS_NAME="macOS (Darwin ${OS_VERSION})"
            fi
            ;;
        Linux)
            OS_TYPE="linux"
            if [[ -f /etc/os-release ]]; then
                local id=""
                local id_like=""
                local pretty_name=""
                local ver=""

                id="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'" || true)"
                id_like="$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'" || true)"
                pretty_name="$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'" || true)"
                ver="$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'" || true)"

                OS_NAME="${pretty_name:-Linux}"
                OS_VERSION="${ver:-unknown}"

                local id_combined=" ${id} ${id_like} "

                case "$id_combined" in
                    *" ubuntu "*|*" debian "*|*" pop "*|*" linuxmint "*|*" kali "*|*" elementary "*)
                        OS_FAMILY="debian"
                        ;;
                    *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*)
                        OS_FAMILY="fedora"
                        ;;
                    *" arch "*|*" manjaro "*|*" endeavouros "*|*" artix "*)
                        OS_FAMILY="arch"
                        ;;
                    *)
                        OS_FAMILY="unknown"
                        ;;
                esac
            elif [[ -f /etc/redhat-release ]]; then
                OS_FAMILY="fedora"
                OS_NAME="$(cat /etc/redhat-release)"
                OS_VERSION="unknown"
            elif [[ -f /etc/debian_version ]]; then
                OS_FAMILY="debian"
                OS_NAME="Debian GNU/Linux"
                OS_VERSION="$(cat /etc/debian_version)"
            else
                OS_FAMILY="unknown"
                OS_NAME="Generic Linux"
                OS_VERSION="unknown"
            fi
            ;;
        *)
            OS_TYPE="unsupported"
            OS_FAMILY="unsupported"
            OS_NAME="$kernel_name"
            OS_VERSION="unknown"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# CPU Architecture Detection
# ------------------------------------------------------------------------------
detect_arch() {
    local raw_arch
    raw_arch="$(uname -m 2>/dev/null || echo "unknown")"

    case "$raw_arch" in
        x86_64|amd64)
            CPU_ARCH="x86_64"
            ;;
        arm64|aarch64)
            CPU_ARCH="arm64"
            ;;
        *)
            CPU_ARCH="$raw_arch"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Shell Detection
# ------------------------------------------------------------------------------
detect_shell() {
    local shell_bin=""

    # Check active $SHELL first
    if [[ -n "${SHELL:-}" ]]; then
        shell_bin="$(basename "$SHELL")"
    fi

    # Fallback: inspect parent process if $SHELL is unset
    if [[ -z "$shell_bin" ]]; then
        local p_comm=""
        if command -v ps >/dev/null 2>&1; then
            p_comm="$(ps -p $$ -o comm= 2>/dev/null | tr -d '-' || true)"
            shell_bin="$(basename "$p_comm")"
        fi
    fi

    case "$shell_bin" in
        zsh*)
            ACTIVE_SHELL="zsh"
            TARGET_SHELL_RC="${HOME}/.zshrc"
            ;;
        fish*)
            ACTIVE_SHELL="fish"
            TARGET_SHELL_RC="${HOME}/.config/fish/config.fish"
            ;;
        bash*|*)
            ACTIVE_SHELL="bash"
            if [[ "$OS_TYPE" == "macos" ]]; then
                if [[ -f "${HOME}/.bash_profile" ]]; then
                    TARGET_SHELL_RC="${HOME}/.bash_profile"
                else
                    TARGET_SHELL_RC="${HOME}/.bashrc"
                fi
            else
                TARGET_SHELL_RC="${HOME}/.bashrc"
            fi
            ;;
    esac

    # Populate candidate list for uninstallation / cleanup
    # shellcheck disable=SC2034
    ALL_CANDIDATE_RCS=(
        "${HOME}/.zshrc"
        "${HOME}/.bashrc"
        "${HOME}/.bash_profile"
        "${HOME}/.profile"
        "${HOME}/.config/fish/config.fish"
    )
}

# ------------------------------------------------------------------------------
# Disk Space Check
# ------------------------------------------------------------------------------
check_disk_space() {
    local target_dir="${1:-$HOME}"
    local min_gb="${2:-${MIN_DISK_SPACE_GB:-15}}"

    if [[ ! -d "$target_dir" ]]; then
        target_dir="$(dirname "$target_dir")"
    fi

    # Portable POSIX df check with 1024-byte blocks
    local avail_kb=0
    local avail_gb=0

    if command -v df >/dev/null 2>&1; then
        avail_kb="$(df -k -P "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")"
        if [[ -n "$avail_kb" && "$avail_kb" =~ ^[0-9]+$ && "$avail_kb" -gt 0 ]]; then
            avail_gb=$(( avail_kb / 1048576 ))
        fi
    fi

    if [[ "$avail_gb" -gt 0 ]]; then
        if [[ "$avail_gb" -lt "$min_gb" ]]; then
            log_warn "Low disk space on partition ($target_dir): ${avail_gb} GB free."
            log_warn "Recommended minimum free disk space is ${min_gb} GB for Android SDK, NDK, and Flutter."
            return 1
        else
            log_info "Disk space check passed: ${avail_gb} GB free on $target_dir (minimum: ${min_gb} GB)."
            return 0
        fi
    else
        log_warn "Could not determine free disk space for: $target_dir"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# Base Prerequisites Check & Installation
# ------------------------------------------------------------------------------
install_prerequisites() {
    local dry_run="${1:-false}"

    log_step "Verifying system base prerequisites"

    if [[ "$OS_TYPE" == "macos" ]]; then
        # Check Xcode Command Line Tools
        if xcode-select -p >/dev/null 2>&1; then
            local clt_path
            clt_path="$(xcode-select -p 2>/dev/null || echo "")"
            log_success "Xcode Command Line Tools detected: ${clt_path}"
        else
            log_warn "Xcode Command Line Tools not detected."
            if [[ "$dry_run" == "true" ]]; then
                log_dry_run "Would prompt installation: xcode-select --install"
            else
                log_info "Initiating Xcode Command Line Tools installation..."
                xcode-select --install || true
            fi
        fi

        # Check Homebrew
        if command -v brew >/dev/null 2>&1; then
            local brew_ver
            brew_ver="$(brew --version 2>/dev/null | head -n1 || echo "Homebrew")"
            log_success "Homebrew detected: ${brew_ver}"
        else
            log_warn "Homebrew is not detected in PATH."
            log_info "Homebrew is recommended to install dependencies. (https://brew.sh)"
            if [[ "$dry_run" == "true" ]]; then
                log_dry_run "Would suggest: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            fi
        fi

    elif [[ "$OS_TYPE" == "linux" ]]; then
        local missing_pkgs=()

        case "$OS_FAMILY" in
            debian)
                local req_cmds=("curl" "git" "unzip" "xz" "clang" "ninja")
                for cmd in "${req_cmds[@]}"; do
                    if ! command -v "$cmd" >/dev/null 2>&1; then
                        case "$cmd" in
                            ninja) missing_pkgs+=("ninja-build") ;;
                            xz) missing_pkgs+=("xz-utils") ;;
                            *) missing_pkgs+=("$cmd") ;;
                        esac
                    fi
                done

                # GTK3 check
                if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists gtk+-3.0 2>/dev/null; then
                    missing_pkgs+=("libgtk-3-dev" "pkg-config")
                fi

                if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
                    local pkg_list="${missing_pkgs[*]}"
                    log_info "Missing required packages: ${pkg_list}"
                    if [[ "$dry_run" == "true" ]]; then
                        log_dry_run "Would execute: sudo apt-get update && sudo apt-get install -y ${pkg_list}"
                    else
                        if [[ "$(id -u)" -eq 0 ]]; then
                            apt-get update && apt-get install -y "${missing_pkgs[@]}"
                        elif command -v sudo >/dev/null 2>&1; then
                            sudo apt-get update && sudo apt-get install -y "${missing_pkgs[@]}"
                        else
                            log_error "Root or sudo required to install: ${pkg_list}"
                            return 1
                        fi
                    fi
                else
                    log_success "All Linux base prerequisites are satisfied (curl, git, unzip, xz, clang, ninja, gtk3)."
                fi
                ;;

            fedora)
                local req_cmds=("curl" "git" "unzip" "xz" "clang" "ninja")
                for cmd in "${req_cmds[@]}"; do
                    if ! command -v "$cmd" >/dev/null 2>&1; then
                        case "$cmd" in
                            ninja) missing_pkgs+=("ninja-build") ;;
                            *) missing_pkgs+=("$cmd") ;;
                        esac
                    fi
                done

                if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists gtk+-3.0 2>/dev/null; then
                    missing_pkgs+=("gtk3-devel" "pkgconf-pkg-config")
                fi

                if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
                    local pkg_list="${missing_pkgs[*]}"
                    log_info "Missing required packages: ${pkg_list}"
                    if [[ "$dry_run" == "true" ]]; then
                        log_dry_run "Would execute: sudo dnf install -y ${pkg_list}"
                    else
                        if [[ "$(id -u)" -eq 0 ]]; then
                            dnf install -y "${missing_pkgs[@]}"
                        elif command -v sudo >/dev/null 2>&1; then
                            sudo dnf install -y "${missing_pkgs[@]}"
                        else
                            log_error "Root or sudo required to install: ${pkg_list}"
                            return 1
                        fi
                    fi
                else
                    log_success "All Linux base prerequisites are satisfied."
                fi
                ;;

            arch)
                local req_cmds=("curl" "git" "unzip" "xz" "clang" "ninja")
                for cmd in "${req_cmds[@]}"; do
                    if ! command -v "$cmd" >/dev/null 2>&1; then
                        missing_pkgs+=("$cmd")
                    fi
                done

                if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists gtk+-3.0 2>/dev/null; then
                    missing_pkgs+=("gtk3" "pkgconf")
                fi

                if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
                    local pkg_list="${missing_pkgs[*]}"
                    log_info "Missing required packages: ${pkg_list}"
                    if [[ "$dry_run" == "true" ]]; then
                        log_dry_run "Would execute: sudo pacman -Sy --noconfirm ${pkg_list}"
                    else
                        if [[ "$(id -u)" -eq 0 ]]; then
                            pacman -Sy --noconfirm "${missing_pkgs[@]}"
                        elif command -v sudo >/dev/null 2>&1; then
                            sudo pacman -Sy --noconfirm "${missing_pkgs[@]}"
                        else
                            log_error "Root or sudo required to install: ${pkg_list}"
                            return 1
                        fi
                    fi
                else
                    log_success "All Linux base prerequisites are satisfied."
                fi
                ;;

            *)
                log_warn "Unknown Linux distribution family. Please ensure curl, git, unzip, xz, clang, ninja, and gtk3 are installed."
                ;;
        esac
    else
        log_warn "Unsupported operating system type: ${OS_TYPE}"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Full Detection Routine
# ------------------------------------------------------------------------------
detect_all() {
    detect_os
    detect_arch
    detect_shell
    log_info "Detected OS: ${OS_NAME} (${OS_TYPE}/${OS_FAMILY})"
    log_info "Detected Architecture: ${CPU_ARCH}"
    log_info "Detected Active Shell: ${ACTIVE_SHELL} (${TARGET_SHELL_RC})"
}
