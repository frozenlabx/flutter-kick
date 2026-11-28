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
  _____ _       _   _              _  ___      _    
 |  ___| |_   _| |_| |_ ___ _ __  | |/ (_) ___| | __
 | |_  | | | | | __| __/ _ \ '__| | ' /| |/ __| |/ /
 |  _| | | |_| | |_| ||  __/ |    | . \| | (__|   < 
 |_|   |_|\__,_|\__|\__\___|_|    |_|\_\_|\___|_|\_\
================================================================================
EOF
    printf " %s* Headless Flutter & Android SDK Environment Manager%s\n" "${CLR_BOLD}${CLR_WHITE}" "${CLR_RESET}"
    if [[ "$LOG_FILE_WRITABLE" -eq 1 ]]; then
        printf " %s* Log: %s%s\n" "${CLR_DIM}" "$LOG_FILE" "${CLR_RESET}"
    fi
    printf "================================================================================\n\n"
}

print_toolchain_overview() {
    local os_str="$1"
    local arch_str="$2"
    local shell_str="$3"

    printf "%s--------------------------------------------------------------------------------%s\n" "${CLR_CYAN}" "${CLR_RESET}"
    printf " %sTarget System:%s %s (%s)  |  %sShell:%s %s\n" "${CLR_BOLD}" "${CLR_RESET}" "$os_str" "$arch_str" "${CLR_BOLD}" "${CLR_RESET}" "$shell_str"
    printf "%s--------------------------------------------------------------------------------%s\n" "${CLR_CYAN}" "${CLR_RESET}"
    printf " %sExisting Toolchain Status:%s\n" "${CLR_BOLD}" "${CLR_RESET}"

    if [[ "${DETECTED_JDK_VALID:-0}" -eq 1 ]]; then
        printf "   %s[✓] Java JDK       :%s %s %s(Reusing)%s\n" "${CLR_GREEN}" "${CLR_RESET}" "${DETECTED_JDK_VER}" "${CLR_DIM}" "${CLR_RESET}"
    else
        printf "   %s[○] Java JDK       :%s Not found %s(Will install Temurin %s)%s\n" "${CLR_CYAN}" "${CLR_RESET}" "${CLR_DIM}" "${JDK_VERSION:-17}" "${CLR_RESET}"
    fi

    if [[ "${DETECTED_ANDROID_VALID:-0}" -eq 1 ]]; then
        printf "   %s[✓] Android SDK    :%s %s %s(Reusing)%s\n" "${CLR_GREEN}" "${CLR_RESET}" "${DETECTED_ANDROID_HOME}" "${CLR_DIM}" "${CLR_RESET}"
    else
        printf "   %s[○] Android SDK    :%s Not found %s(Will install cmdline-tools & API %s)%s\n" "${CLR_CYAN}" "${CLR_RESET}" "${CLR_DIM}" "${ANDROID_API:-36}" "${CLR_RESET}"
    fi

    if [[ "${DETECTED_GRADLE_VALID:-0}" -eq 1 ]]; then
        printf "   %s[✓] Gradle         :%s %s %s(Reusing)%s\n" "${CLR_GREEN}" "${CLR_RESET}" "${DETECTED_GRADLE_VER}" "${CLR_DIM}" "${CLR_RESET}"
    else
        printf "   %s[○] Gradle         :%s Not installed %s(Projects with './gradlew' don't require this)%s\n" "${CLR_CYAN}" "${CLR_RESET}" "${CLR_DIM}" "${CLR_RESET}"
    fi

    if [[ "${DETECTED_FLUTTER_VALID:-0}" -eq 1 ]]; then
        printf "   %s[✓] Flutter SDK    :%s %s %s(Reusing)%s\n" "${CLR_GREEN}" "${CLR_RESET}" "${DETECTED_FLUTTER_VER}" "${CLR_DIM}" "${CLR_RESET}"
    else
        printf "   %s[○] Flutter SDK    :%s Not found %s(Will install %s channel)%s\n" "${CLR_CYAN}" "${CLR_RESET}" "${CLR_DIM}" "${FLUTTER_CHANNEL:-stable}" "${CLR_RESET}"
    fi
    printf "%s--------------------------------------------------------------------------------%s\n\n" "${CLR_CYAN}" "${CLR_RESET}"
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
    printf "%sWhat would you like to do?%s\n\n" "${CLR_BOLD}" "${CLR_RESET}"
    printf "  %s[1] Quick Setup (Recommended)%s  - Setup Flutter & Android toolchain automatically\n" "${CLR_GREEN}${CLR_BOLD}" "${CLR_RESET}"
    printf "                                      (Reuses existing tools; installs only missing components)\n"
    printf "  %s[2] Custom Setup%s               - Choose custom JDK, Android API, NDK, CMake, Flutter\n" "${CLR_CYAN}${CLR_BOLD}" "${CLR_RESET}"
    printf "  %s[3] Run Doctor / Troubleshoot%s  - Analyze setup health, accept licenses & repair issues\n" "${CLR_YELLOW}${CLR_BOLD}" "${CLR_RESET}"
    printf "  %s[4] Clean Uninstall%s            - Revert shell environment and remove managed SDKs\n" "${CLR_RED}${CLR_BOLD}" "${CLR_RESET}"
    printf "  %s[q] Exit%s\n\n" "${CLR_DIM}" "${CLR_RESET}"

    local choice=""
    printf "  %s?%s Enter choice [%s1%s]: " "${CLR_CYAN}" "${CLR_RESET}" "${CLR_BOLD}" "${CLR_RESET}"
    if read -r choice; then
        choice="${choice:-1}"
    else
        choice="1"
    fi

    case "$choice" in
        2)
            choice="2"
            ;;
        3|[dD]|[dD]octor)
            choice="doctor"
            ;;
        4|[uU]|[uU]ninstall)
            choice="uninstall"
            ;;
        [qQ]|[qQ]uit|[eE]xit)
            printf "\nExiting Flutter-Kick.\n"
            exit 0
            ;;
        *)
            choice="1"
            ;;
    esac

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
