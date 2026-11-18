#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Gradle Installation Module
# Downloads and extracts Gradle distribution into ~/.local/share/gradle
# ==============================================================================
set -euo pipefail

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_LIB_DIR}/../.." && pwd)"

if [[ -f "${SCRIPT_LIB_DIR}/ui.sh" ]]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_LIB_DIR}/ui.sh"
fi

install_gradle() {
    local target_ver="${1:-${GRADLE_VERSION:-8.11.1}}"
    local install_dir="${2:-${DEFAULT_GRADLE_INSTALL_DIR:-${HOME}/.local/share/gradle}}"
    local is_dry_run="${3:-false}"
    local is_verbose="${4:-0}"

    if [[ "$target_ver" == "skip" || -z "$target_ver" ]]; then
        log_info "Skipping Gradle installation as requested."
        return 0
    fi

    log_step "Configuring Gradle ${target_ver}"

    local target_home="${install_dir}/gradle-${target_ver}"
    local download_url="https://services.gradle.org/distributions/gradle-${target_ver}-bin.zip"

    # Check if already installed in target directory
    if [[ -x "${target_home}/bin/gradle" ]]; then
        export GRADLE_HOME="${target_home}"
        export PATH="${GRADLE_HOME}/bin:${PATH}"
        log_success "Gradle ${target_ver} is already installed at: ${GRADLE_HOME}"
        local g_ver_str
        g_ver_str="$("${GRADLE_HOME}/bin/gradle" -v 2>&1 | grep -E '^Gradle [0-9]' || echo "Gradle ${target_ver}")"
        log_info "Version: ${g_ver_str}"
        return 0
    fi

    if [[ "$is_dry_run" == "true" ]]; then
        log_dry_run "Target GRADLE_HOME: ${target_home}"
        log_dry_run "Would download Gradle distribution from: ${download_url}"
        log_dry_run "Would extract archive into: ${install_dir}"
        log_dry_run "Would export GRADLE_HOME=\"${target_home}\""
        log_dry_run "Would prepend \"${target_home}/bin\" to PATH"
        export GRADLE_HOME="${target_home}"
        export PATH="${GRADLE_HOME}/bin:${PATH}"
        return 0
    fi

    # Live installation
    mkdir -p "$install_dir"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local tmp_zip="${tmp_dir}/gradle-${target_ver}-bin.zip"

    log_info "Downloading Gradle ${target_ver} from ${download_url}..."
    if ! curl -fSL --connect-timeout 10 --retry 2 -o "$tmp_zip" "$download_url"; then
        log_error "Failed to download Gradle ${target_ver}."
        rm -rf "$tmp_dir"
        return 1
    fi

    log_info "Extracting Gradle into ${install_dir}..."
    unzip -q -o "$tmp_zip" -d "$install_dir"
    rm -rf "$tmp_dir"

    chmod +x "${target_home}/bin/gradle" 2>/dev/null || true

    export GRADLE_HOME="${target_home}"
    export PATH="${GRADLE_HOME}/bin:${PATH}"

    if [[ -x "${GRADLE_HOME}/bin/gradle" ]]; then
        log_success "Gradle ${target_ver} successfully installed at ${GRADLE_HOME}"
        local g_ver_info
        g_ver_info="$("${GRADLE_HOME}/bin/gradle" -v 2>&1 | grep -E '^Gradle [0-9]' || true)"
        [[ -n "$g_ver_info" ]] && log_info "Verified: ${g_ver_info}"
    else
        log_error "Gradle binary not found at ${GRADLE_HOME}/bin/gradle."
        return 1
    fi

    return 0
}

# Allow direct script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _CLI_VER="8.11.1"
    _CLI_DIR="${DEFAULT_GRADLE_INSTALL_DIR:-${HOME}/.local/share/gradle}"
    _CLI_DRY="false"
    _CLI_VERB=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) _CLI_VER="$2"; shift 2 ;;
            --install-dir|--gradle-home) _CLI_DIR="$2"; shift 2 ;;
            --dry-run) _CLI_DRY="true"; shift ;;
            --verbose) _CLI_VERB=1; shift ;;
            *) shift ;;
        esac
    done

    install_gradle "$_CLI_VER" "$_CLI_DIR" "$_CLI_DRY" "$_CLI_VERB"
fi
