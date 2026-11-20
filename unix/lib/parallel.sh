#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Parallel Ingestion Module
# Concurrently pre-fetches JDK, Android cmdline-tools, Gradle, and Flutter SDK
# Displays live percentage progress indicators for all components
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
# Size & Progress Inspection Helpers (POSIX / macOS / Linux compatible)
# ------------------------------------------------------------------------------
get_path_size_mb() {
    local target="$1"
    if [[ -f "$target" ]]; then
        local bytes
        bytes="$(wc -c < "$target" 2>/dev/null || echo 0)"
        bytes="${bytes//[[:space:]]/}"
        if [[ -n "$bytes" && "$bytes" -gt 0 ]]; then
            local mb=$(( bytes / 1048576 ))
            local dec=$(( (bytes % 1048576) * 10 / 1048576 ))
            echo "${mb}.${dec} MB"
            return 0
        fi
    elif [[ -d "$target" ]]; then
        local kb
        kb="$(du -sk "$target" 2>/dev/null | awk '{print $1}')"
        if [[ -n "$kb" && "$kb" -gt 0 ]]; then
            local mb=$(( kb / 1024 ))
            local dec=$(( (kb % 1024) * 10 / 1024 ))
            echo "${mb}.${dec} MB"
            return 0
        fi
    fi
    echo "0.0 MB"
}

get_curl_progress() {
    local log_file="$1"
    local path="$2"
    if [[ -f "$log_file" ]]; then
        local line
        line="$(tail -c 1200 "$log_file" 2>/dev/null | tr '\r' '\n' | grep -E "^[ ]*[0-9]+[ ]+[0-9]+[kMGT]?" | tail -n 1 || true)"
        if [[ -n "$line" ]]; then
            local pct
            local tot
            local rcv
            pct="$(echo "$line" | awk '{print $1}')"
            tot="$(echo "$line" | awk '{print $2}')"
            rcv="$(echo "$line" | awk '{print $4}')"
            if [[ -n "$pct" && "$pct" =~ ^[0-9]+$ ]]; then
                echo "${pct}% (${rcv}/${tot})"
                return 0
            fi
        fi
    fi
    local sz
    sz="$(get_path_size_mb "$path")"
    if [[ "$sz" != "0.0 MB" ]]; then
        echo "${sz}"
        return 0
    fi
    echo "0%"
}

get_git_progress() {
    local log_file="$1"
    local path="$2"
    if [[ -f "$log_file" ]]; then
        local line
        line="$(tail -c 800 "$log_file" 2>/dev/null | tr '\r' '\n' | grep -E "(Receiving objects|Resolving deltas)" | tail -n 1 || true)"
        if [[ -n "$line" ]]; then
            local pct
            pct="$(echo "$line" | grep -o -E "[0-9]+%" | head -n1 || true)"
            local sz
            sz="$(get_path_size_mb "$path")"
            if [[ -n "$pct" ]]; then
                echo "${pct} (${sz})"
                return 0
            fi
        fi
    fi
    local sz
    sz="$(get_path_size_mb "$path")"
    if [[ "$sz" != "0.0 MB" ]]; then
        echo "${sz}"
        return 0
    fi
    echo "0%"
}

