#!/usr/bin/env bash
# ==============================================================================
# Alias Wrapper -> Calls build-wsl.sh with all CLI arguments
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/build-wsl.sh" "$@"
