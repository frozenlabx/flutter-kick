#!/usr/bin/env bash
# shellcheck disable=SC2034
# ==============================================================================
# mobile-toolchain-setup: Diagnostic Doctor & Tool Detection Library
# Inspects existing installations of JDK, Android SDK, Gradle, and Flutter.
# Provides comprehensive diagnostics, actionable troubleshooting & auto-fixing.
# ==============================================================================
set -euo pipefail

if [[ -n "${_DOCTOR_LIB_LOADED:-}" ]]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi
_DOCTOR_LIB_LOADED=1

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_LIB_DIR}/ui.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/ui.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/os_detect.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/os_detect.sh"
fi

# ------------------------------------------------------------------------------
# Global Detection State Variables
# ------------------------------------------------------------------------------
# shellcheck disable=SC2034
DETECTED_JDK_VALID=0
DETECTED_JDK_PATH=""
DETECTED_JDK_VER=""
DETECTED_JDK_MAJOR=0

DETECTED_ANDROID_VALID=0
DETECTED_ANDROID_HOME=""
DETECTED_CMDLINE_VALID=0
DETECTED_CMDLINE_PATH=""
DETECTED_ADB_VALID=0
DETECTED_ADB_PATH=""
DETECTED_ADB_VER=""
DETECTED_PLATFORMS_LIST=""
DETECTED_BUILD_TOOLS_LIST=""
DETECTED_NDK_LIST=""
DETECTED_CMAKE_LIST=""
DETECTED_LICENSES_VALID=0

DETECTED_GRADLE_VALID=0
DETECTED_GRADLE_PATH=""
DETECTED_GRADLE_VER=""

DETECTED_FLUTTER_VALID=0
DETECTED_FLUTTER_PATH=""
DETECTED_FLUTTER_VER=""
DETECTED_FLUTTER_CHANNEL=""

