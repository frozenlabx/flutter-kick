#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Root Convenience Wrapper
# Delegates to unix/install.sh
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/unix/install.sh" "$@"
