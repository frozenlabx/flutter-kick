#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: JDK Installation Module
# Installs OpenJDK / Eclipse Temurin (17 or 21) and configures JAVA_HOME
# ==============================================================================
set -euo pipefail

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_LIB_DIR}/../.." && pwd)"

if [[ -f "${SCRIPT_LIB_DIR}/ui.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/ui.sh"
fi
if [[ -f "${SCRIPT_LIB_DIR}/os_detect.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/os_detect.sh"
fi

install_jdk() {
    local target_ver="${1:-${JDK_VERSION:-17}}"
    local install_root="${2:-${DEFAULT_JDK_INSTALL_DIR:-${HOME}/.local/share/jdks}}"
    local is_dry_run="${3:-false}"
    local is_verbose="${4:-0}"

    log_step "Installing / Verifying JDK ${target_ver}"

    # Ensure system details are detected
    if [[ -z "${OS_TYPE:-}" || -z "${CPU_ARCH:-}" ]]; then
        detect_all >/dev/null 2>&1 || true
    fi

    local target_jdk_dir="${install_root}/temurin-${target_ver}"
    local resolved_java_home=""

    # 1. Check if user already has a matching JDK in target local directory
    if [[ "$OS_TYPE" == "macos" && -d "${target_jdk_dir}/Contents/Home/bin" ]]; then
        resolved_java_home="${target_jdk_dir}/Contents/Home"
    elif [[ -d "${target_jdk_dir}/bin" ]]; then
        resolved_java_home="${target_jdk_dir}"
    fi

    # 2. Check macOS system / Homebrew JDK if local not found
    if [[ -z "$resolved_java_home" && "$OS_TYPE" == "macos" ]]; then
        if command -v /usr/libexec/java_home >/dev/null 2>&1; then
            local sys_jh
            sys_jh="$(/usr/libexec/java_home -v "${target_ver}" 2>/dev/null || true)"
            if [[ -n "$sys_jh" && -d "${sys_jh}/bin" ]]; then
                resolved_java_home="$sys_jh"
            fi
        fi
    fi

    # 3. Check Linux system JVM if local not found
    if [[ -z "$resolved_java_home" && "$OS_TYPE" == "linux" ]]; then
        local linux_candidate="/usr/lib/jvm/java-${target_ver}-openjdk-${CPU_ARCH}"
        if [[ ! -d "$linux_candidate" ]]; then
            linux_candidate="/usr/lib/jvm/java-${target_ver}-openjdk"
        fi
        if [[ -d "${linux_candidate}/bin" ]]; then
            resolved_java_home="$linux_candidate"
        fi
    fi

    # 4. Check active JAVA_HOME
    if [[ -z "$resolved_java_home" && -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
        local active_ver_str
        active_ver_str="$("${JAVA_HOME}/bin/java" -version 2>&1 | head -n1 || true)"
        if echo "$active_ver_str" | grep -q -E "(\"${target_ver}\.|\"1\.${target_ver}\.)"; then
            resolved_java_home="${JAVA_HOME}"
        fi
    fi

    # If already found and valid, export and return
    if [[ -n "$resolved_java_home" ]]; then
        export JAVA_HOME="$resolved_java_home"
        export PATH="${JAVA_HOME}/bin:${PATH}"
        log_success "Matching JDK ${target_ver} is already installed at: ${JAVA_HOME}"
        log_info "Java Version: $("${JAVA_HOME}/bin/java" -version 2>&1 | head -n1)"
        return 0
    fi

    # 5. Perform Installation
    log_info "JDK ${target_ver} not found locally. Initiating installation..."

    # Resolve Adoptium API slugs
    local os_slug="linux"
    [[ "$OS_TYPE" == "macos" ]] && os_slug="mac"

    local arch_slug="x64"
    [[ "$CPU_ARCH" == "arm64" ]] && arch_slug="aarch64"

    local adoptium_api_url="https://api.adoptium.net/v3/binary/latest/${target_ver}/ga/${os_slug}/${arch_slug}/jdk/hotspot/normal/eclipse"

    # Set expected target JAVA_HOME
    if [[ "$OS_TYPE" == "macos" ]]; then
        resolved_java_home="${target_jdk_dir}/Contents/Home"
    else
        resolved_java_home="${target_jdk_dir}"
    fi

    if [[ "$is_dry_run" == "true" ]]; then
        log_dry_run "Would fetch Eclipse Temurin JDK ${target_ver} (${os_slug}/${arch_slug}) from:"
        log_dry_run "  ${adoptium_api_url}"
        log_dry_run "Would unpack tarball into: ${target_jdk_dir}"
        log_dry_run "Would export JAVA_HOME=\"${resolved_java_home}\""
        log_dry_run "Would prepend \"${resolved_java_home}/bin\" to PATH"
        export JAVA_HOME="$resolved_java_home"
        export PATH="${JAVA_HOME}/bin:${PATH}"
        return 0
    fi

    # Live Installation
    mkdir -p "$install_root"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local tmp_tar="${tmp_dir}/temurin-${target_ver}.tar.gz"

    log_info "Downloading Eclipse Temurin OpenJDK ${target_ver} (${os_slug}/${arch_slug})..."
    log_debug "Adoptium URL: ${adoptium_api_url}"

    local download_success=false
    if command -v curl >/dev/null 2>&1; then
        if curl -fSL --connect-timeout 10 --retry 2 -o "$tmp_tar" "$adoptium_api_url" 2>/dev/null; then
            download_success=true
        fi
    fi

    if [[ "$download_success" != "true" ]]; then
        log_warn "Direct download from Adoptium API failed. Attempting system package manager fallback..."
        rm -rf "$tmp_dir"

        if [[ "$OS_TYPE" == "linux" ]]; then
            case "${OS_FAMILY:-}" in
                debian)
                    if command -v apt-get >/dev/null 2>&1; then
                        log_info "Installing openjdk-${target_ver}-jdk-headless via apt..."
                        if [[ "$(id -u)" -eq 0 ]]; then
                            apt-get update && apt-get install -y "openjdk-${target_ver}-jdk-headless"
                        elif command -v sudo >/dev/null 2>&1; then
                            sudo apt-get update && sudo apt-get install -y "openjdk-${target_ver}-jdk-headless"
                        fi
                        resolved_java_home="/usr/lib/jvm/java-${target_ver}-openjdk-${CPU_ARCH}"
                        [[ ! -d "$resolved_java_home" ]] && resolved_java_home="/usr/lib/jvm/java-${target_ver}-openjdk"
                    fi
                    ;;
                fedora)
                    if command -v dnf >/dev/null 2>&1; then
                        log_info "Installing java-${target_ver}-openjdk-devel via dnf..."
                        if [[ "$(id -u)" -eq 0 ]]; then
                            dnf install -y "java-${target_ver}-openjdk-devel"
                        elif command -v sudo >/dev/null 2>&1; then
                            sudo dnf install -y "java-${target_ver}-openjdk-devel"
                        fi
                        resolved_java_home="/usr/lib/jvm/java-${target_ver}-openjdk"
                    fi
                    ;;
                arch)
                    if command -v pacman >/dev/null 2>&1; then
                        log_info "Installing jdk${target_ver}-openjdk via pacman..."
                        if [[ "$(id -u)" -eq 0 ]]; then
                            pacman -Sy --noconfirm "jdk${target_ver}-openjdk"
                        elif command -v sudo >/dev/null 2>&1; then
                            sudo pacman -Sy --noconfirm "jdk${target_ver}-openjdk"
                        fi
                        resolved_java_home="/usr/lib/jvm/java-${target_ver}-openjdk"
                    fi
                    ;;
            esac
        elif [[ "$OS_TYPE" == "macos" && $(command -v brew) ]]; then
            log_info "Installing temurin@${target_ver} via Homebrew..."
            brew install --cask "temurin@${target_ver}" || brew install --cask "temurin" || true
            if command -v /usr/libexec/java_home >/dev/null 2>&1; then
                resolved_java_home="$(/usr/libexec/java_home -v "${target_ver}" 2>/dev/null || true)"
            fi
        fi

        if [[ -z "$resolved_java_home" || ! -d "$resolved_java_home" ]]; then
            log_error "Failed to install OpenJDK ${target_ver}. Please check your network or install JDK manually."
            return 1
        fi
    else
        log_info "Extracting JDK archive to ${target_jdk_dir}..."
        local extract_dir="${tmp_dir}/extracted"
        mkdir -p "$extract_dir"
        tar -xzf "$tmp_tar" -C "$extract_dir"

        # Locate root directory inside archive
        local inner_root
        inner_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
        if [[ -z "$inner_root" ]]; then
            log_error "Corrupted or unexpected archive structure in JDK download."
            rm -rf "$tmp_dir"
            return 1
        fi

        rm -rf "$target_jdk_dir"
        mkdir -p "$(dirname "$target_jdk_dir")"
        mv "$inner_root" "$target_jdk_dir"
        rm -rf "$tmp_dir"

        if [[ "$OS_TYPE" == "macos" && -d "${target_jdk_dir}/Contents/Home" ]]; then
            resolved_java_home="${target_jdk_dir}/Contents/Home"
        else
            resolved_java_home="${target_jdk_dir}"
        fi
    fi

    export JAVA_HOME="$resolved_java_home"
    export PATH="${JAVA_HOME}/bin:${PATH}"

    if [[ -x "${JAVA_HOME}/bin/java" ]]; then
        log_success "Successfully configured JDK ${target_ver} at ${JAVA_HOME}"
        log_info "Java Version: $("${JAVA_HOME}/bin/java" -version 2>&1 | head -n1)"
    else
        log_error "JDK installation finished but ${JAVA_HOME}/bin/java is missing or not executable."
        return 1
    fi

    return 0
}

# Allow direct script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _CLI_VER="17"
    _CLI_DIR="${DEFAULT_JDK_INSTALL_DIR:-${HOME}/.local/share/jdks}"
    _CLI_DRY="false"
    _CLI_VERB=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) _CLI_VER="$2"; shift 2 ;;
            --install-dir) _CLI_DIR="$2"; shift 2 ;;
            --dry-run) _CLI_DRY="true"; shift ;;
            --verbose) _CLI_VERB=1; shift ;;
            *) shift ;;
        esac
    done

    install_jdk "$_CLI_VER" "$_CLI_DIR" "$_CLI_DRY" "$_CLI_VERB"
fi
