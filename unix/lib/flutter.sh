#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Flutter Installation Module
# Clones / configures Flutter SDK, FVM, Android integration & macOS iOS tools
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

install_flutter() {
    local channel_arg="${1:-${FLUTTER_CHANNEL:-stable}}"
    local flutter_root="${2:-${DEFAULT_FLUTTER_HOME:-${HOME}/development/flutter}}"
    local android_sdk="${3:-${ANDROID_HOME:-}}"
    local macos_tools="${4:-${MACOS_IOS_TOOLS:-yes}}"
    local is_dry_run="${5:-false}"
    local is_verbose="${6:-0}"
    [[ "$is_verbose" -eq 1 ]] && VERBOSE=1

    log_step "Configuring Flutter SDK (${channel_arg})"

    # Ensure system details are detected
    if [[ -z "${OS_TYPE:-}" ]]; then
        detect_all >/dev/null 2>&1 || true
    fi

    # --------------------------------------------------------------------------
    # FVM Mode
    # --------------------------------------------------------------------------
    if [[ "$channel_arg" == "fvm" ]]; then
        log_info "Configuring Flutter Version Management (FVM)..."

        if [[ "$is_dry_run" == "true" ]]; then
            log_dry_run "Would install/verify FVM CLI (brew tap leoafarias/fvm or https://fvm.app/install.sh)"
            log_dry_run "Would run: fvm install stable && fvm global stable"
            log_dry_run "Would configure: flutter config --android-sdk \"${android_sdk}\""
            log_dry_run "Would accept licenses: yes | flutter doctor --android-licenses"
            if [[ "$OS_TYPE" == "macos" && "$macos_tools" == "yes" ]]; then
                log_dry_run "Would verify Xcode Command Line Tools and CocoaPods for iOS"
            fi
            return 0
        fi

        # Live FVM installation
        if ! command -v fvm >/dev/null 2>&1; then
            if [[ "$OS_TYPE" == "macos" && $(command -v brew) ]]; then
                log_info "Installing FVM via Homebrew..."
                brew tap leoafarias/fvm 2>/dev/null || true
                brew install fvm || true
            elif command -v dart >/dev/null 2>&1; then
                log_info "Installing FVM via dart pub..."
                dart pub global activate fvm || true
            else
                log_info "Installing FVM via standalone installer..."
                curl -fsSL https://fvm.app/install.sh | bash || true
            fi
        fi

        if command -v fvm >/dev/null 2>&1; then
            log_info "Installing and configuring stable channel via FVM..."
            fvm install stable || true
            fvm global stable || true
            export PATH="${HOME}/fvm/default/bin:${PATH}"
        fi

        if command -v flutter >/dev/null 2>&1; then
            [[ -n "$android_sdk" ]] && flutter config --android-sdk "$android_sdk" 2>/dev/null || true
            yes 2>/dev/null | flutter doctor --android-licenses >/dev/null 2>&1 || true
            log_success "FVM Flutter environment configured."
        fi

        return 0
    fi

    # --------------------------------------------------------------------------
    # Standard Channel / Git Tag Mode
    # --------------------------------------------------------------------------
    local git_repo_url="https://github.com/flutter/flutter.git"

    if [[ "$is_dry_run" == "true" ]]; then
        log_dry_run "Target FLUTTER_HOME: ${flutter_root}"
        if [[ -d "${flutter_root}/.git" ]]; then
            log_dry_run "Flutter repository already exists at ${flutter_root}. Would switch branch/tag to: ${channel_arg}"
        else
            log_dry_run "Would clone Flutter repository:"
            log_dry_run "  git clone --depth 1 -b ${channel_arg} ${git_repo_url} \"${flutter_root}\""
        fi
        log_dry_run "Would prepend \"${flutter_root}/bin\" to PATH"
        log_dry_run "Would execute: flutter precache --android"
        log_dry_run "Would execute: flutter config --android-sdk \"${android_sdk}\""
        log_dry_run "Would accept licenses: yes | flutter doctor --android-licenses"
        if [[ "$OS_TYPE" == "macos" && "$macos_tools" == "yes" ]]; then
            log_dry_run "macOS iOS Tools: Would verify Xcode Command Line Tools (xcode-select -p) and CocoaPods"
        fi
        export PATH="${flutter_root}/bin:${PATH}"
        return 0
    fi

    # Live Installation
    if [[ -d "${flutter_root}/.git" ]]; then
        log_info "Flutter repository already exists at ${flutter_root}. Checking out ${channel_arg}..."
        git -C "$flutter_root" fetch --tags 2>/dev/null || true
        git -C "$flutter_root" checkout "$channel_arg" 2>/dev/null || \
            git -C "$flutter_root" checkout "tags/$channel_arg" 2>/dev/null || true
    else
        log_info "Cloning Flutter SDK (${channel_arg}) into ${flutter_root}..."
        mkdir -p "$(dirname "$flutter_root")"
        if ! git clone --depth 1 -b "$channel_arg" "$git_repo_url" "$flutter_root" 2>/dev/null; then
            log_warn "Shallow clone failed. Attempting full repository clone to resolve channel/tag..."
            git clone "$git_repo_url" "$flutter_root"
            git -C "$flutter_root" checkout "$channel_arg" 2>/dev/null || \
                git -C "$flutter_root" checkout "tags/$channel_arg" 2>/dev/null || true
        fi
    fi

    export PATH="${flutter_root}/bin:${PATH}"

    if [[ -x "${flutter_root}/bin/flutter" ]]; then
        log_info "Pre-caching Android engine artifacts..."
        "${flutter_root}/bin/flutter" precache --android >/dev/null 2>&1 || true

        if [[ -n "$android_sdk" ]]; then
            log_info "Associating Android SDK location with Flutter..."
            "${flutter_root}/bin/flutter" config --android-sdk "$android_sdk" >/dev/null 2>&1 || true
        fi

        log_info "Accepting Flutter Android licenses..."
        yes 2>/dev/null | "${flutter_root}/bin/flutter" doctor --android-licenses >/dev/null 2>&1 || true

        # macOS iOS Tools (CocoaPods & Xcode CLI)
        if [[ "$OS_TYPE" == "macos" && "$macos_tools" == "yes" ]]; then
            log_info "Checking macOS iOS development tools..."
            if ! xcode-select -p >/dev/null 2>&1; then
                log_info "Initiating Xcode Command Line Tools installation..."
                xcode-select --install || true
            else
                log_success "Xcode Command Line Tools verified."
            fi

            if ! command -v pod >/dev/null 2>&1; then
                if command -v brew >/dev/null 2>&1; then
                    log_info "Installing CocoaPods via Homebrew..."
                    brew install cocoapods 2>/dev/null || true
                elif command -v gem >/dev/null 2>&1; then
                    log_info "Installing CocoaPods via gem..."
                    sudo gem install cocoapods 2>/dev/null || true
                fi
            else
                local pod_ver
                pod_ver="$(pod --version 2>/dev/null || echo "installed")"
                log_success "CocoaPods verified (${pod_ver})."
            fi
        fi

        log_success "Flutter SDK configured successfully."
        local f_ver_info
        f_ver_info="$("${flutter_root}/bin/flutter" --version 2>&1 | head -n1 || true)"
        [[ -n "$f_ver_info" ]] && log_info "${f_ver_info}"
    else
        log_error "Flutter binary not found at ${flutter_root}/bin/flutter."
        return 1
    fi

    return 0
}

# Allow direct script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _CLI_CHANNEL="stable"
    _CLI_HOME="${DEFAULT_FLUTTER_HOME:-${HOME}/development/flutter}"
    _CLI_ANDROID="${ANDROID_HOME:-}"
    _CLI_MACOS="yes"
    _CLI_DRY="false"
    _CLI_VERB=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --channel) _CLI_CHANNEL="$2"; shift 2 ;;
            --flutter-home) _CLI_HOME="$2"; shift 2 ;;
            --android-sdk|--android-home) _CLI_ANDROID="$2"; shift 2 ;;
            --macos-ios-tools) _CLI_MACOS="$2"; shift 2 ;;
            --dry-run) _CLI_DRY="true"; shift ;;
            --verbose) _CLI_VERB=1; shift ;;
            *) shift ;;
        esac
    done

    install_flutter "$_CLI_CHANNEL" "$_CLI_HOME" "$_CLI_ANDROID" "$_CLI_MACOS" "$_CLI_DRY" "$_CLI_VERB"
fi
