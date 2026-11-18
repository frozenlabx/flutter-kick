#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: JDK Wrapper
# Delegates to unix/lib/jdk.sh
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../lib/jdk.sh" "$@"
