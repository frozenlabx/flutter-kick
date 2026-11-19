#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Android SDK Installation Module
# Headless setup: cmdline-tools, platform-tools, platforms, build-tools, NDK, CMake
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

# ------------------------------------------------------------------------------
# Dynamic XML Fetcher & Parser for cmdline-tools
# ------------------------------------------------------------------------------
resolve_cmdline_tools_url() {
    local target_os="$1"
    local repo_url="${ANDROID_REPO_XML_URL:-https://dl.google.com/android/repository/repository2-3.xml}"
    local default_fallback=""

    if [[ "$target_os" == "macos" ]]; then
        default_fallback="${CMDLINE_TOOLS_URL_MAC:-https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip}"
    else
        default_fallback="${CMDLINE_TOOLS_URL_LINUX:-https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip}"
    fi

    local xml_host="linux"
    [[ "$target_os" == "macos" ]] && xml_host="macosx"

    local target_arch="${CPU_ARCH:-}"
    if [[ -z "$target_arch" ]]; then
        target_arch="$(uname -m 2>/dev/null || echo "")"
    fi

    local parsed_url=""

    # Attempt dynamic fetch and parse if curl and python3 exist
    if command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        local xml_content
        xml_content="$(curl -sSfL --connect-timeout 5 --max-time 10 "$repo_url" 2>/dev/null || true)"
        if [[ -n "$xml_content" ]]; then
            parsed_url="$(python3 -c "
import sys, xml.etree.ElementTree as ET

def find_cmdline_url(xml_str, target_host, target_arch=''):
    try:
        root = ET.fromstring(xml_str)
    except Exception:
        return ''

    norm_arch = ''
    if target_arch in ('arm64', 'aarch64'):
        norm_arch = 'aarch64'
    elif target_arch in ('x86_64', 'amd64', 'x64'):
        norm_arch = 'x64'

    def get_archive_url(pkg):
        candidates = []
        for archive in pkg.findall('.//{*}archive'):
            host_elem = archive.find('{*}host-os')
            host = host_elem.text if host_elem is not None else ''
            if host != target_host:
                continue
            arch_elem = archive.find('{*}host-arch')
            arch = arch_elem.text if arch_elem is not None else ''
            url_elem = archive.find('.//{*}url')
            url = url_elem.text.strip() if (url_elem is not None and url_elem.text) else ''
            if url:
                candidates.append((arch, url))
        if not candidates:
            return ''
        if norm_arch:
            for arch, url in candidates:
                if arch == norm_arch:
                    return url
        for arch, url in candidates:
            if not arch or arch == 'x64':
                return url
        return candidates[0][1]

    # Priority 1: Canonical 'cmdline-tools;latest' package
    for pkg in root.findall('.//{*}remotePackage'):
        if pkg.get('path') == 'cmdline-tools;latest':
            url = get_archive_url(pkg)
            if url:
                return url

    # Priority 2: Highest numbered cmdline-tools;<N> package
    numbered = []
    for pkg in root.findall('.//{*}remotePackage'):
        path = pkg.get('path', '')
        if path.startswith('cmdline-tools;'):
            ver_str = path.split(';', 1)[1]
            try:
                parts = [int(p) for p in ver_str.split('-')[0].split('.') if p.isdigit()]
                if parts:
                    numbered.append((parts, pkg))
            except Exception:
                pass
    if numbered:
        numbered.sort(key=lambda x: x[0], reverse=True)
        for _, pkg in numbered:
            url = get_archive_url(pkg)
            if url:
                return url
    return ''

try:
    xml_data = sys.stdin.read()
    target_host = sys.argv[1]
    target_arch = sys.argv[2] if len(sys.argv) > 2 else ''
    url = find_cmdline_url(xml_data, target_host, target_arch)
    if url:
        if not url.startswith('http'):
            url = 'https://dl.google.com/android/repository/' + url
        print(url)
except Exception:
    pass
" "$xml_host" "$target_arch" <<< "$xml_content" 2>/dev/null || true)"
        fi
    fi

    if [[ -n "$parsed_url" ]]; then
        log_info "Dynamically resolved latest cmdline-tools: ${parsed_url}" >&2
        echo "$parsed_url"
    else
        log_debug "Using static fallback cmdline-tools URL: ${default_fallback}"
        echo "$default_fallback"
    fi
}

