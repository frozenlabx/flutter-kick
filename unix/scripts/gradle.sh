#!/usr/bin/env bash
# ==============================================================================
# mobile-toolchain-setup: Gradle Wrapper
# Delegates to unix/lib/gradle.sh
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../lib/gradle.sh" "$@"
