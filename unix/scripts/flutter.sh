#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Flutter Wrapper
# Delegates to unix/lib/flutter.sh
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../lib/flutter.sh" "$@"
