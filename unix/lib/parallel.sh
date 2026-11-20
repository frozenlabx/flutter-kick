#!/usr/bin/env bash
# shellcheck disable=SC2317
# ==============================================================================
# mobile-toolchain-setup: Parallel Ingestion Module
# Concurrently pre-fetches JDK, Android cmdline-tools, Gradle, and Flutter SDK
# ==============================================================================
set -euo pipefail

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_LIB_DIR}/ui.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/ui.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/os_detect.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/os_detect.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/android.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/android.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/jdk.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/jdk.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/gradle.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/gradle.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/flutter.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/flutter.sh"
fi

# ------------------------------------------------------------------------------
# Parallel Download Workers
# ------------------------------------------------------------------------------
fetch_jdk_asset() {
    local target_ver="$1"
    local dest_tar="$2"
    local log_file="$3"

    {
        local os_slug="linux"
        [[ "${OS_TYPE:-}" == "macos" ]] && os_slug="mac"

        local arch_slug="x64"
        [[ "${CPU_ARCH:-}" == "arm64" ]] && arch_slug="aarch64"

        local api_url="https://api.adoptium.net/v3/binary/latest/${target_ver}/ga/${os_slug}/${arch_slug}/jdk/hotspot/normal/eclipse"
        echo "Fetching JDK ${target_ver} from ${api_url} -> ${dest_tar}"
        if command -v curl >/dev/null 2>&1; then
            curl -fSL --connect-timeout 15 --retry 2 -o "$dest_tar" "$api_url"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$dest_tar" "$api_url"
        else
            echo "curl or wget required" >&2
            exit 1
        fi
    } > "$log_file" 2>&1
}

fetch_cmdline_asset() {
    local cmdline_url="$1"
    local dest_zip="$2"
    local log_file="$3"

    {
        echo "Fetching Android cmdline-tools from ${cmdline_url} -> ${dest_zip}"
        if command -v curl >/dev/null 2>&1; then
            curl -fSL --connect-timeout 15 --retry 2 -o "$dest_zip" "$cmdline_url"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$dest_zip" "$cmdline_url"
        else
            echo "curl or wget required" >&2
            exit 1
        fi
    } > "$log_file" 2>&1
}

fetch_gradle_asset() {
    local target_ver="$1"
    local dest_zip="$2"
    local log_file="$3"

    {
        if [[ "$target_ver" == "skip" || -z "$target_ver" ]]; then
            echo "Gradle skipped"
            exit 0
        fi
        local url="https://services.gradle.org/distributions/gradle-${target_ver}-bin.zip"
        echo "Fetching Gradle ${target_ver} from ${url} -> ${dest_zip}"
        if command -v curl >/dev/null 2>&1; then
            curl -fSL --connect-timeout 15 --retry 2 -o "$dest_zip" "$url"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$dest_zip" "$url"
        else
            echo "curl or wget required" >&2
            exit 1
        fi
    } > "$log_file" 2>&1
}

fetch_flutter_asset() {
    local channel_arg="$1"
    local flutter_root="$2"
    local log_file="$3"

    {
        if [[ "$channel_arg" == "fvm" ]]; then
            echo "Flutter FVM mode handled in main installer"
            exit 0
        fi
        if [[ -d "${flutter_root}/.git" ]]; then
            echo "Flutter repository already exists at ${flutter_root}"
            exit 0
        fi
        local git_url="https://github.com/flutter/flutter.git"
        echo "Cloning Flutter (${channel_arg}) into ${flutter_root}"
        mkdir -p "$(dirname "$flutter_root")"
        if ! git clone --depth 1 -b "$channel_arg" "$git_url" "$flutter_root" 2>/dev/null; then
            echo "Shallow clone failed, attempting full clone..."
            git clone "$git_url" "$flutter_root"
            git -C "$flutter_root" checkout "$channel_arg" 2>/dev/null || \
                git -C "$flutter_root" checkout "tags/$channel_arg" 2>/dev/null || true
        fi
    } > "$log_file" 2>&1
}

