#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Android SDK Wrapper
# Delegates to unix/lib/android.sh
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../lib/android.sh" "$@"