# ------------------------------------------------------------------------------
# Smart NDK Resolution (Partial version to full revision)
# ------------------------------------------------------------------------------
resolve_ndk_version() {
    local raw_ndk="$1"
    local sdk_root="$2"
    local is_dry_run="${3:-false}"

    if [[ "$raw_ndk" == "skip" || -z "$raw_ndk" ]]; then
        echo "skip"
        return 0
    fi

    # If it's already a full 4-part revision e.g. 27.2.12479018
    if [[ "$raw_ndk" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$raw_ndk"
        return 0
    fi

    # Query sdkmanager --list if available
    local sdkmanager_bin="${sdk_root}/cmdline-tools/latest/bin/sdkmanager"
    local query_match=""

    if [[ -x "$sdkmanager_bin" && "$is_dry_run" == "false" ]]; then
        log_info "Querying sdkmanager for available NDK revisions matching '${raw_ndk}'..." >&2
        query_match="$(yes 2>/dev/null | "$sdkmanager_bin" --list --sdk_root="$sdk_root" 2>/dev/null | \
            grep -E "ndk;${raw_ndk}" | awk -F';' '{print $2}' | awk '{print $1}' | sort -V | tail -n1 || true)"
    fi

    if [[ -n "$query_match" ]]; then
        log_success "Smart NDK resolution: '${raw_ndk}' -> '${query_match}' (via sdkmanager)" >&2
        echo "$query_match"
        return 0
    fi

    # Built-in lookup map for common partial versions
    local mapped_revision=""
    case "$raw_ndk" in
        28.0|28) mapped_revision="28.0.13004108" ;;
        27.2|27) mapped_revision="27.2.12479018" ;;
        27.1)    mapped_revision="27.1.12297006" ;;
        26.3|26) mapped_revision="26.3.11579264" ;;
        25.2|25) mapped_revision="25.2.9519653"  ;;
        23.2|23) mapped_revision="23.2.8568313"  ;;
        21.4|21) mapped_revision="21.4.7075529"  ;;
        *)       mapped_revision="$raw_ndk"      ;;
    esac

    if [[ "$mapped_revision" != "$raw_ndk" ]]; then
        log_info "Smart NDK resolution: mapped partial '${raw_ndk}' -> '${mapped_revision}'" >&2
    fi

    echo "$mapped_revision"
}

