#!/usr/bin/env bash
# Wires read-only host ~/.claude artifacts (skills, agents, commands, settings,
# per-project memory) into the container's writable ~/.claude. Idempotent —
# safe to run on every container start.

set -euo pipefail

HOST_CLAUDE="${HOST_CLAUDE_DIR:-/host/.claude}"
DEV_CLAUDE="${HOME}/.claude"

if [[ ! -d "$HOST_CLAUDE" ]]; then
  echo "[claude-share] host ~/.claude not mounted at $HOST_CLAUDE; skipping."
  exit 0
fi

mkdir -p "$DEV_CLAUDE"

# Symlink top-level read-only artifacts. Live updates from host are visible
# immediately because these are symlinks into the RO mount.
for item in skills agents commands CLAUDE.md MEMORY.md \
            statusline-command.sh statusline.sh; do
  src="$HOST_CLAUDE/$item"
  dst="$DEV_CLAUDE/$item"
  if [[ -e "$src" && ! -e "$dst" ]]; then
    ln -s "$src" "$dst"
    echo "[claude-share] linked $item"
  fi
done

# settings.json: copy (not symlink) so the container can override without
# trying to write to the RO mount. First run only; user edits inside the
# container are preserved.
if [[ -f "$HOST_CLAUDE/settings.json" && ! -e "$DEV_CLAUDE/settings.json" ]]; then
  cp "$HOST_CLAUDE/settings.json" "$DEV_CLAUDE/settings.json"
  chmod 644 "$DEV_CLAUDE/settings.json"
  echo "[claude-share] seeded settings.json (writable copy)"
fi

# plugins/: seed a writable copy so `claude plugin install` works inside the
# container. First run only; host updates after that are NOT propagated.
# Install plugins inside the container from then on (or delete this dir to
# re-seed from the host on next start).
if [[ -d "$HOST_CLAUDE/plugins" && ! -e "$DEV_CLAUDE/plugins" ]]; then
  cp -a "$HOST_CLAUDE/plugins" "$DEV_CLAUDE/plugins"
  echo "[claude-share] seeded plugins/ (writable copy)"
fi

# Per-project memory: symlink only the memory/ subdir of each project, so
# the container reuses host memories but writes its own session history
# alongside in the writable volume.
if [[ -d "$HOST_CLAUDE/projects" ]]; then
  shopt -s nullglob
  count=0
  for proj_dir in "$HOST_CLAUDE/projects/"*/; do
    proj_name="$(basename "$proj_dir")"
    src="$proj_dir/memory"
    dst="$DEV_CLAUDE/projects/$proj_name/memory"
    if [[ -d "$src" && ! -e "$dst" ]]; then
      mkdir -p "$DEV_CLAUDE/projects/$proj_name"
      ln -s "$src" "$dst"
      count=$((count+1))
    fi
  done
  shopt -u nullglob
  [[ $count -gt 0 ]] && echo "[claude-share] linked memory/ for $count project(s)"
fi

echo "[claude-share] done."
