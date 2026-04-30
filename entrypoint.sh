#!/usr/bin/env bash
set -euo pipefail

# Run firewall once per container start (no-op if NET_ADMIN missing).
# Mode is controlled by FIREWALL_MODE: web (default) | strict | off.
/usr/local/bin/init-firewall.sh || echo "firewall setup failed (continuing)"

# Wire host ~/.claude (RO bind) into container's writable ~/.claude.
if [[ "${CLAUDE_BOX_SHARE_HOST:-1}" == "1" ]]; then
  /usr/local/bin/setup-host-claude.sh || echo "host-claude setup failed (continuing)"
fi

# Make ~/Projects resolve inside the container even though the bind mount
# uses the host's absolute path (so memory keys match).
if [[ -n "${CLAUDE_BOX_HOST_PROJECTS:-}" && -d "$CLAUDE_BOX_HOST_PROJECTS" && ! -e "$HOME/Projects" ]]; then
  ln -s "$CLAUDE_BOX_HOST_PROJECTS" "$HOME/Projects"
fi

exec "$@"