# ------------------------------------------------------------------------------
# Main Android Installation Routine
# ------------------------------------------------------------------------------
install_android_sdk() {
    local api_arg="${1:-${ANDROID_API:-36}}"
    local build_tools_arg="${2:-${BUILD_TOOLS_VERSION:-36.0.0}}"
    local ndk_arg="${3:-${NDK_VERSION:-27.2.12479018}}"
    local cmake_arg="${4:-${CMAKE_VERSION:-3.22.1}}"
    local sdk_root="${5:-}"
    local is_dry_run="${6:-false}"
    local is_verbose="${7:-0}"
    [[ "$is_verbose" -eq 1 ]] && export VERBOSE=1

    log_step "Configuring Headless Android SDK"

    # Ensure system details are detected
    if [[ -z "${OS_TYPE:-}" ]]; then
        detect_all >/dev/null 2>&1 || true
    fi

    if [[ -z "$sdk_root" ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            sdk_root="${DEFAULT_ANDROID_HOME_MAC:-${HOME}/Library/Android/sdk}"
        else
            sdk_root="${DEFAULT_ANDROID_HOME_LINUX:-${HOME}/Android/Sdk}"
        fi
    fi

    export ANDROID_HOME="$sdk_root"
    export ANDROID_SDK_ROOT="$sdk_root"

    local cmdline_url
    cmdline_url="$(resolve_cmdline_tools_url "$OS_TYPE")"

    local resolved_ndk
    resolved_ndk="$(resolve_ndk_version "$ndk_arg" "$sdk_root" "$is_dry_run")"

    # Prepare package list supporting comma-separated APIs
    local packages_to_install=("platform-tools")

    local api_items=()
    IFS=',' read -r -a api_items <<< "$api_arg"
    for api_item in "${api_items[@]}"; do
        local api_clean
        api_clean="$(echo "$api_item" | tr -d ' ')"
        if [[ -n "$api_clean" ]]; then
            packages_to_install+=("platforms;android-${api_clean}")
        fi
    done

    if [[ -n "$build_tools_arg" && "$build_tools_arg" != "skip" ]]; then
        packages_to_install+=("build-tools;${build_tools_arg}")
    fi

    if [[ -n "$resolved_ndk" && "$resolved_ndk" != "skip" ]]; then
        packages_to_install+=("ndk;${resolved_ndk}")
    fi

    if [[ -n "$cmake_arg" && "$cmake_arg" != "skip" ]]; then
        packages_to_install+=("cmake;${cmake_arg}")
    fi

    local sdkmanager_bin="${sdk_root}/cmdline-tools/latest/bin/sdkmanager"

    if [[ "$is_dry_run" == "true" ]]; then
        log_dry_run "Target ANDROID_HOME: ${sdk_root}"
        log_dry_run "cmdline-tools source: ${cmdline_url}"
        log_dry_run "Would extract into: ${sdk_root}/cmdline-tools/latest"
        log_dry_run "Would accept licenses: yes | sdkmanager --licenses --sdk_root=\"${sdk_root}\""
        log_dry_run "Would install packages:"
        for pkg in "${packages_to_install[@]}"; do
            log_dry_run "  - ${pkg}"
        done
        log_dry_run "Would export PATH additions: ${sdk_root}/cmdline-tools/latest/bin, ${sdk_root}/platform-tools"
        export PATH="${sdk_root}/cmdline-tools/latest/bin:${sdk_root}/platform-tools:${PATH}"
        return 0
    fi

    # Live Installation
    # 1. Download and extract cmdline-tools if sdkmanager is not present
    if [[ ! -x "$sdkmanager_bin" ]]; then
        log_info "Installing Android SDK Command-line Tools into ${sdk_root}/cmdline-tools/latest..."
        mkdir -p "${sdk_root}/cmdline-tools"

        local tmp_dir
        tmp_dir="$(mktemp -d)"
        local tmp_zip="${tmp_dir}/cmdline-tools.zip"

        log_info "Downloading cmdline-tools package from ${cmdline_url}..."
        if ! curl -fSL --connect-timeout 10 --retry 2 -o "$tmp_zip" "$cmdline_url"; then
            log_error "Failed to download Android command-line tools."
            rm -rf "$tmp_dir"
            return 1
        fi

        log_info "Extracting cmdline-tools archive..."
        local extract_dir="${tmp_dir}/extracted"
        mkdir -p "$extract_dir"
        unzip -q "$tmp_zip" -d "$extract_dir"

        rm -rf "${sdk_root}/cmdline-tools/latest"

        # Handle inner structure: Google archives may contain 'cmdline-tools', 'tools', or flat files
        if [[ -d "${extract_dir}/cmdline-tools" ]]; then
            mv "${extract_dir}/cmdline-tools" "${sdk_root}/cmdline-tools/latest"
        elif [[ -d "${extract_dir}/tools" ]]; then
            mv "${extract_dir}/tools" "${sdk_root}/cmdline-tools/latest"
        else
            mkdir -p "${sdk_root}/cmdline-tools/latest"
            cp -R "${extract_dir}/." "${sdk_root}/cmdline-tools/latest/"
        fi

        chmod +x "${sdk_root}/cmdline-tools/latest/bin/"* 2>/dev/null || true
        rm -rf "$tmp_dir"

        if [[ ! -x "$sdkmanager_bin" ]]; then
            log_error "sdkmanager binary not found or not executable at ${sdkmanager_bin}"
            return 1
        fi
        log_success "cmdline-tools installed at ${sdk_root}/cmdline-tools/latest"
    else
        log_success "Android cmdline-tools already present at ${sdk_root}/cmdline-tools/latest"
    fi

    # Ensure Java and Android tools are in active subshell PATH
    if [[ -n "${JAVA_HOME:-}" && -d "${JAVA_HOME}/bin" && ":${PATH}:" != *":${JAVA_HOME}/bin:"* ]]; then
        export PATH="${JAVA_HOME}/bin:${PATH}"
    fi
    export PATH="${sdk_root}/cmdline-tools/latest/bin:${sdk_root}/platform-tools:${PATH}"

    # 2. Auto-accept SDK licenses
    log_info "Auto-accepting Android SDK licenses..."
    yes 2>/dev/null | "$sdkmanager_bin" --licenses --sdk_root="$sdk_root" >/dev/null 2>&1 || true
    log_success "Android SDK licenses accepted."

    # 3. Install required SDK packages
    log_info "Installing Android SDK packages: ${packages_to_install[*]}"
    if ! yes 2>/dev/null | "$sdkmanager_bin" --sdk_root="$sdk_root" "${packages_to_install[@]}"; then
        log_warn "Some packages failed to install on first attempt. Retrying with license refresh..."
        yes 2>/dev/null | "$sdkmanager_bin" --licenses --sdk_root="$sdk_root" >/dev/null 2>&1 || true
        yes 2>/dev/null | "$sdkmanager_bin" --sdk_root="$sdk_root" "${packages_to_install[@]}" || true
    fi

    # Verify adb
    if [[ -x "${sdk_root}/platform-tools/adb" ]]; then
        log_success "Android platform-tools ready: $("${sdk_root}/platform-tools/adb" --version 2>&1 | head -n1)"
    else
        log_warn "adb not found in ${sdk_root}/platform-tools (may be installed in background or non-standard path)."
    fi

    return 0
}

# Allow direct script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _CLI_API="36"
    _CLI_BT="36.0.0"
    _CLI_NDK="27.2.12479018"
    _CLI_CMAKE="3.22.1"
    _CLI_ROOT=""
    _CLI_DRY="false"
    _CLI_VERB=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api) _CLI_API="$2"; shift 2 ;;
            --build-tools) _CLI_BT="$2"; shift 2 ;;
            --ndk) _CLI_NDK="$2"; shift 2 ;;
            --cmake) _CLI_CMAKE="$2"; shift 2 ;;
            --sdk-root) _CLI_ROOT="$2"; shift 2 ;;
            --dry-run) _CLI_DRY="true"; shift ;;
            --verbose) _CLI_VERB=1; shift ;;
            *) shift ;;
        esac
    done

    install_android_sdk "$_CLI_API" "$_CLI_BT" "$_CLI_NDK" "$_CLI_CMAKE" "$_CLI_ROOT" "$_CLI_DRY" "$_CLI_VERB"
fi
