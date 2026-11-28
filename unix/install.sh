#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Unix Entrypoint
# Automates headless Android SDK & Flutter development environment setup
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/config"
LIB_DIR="${SCRIPT_DIR}/lib"

# ------------------------------------------------------------------------------
# Source Configuration and Libraries
# ------------------------------------------------------------------------------
if [[ -f "${CONFIG_DIR}/defaults.env" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_DIR}/defaults.env"
else
    echo "ERROR: Configuration file not found at ${CONFIG_DIR}/defaults.env" >&2
    exit 1
fi

if [[ -f "${LIB_DIR}/ui.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/ui.sh"
else
    echo "ERROR: UI library not found at ${LIB_DIR}/ui.sh" >&2
    exit 1
fi

if [[ -f "${LIB_DIR}/os_detect.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/os_detect.sh"
else
    echo "ERROR: OS detection library not found at ${LIB_DIR}/os_detect.sh" >&2
    exit 1
fi

if [[ -f "${LIB_DIR}/env.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/env.sh"
else
    echo "ERROR: Environment library not found at ${LIB_DIR}/env.sh" >&2
    exit 1
fi

if [[ -f "${LIB_DIR}/jdk.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/jdk.sh"
fi

if [[ -f "${LIB_DIR}/android.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/android.sh"
fi

if [[ -f "${LIB_DIR}/gradle.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/gradle.sh"
fi

if [[ -f "${LIB_DIR}/flutter.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/flutter.sh"
fi

if [[ -f "${LIB_DIR}/parallel.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/parallel.sh"
fi

if [[ -f "${LIB_DIR}/doctor.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/doctor.sh"
fi

# ------------------------------------------------------------------------------
# Help Documentation
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Automated, headless Android SDK and Flutter environment setup for Linux & macOS.

Modes:
  Interactive (Default):
    Prompts to choose between [1] Recommended (LTS) or [2] Custom Setup.
    Pressing [Enter] accepts the bracketed default values.

Options:
  -d, --default             Use recommended LTS defaults with zero interactive prompts
  -n, --dry-run             Simulate all operations without modifying filesystem or configs
  -u, --uninstall           Cleanly remove mobile-toolchain markers and installed SDKs
  -y, --yes                 Automatically answer 'yes' to confirmation prompts
  -v, --verbose             Enable detailed debug log output
  -h, --help                Show this help message and exit

Troubleshooting & Diagnostics:
  --doctor                  Inspect host system & mobile toolchain health (JDK, Android SDK, PATH)
  --fix                     Automatically apply recommended fixes alongside doctor
  --reinstall, --fresh      Force fresh downloads/reinstalls, ignoring existing detected tools

Component Overrides:
  --jdk <version>           JDK version (17, 21) [Default: ${JDK_VERSION}]
  --api <level>             Android API level (e.g. 36, 35) [Default: ${ANDROID_API}]
  --build-tools <version>   Android Build-Tools version [Default: ${BUILD_TOOLS_VERSION}]
  --ndk <version|skip>      Android NDK version or 'skip' [Default: ${NDK_VERSION}]
  --cmake <version|skip>    CMake version or 'skip' [Default: ${CMAKE_VERSION}]
  --gradle <version|skip>   Gradle version or 'skip' [Default: ${GRADLE_VERSION}]
  --flutter <channel|fvm>   Flutter channel, tag, or 'fvm' [Default: ${FLUTTER_CHANNEL}]
  --macos-ios-tools <yes|no> Configure macOS iOS tools (Xcode CLI/CocoaPods) [Default: ${MACOS_IOS_TOOLS}]

Examples:
  ./unix/install.sh                             # Interactive setup
  ./unix/install.sh --default                   # Quick recommended setup
  ./unix/install.sh --dry-run                   # Preview actions without writing anything
  ./unix/install.sh --jdk 21 --api 35 --dry-run # Preview custom toolchain
  ./unix/install.sh --uninstall                 # Clean removal of toolchain
EOF
}

# ------------------------------------------------------------------------------
# Parse CLI Options
# ------------------------------------------------------------------------------
MODE=""
DRY_RUN=false
UNINSTALL=false
AUTO_CONFIRM=false
VERBOSE=0
DOCTOR_MODE=false
AUTO_FIX=false
FORCE_REINSTALL=false

CLI_JDK=""
CLI_API=""
CLI_BUILD_TOOLS=""
CLI_NDK=""
CLI_CMAKE=""
CLI_GRADLE=""
CLI_FLUTTER=""
CLI_MACOS_IOS_TOOLS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--default)
            MODE="1"
            shift
            ;;
        -p|--parallel)
            shift
            ;;
        --doctor)
            DOCTOR_MODE=true
            shift
            ;;
        --fix)
            AUTO_FIX=true
            shift
            ;;
        --reinstall|--fresh)
            FORCE_REINSTALL=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -u|--uninstall)
            UNINSTALL=true
            shift
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --jdk)
            CLI_JDK="$2"
            shift 2
            ;;
        --api)
            CLI_API="$2"
            shift 2
            ;;
        --build-tools)
            CLI_BUILD_TOOLS="$2"
            shift 2
            ;;
        --ndk)
            CLI_NDK="$2"
            shift 2
            ;;
        --cmake)
            CLI_CMAKE="$2"
            shift 2
            ;;
        --gradle)
            CLI_GRADLE="$2"
            shift 2
            ;;
        --flutter)
            CLI_FLUTTER="$2"
            shift 2
            ;;
        --macos-ios-tools)
            CLI_MACOS_IOS_TOOLS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Initialize UI and Logging
# ------------------------------------------------------------------------------
init_logging "$DEFAULT_LOG_FILE"
show_banner

if [[ "$DOCTOR_MODE" == "true" ]]; then
    run_doctor "$AUTO_FIX"
    exit $?
fi

# ------------------------------------------------------------------------------
# System Detection
# ------------------------------------------------------------------------------
log_step "1" "7" "Detecting Host Operating System & Shell"
detect_all

# Resolve platform default paths
if [[ "$OS_TYPE" == "macos" ]]; then
    ANDROID_HOME="${DEFAULT_ANDROID_HOME_MAC:-${HOME}/Library/Android/sdk}"
    JAVA_HOME_DEFAULT="${DEFAULT_JDK_INSTALL_DIR:-${HOME}/.local/share/jdks}/temurin-${JDK_VERSION}/Contents/Home"
else
    ANDROID_HOME="${DEFAULT_ANDROID_HOME_LINUX:-${HOME}/Android/Sdk}"
    JAVA_HOME_DEFAULT="${DEFAULT_JDK_INSTALL_DIR:-${HOME}/.local/share/jdks}/temurin-${JDK_VERSION}"
fi
FLUTTER_HOME="${DEFAULT_FLUTTER_HOME:-${HOME}/development/flutter}"
GRADLE_INSTALL_DIR="${DEFAULT_GRADLE_INSTALL_DIR:-${HOME}/.local/share/gradle}"
GRADLE_HOME="${GRADLE_INSTALL_DIR}/gradle-${GRADLE_VERSION}"
JAVA_HOME="$JAVA_HOME_DEFAULT"

# ------------------------------------------------------------------------------
# Handle Uninstallation
# ------------------------------------------------------------------------------
if [[ "$UNINSTALL" == "true" ]]; then
    uninstall_toolchain "$DRY_RUN" "$AUTO_CONFIRM" "$ANDROID_HOME" "$FLUTTER_HOME" "$GRADLE_HOME"
    exit 0
fi

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Pre-Flight Disk Space Verification & Tool Detection
# ------------------------------------------------------------------------------
log_step "2" "7" "Pre-Flight Checks"
if ! check_disk_space "$HOME" "${MIN_DISK_SPACE_GB:-15}"; then
    if [[ "$DRY_RUN" == "false" && "$AUTO_CONFIRM" == "false" && -t 0 ]]; then
        if ! prompt_confirm "Free disk space is lower than recommended (${MIN_DISK_SPACE_GB} GB). Continue anyway?" false; then
            log_error "Installation aborted due to low disk space."
            exit 1
        fi
    fi
fi

detect_existing_tools

REUSE_JDK=false
REUSE_ANDROID=false
REUSE_GRADLE=false
REUSE_FLUTTER=false

if [[ "$FORCE_REINSTALL" == "false" ]]; then
    if [[ "$DETECTED_JDK_VALID" -eq 1 ]]; then
        log_info "Detected existing JDK: ${DETECTED_JDK_VER} (${DETECTED_JDK_PATH})"
    fi
    if [[ "$DETECTED_ANDROID_VALID" -eq 1 ]]; then
        log_info "Detected existing Android SDK: ${DETECTED_ANDROID_HOME}"
    fi
    if [[ "$DETECTED_GRADLE_VALID" -eq 1 ]]; then
        log_info "Detected existing Gradle: ${DETECTED_GRADLE_VER} (${DETECTED_GRADLE_PATH})"
    fi
    if [[ "$DETECTED_FLUTTER_VALID" -eq 1 ]]; then
        log_info "Detected existing Flutter: ${DETECTED_FLUTTER_VER} (${DETECTED_FLUTTER_PATH})"
    fi
fi

# ------------------------------------------------------------------------------
# Mode Selection & Configuration Gathering
# ------------------------------------------------------------------------------
has_cli_overrides=false
if [[ -n "$CLI_JDK" || -n "$CLI_API" || -n "$CLI_BUILD_TOOLS" || -n "$CLI_NDK" || -n "$CLI_CMAKE" || -n "$CLI_GRADLE" || -n "$CLI_FLUTTER" || -n "$CLI_MACOS_IOS_TOOLS" ]]; then
    has_cli_overrides=true
fi

if [[ "$has_cli_overrides" == "true" ]]; then
    # Non-interactive CLI flag override mode
    if [[ -n "$CLI_JDK" ]]; then
        CFG_JDK="$CLI_JDK"
        REUSE_JDK=false
    elif [[ "$DETECTED_JDK_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
        REUSE_JDK=true
        JAVA_HOME="$DETECTED_JDK_PATH"
        CFG_JDK="existing (${DETECTED_JDK_VER})"
    else
        CFG_JDK="$JDK_VERSION"
    fi

    CFG_API="${CLI_API:-$ANDROID_API}"
    CFG_BUILD_TOOLS="${CLI_BUILD_TOOLS:-$BUILD_TOOLS_VERSION}"
    CFG_NDK="${CLI_NDK:-$NDK_VERSION}"
    CFG_CMAKE="${CLI_CMAKE:-$CMAKE_VERSION}"

    if [[ "$DETECTED_ANDROID_VALID" -eq 1 && "$DETECTED_CMDLINE_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
        REUSE_ANDROID=true
        ANDROID_HOME="$DETECTED_ANDROID_HOME"
    fi

    if [[ -n "$CLI_GRADLE" ]]; then
        CFG_GRADLE="$CLI_GRADLE"
        REUSE_GRADLE=false
    elif [[ "$DETECTED_GRADLE_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
        REUSE_GRADLE=true
        GRADLE_HOME="$(dirname "$(dirname "$DETECTED_GRADLE_PATH")")"
        CFG_GRADLE="existing (${DETECTED_GRADLE_VER})"
    else
        CFG_GRADLE="$GRADLE_VERSION"
    fi

    if [[ -n "$CLI_FLUTTER" ]]; then
        CFG_FLUTTER="$CLI_FLUTTER"
        REUSE_FLUTTER=false
    elif [[ "$DETECTED_FLUTTER_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
        REUSE_FLUTTER=true
        FLUTTER_HOME="$DETECTED_FLUTTER_PATH"
        CFG_FLUTTER="existing (${DETECTED_FLUTTER_VER})"
    else
        CFG_FLUTTER="$FLUTTER_CHANNEL"
    fi

    CFG_MACOS_IOS_TOOLS="${CLI_MACOS_IOS_TOOLS:-$MACOS_IOS_TOOLS}"
elif [[ "$MODE" == "1" ]]; then
    # Recommended LTS default mode with smart installation reuse
    log_info "Applying Recommended LTS default configurations."
    if [[ "$DETECTED_JDK_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
        REUSE_JDK=true
        JAVA_HOME="$DETECTED_JDK_PATH"
        CFG_JDK="existing (${DETECTED_JDK_VER})"
        log_success "Reusing existing JDK (${DETECTED_JDK_VER})."
    else
        CFG_JDK="$JDK_VERSION"
    fi

    if [[ "$DETECTED_ANDROID_VALID" -eq 1 && "$DETECTED_CMDLINE_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
        REUSE_ANDROID=true
        ANDROID_HOME="$DETECTED_ANDROID_HOME"
        log_success "Reusing existing Android SDK (${DETECTED_ANDROID_HOME})."
    fi

    CFG_API="$ANDROID_API"
    CFG_BUILD_TOOLS="$BUILD_TOOLS_VERSION"
    CFG_NDK="$NDK_VERSION"
    CFG_CMAKE="$CMAKE_VERSION"

    if [[ "$DETECTED_GRADLE_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
        REUSE_GRADLE=true
        GRADLE_HOME="$(dirname "$(dirname "$DETECTED_GRADLE_PATH")")"
        CFG_GRADLE="existing (${DETECTED_GRADLE_VER})"
        log_success "Reusing existing Gradle (${DETECTED_GRADLE_VER})."
    else
        CFG_GRADLE="$GRADLE_VERSION"
    fi

    if [[ "$DETECTED_FLUTTER_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
        REUSE_FLUTTER=true
        FLUTTER_HOME="$DETECTED_FLUTTER_PATH"
        CFG_FLUTTER="existing (${DETECTED_FLUTTER_VER})"
        log_success "Reusing existing Flutter SDK (${DETECTED_FLUTTER_VER})."
    else
        CFG_FLUTTER="$FLUTTER_CHANNEL"
    fi

    CFG_MACOS_IOS_TOOLS="$MACOS_IOS_TOOLS"
else
    # Interactive or piped mode selection
    print_toolchain_overview "${OS_NAME:-$OS_TYPE}" "${CPU_ARCH:-unknown}" "${ACTIVE_SHELL:-zsh}"
    if [[ -t 0 ]]; then
        prompt_mode_selection MODE
    else
        # If input is piped into script, attempt to read choice; fallback to Recommended on EOF
        if read -r piped_choice 2>/dev/null; then
            piped_choice="${piped_choice:-1}"
            case "$piped_choice" in
                2) MODE="2" ;;
                3|[dD]octor) MODE="doctor" ;;
                4|[uU]ninstall) MODE="uninstall" ;;
                [qQ]|[qQ]uit|[eE]xit)
                    printf "\nExiting Flutter-Kick.\n"
                    exit 0
                    ;;
                *) MODE="1" ;;
            esac
        else
            log_info "Non-interactive environment detected. Using Recommended (Default) mode."
            MODE="1"
        fi
    fi

    if [[ "$MODE" == "doctor" ]]; then
        run_doctor "$AUTO_FIX"
        exit $?
    elif [[ "$MODE" == "uninstall" ]]; then
        uninstall_toolchain "$DRY_RUN" "$AUTO_CONFIRM" "$ANDROID_HOME" "$FLUTTER_HOME" "$GRADLE_HOME"
        exit 0
    fi

    if [[ "$MODE" == "1" ]]; then
        log_info "Applying Recommended LTS default configurations."
        if [[ "$DETECTED_JDK_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
            REUSE_JDK=true
            JAVA_HOME="$DETECTED_JDK_PATH"
            CFG_JDK="existing (${DETECTED_JDK_VER})"
            log_success "Reusing existing JDK (${DETECTED_JDK_VER})."
        else
            CFG_JDK="$JDK_VERSION"
        fi

        if [[ "$DETECTED_ANDROID_VALID" -eq 1 && "$DETECTED_CMDLINE_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
            REUSE_ANDROID=true
            ANDROID_HOME="$DETECTED_ANDROID_HOME"
            log_success "Reusing existing Android SDK (${DETECTED_ANDROID_HOME})."
        fi

        CFG_API="$ANDROID_API"
        CFG_BUILD_TOOLS="$BUILD_TOOLS_VERSION"
        CFG_NDK="$NDK_VERSION"
        CFG_CMAKE="$CMAKE_VERSION"

        if [[ "$DETECTED_GRADLE_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
            REUSE_GRADLE=true
            GRADLE_HOME="$(dirname "$(dirname "$DETECTED_GRADLE_PATH")")"
            CFG_GRADLE="existing (${DETECTED_GRADLE_VER})"
            log_success "Reusing existing Gradle (${DETECTED_GRADLE_VER})."
        else
            CFG_GRADLE="$GRADLE_VERSION"
        fi

        if [[ "$DETECTED_FLUTTER_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
            REUSE_FLUTTER=true
            FLUTTER_HOME="$DETECTED_FLUTTER_PATH"
            CFG_FLUTTER="existing (${DETECTED_FLUTTER_VER})"
            log_success "Reusing existing Flutter SDK (${DETECTED_FLUTTER_VER})."
        else
            CFG_FLUTTER="$FLUTTER_CHANNEL"
        fi

        CFG_MACOS_IOS_TOOLS="$MACOS_IOS_TOOLS"
    else
        # Interactive Custom Setup mode
        printf "\n%s--- Custom Configuration ---%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"
        printf "%sSelect or enter your preferred versions below.%s\n" "${CLR_DIM}" "${CLR_RESET}"
        printf "%sPress [Enter] to accept the bracketed default values.%s\n\n" "${CLR_DIM}" "${CLR_RESET}"

        # 1. JDK
        printf "  %s• Java Development Kit (JDK):%s\n" "${CLR_BOLD}" "${CLR_RESET}"
        if [[ "$DETECTED_JDK_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
            printf "    %sDetected existing JDK: %s (%s)%s\n" "${CLR_CYAN}" "${DETECTED_JDK_VER}" "${DETECTED_JDK_PATH}" "${CLR_RESET}"
            if prompt_confirm "Reuse existing JDK?" true; then
                REUSE_JDK=true
                JAVA_HOME="$DETECTED_JDK_PATH"
                CFG_JDK="existing (${DETECTED_JDK_VER})"
            else
                printf "    %sOptions: 17 (LTS, Recommended for AGP 8 & Flutter), 21 (LTS)%s\n" "${CLR_DIM}" "${CLR_RESET}"
                prompt_with_default "JDK Version (17/21)" "$JDK_VERSION" CFG_JDK
            fi
        else
            printf "    %sOptions: 17 (LTS, Recommended for AGP 8 & Flutter), 21 (LTS)%s\n" "${CLR_DIM}" "${CLR_RESET}"
            prompt_with_default "JDK Version (17/21)" "$JDK_VERSION" CFG_JDK
        fi

        # 2. Android API & SDK location
        printf "\n  %s• Android SDK Platform API:%s\n" "${CLR_BOLD}" "${CLR_RESET}"
        if [[ "$DETECTED_ANDROID_VALID" -eq 1 && "$DETECTED_CMDLINE_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
            printf "    %sDetected existing Android SDK: %s%s\n" "${CLR_CYAN}" "${DETECTED_ANDROID_HOME}" "${CLR_RESET}"
            if prompt_confirm "Reuse existing Android SDK location?" true; then
                REUSE_ANDROID=true
                ANDROID_HOME="$DETECTED_ANDROID_HOME"
            fi
        fi
        printf "    %sCommon: 36 (Android 16), 35 (Android 15), 34 (Android 14), 33 (Android 13)%s\n" "${CLR_DIM}" "${CLR_RESET}"
        printf "    %sTip: You can specify multiple APIs separated by commas (e.g. 34,35,36)%s\n" "${CLR_DIM}" "${CLR_RESET}"
        prompt_with_default "Android API Level" "$ANDROID_API" CFG_API

        # 3. Android Build-Tools
        printf "\n  %s• Android SDK Build-Tools:%s\n" "${CLR_BOLD}" "${CLR_RESET}"
        printf "    %sCommon: 36.0.0 (pairs with API 36), 35.0.0, 34.0.0%s\n" "${CLR_DIM}" "${CLR_RESET}"
        prompt_with_default "Android Build-Tools" "$BUILD_TOOLS_VERSION" CFG_BUILD_TOOLS

        # 4. Android NDK
        printf "\n  %s• Android NDK (Native Development Kit):%s\n" "${CLR_BOLD}" "${CLR_RESET}"
        printf "    %sCommon: 28.0 (r28 LTS), 27.2 (r27c LTS), 26.3 (r26d), 25.2, or 'skip'%s\n" "${CLR_DIM}" "${CLR_RESET}"
        printf "    %sTip: Partial versions like '28.0' auto-resolve to full revisions%s\n" "${CLR_DIM}" "${CLR_RESET}"
        prompt_with_default "Android NDK Version (version or 'skip')" "$NDK_VERSION" CFG_NDK

        # 5. CMake
        printf "\n  %s• CMake (Native build tool):%s\n" "${CLR_BOLD}" "${CLR_RESET}"
        printf "    %sCommon: 3.22.1 (Recommended for Android Gradle Plugin), 3.28.0, or 'skip'%s\n" "${CLR_DIM}" "${CLR_RESET}"
        prompt_with_default "CMake Version (version or 'skip')" "$CMAKE_VERSION" CFG_CMAKE

        # 6. Gradle
        printf "\n  %s• Gradle Build Tool:%s\n" "${CLR_BOLD}" "${CLR_RESET}"
        if [[ "$DETECTED_GRADLE_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
            printf "    %sDetected existing Gradle: %s%s\n" "${CLR_CYAN}" "${DETECTED_GRADLE_VER}" "${CLR_RESET}"
            if prompt_confirm "Reuse existing Gradle?" true; then
                REUSE_GRADLE=true
                GRADLE_HOME="$(dirname "$(dirname "$DETECTED_GRADLE_PATH")")"
                CFG_GRADLE="existing (${DETECTED_GRADLE_VER})"
            else
                printf "    %sCommon: 8.11.1 (Current Stable), 8.10.2, 8.9, 8.7, or 'skip'%s\n" "${CLR_DIM}" "${CLR_RESET}"
                prompt_with_default "Gradle Version (version or 'skip')" "$GRADLE_VERSION" CFG_GRADLE
            fi
        else
            printf "    %sCommon: 8.11.1 (Current Stable), 8.10.2, 8.9, 8.7, or 'skip'%s\n" "${CLR_DIM}" "${CLR_RESET}"
            prompt_with_default "Gradle Version (version or 'skip')" "$GRADLE_VERSION" CFG_GRADLE
        fi

        # 7. Flutter
        printf "\n  %s• Flutter SDK Channel / Version Management:%s\n" "${CLR_BOLD}" "${CLR_RESET}"
        if [[ "$DETECTED_FLUTTER_VALID" -eq 1 && "$FORCE_REINSTALL" == "false" ]]; then
            printf "    %sDetected existing Flutter: %s (%s)%s\n" "${CLR_CYAN}" "${DETECTED_FLUTTER_VER}" "${DETECTED_FLUTTER_PATH}" "${CLR_RESET}"
            if prompt_confirm "Reuse existing Flutter SDK?" true; then
                REUSE_FLUTTER=true
                FLUTTER_HOME="$DETECTED_FLUTTER_PATH"
                CFG_FLUTTER="existing (${DETECTED_FLUTTER_VER})"
            else
                printf "    %sOptions: stable (Recommended), beta, master, git tag (e.g. 3.27.0), or 'fvm'%s\n" "${CLR_DIM}" "${CLR_RESET}"
                prompt_with_default "Flutter Channel/Tag or 'fvm'" "$FLUTTER_CHANNEL" CFG_FLUTTER
            fi
        else
            printf "    %sOptions: stable (Recommended), beta, master, git tag (e.g. 3.27.0), or 'fvm'%s\n" "${CLR_DIM}" "${CLR_RESET}"
            prompt_with_default "Flutter Channel/Tag or 'fvm'" "$FLUTTER_CHANNEL" CFG_FLUTTER
        fi

        # 8. macOS iOS Tools (macOS only)
        if [[ "$OS_TYPE" == "macos" ]]; then
            printf "\n  %s• macOS iOS Development Tools:%s\n" "${CLR_BOLD}" "${CLR_RESET}"
            printf "    %sOptions: yes (verifies Xcode CLI tools and CocoaPods), no%s\n" "${CLR_DIM}" "${CLR_RESET}"
            prompt_with_default "Setup macOS iOS Tools (Xcode CLI/CocoaPods) (yes/no)" "$MACOS_IOS_TOOLS" CFG_MACOS_IOS_TOOLS
        else
            CFG_MACOS_IOS_TOOLS="no"
        fi
    fi
fi

# Update default JAVA_HOME and GRADLE_HOME based on chosen versions
if [[ "$REUSE_JDK" != "true" ]]; then
    JDK_INSTALL_DIR="${DEFAULT_JDK_INSTALL_DIR:-${HOME}/.local/share/jdks}"
    if [[ "$OS_TYPE" == "macos" ]]; then
        JAVA_HOME="${JDK_INSTALL_DIR}/temurin-${CFG_JDK}/Contents/Home"
    else
        JAVA_HOME="${JDK_INSTALL_DIR}/temurin-${CFG_JDK}"
    fi
else
    JDK_INSTALL_DIR="$(dirname "$JAVA_HOME")"
fi

if [[ "$REUSE_GRADLE" != "true" ]]; then
    GRADLE_INSTALL_DIR="${DEFAULT_GRADLE_INSTALL_DIR:-${HOME}/.local/share/gradle}"
    if [[ "$CFG_GRADLE" != "skip" ]]; then
        GRADLE_HOME="${GRADLE_INSTALL_DIR}/gradle-${CFG_GRADLE}"
    else
        GRADLE_HOME="${DEFAULT_GRADLE_USER_HOME:-${HOME}/.gradle}"
    fi
else
    GRADLE_INSTALL_DIR="$(dirname "$GRADLE_HOME")"
fi

# ------------------------------------------------------------------------------
# Summary and User Confirmation
# ------------------------------------------------------------------------------
print_summary_box \
    "$OS_NAME" \
    "$CPU_ARCH" \
    "$ACTIVE_SHELL" \
    "$CFG_JDK" \
    "$CFG_API" \
    "$CFG_BUILD_TOOLS" \
    "$CFG_NDK" \
    "$CFG_CMAKE" \
    "$CFG_GRADLE" \
    "$CFG_FLUTTER" \
    "$DRY_RUN" \
    "$TARGET_SHELL_RC"

if [[ "$DRY_RUN" == "false" && "$AUTO_CONFIRM" == "false" && -t 0 ]]; then
    if ! prompt_confirm "Proceed with toolchain installation?" true; then
        log_warn "Installation cancelled by user."
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# Step 3: Base System Prerequisites
# ------------------------------------------------------------------------------
log_step "3" "7" "Installing Base Prerequisites"
install_prerequisites "$DRY_RUN"

# ------------------------------------------------------------------------------
# Step 4: Installing Toolchain Components
# ------------------------------------------------------------------------------
log_step "4" "7" "Installing Toolchain Components"

run_parallel_ingestion \
    "$CFG_JDK" "$CFG_API" "$CFG_BUILD_TOOLS" "$CFG_NDK" "$CFG_CMAKE" \
    "$CFG_GRADLE" "$CFG_FLUTTER" "$JDK_INSTALL_DIR" "$ANDROID_HOME" \
    "$GRADLE_INSTALL_DIR" "$FLUTTER_HOME" "$CFG_MACOS_IOS_TOOLS" \
    "$DRY_RUN" "$VERBOSE" \
    "$REUSE_JDK" "$REUSE_ANDROID" "$REUSE_GRADLE" "$REUSE_FLUTTER"

if [[ "$CFG_GRADLE" != "skip" ]]; then
    GRADLE_HOME="${GRADLE_INSTALL_DIR}/gradle-${CFG_GRADLE}"
fi

# ------------------------------------------------------------------------------
# Step 5: Environment and PATH Configuration
# ------------------------------------------------------------------------------
log_step "5" "7" "Injecting Environment Variables and PATH"

env_block="$(generate_env_block "$ACTIVE_SHELL" "$JAVA_HOME" "$ANDROID_HOME" "$GRADLE_HOME" "$FLUTTER_HOME" "$CFG_BUILD_TOOLS")"
inject_env_block "$TARGET_SHELL_RC" "$env_block" "$DRY_RUN"

# On macOS, if using bash and .bash_profile exists alongside .bashrc, keep both in sync
if [[ "$OS_TYPE" == "macos" && "$ACTIVE_SHELL" == "bash" ]]; then
    if [[ "$TARGET_SHELL_RC" == "${HOME}/.bash_profile" && -f "${HOME}/.bashrc" ]]; then
        log_info "Also synchronizing ${HOME}/.bashrc for macOS bash subshells..."
        inject_env_block "${HOME}/.bashrc" "$env_block" "$DRY_RUN"
    fi
fi

# ------------------------------------------------------------------------------
# Step 6: Post-Installation Verification
# ------------------------------------------------------------------------------
run_post_install_verification() {
    local is_dry_run="$1"
    local gradle_ver="$2"

    if [[ "$is_dry_run" == "true" ]]; then
        log_dry_run "Verification: Would execute 'java -version'"
        log_dry_run "Verification: Would execute 'gradle -v'"
        log_dry_run "Verification: Would execute 'adb --version'"
        log_dry_run "Verification: Would execute 'flutter doctor -v'"
        return 0
    fi

    printf "\n%s--- Toolchain Verification Summary ---%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"

    # Ensure PATH contains all installed binaries
    export PATH="${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/${CFG_BUILD_TOOLS}:${GRADLE_HOME}/bin:${FLUTTER_HOME}/bin:${PATH}"

    # 1. Java check
    if command -v java >/dev/null 2>&1; then
        local java_out
        java_out="$(java -version 2>&1 | head -n1)"
        log_success "Java: ${java_out}"
    else
        log_warn "Java executable not found in PATH."
    fi

    # 2. Gradle check
    if [[ "$gradle_ver" != "skip" ]]; then
        if command -v gradle >/dev/null 2>&1; then
            local gradle_out
            gradle_out="$(gradle -v 2>&1 | grep -E '^Gradle [0-9]' || echo "Gradle ready")"
            log_success "Gradle: ${gradle_out}"
        else
            log_warn "Gradle executable not found in PATH."
        fi
    fi

    # 3. Android adb check
    if command -v adb >/dev/null 2>&1; then
        local adb_out
        adb_out="$(adb --version 2>&1 | head -n1)"
        log_success "Android Platform Tools: ${adb_out}"
    else
        log_warn "adb executable not found in PATH."
    fi

    # 4. Flutter Doctor check
    if command -v flutter >/dev/null 2>&1; then
        log_info "Running Flutter diagnostic (flutter doctor -v)..."
        flutter doctor -v || true
        log_success "Flutter Doctor check complete."
    else
        log_warn "Flutter executable not found in PATH."
    fi
}

log_step "6" "7" "Post-Installation Verification"
run_post_install_verification "$DRY_RUN" "$CFG_GRADLE"

# ------------------------------------------------------------------------------
# Step 7: Completion and Next Steps
# ------------------------------------------------------------------------------
log_step "7" "7" "Installation Completed"

if [[ "$DRY_RUN" == "true" ]]; then
    log_success "Dry run simulation finished successfully! No changes were made."
else
    log_success "Mobile toolchain setup finished successfully!"
    printf "\n%sNext Steps:%s\n" "${CLR_BOLD}" "${CLR_RESET}"
    printf "  1. Reload your active shell configuration:\n"
    printf "     %ssource %s%s\n" "${CLR_CYAN}${CLR_BOLD}" "$TARGET_SHELL_RC" "${CLR_RESET}"
    printf "  2. Verify your setup by running:\n"
    printf "     %sflutter doctor -v%s\n" "${CLR_CYAN}${CLR_BOLD}" "${CLR_RESET}"
    printf "     %sjava -version%s\n" "${CLR_CYAN}${CLR_BOLD}" "${CLR_RESET}"
    printf "     %ssdkmanager --list_installed%s\n\n" "${CLR_CYAN}${CLR_BOLD}" "${CLR_RESET}"
fi