# ------------------------------------------------------------------------------
# Parallel Orchestration Entrypoint
# ------------------------------------------------------------------------------
run_parallel_ingestion() {
    local cfg_jdk="$1"
    local cfg_api="$2"
    local cfg_bt="$3"
    local cfg_ndk="$4"
    local cfg_cmake="$5"
    local cfg_gradle="$6"
    local cfg_flutter="$7"
    local jdk_install_dir="$8"
    local android_home="$9"
    shift 9
    local gradle_install_dir="$1"
    local flutter_home="$2"
    local macos_tools="$3"
    local is_dry_run="$4"
    local is_verbose="$5"
    [[ "$is_verbose" -eq 1 ]] && export VERBOSE=1

    if [[ "$is_dry_run" == "true" ]]; then
        log_info "Parallel Toolchain Ingestion enabled (4 concurrent download workers)"
        log_dry_run "Parallel Worker 1: Fetch Eclipse Temurin JDK ${cfg_jdk}"
        log_dry_run "Parallel Worker 2: Fetch Android SDK cmdline-tools"
        log_dry_run "Parallel Worker 3: Fetch Gradle ${cfg_gradle} distribution"
        log_dry_run "Parallel Worker 4: Clone Flutter SDK (${cfg_flutter})"
        log_dry_run "Staged Configuration Pipeline:"
        log_dry_run "  -> Extract JDK & export JAVA_HOME"
        log_dry_run "  -> Extract cmdline-tools into ${android_home}/cmdline-tools/latest"
        log_dry_run "  -> Concurrently run sdkmanager packages and Flutter precache"
        log_dry_run "  -> Finalize Flutter Android SDK linkage and doctor licenses"

        # Maintain exported environment paths across dry-run
        install_jdk "$cfg_jdk" "$jdk_install_dir" "true" "$is_verbose"
        install_android_sdk "$cfg_api" "$cfg_bt" "$cfg_ndk" "$cfg_cmake" "$android_home" "true" "$is_verbose"
        install_gradle "$cfg_gradle" "$gradle_install_dir" "true" "$is_verbose"
        install_flutter "$cfg_flutter" "$flutter_home" "$android_home" "$macos_tools" "true" "$is_verbose"
        return 0
    fi

    log_step "Parallel Toolchain Ingestion (Concurrent Download & Staged Pipeline)"
    local parallel_scratch
    parallel_scratch="$(mktemp -d "${TMPDIR:-/tmp}/mto-parallel.XXXXXX")"
    local jdk_tar="${parallel_scratch}/temurin-${cfg_jdk}.tar.gz"
    local cmdline_zip="${parallel_scratch}/cmdline-tools.zip"
    local gradle_zip="${parallel_scratch}/gradle-${cfg_gradle}.zip"

    local log_jdk="${parallel_scratch}/jdk.log"
    local log_cmd="${parallel_scratch}/cmdline.log"
    local log_gradle="${parallel_scratch}/gradle.log"
    local log_flutter="${parallel_scratch}/flutter.log"

    local cmdline_url
    cmdline_url="$(resolve_cmdline_tools_url "${OS_TYPE:-linux}")"

    log_info "Spawning 4 concurrent download workers..."
    local start_time
    start_time="$(date +%s)"

    # Spawn workers
    fetch_jdk_asset "$cfg_jdk" "$jdk_tar" "$log_jdk" &
    local pid_jdk=$!

    fetch_cmdline_asset "$cmdline_url" "$cmdline_zip" "$log_cmd" &
    local pid_cmd=$!

    fetch_gradle_asset "$cfg_gradle" "$gradle_zip" "$log_gradle" &
    local pid_gradle=$!

    fetch_flutter_asset "$cfg_flutter" "$flutter_home" "$log_flutter" &
    local pid_flutter=$!

    # Helper to kill background processes on error
    kill_workers() {
        kill -9 "$pid_jdk" "$pid_cmd" "$pid_gradle" "$pid_flutter" 2>/dev/null || true
        wait 2>/dev/null || true
    }

    # Monitor and wait for JDK & cmdline-tools first
    if ! wait "$pid_jdk"; then
        log_error "JDK download failed. Worker log:"
        cat "$log_jdk" >&2
        kill_workers
        rm -rf "$parallel_scratch"
        return 1
    fi
    log_success "Eclipse Temurin JDK ${cfg_jdk} downloaded."

    if ! wait "$pid_cmd"; then
        log_error "Android cmdline-tools download failed. Worker log:"
        cat "$log_cmd" >&2
        kill_workers
        rm -rf "$parallel_scratch"
        return 1
    fi
    log_success "Android SDK cmdline-tools downloaded."

    # Immediate Stage: Extract JDK & cmdline-tools so sdkmanager can start packages early!
    log_info "Configuring JDK & cmdline-tools..."
    install_jdk "$cfg_jdk" "$jdk_install_dir" "false" "$is_verbose" "$jdk_tar"
    install_android_sdk "$cfg_api" "$cfg_bt" "$cfg_ndk" "$cfg_cmake" "$android_home" "false" "$is_verbose" "$cmdline_zip"

    # Wait for Gradle
    if ! wait "$pid_gradle"; then
        log_error "Gradle download failed. Worker log:"
        cat "$log_gradle" >&2
        kill_workers
        rm -rf "$parallel_scratch"
        return 1
    fi
    log_success "Gradle ${cfg_gradle} downloaded."
    install_gradle "$cfg_gradle" "$gradle_install_dir" "false" "$is_verbose" "$gradle_zip"

    # Wait for Flutter
    if ! wait "$pid_flutter"; then
        log_error "Flutter repository clone failed. Worker log:"
        cat "$log_flutter" >&2
        kill_workers
        rm -rf "$parallel_scratch"
        return 1
    fi
    log_success "Flutter repository ready."
    install_flutter "$cfg_flutter" "$flutter_home" "$android_home" "$macos_tools" "false" "$is_verbose"

    local elapsed=$(( $(date +%s) - start_time ))
    log_success "All toolchain components ingested in ${elapsed}s (parallel execution)."

    # Append worker logs to central log
    {
        echo "=== Parallel Ingestion Logs ==="
        cat "$log_jdk" "$log_cmd" "$log_gradle" "$log_flutter" 2>/dev/null || true
    } >> "${DEFAULT_LOG_FILE:-${HOME}/.mobile-toolchain-setup.log}" 2>/dev/null || true

    rm -rf "$parallel_scratch"
    return 0
}