# ------------------------------------------------------------------------------
# Download Workers
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
        if ! git clone --progress --depth 1 -b "$channel_arg" "$git_url" "$flutter_root" 2>/dev/null; then
            echo "Shallow clone failed, attempting full clone..."
            git clone --progress "$git_url" "$flutter_root"
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
        log_dry_run "Worker 1: Fetch Eclipse Temurin JDK ${cfg_jdk}"
        log_dry_run "Worker 2: Fetch Android SDK cmdline-tools"
        log_dry_run "Worker 3: Fetch Gradle ${cfg_gradle} distribution"
        log_dry_run "Worker 4: Clone Flutter SDK (${cfg_flutter})"
        log_dry_run "Configuration Pipeline:"
        log_dry_run "  -> Extract JDK & export JAVA_HOME"
        log_dry_run "  -> Extract cmdline-tools into ${android_home}/cmdline-tools/latest"
        log_dry_run "  -> Run sdkmanager packages"
        log_dry_run "  -> Finalize Flutter Android SDK linkage and doctor licenses"

        # Maintain exported environment paths across dry-run
        install_jdk "$cfg_jdk" "$jdk_install_dir" "true" "$is_verbose"
        install_android_sdk "$cfg_api" "$cfg_bt" "$cfg_ndk" "$cfg_cmake" "$android_home" "true" "$is_verbose"
        install_gradle "$cfg_gradle" "$gradle_install_dir" "true" "$is_verbose"
        install_flutter "$cfg_flutter" "$flutter_home" "$android_home" "$macos_tools" "true" "$is_verbose"
        return 0
    fi

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

    # Helper to kill background processes on error or cancellation
    kill_workers() {
        kill -9 "$pid_jdk" "$pid_cmd" "$pid_gradle" "$pid_flutter" 2>/dev/null || true
        wait 2>/dev/null || true
    }
    trap kill_workers INT TERM

    # --------------------------------------------------------------------------
    # Live Multi-Worker Progress Monitoring Loop
    # --------------------------------------------------------------------------
    local is_interactive=0
    [[ -t 1 ]] && is_interactive=1

    local spin_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local spin_len=10
    local spin_idx=0

    local task_names=(
        "OpenJDK ${cfg_jdk}"
        "Android cmdline-tools"
        "Gradle ${cfg_gradle}"
        "Flutter (${cfg_flutter})"
    )
    local pids=("$pid_jdk" "$pid_cmd" "$pid_gradle" "$pid_flutter")
    local logs=("$log_jdk" "$log_cmd" "$log_gradle" "$log_flutter")
    local paths=("$jdk_tar" "$cmdline_zip" "$gradle_zip" "$flutter_home")
    local exit_codes=(-1 -1 -1 -1)
    local final_status=("" "" "" "")

    # In interactive TTY, print the initial 4 lines
    if [[ "$is_interactive" -eq 1 ]]; then
        local i
        for i in 0 1 2 3; do
            printf "  [%d/4] %-26s : %s Connecting...\n" "$((i + 1))" "${task_names[i]}" "${CLR_CYAN}⠋${CLR_RESET}"
        done
    fi

    local all_done=0
    local tick=0
    local last_non_tty_report=0

    while [[ $all_done -eq 0 ]]; do
        all_done=1

        # Check each worker status
        local idx
        for idx in 0 1 2 3; do
            if [[ ${exit_codes[idx]} -eq -1 ]]; then
                if ! kill -0 "${pids[idx]}" 2>/dev/null; then
                    local code=0
                    if wait "${pids[idx]}"; then
                        code=0
                    else
                        code=$?
                    fi
                    exit_codes[idx]=$code

                    local sz
                    sz="$(get_path_size_mb "${paths[idx]}")"

                    if [[ $code -eq 0 ]]; then
                        if [[ -f "${logs[idx]}" ]] && grep -q -E "(skipped|already exists|FVM mode)" "${logs[idx]}"; then
                            final_status[idx]="${CLR_YELLOW}[-] Up-to-date / Skipped${CLR_RESET}"
                        else
                            final_status[idx]="${CLR_GREEN}[✓] Complete 100% (${sz})${CLR_RESET}"
                        fi
                    else
                        final_status[idx]="${CLR_RED}[✗] Failed${CLR_RESET}"
                    fi

                    # If not interactive, log immediately as each item completes
                    if [[ "$is_interactive" -eq 0 ]]; then
                        if [[ $code -eq 0 ]]; then
                            log_success "${task_names[idx]} ready (${sz})."
                        else
                            log_error "${task_names[idx]} download failed."
                        fi
                    fi
                else
                    all_done=0
                fi
            fi
        done

        # If any worker failed, abort immediately!
        for idx in 0 1 2 3; do
            if [[ ${exit_codes[idx]} -gt 0 ]]; then
                kill_workers
                if [[ "$is_interactive" -eq 1 ]]; then
                    printf "\n"
                fi
                log_error "Download worker failed: ${task_names[idx]}"
                if [[ -f "${logs[idx]}" ]]; then
                    cat "${logs[idx]}" >&2
                fi
                rm -rf "$parallel_scratch"
                return 1
            fi
        done

        if [[ $all_done -eq 1 ]]; then
            break
        fi

        # Update display
        if [[ "$is_interactive" -eq 1 ]]; then
            local spin="${spin_chars[spin_idx]}"
            spin_idx=$(( (spin_idx + 1) % spin_len ))

            # Move cursor up 4 lines
            printf "\033[4A\r"
            for idx in 0 1 2 3; do
                if [[ ${exit_codes[idx]} -eq -1 ]]; then
                    local prog_str
                    if [[ $idx -eq 3 ]]; then
                        prog_str="$(get_git_progress "${logs[idx]}" "${paths[idx]}")"
                        printf "\033[2K  [%d/4] %-26s : %s%s%s Cloning repo... %s\n" \
                            "$((idx + 1))" "${task_names[idx]}" \
                            "${CLR_CYAN}" "$spin" "${CLR_RESET}" \
                            "$prog_str"
                    else
                        prog_str="$(get_curl_progress "${logs[idx]}" "${paths[idx]}")"
                        printf "\033[2K  [%d/4] %-26s : %s%s%s Downloading... %s\n" \
                            "$((idx + 1))" "${task_names[idx]}" \
                            "${CLR_CYAN}" "$spin" "${CLR_RESET}" \
                            "$prog_str"
                    fi
                else
                    printf "\033[2K  [%d/4] %-26s : %s\n" \
                        "$((idx + 1))" "${task_names[idx]}" "${final_status[idx]}"
                fi
            done
        else
            # Non-TTY periodic log every 5 seconds (10 ticks)
            tick=$((tick + 1))
            if [[ $((tick - last_non_tty_report)) -ge 10 ]]; then
                last_non_tty_report=$tick
                local prog_jdk; prog_jdk="$(get_curl_progress "$log_jdk" "$jdk_tar")"
                local prog_cmd; prog_cmd="$(get_curl_progress "$log_cmd" "$cmdline_zip")"
                local prog_grd; prog_grd="$(get_curl_progress "$log_gradle" "$gradle_zip")"
                local prog_flt; prog_flt="$(get_git_progress "$log_flutter" "$flutter_home")"
                log_info "Downloads: JDK ${prog_jdk} | Cmdline ${prog_cmd} | Gradle ${prog_grd} | Flutter ${prog_flt}"
            fi
        fi

        sleep 0.5
    done

    # Final interactive redraw showing all completed
    if [[ "$is_interactive" -eq 1 ]]; then
        printf "\033[4A\r"
        for idx in 0 1 2 3; do
            printf "\033[2K  [%d/4] %-26s : %s\n" \
                "$((idx + 1))" "${task_names[idx]}" "${final_status[idx]}"
        done
        printf "\n"
    fi

    # --------------------------------------------------------------------------
    # Staged Toolchain Assembly & Configuration Pipeline
    # --------------------------------------------------------------------------
    log_info "Configuring Eclipse Temurin OpenJDK ${cfg_jdk}..."
    install_jdk "$cfg_jdk" "$jdk_install_dir" "false" "$is_verbose" "$jdk_tar"

    log_info "Configuring Android SDK Command-line Tools and Packages..."
    install_android_sdk "$cfg_api" "$cfg_bt" "$cfg_ndk" "$cfg_cmake" "$android_home" "false" "$is_verbose" "$cmdline_zip"

    if [[ "$cfg_gradle" != "skip" && -n "$cfg_gradle" ]]; then
        log_info "Configuring Gradle ${cfg_gradle}..."
        install_gradle "$cfg_gradle" "$gradle_install_dir" "false" "$is_verbose" "$gradle_zip"
    fi

    log_info "Configuring Flutter SDK (${cfg_flutter})..."
    install_flutter "$cfg_flutter" "$flutter_home" "$android_home" "$macos_tools" "false" "$is_verbose"

    local total_elapsed=$(( $(date +%s) - start_time ))
    log_success "All toolchain components configured in ${total_elapsed}s."

    # Append worker logs to central log
    {
        echo "=== Parallel Ingestion Logs ==="
        echo "--- JDK Log ---"
        cat "$log_jdk" 2>/dev/null || true
        echo "--- Android Cmdline Log ---"
        cat "$log_cmd" 2>/dev/null || true
        echo "--- Gradle Log ---"
        cat "$log_gradle" 2>/dev/null || true
        echo "--- Flutter Log ---"
        cat "$log_flutter" 2>/dev/null || true
    } >> "${LOG_FILE:-/tmp/.mobile-toolchain-setup.log}" 2>/dev/null || true

    rm -rf "$parallel_scratch"
    trap - INT TERM
    return 0
}
