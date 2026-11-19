#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup (flutter-kick)
# Universal Web & Local Installer Bootstrapper
#
# One-liner execution without cloning:
#   curl -fsSL https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/frozenlabx/flutter-kick/main/install.sh | bash -s -- --default
# ==============================================================================
set -euo pipefail

# 1. Local checkout check
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [[ -n "$CURRENT_DIR" && -f "${CURRENT_DIR}/unix/install.sh" && -f "${CURRENT_DIR}/config/defaults.env" ]]; then
    exec "${CURRENT_DIR}/unix/install.sh" "$@"
fi

# 2. Remote / Standalone mode: Download repository archive into a secure temp directory
REPO_URL="https://github.com/frozenlabx/flutter-kick"
BRANCH="${FLUTTER_KICK_BRANCH:-main}"
ARCHIVE_URL="${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flutter-kick-setup.XXXXXX")"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

printf "\033[1;36m%s\033[0m\n" "========================================================================"
printf "\033[1;36m%s\033[0m\n" " Flutter-Kick: Headless Android SDK & Flutter Toolchain Bootstrapper"
printf "\033[1;36m%s\033[0m\n" "========================================================================"
printf "\033[0;34m[i] Fetching latest toolchain scripts from %s (%s)...\033[0m\n" "$REPO_URL" "$BRANCH"

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$TMP_DIR" --strip-components=1
elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$ARCHIVE_URL" | tar -xz -C "$TMP_DIR" --strip-components=1
else
    printf "\033[0;31m[!] Error: curl or wget is required to download flutter-kick.\033[0m\n" >&2
    exit 1
fi

chmod +x "${TMP_DIR}/unix/install.sh" "${TMP_DIR}/unix/lib/"*.sh

# 3. If standard input is piped (e.g. curl | bash), reconnect to /dev/tty for interactive menus
if [[ ! -t 0 && -c /dev/tty ]]; then
    exec < /dev/tty
fi

# 4. Execute the toolchain installer with all forwarded CLI arguments
exec "${TMP_DIR}/unix/install.sh" "$@"
