#!/usr/bin/env bash
# claude wrapper for the sandbox: enables --dangerously-skip-permissions
# by default. Safe here because the container is the security boundary.
#
# Override for a single invocation:   CLAUDE_BYPASS=0 claude
# Bypass the wrapper entirely:         /usr/bin/claude

set -euo pipefail

if [[ "${CLAUDE_BYPASS:-1}" == "1" ]]; then
  exec /usr/bin/claude --dangerously-skip-permissions "$@"
else
  exec /usr/bin/claude "$@"
fi
