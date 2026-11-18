#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: UI and Logging Library
# Provides colored terminal formatting, status badges, logging, and interactive UI
# ==============================================================================

# Guard against multiple sourcing
if [[ -n "${_UI_LIB_LOADED:-}" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
_UI_LIB_LOADED=1

# ------------------------------------------------------------------------------
# Terminal Color Setup (Respects NO_COLOR, TERM=dumb, non-tty)
# ------------------------------------------------------------------------------
# shellcheck disable=SC2034
setup_colors() {
    if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then
        CLR_RESET=$'\033[0m'
        CLR_BOLD=$'\033[1m'
        CLR_DIM=$'\033[2m'
        CLR_RED=$'\033[0;31m'
        CLR_GREEN=$'\033[0;32m'
        CLR_YELLOW=$'\033[0;33m'
        CLR_BLUE=$'\033[0;34m'
        CLR_MAGENTA=$'\033[0;35m'
        CLR_CYAN=$'\033[0;36m'
        CLR_WHITE=$'\033[1;37m'
        CLR_BG_BLUE=$'\033[44m'
    else
        CLR_RESET=""
        CLR_BOLD=""
        CLR_DIM=""
        CLR_RED=""
        CLR_GREEN=""
        CLR_YELLOW=""
        CLR_BLUE=""
        CLR_MAGENTA=""
        CLR_CYAN=""
        CLR_WHITE=""
        CLR_BG_BLUE=""
    fi
}
setup_colors

# ------------------------------------------------------------------------------
# Centralized Logging Initialization with Resilient Permission Fallback
# ------------------------------------------------------------------------------
LOG_FILE="${DEFAULT_LOG_FILE:-${HOME}/.mobile-toolchain-setup.log}"
LOG_FILE_WRITABLE=0
VERBOSE="${VERBOSE:-0}"

init_logging() {
    local target_log="${1:-$LOG_FILE}"
    LOG_FILE="$target_log"
    LOG_FILE_WRITABLE=0

    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi

    # Check if target log file is writable
    if { : >> "$LOG_FILE"; } 2>/dev/null; then
        LOG_FILE_WRITABLE=1
    else
        # Fallback 1: /tmp
        local tmp_fallback="/tmp/.mobile-toolchain-setup.log"
        if { : >> "$tmp_fallback"; } 2>/dev/null; then
            LOG_FILE="$tmp_fallback"
            LOG_FILE_WRITABLE=1
        else
            # Fallback 2: current working directory
            local cwd_fallback="./.mobile-toolchain-setup.log"
            if { : >> "$cwd_fallback"; } 2>/dev/null; then
                LOG_FILE="$cwd_fallback"
                LOG_FILE_WRITABLE=1
            fi
        fi
    fi

    if [[ "$LOG_FILE_WRITABLE" -eq 1 ]]; then
        local timestamp
        timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
        printf "\n=== Session Started: %s ===\n" "$timestamp" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

_write_log() {
    if [[ "${LOG_FILE_WRITABLE:-0}" -ne 1 ]]; then
        return 0
    fi
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    # Strip ANSI escape codes when writing to log file
    local plain_message
    plain_message="$(printf "%s" "$message" | sed -E $'s/\033\\[[0-9;]*[a-zA-Z]//g')"
    printf "[%s] [%-7s] %s\n" "$timestamp" "$level" "$plain_message" >> "$LOG_FILE" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Logging & Status Helpers
# ------------------------------------------------------------------------------
log_info() {
    local msg="$1"
    printf "%s[i]%s %s\n" "${CLR_CYAN}" "${CLR_RESET}" "$msg"
    _write_log "INFO" "$msg"
}

log_success() {
    local msg="$1"
    printf "%s[✓]%s %s%s%s\n" "${CLR_GREEN}" "${CLR_RESET}" "${CLR_BOLD}" "$msg" "${CLR_RESET}"
    _write_log "SUCCESS" "$msg"
}

log_warn() {
    local msg="$1"
    printf "%s[!]%s %s%s%s\n" "${CLR_YELLOW}" "${CLR_RESET}" "${CLR_YELLOW}" "$msg" "${CLR_RESET}" >&2
    _write_log "WARN" "$msg"
}

log_error() {
    local msg="$1"
    printf "%s[✗]%s %s%s%s\n" "${CLR_RED}" "${CLR_RESET}" "${CLR_RED}" "$msg" "${CLR_RESET}" >&2
    _write_log "ERROR" "$msg"
}

log_step() {
    local step_num="${1:-}"
    local total_steps="${2:-}"
    local msg="${3:-}"
    if [[ -n "$total_steps" ]]; then
        printf "\n%s[%s/%s]%s %s%s%s\n" "${CLR_BOLD}${CLR_BLUE}" "$step_num" "$total_steps" "${CLR_RESET}" "${CLR_BOLD}" "$msg" "${CLR_RESET}"
        _write_log "STEP" "[$step_num/$total_steps] $msg"
    else
        printf "\n%s[→]%s %s%s%s\n" "${CLR_BOLD}${CLR_BLUE}" "${CLR_RESET}" "${CLR_BOLD}" "$step_num" "${CLR_RESET}"
        _write_log "STEP" "$step_num"
    fi
}

log_debug() {
    local msg="$1"
    _write_log "DEBUG" "$msg"
    if [[ "${VERBOSE:-0}" -eq 1 ]]; then
        printf "%s[D]%s %s\n" "${CLR_DIM}" "${CLR_RESET}" "$msg"
    fi
}

log_dry_run() {
    local msg="$1"
    printf "%s[DRY-RUN]%s %s%s%s\n" "${CLR_MAGENTA}${CLR_BOLD}" "${CLR_RESET}" "${CLR_MAGENTA}" "$msg" "${CLR_RESET}"
    _write_log "DRY-RUN" "$msg"
}

# ------------------------------------------------------------------------------
# Banner and Headers
# ------------------------------------------------------------------------------
show_banner() {
    cat << 'EOF'
================================================================================
 __  __       _     _ _        _____           _      _           _     
|  \/  |     | |   (_) |      |_   _|         | |    | |         (_)    
| \  / | ___ | |__  _| | ___    | | ___   ___ | | ___| |__   __ _ _ _ __
| |\/| |/ _ \| '_ \| | |/ _ \   | |/ _ \ / _ \| |/ __| '_ \ / _` | | '_ \
| |  | | (_) | |_) | | |  __/   | | (_) | (_) | | (__| | | | (_| | | | | |
|_|  |_|\___/|_.__/|_|_|\___|   \_/\___/ \___/|_|\___|_| |_|\__,_|_|_| |_|
================================================================================
EOF
    printf " %s* Headless Android SDK & Flutter Toolchain Automation%s\n" "${CLR_DIM}" "${CLR_RESET}"
    if [[ "$LOG_FILE_WRITABLE" -eq 1 ]]; then
        printf " %s* Log: %s%s\n" "${CLR_DIM}" "$LOG_FILE" "${CLR_RESET}"
    fi
    printf "================================================================================\n\n"
}

# ------------------------------------------------------------------------------
# Interactive UI Helpers (Bash 3.2+ compatible)
# ------------------------------------------------------------------------------
prompt_with_default() {
    local label="$1"
    local default_val="$2"
    local __resultvar="$3"
    local user_input=""

    printf "  %s?%s %s [%s%s%s]: " "${CLR_CYAN}" "${CLR_RESET}" "$label" "${CLR_BOLD}" "$default_val" "${CLR_RESET}"
    if read -r user_input; then
        if [[ -z "$user_input" ]]; then
            eval "$__resultvar=\"$default_val\""
        else
            eval "$__resultvar=\"$user_input\""
        fi
    else
        # End of input / non-interactive fallback
        eval "$__resultvar=\"$default_val\""
    fi
}

prompt_confirm() {
    local label="$1"
    local default_is_yes="${2:-true}"
    local prompt_suffix="[Y/n]"
    if [[ "$default_is_yes" != "true" ]]; then
        prompt_suffix="[y/N]"
    fi

    printf "  %s?%s %s %s: " "${CLR_YELLOW}" "${CLR_RESET}" "$label" "$prompt_suffix"
    local answer=""
    if read -r answer; then
        answer="$(printf "%s" "$answer" | tr '[:upper:]' '[:lower:]')"
        if [[ -z "$answer" ]]; then
            [[ "$default_is_yes" == "true" ]] && return 0 || return 1
        fi
        if [[ "$answer" == "y" || "$answer" == "yes" ]]; then
            return 0
        else
            return 1
        fi
    else
        [[ "$default_is_yes" == "true" ]] && return 0 || return 1
    fi
}

prompt_mode_selection() {
    local __mode_var="$1"
    printf "%sSelect Installation Mode:%s\n" "${CLR_BOLD}" "${CLR_RESET}"
    printf "  %s[1] Recommended (Default)%s  - Quick setup with verified LTS toolchain\n" "${CLR_GREEN}${CLR_BOLD}" "${CLR_RESET}"
    printf "                                (JDK %s, Android API %s, Build-Tools %s, Flutter %s)\n" \
        "${JDK_VERSION:-17}" "${ANDROID_API:-36}" "${BUILD_TOOLS_VERSION:-36.0.0}" "${FLUTTER_CHANNEL:-stable}"
    printf "  %s[2] Custom Setup%s           - Configure JDK, Android APIs, NDK, CMake, Gradle, Flutter\n" "${CLR_CYAN}${CLR_BOLD}" "${CLR_RESET}"
    echo ""

    local choice=""
    printf "  %s?%s Enter choice [%s1%s]: " "${CLR_CYAN}" "${CLR_RESET}" "${CLR_BOLD}" "${CLR_RESET}"
    if read -r choice; then
        choice="${choice:-1}"
    else
        choice="1"
    fi

    if [[ "$choice" != "2" ]]; then
        choice="1"
    fi
    eval "$__mode_var=\"$choice\""
}

print_summary_box() {
    local os_str="$1"
    local arch_str="$2"
    local shell_str="$3"
    local jdk_str="$4"
    local api_str="$5"
    local bt_str="$6"
    local ndk_str="$7"
    local cmake_str="$8"
    local gradle_str="$9"
    shift 9
    local flutter_str="$1"
    local dry_run_str="$2"
    local target_rc="$3"

    printf "\n%s--------------------------------------------------------------------------------%s\n" "${CLR_DIM}" "${CLR_RESET}"
    printf "%sConfiguration Summary:%s\n" "${CLR_BOLD}" "${CLR_RESET}"
    printf "  %-22s : %s (%s)\n" "Target OS / Arch" "$os_str" "$arch_str"
    printf "  %-22s : %s (%s)\n" "Shell & Config" "$shell_str" "$target_rc"
    printf "  %-22s : %s\n" "JDK Version" "$jdk_str"
    printf "  %-22s : API %s (Build-Tools: %s)\n" "Android SDK" "$api_str" "$bt_str"
    printf "  %-22s : %s\n" "Android NDK" "$ndk_str"
    printf "  %-22s : %s\n" "CMake" "$cmake_str"
    printf "  %-22s : %s\n" "Gradle" "$gradle_str"
    printf "  %-22s : %s\n" "Flutter Channel/SDK" "$flutter_str"
    if [[ "$dry_run_str" == "true" ]]; then
        printf "  %-22s : %sYES (Simulation only, no files modified)%s\n" "Dry-Run Mode" "${CLR_MAGENTA}${CLR_BOLD}" "${CLR_RESET}"
    else
        printf "  %-22s : %sNO (Live installation)%s\n" "Dry-Run Mode" "${CLR_GREEN}" "${CLR_RESET}"
    fi
    printf "%s--------------------------------------------------------------------------------%s\n\n" "${CLR_DIM}" "${CLR_RESET}"
}