# ------------------------------------------------------------------------------
# Detection Functions
# ------------------------------------------------------------------------------
detect_existing_jdk() {
    DETECTED_JDK_VALID=0
    DETECTED_JDK_PATH=""
    DETECTED_JDK_VER=""
    DETECTED_JDK_MAJOR=0

    local candidate_homes=()
    local candidate_bins=()

    # 1. Active JAVA_HOME
    if [[ -n "${JAVA_HOME:-}" && -d "${JAVA_HOME}" ]]; then
        candidate_homes+=("${JAVA_HOME}")
    fi

    # 2. Local Flutter-Kick installation directories
    local local_jdks_dir="${HOME}/.local/share/jdks"
    if [[ -d "$local_jdks_dir" ]]; then
        for d in "${local_jdks_dir}"/temurin-*; do
            if [[ -d "$d" ]]; then
                if [[ -d "${d}/Contents/Home" ]]; then
                    candidate_homes+=("${d}/Contents/Home")
                else
                    candidate_homes+=("$d")
                fi
            fi
        done
    fi

    # 3. macOS system directories
    if [[ "${OS_TYPE:-}" == "macos" || "$(uname -s)" == "Darwin" ]]; then
        for d in /Library/Java/JavaVirtualMachines/*/Contents/Home; do
            [[ -d "$d" ]] && candidate_homes+=("$d")
        done
        for d in "${HOME}"/Library/Java/JavaVirtualMachines/*/Contents/Home; do
            [[ -d "$d" ]] && candidate_homes+=("$d")
        done
        if command -v /usr/libexec/java_home >/dev/null 2>&1; then
            local jh_out
            jh_out="$(/usr/libexec/java_home 2>/dev/null || true)"
            [[ -n "$jh_out" && -d "$jh_out" ]] && candidate_homes+=("$jh_out")
        fi
    fi

    # 4. Linux system JVM directories
    if [[ "${OS_TYPE:-}" == "linux" || "$(uname -s)" == "Linux" ]]; then
        for d in /usr/lib/jvm/*; do
            [[ -d "$d" ]] && candidate_homes+=("$d")
        done
        for d in /opt/java/* /opt/jdk/*; do
            [[ -d "$d" ]] && candidate_homes+=("$d")
        done
    fi

    # 5. Common version managers (SDKMAN, ASDF)
    if [[ -d "${HOME}/.sdkman/candidates/java" ]]; then
        for d in "${HOME}"/.sdkman/candidates/java/*; do
            [[ -d "$d" && "$d" != *"current"* ]] && candidate_homes+=("$d")
        done
    fi
    if [[ -d "${HOME}/.asdf/installs/java" ]]; then
        for d in "${HOME}"/.asdf/installs/java/*; do
            [[ -d "$d" ]] && candidate_homes+=("$d")
        done
    fi

    # 6. Binary on PATH
    if command -v java >/dev/null 2>&1; then
        candidate_bins+=("$(command -v java)")
    fi

    if [[ ${#candidate_homes[@]} -gt 0 ]]; then
        local home_cand
        for home_cand in "${candidate_homes[@]}"; do
            local test_bin="${home_cand}/bin/java"
            if [[ -x "$test_bin" ]]; then
                local test_out
                if test_out="$("$test_bin" -version 2>&1)"; then
                    DETECTED_JDK_VALID=1
                    DETECTED_JDK_PATH="$home_cand"
                    DETECTED_JDK_VER="$(echo "$test_out" | head -n1)"
                    local major_match
                    major_match="$(echo "$test_out" | grep -o -E '(version "([0-9]+)|version "1\.([0-9]+))' | head -n1 || true)"
                    if [[ "$major_match" =~ 1\.([0-9]+) ]]; then
                        DETECTED_JDK_MAJOR="${BASH_REMATCH[1]}"
                    elif [[ "$major_match" =~ \"([0-9]+) ]]; then
                        DETECTED_JDK_MAJOR="${BASH_REMATCH[1]}"
                    fi
                    return 0
                fi
            fi
        done
    fi

    if [[ ${#candidate_bins[@]} -gt 0 ]]; then
        local bin_cand
        for bin_cand in "${candidate_bins[@]}"; do
            local test_out
            if test_out="$("$bin_cand" -version 2>&1)"; then
                DETECTED_JDK_VALID=1
                DETECTED_JDK_PATH="$(dirname "$(dirname "$bin_cand")")"
                DETECTED_JDK_VER="$(echo "$test_out" | head -n1)"
                local major_match
                major_match="$(echo "$test_out" | grep -o -E '(version "([0-9]+)|version "1\.([0-9]+))' | head -n1 || true)"
                if [[ "$major_match" =~ 1\.([0-9]+) ]]; then
                    DETECTED_JDK_MAJOR="${BASH_REMATCH[1]}"
                elif [[ "$major_match" =~ \"([0-9]+) ]]; then
                    DETECTED_JDK_MAJOR="${BASH_REMATCH[1]}"
                fi
                return 0
            fi
        done
    fi

    return 0
}

detect_existing_android_sdk() {
    DETECTED_ANDROID_VALID=0
    DETECTED_ANDROID_HOME=""
    DETECTED_CMDLINE_VALID=0
    DETECTED_CMDLINE_PATH=""
    DETECTED_ADB_VALID=0
    DETECTED_ADB_PATH=""
    DETECTED_ADB_VER=""
    DETECTED_PLATFORMS_LIST=""
    DETECTED_BUILD_TOOLS_LIST=""
    DETECTED_NDK_LIST=""
    DETECTED_CMAKE_LIST=""
    DETECTED_LICENSES_VALID=0

    local sdk_candidates=()
    [[ -n "${ANDROID_HOME:-}" ]] && sdk_candidates+=("${ANDROID_HOME}")
    [[ -n "${ANDROID_SDK_ROOT:-}" ]] && sdk_candidates+=("${ANDROID_SDK_ROOT}")
    sdk_candidates+=("${HOME}/Library/Android/sdk" "${HOME}/Android/Sdk" "/opt/android-sdk" "/usr/lib/android-sdk")

    local found_sdk=""
    local cand
    for cand in "${sdk_candidates[@]}"; do
        if [[ -d "$cand" ]]; then
            # Verify it looks like an Android SDK
            if [[ -d "${cand}/cmdline-tools" || -d "${cand}/platform-tools" || -d "${cand}/platforms" || -d "${cand}/tools" ]]; then
                found_sdk="$cand"
                break
            fi
        fi
    done

    if [[ -z "$found_sdk" ]]; then
        return 0
    fi

    DETECTED_ANDROID_HOME="$found_sdk"
    DETECTED_ANDROID_VALID=1

    # Check cmdline-tools / sdkmanager
    local sm_candidates=(
        "${found_sdk}/cmdline-tools/latest/bin/sdkmanager"
        "${found_sdk}/cmdline-tools/bin/sdkmanager"
        "${found_sdk}/tools/bin/sdkmanager"
    )
    for sm in "${sm_candidates[@]}"; do
        if [[ -x "$sm" ]]; then
            DETECTED_CMDLINE_VALID=1
            DETECTED_CMDLINE_PATH="$sm"
            break
        fi
    done

    # Check platform-tools / adb
    local adb_cand="${found_sdk}/platform-tools/adb"
    if [[ -x "$adb_cand" ]]; then
        DETECTED_ADB_VALID=1
        DETECTED_ADB_PATH="$adb_cand"
        DETECTED_ADB_VER="$("$adb_cand" --version 2>&1 | head -n1 || echo "ready")"
    elif command -v adb >/dev/null 2>&1; then
        DETECTED_ADB_VALID=1
        DETECTED_ADB_PATH="$(command -v adb)"
        DETECTED_ADB_VER="$(adb --version 2>&1 | head -n1 || echo "ready")"
    fi

    # Check platforms
    if [[ -d "${found_sdk}/platforms" ]]; then
        local p_list=()
        for p in "${found_sdk}"/platforms/android-*; do
            [[ -d "$p" ]] && p_list+=("$(basename "$p")")
        done
        if [[ ${#p_list[@]} -gt 0 ]]; then
            DETECTED_PLATFORMS_LIST="$(IFS=,; echo "${p_list[*]}")"
        fi
    fi

    # Check build-tools
    if [[ -d "${found_sdk}/build-tools" ]]; then
        local bt_list=()
        for bt in "${found_sdk}"/build-tools/*; do
            [[ -d "$bt" ]] && bt_list+=("$(basename "$bt")")
        done
        if [[ ${#bt_list[@]} -gt 0 ]]; then
            DETECTED_BUILD_TOOLS_LIST="$(IFS=,; echo "${bt_list[*]}")"
        fi
    fi

    # Check NDK
    if [[ -d "${found_sdk}/ndk" ]]; then
        local ndk_list=()
        for ndk_dir in "${found_sdk}"/ndk/*; do
            [[ -d "$ndk_dir" ]] && ndk_list+=("$(basename "$ndk_dir")")
        done
        if [[ ${#ndk_list[@]} -gt 0 ]]; then
            DETECTED_NDK_LIST="$(IFS=,; echo "${ndk_list[*]}")"
        fi
    elif [[ -d "${found_sdk}/ndk-bundle" ]]; then
        DETECTED_NDK_LIST="ndk-bundle"
    fi

    # Check CMake
    if [[ -d "${found_sdk}/cmake" ]]; then
        local cmake_list=()
        for cm in "${found_sdk}"/cmake/*; do
            [[ -d "$cm" ]] && cmake_list+=("$(basename "$cm")")
        done
        if [[ ${#cmake_list[@]} -gt 0 ]]; then
            DETECTED_CMAKE_LIST="$(IFS=,; echo "${cmake_list[*]}")"
        fi
    fi

    # Check licenses
    if [[ -f "${found_sdk}/licenses/android-sdk-license" ]]; then
        DETECTED_LICENSES_VALID=1
    fi

    return 0
}

detect_existing_gradle() {
    DETECTED_GRADLE_VALID=0
    DETECTED_GRADLE_PATH=""
    DETECTED_GRADLE_VER=""

    local candidate_bins=()
    if [[ -n "${GRADLE_HOME:-}" && -x "${GRADLE_HOME}/bin/gradle" ]]; then
        candidate_bins+=("${GRADLE_HOME}/bin/gradle")
    fi
    if command -v gradle >/dev/null 2>&1; then
        candidate_bins+=("$(command -v gradle)")
    fi
    local local_gradle_dir="${HOME}/.local/share/gradle"
    if [[ -d "$local_gradle_dir" ]]; then
        for d in "${local_gradle_dir}"/gradle-*/bin/gradle; do
            [[ -x "$d" ]] && candidate_bins+=("$d")
        done
    fi

    if [[ ${#candidate_bins[@]} -gt 0 ]]; then
        local bin
        for bin in "${candidate_bins[@]}"; do
            local g_out
            if g_out="$("$bin" -v 2>&1)"; then
                DETECTED_GRADLE_VALID=1
                DETECTED_GRADLE_PATH="$bin"
                DETECTED_GRADLE_VER="$(echo "$g_out" | grep -E '^Gradle [0-9]' | head -n1 || echo "ready")"
                return 0
            fi
        done
    fi

    return 0
}

detect_existing_flutter() {
    DETECTED_FLUTTER_VALID=0
    DETECTED_FLUTTER_PATH=""
    DETECTED_FLUTTER_VER=""
    DETECTED_FLUTTER_CHANNEL=""

    local candidate_bins=()
    if [[ -n "${FLUTTER_HOME:-}" && -x "${FLUTTER_HOME}/bin/flutter" ]]; then
        candidate_bins+=("${FLUTTER_HOME}/bin/flutter")
    fi
    if command -v flutter >/dev/null 2>&1; then
        candidate_bins+=("$(command -v flutter)")
    fi
    candidate_bins+=(
        "${HOME}/development/flutter/bin/flutter"
        "${HOME}/flutter/bin/flutter"
        "/opt/flutter/bin/flutter"
    )

    local bin
    for bin in "${candidate_bins[@]}"; do
        if [[ -x "$bin" ]]; then
            local f_dir
            f_dir="$(dirname "$(dirname "$bin")")"
            if [[ -d "${f_dir}/.git" || -f "${f_dir}/bin/flutter" ]]; then
                DETECTED_FLUTTER_VALID=1
                DETECTED_FLUTTER_PATH="$f_dir"
                local f_out
                f_out="$("$bin" --version 2>&1 | head -n1 || true)"
                DETECTED_FLUTTER_VER="$f_out"
                if [[ "$f_out" =~ channel[[:space:]]+([^[:space:]]+) ]]; then
                    DETECTED_FLUTTER_CHANNEL="${BASH_REMATCH[1]}"
                else
                    DETECTED_FLUTTER_CHANNEL="stable"
                fi
                return 0
            fi
        fi
    done

    return 0
}

detect_existing_tools() {
    detect_existing_jdk
    detect_existing_android_sdk
    detect_existing_gradle
    detect_existing_flutter
}

# ------------------------------------------------------------------------------
# Troubleshooting Doctor Diagnostic Runner
# ------------------------------------------------------------------------------
run_doctor() {
    local auto_fix="${1:-false}"

    # Ensure system details are detected
    if [[ -z "${OS_TYPE:-}" ]]; then
        detect_all >/dev/null 2>&1 || true
    fi

    printf "\n"
    printf "%s========================================================================%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"
    printf "%s Flutter-Kick Toolchain Doctor & Diagnostic Analyzer%s\n" "${CLR_BOLD}${CLR_WHITE}" "${CLR_RESET}"
    printf "%s========================================================================%s\n\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"

    local count_passed=0
    local count_warn=0
    local count_error=0
    local -a issue_descriptions=()
    local -a fix_recommendations=()

    # 1. Operating System & Shell Environment
    printf "%s[1/6] Operating System & Shell Environment%s\n" "${CLR_BOLD}" "${CLR_RESET}"
    log_success "Operating System: ${OS_NAME:-$(uname -s)} (${CPU_ARCH:-$(uname -m)})"
    count_passed=$((count_passed + 1))

    local target_rc="${TARGET_SHELL_RC:-${HOME}/.${ACTIVE_SHELL:-zsh}rc}"
    log_success "Active Shell: ${ACTIVE_SHELL:-unknown} (Configuration: ${target_rc})"
    count_passed=$((count_passed + 1))

    if check_disk_space "$HOME" 10; then
        log_success "Free Disk Space: Sufficient (checked ${HOME})"
        count_passed=$((count_passed + 1))
    else
        log_warn "Free Disk Space: Less than 10 GB free on ${HOME}"
        count_warn=$((count_warn + 1))
        issue_descriptions+=("Low free disk space (< 10 GB).")
        fix_recommendations+=("Free up disk space before installing large SDK packages or emulators.")
    fi

    # 2. Prerequisites
    printf "\n%s[2/6] Core Prerequisites%s\n" "${CLR_BOLD}" "${CLR_RESET}"
    for tool in curl git unzip tar; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_success "Required utility: ${tool} detected"
            count_passed=$((count_passed + 1))
        else
            log_error "Missing utility: ${tool} is required but not installed."
            count_error=$((count_error + 1))
            issue_descriptions+=("Missing core utility: ${tool}.")
            fix_recommendations+=("Install ${tool} using your system package manager.")
        fi
    done

    if [[ "$OS_TYPE" == "macos" ]]; then
        if command -v xcode-select >/dev/null 2>&1 && xcode-select -p >/dev/null 2>&1; then
            log_success "Xcode Command Line Tools: $(xcode-select -p)"
            count_passed=$((count_passed + 1))
        else
            log_warn "Xcode Command Line Tools: Not detected."
            count_warn=$((count_warn + 1))
            issue_descriptions+=("Xcode Command Line Tools not configured.")
            fix_recommendations+=("Run: xcode-select --install")
        fi

        if command -v pod >/dev/null 2>&1; then
            log_success "CocoaPods: $(pod --version 2>&1 || echo "ready")"
            count_passed=$((count_passed + 1))
        else
            log_info "CocoaPods: Not installed (optional for iOS development; install via 'sudo gem install cocoapods' or 'brew install cocoapods')"
        fi
    fi

    # 3. Java Development Kit (JDK)
    printf "\n%s[3/6] Java Development Kit (JDK)%s\n" "${CLR_BOLD}" "${CLR_RESET}"
    detect_existing_jdk
    if [[ "$DETECTED_JDK_VALID" -eq 1 ]]; then
        log_success "JDK Location: ${DETECTED_JDK_PATH}"
        log_success "Java Version: ${DETECTED_JDK_VER}"
        count_passed=$((count_passed + 2))

        if [[ "$DETECTED_JDK_MAJOR" -ge 17 ]]; then
            log_success "Version Compatibility: Java ${DETECTED_JDK_MAJOR} meets AGP 8.0+ requirements (>= 17)."
            count_passed=$((count_passed + 1))
        else
            log_warn "Version Compatibility: Java ${DETECTED_JDK_MAJOR} is older than recommended (Java 17+ required for AGP 8.0+)."
            count_warn=$((count_warn + 1))
            issue_descriptions+=("Installed Java version (${DETECTED_JDK_MAJOR}) is too old for modern Android Gradle Plugin.")
            fix_recommendations+=("Run './install.sh --default' to install OpenJDK 17 LTS.")
        fi
    else
        log_error "Java Development Kit: No working Java Runtime found on system."
        count_error=$((count_error + 1))
        issue_descriptions+=("JDK is not installed or JAVA_HOME is invalid.")
        fix_recommendations+=("Run './install.sh --default' to install Eclipse Temurin OpenJDK 17.")
    fi

    # 4. Android SDK & Tools
    printf "\n%s[4/6] Android SDK & Command-Line Tools%s\n" "${CLR_BOLD}" "${CLR_RESET}"
    detect_existing_android_sdk
    if [[ "$DETECTED_ANDROID_VALID" -eq 1 ]]; then
        log_success "ANDROID_HOME: ${DETECTED_ANDROID_HOME}"
        count_passed=$((count_passed + 1))

        if [[ "$DETECTED_CMDLINE_VALID" -eq 1 ]]; then
            log_success "cmdline-tools: sdkmanager is executable (${DETECTED_CMDLINE_PATH})"
            count_passed=$((count_passed + 1))
        else
            log_error "cmdline-tools: sdkmanager not found in ${DETECTED_ANDROID_HOME}/cmdline-tools/latest"
            count_error=$((count_error + 1))
            issue_descriptions+=("Android cmdline-tools is missing sdkmanager.")
            fix_recommendations+=("Run './install.sh' to download and configure canonical cmdline-tools;latest.")
        fi

        if [[ "$DETECTED_ADB_VALID" -eq 1 ]]; then
            log_success "platform-tools: adb ready (${DETECTED_ADB_VER}) [${DETECTED_ADB_PATH}]"
            count_passed=$((count_passed + 1))
        else
            log_warn "platform-tools: adb not found in ${DETECTED_ANDROID_HOME}/platform-tools"
            count_warn=$((count_warn + 1))
            issue_descriptions+=("Android platform-tools (adb) is missing.")
            fix_recommendations+=("Install platform-tools via: sdkmanager 'platform-tools'")
        fi

        if [[ -n "$DETECTED_PLATFORMS_LIST" ]]; then
            log_success "Installed Platforms: ${DETECTED_PLATFORMS_LIST}"
            count_passed=$((count_passed + 1))
        else
            log_warn "Installed Platforms: No Android SDK platform (e.g. android-34/35/36) installed."
            count_warn=$((count_warn + 1))
            issue_descriptions+=("No Android SDK platforms installed.")
            fix_recommendations+=("Install platform via: sdkmanager 'platforms;android-36'")
        fi

        if [[ -n "$DETECTED_BUILD_TOOLS_LIST" ]]; then
            log_success "Installed Build-Tools: ${DETECTED_BUILD_TOOLS_LIST}"
            count_passed=$((count_passed + 1))
        else
            log_warn "Installed Build-Tools: No Android SDK build-tools found."
            count_warn=$((count_warn + 1))
            issue_descriptions+=("No Android build-tools installed.")
            fix_recommendations+=("Install build-tools via: sdkmanager 'build-tools;36.0.0'")
        fi

        if [[ -n "$DETECTED_NDK_LIST" ]]; then
            log_info "Installed NDK: ${DETECTED_NDK_LIST}"
        fi

        if [[ -n "$DETECTED_CMAKE_LIST" ]]; then
            log_info "Installed CMake: ${DETECTED_CMAKE_LIST}"
        fi

        if [[ "$DETECTED_LICENSES_VALID" -eq 1 ]]; then
            log_success "Android SDK Licenses: Accepted (license file verified)"
            count_passed=$((count_passed + 1))
        else
            log_warn "Android SDK Licenses: License agreement missing or not accepted."
            count_warn=$((count_warn + 1))
            issue_descriptions+=("Android SDK licenses are not accepted.")
            fix_recommendations+=("Accept licenses via: yes | \"${DETECTED_CMDLINE_PATH:-sdkmanager}\" --licenses --sdk_root=\"${DETECTED_ANDROID_HOME}\"")
        fi
    else
        log_error "Android SDK: No Android SDK installation found."
        count_error=$((count_error + 1))
        issue_descriptions+=("Android SDK is not installed.")
        fix_recommendations+=("Run './install.sh --default' to bootstrap headless Android SDK.")
    fi

    # 5. Gradle & Flutter
    printf "\n%s[5/6] Gradle & Flutter SDK%s\n" "${CLR_BOLD}" "${CLR_RESET}"
    detect_existing_gradle
    if [[ "$DETECTED_GRADLE_VALID" -eq 1 ]]; then
        log_success "Gradle: ${DETECTED_GRADLE_VER} (${DETECTED_GRADLE_PATH})"
        count_passed=$((count_passed + 1))
    else
        log_info "Gradle: Standalone Gradle not found (note: projects with Gradle Wrapper './gradlew' do not strictly require a global install)."
    fi

    detect_existing_flutter
    if [[ "$DETECTED_FLUTTER_VALID" -eq 1 ]]; then
        local channel_str=""
        [[ -n "$DETECTED_FLUTTER_CHANNEL" ]] && channel_str=" [channel: ${DETECTED_FLUTTER_CHANNEL}]"
        log_success "Flutter SDK: ${DETECTED_FLUTTER_VER}${channel_str} (${DETECTED_FLUTTER_PATH})"
        count_passed=$((count_passed + 1))

        # Check flutter android-sdk configuration
        if command -v flutter >/dev/null 2>&1; then
            local f_cfg
            f_cfg="$(flutter config 2>&1 || true)"
            if echo "$f_cfg" | grep -q "android-sdk:"; then
                log_success "Flutter Android SDK Configuration: android-sdk correctly linked"
                count_passed=$((count_passed + 1))
            elif [[ "$DETECTED_ANDROID_VALID" -eq 1 ]]; then
                log_warn "Flutter Android SDK Configuration: android-sdk not explicitly configured."
                count_warn=$((count_warn + 1))
                issue_descriptions+=("Flutter android-sdk path is not configured.")
                fix_recommendations+=("Run: flutter config --android-sdk \"${DETECTED_ANDROID_HOME}\"")
            fi
        fi
    else
        log_warn "Flutter SDK: Flutter is not installed or not in PATH."
        count_warn=$((count_warn + 1))
        issue_descriptions+=("Flutter SDK is missing.")
        fix_recommendations+=("Run './install.sh --default' to clone and configure Flutter stable.")
    fi

    # 6. Shell Environment & PATH
    printf "\n%s[6/6] Shell Environment & PATH Integration%s\n" "${CLR_BOLD}" "${CLR_RESET}"
    local marker_start="# >>> MOBILE_TOOLCHAIN_SETUP_START >>>"
    if [[ -f "$target_rc" ]] && grep -q "$marker_start" "$target_rc"; then
        log_success "Shell Environment Marker: Reversible configuration block present in ${target_rc}"
        count_passed=$((count_passed + 1))
    else
        log_warn "Shell Environment Marker: Marker block missing from ${target_rc}"
        count_warn=$((count_warn + 1))
        issue_descriptions+=("Shell RC (${target_rc}) does not contain mobile-toolchain environment block.")
        fix_recommendations+=("Run './install.sh' to inject environment variables and PATH into ${target_rc}.")
    fi

    # Check active subshell PATH
    local missing_paths=()
    if [[ "$DETECTED_JDK_VALID" -eq 1 && ":${PATH}:" != *":${DETECTED_JDK_PATH}/bin:"* ]]; then
        missing_paths+=("JAVA_HOME/bin")
    fi
    if [[ "$DETECTED_ANDROID_VALID" -eq 1 ]]; then
        [[ ":${PATH}:" != *":${DETECTED_ANDROID_HOME}/cmdline-tools/latest/bin:"* ]] && missing_paths+=("cmdline-tools")
        [[ ":${PATH}:" != *":${DETECTED_ANDROID_HOME}/platform-tools:"* ]] && missing_paths+=("platform-tools")
    fi
    if [[ "$DETECTED_FLUTTER_VALID" -eq 1 && ":${PATH}:" != *":${DETECTED_FLUTTER_PATH}/bin:"* ]]; then
        missing_paths+=("flutter/bin")
    fi

    if [[ ${#missing_paths[@]} -eq 0 ]]; then
        log_success "Active PATH: Contains all detected toolchain binary directories"
        count_passed=$((count_passed + 1))
    else
        local missing_str
        missing_str="$(IFS=,; echo "${missing_paths[*]}")"
        log_warn "Active PATH: Missing binary paths in current shell session: ${missing_str}"
        count_warn=$((count_warn + 1))
        issue_descriptions+=("Current session PATH is missing: ${missing_str}.")
        fix_recommendations+=("Source your shell config: source \"${target_rc}\" or restart your terminal.")
    fi

    # --------------------------------------------------------------------------
    # Doctor Summary Box
    # --------------------------------------------------------------------------
    printf "\n"
    printf "%s========================================================================%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"
    printf "%s Doctor Summary: %d passed, %d warning(s), %d issue(s) found.%s\n" \
        "${CLR_BOLD}${CLR_WHITE}" "$count_passed" "$count_warn" "$count_error" "${CLR_RESET}"

    if [[ ${#issue_descriptions[@]} -gt 0 ]]; then
        printf "\n%sActionable Recommendations:%s\n" "${CLR_BOLD}${CLR_YELLOW}" "${CLR_RESET}"
        local i
        for ((i=0; i<${#issue_descriptions[@]}; i++)); do
            printf "  %s[%d]%s %s\n" "${CLR_YELLOW}" "$((i + 1))" "${CLR_RESET}" "${issue_descriptions[i]}"
            printf "      %s→ Suggestion:%s %s\n" "${CLR_CYAN}" "${CLR_RESET}" "${fix_recommendations[i]}"
        done
    else
        printf " %sAll checks passed! Your mobile development toolchain is healthy.%s\n" "${CLR_GREEN}" "${CLR_RESET}"
    fi
    printf "%s========================================================================%s\n\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"

    # Auto-Fix routine
    local can_fix=false
    if [[ "$DETECTED_ANDROID_VALID" -eq 1 && "$DETECTED_LICENSES_VALID" -eq 0 && -n "$DETECTED_CMDLINE_PATH" ]]; then
        can_fix=true
    fi
    if [[ "$DETECTED_FLUTTER_VALID" -eq 1 && "$DETECTED_ANDROID_VALID" -eq 1 ]] && command -v flutter >/dev/null 2>&1; then
        local f_cfg; f_cfg="$(flutter config 2>&1 || true)"
        if ! echo "$f_cfg" | grep -q "android-sdk:"; then
            can_fix=true
        fi
    fi
    local marker_start="# >>> MOBILE_TOOLCHAIN_SETUP_START >>>"
    if [[ ! -f "$target_rc" ]] || ! grep -q "$marker_start" "$target_rc"; then
        if [[ "$DETECTED_JDK_VALID" -eq 1 || "$DETECTED_ANDROID_VALID" -eq 1 || "$DETECTED_FLUTTER_VALID" -eq 1 ]]; then
            can_fix=true
        fi
    fi

    if [[ "$can_fix" == "true" ]]; then
        local should_fix=false
        if [[ "$auto_fix" == "true" || "${AUTO_CONFIRM:-false}" == "true" ]]; then
            should_fix=true
        elif [[ -t 0 ]]; then
            if prompt_confirm "Would you like Flutter-Kick to attempt auto-fixing these issues?" true; then
                should_fix=true
            fi
        fi

        if [[ "$should_fix" == "true" ]]; then
            log_step "Running Automated Toolchain Fixes"
            
            # Fix 1: Accept licenses if Android SDK exists but licenses missing
            if [[ "$DETECTED_ANDROID_VALID" -eq 1 && "$DETECTED_LICENSES_VALID" -eq 0 && -n "$DETECTED_CMDLINE_PATH" ]]; then
                log_info "Accepting Android SDK licenses..."
                yes 2>/dev/null | "$DETECTED_CMDLINE_PATH" --licenses --sdk_root="$DETECTED_ANDROID_HOME" >/dev/null 2>&1 || true
                log_success "Android SDK licenses accepted."
            fi

            # Fix 2: Link Android SDK to Flutter if both exist
            if [[ "$DETECTED_FLUTTER_VALID" -eq 1 && "$DETECTED_ANDROID_VALID" -eq 1 ]] && command -v flutter >/dev/null 2>&1; then
                log_info "Linking Android SDK to Flutter..."
                flutter config --android-sdk "$DETECTED_ANDROID_HOME" >/dev/null 2>&1 || true
                yes 2>/dev/null | flutter doctor --android-licenses >/dev/null 2>&1 || true
                log_success "Flutter Android SDK linked."
            fi

            # Fix 3: Re-inject shell environment block if missing
            if [[ -f "${SCRIPT_LIB_DIR}/env.sh" ]]; then
                # shellcheck source=/dev/null
                source "${SCRIPT_LIB_DIR}/env.sh"
                log_info "Re-injecting shell environment block into ${target_rc}..."
                local jh="${DETECTED_JDK_PATH:-}"
                local ah="${DETECTED_ANDROID_HOME:-}"
                local gh="${DETECTED_GRADLE_PATH:+$(dirname "$(dirname "$DETECTED_GRADLE_PATH")")}"
                local fh="${DETECTED_FLUTTER_PATH:-}"
                local bt="${DETECTED_BUILD_TOOLS_LIST%%,*}"
                local block
                block="$(generate_env_block "${ACTIVE_SHELL:-zsh}" "$jh" "$ah" "$gh" "$fh" "$bt")"
                inject_env_block "$target_rc" "$block" "false"
                log_success "Shell environment updated. Run 'source ${target_rc}' to apply."
            fi

            log_success "Auto-fix routine complete. Re-run './install.sh --doctor' to re-verify."
        fi
    fi

    if [[ "$count_error" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Standalone execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _FIX_FLAG="false"
    for arg in "$@"; do
        [[ "$arg" == "--fix" || "$arg" == "-f" ]] && _FIX_FLAG="true"
    done
    run_doctor "$_FIX_FLAG"
fi
