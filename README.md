# claude-box

A sandboxed Ubuntu 24.04 (arm64) container that runs Claude Code with restricted
network egress, your `~/Projects` mounted in, and your host `~/.claude` shared
read-only so skills/agents/commands/memories carry over.

You attach via `docker exec` + `tmux`, so sessions survive disconnects and
container restarts.

---

## Contents

- [What's inside](#whats-inside)
- [Prerequisites](#prerequisites)
- [First-time build](#first-time-build)
- [Connecting via tmux](#connecting-via-tmux)
- [Authenticating Claude Code](#authenticating-claude-code)
- [Daily workflow](#daily-workflow)
- [Configuration knobs](#configuration-knobs)
- [Firewall modes](#firewall-modes)
- [Exposing a dev server (ngrok)](#exposing-a-dev-server-ngrok)
- [What's persisted, what isn't](#whats-persisted-what-isnt)
- [Troubleshooting](#troubleshooting)

---

## What's inside

- **OS:** Ubuntu 24.04 LTS, pinned to `linux/arm64` (native on Apple Silicon)
- **Runtimes:** Node.js 22 LTS, Bun, Python 3 (with `pipx` and `uv`), OpenJDK 21 + Maven + Gradle
- **CLI tools:** git, git-lfs, openssh-client, vim, nano, tmux, screen, ripgrep, fd, fzf, jq, yq, htop, tree, rsync, curl, wget, build-essential, cmake, and more
- **Claude Code CLI** + **ngrok** agent
- **Egress firewall** (iptables + ipset) with three modes: `web` (default), `strict`, `off`
- **Auto-start** on Docker daemon launch (`restart: unless-stopped`)

---

## Prerequisites

- Docker Desktop for macOS (Apple Silicon)
- Docker Desktop set to launch at login (Settings → General) if you want the container to come back automatically after host reboot

That's it. No other host-side tooling required.

---

## First-time build

```bash
cd ~/Projects/claude-box
make build         # initial build (~5–10 min on first run)
make up            # start container in background, runs sleep infinity
make status        # confirm it's Up
```

The container is named `claude-box` and runs in the background. From here on,
you only need `make tmux` for daily use.

---

## Connecting via tmux

The intended workflow: one persistent tmux session inside the container that
you attach/detach from as needed.

```bash
make tmux
```

What that does under the hood:

```bash
docker exec -it claude-box tmux new-session -A -s main
```

The `-A` flag means *attach if it exists, create if it doesn't*. So the first
call creates the session, subsequent calls re-attach to the same one.

### Inside tmux

| Keybinding | Action |
|---|---|
| `Ctrl-b c` | New window |
| `Ctrl-b n` / `p` | Next / previous window |
| `Ctrl-b %` | Vertical split |
| `Ctrl-b "` | Horizontal split |
| `Ctrl-b →←↑↓` | Move between panes |
| `Ctrl-b d` | **Detach** (session keeps running) |
| `Ctrl-b [` | Scroll mode (`q` to exit) |
| `Ctrl-b ?` | Full keybinding list |

### Re-attaching later

Just run `make tmux` again. The session, your shells, running processes, and
scrollback are all still there.

### Multiple terminal windows on your Mac, one tmux session

Run `make tmux` from any terminal — they all share the same session. Helpful
for "Claude doing work in pane 1, server logs in pane 2, browser-pointed
shell in pane 3."

For independent sessions, name them: `docker exec -it claude-box tmux new -A -s logs`.

### Plain shell (no tmux)

If you just want a one-off shell:

```bash
make shell
```

This won't persist — when you disconnect, the shell is gone.

---

## Authenticating Claude Code

The container can't read macOS Keychain (where your host `claude` stores its
token), so it needs its own auth. Two options:

### Option A — interactive login (one-time)

```bash
make login   # runs `claude` inside the container; opens browser flow
```

The token gets written to `/home/dev/.claude/.credentials.json` inside the
named volume `claude-config`, so it survives `make rebuild`. You only need
to do this once.

### Option B — API key via env var (stateless)

Add to a `.env` file next to `docker-compose.yml`:

```
ANTHROPIC_API_KEY=sk-ant-...
```

Then in `docker-compose.yml`, add to the `environment:` block:

```yaml
ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
```

`make up` and you're done — no login, no creds on disk inside the container.
Best for unattended/automated use.

---

## Daily workflow

```bash
# Start everything (only needed if it's stopped)
make up

# Attach
make tmux

# Inside tmux:
cd ~/Projects/your-project
claude                              # start Claude Code

# When done, detach (Ctrl-b d) — leave the container running
# Next time, just `make tmux` again
```

The container auto-starts whenever Docker Desktop starts, so after a reboot
you can go straight to `make tmux`.

---

## Configuration knobs

All configurable via environment variables (set in shell, in a `.env` file
next to compose, or directly in `docker-compose.yml`):

| Variable | Default | Effect |
|---|---|---|
| `FIREWALL_MODE` | `web` | `web` / `strict` / `off` — see [Firewall modes](#firewall-modes) |
| `CLAUDE_BOX_SHARE_HOST` | `1` | If `1`, symlinks host `~/.claude` skills/agents/commands/memories into the container |
| `CLAUDE_BOX_HOST_PROJECTS` | `${HOME}/Projects` | Host path for the `~/Projects` symlink inside the container |
| `NGROK_AUTHTOKEN` | (empty) | Required for `make tunnel` |
| `ANTHROPIC_API_KEY` | (empty) | Optional alternative to interactive login |

---

## Firewall modes

The container's outbound traffic is filtered by iptables. Mode is set by
`FIREWALL_MODE` and applied at container start by `init-firewall.sh`.

### `web` (default)

Outbound TCP **80/443** to **any** public address, plus DNS and ICMP.
Blocks everything else: SSH out, custom ports, all UDP except DNS, and all
RFC1918 ranges (so the container can't reach your home LAN, your Mac on its
LAN IP, or `host.docker.internal`).

This is the right mode for normal interactive dev — Claude can research the
web, fetch packages, use ngrok, etc., but can't open arbitrary outbound
sockets or scan your network.

### `strict`

Outbound 80/443 only to a small allowlist (Anthropic, npm, GitHub, PyPI,
Ubuntu mirrors). Suitable for unattended agents or hostile-code review.
The allowlist is in `init-firewall.sh` → `ALLOWED_DOMAINS`.

### `off`

No firewall, full network. Use when convenience > isolation.

### Switching modes

**At startup**, via env or `.env`:

```bash
FIREWALL_MODE=strict make up
```

**Live** (no restart, useful mid-session):

```bash
make firewall-strict
make firewall-web
make firewall-off
```

---

## Exposing a dev server (ngrok)

Inbound from your Mac to the container is **not** published by default — to
validate something Claude built, use ngrok.

### One-time setup

1. Get an authtoken at https://dashboard.ngrok.com/get-started/your-authtoken
2. Create `.env` next to `docker-compose.yml`:
   ```
   NGROK_AUTHTOKEN=2abc...your-token
   ```
3. `make up` (or `make down && make up` if it was already running) to pick up the env var.

### Usage

```bash
# Pane 1 (in tmux): start your dev server
cd ~/Projects/myapp && npm run dev

# Pane 2 (in tmux) — or another terminal on the host:
make tunnel PORT=3000
```

ngrok prints a public `https://xxxx.ngrok-free.app` URL. Open it in any
browser. Tunnel survives until you `Ctrl-c`.

### Auth on the public URL

For sensitive previews:

```bash
docker exec -it claude-box ngrok http 3000 --basic-auth user:pass
```

> ⚠️ Note: in `strict` firewall mode, ngrok will fail to connect because its
> edge servers aren't in the allowlist. Use `web` (default) or `off` for
> ngrok.

---

## What's persisted, what isn't

| Path inside container | Storage | Persists across rebuild? |
|---|---|---|
| `~/Projects/...` | Bind to host `~/Projects` | Yes (lives on host) |
| `~/.claude/` (writable) | Named volume `claude-config` | Yes |
| `~/.local/` (pipx, uv installs) | Named volume `claude-home` | Yes |
| `/host/.claude/` (read-only) | Bind to host `~/.claude` | Reflects host live |
| `~/.gitconfig` | Bind to host (read-only) | Reflects host live |
| Shell history, tmux state | Container filesystem | Lost on rebuild |
| Installed apt packages added at runtime | Container filesystem | Lost on rebuild |

To wipe everything (creds, sessions, pipx installs):

```bash
make down
docker volume rm claude-box_claude-config claude-box_claude-home
```

To back up Claude state:

```bash
docker run --rm \
  -v claude-box_claude-config:/data \
  -v "$PWD":/backup \
  ubuntu tar czf /backup/claude-config-backup.tgz -C /data .
```

---

## Troubleshooting

### "groupadd: GID '1000' already exists" during build

Already fixed in the Dockerfile (Ubuntu 24.04 ships with a default `ubuntu`
user at UID 1000; we delete it before creating `dev`). If you see this, you
have an old Dockerfile — pull the latest and `make rebuild`.

### Container won't start after host reboot

Check Docker Desktop is running and set to start at login (Settings →
General). Then:

```bash
make status   # is the container Up?
make up       # if not, start it
make logs     # check for errors
```

### `claude` says "not authenticated"

The named volume holding your creds got wiped, or you're on a fresh build.
Run `make login` again.

### Memory from host isn't showing up in the container

Two things have to be true:
1. `CLAUDE_BOX_SHARE_HOST=1` (default).
2. You're working in a path that exists on the **host** at the same
   absolute path (e.g., `$HOME/Projects/foo`). Memory keys are derived
   from the absolute cwd, so paths must match.

The compose file mounts your `~/Projects` at the same absolute path as on
the host (`${HOME}/Projects:${HOME}/Projects`) for exactly this reason. If
you `cd` somewhere outside that mount, host memories won't be reachable.

### Outbound HTTPS works but a specific domain fails

You're probably in `strict` mode and the domain isn't in the allowlist. Either:
- `make firewall-web` for the session, or
- Add the domain to `ALLOWED_DOMAINS` in `init-firewall.sh` and rebuild.

### Build is slow / pulls every time

`make build` (without `--no-cache`) reuses layers. Only `make rebuild` does
`--no-cache`. Use `make build && make up` for incremental changes.

### Container can't reach my local backend on the Mac

Expected — the firewall blocks RFC1918, which includes `host.docker.internal`.
To poke a hole for a specific host port, see the comment in `init-firewall.sh`
about `HOST_BACKEND_PORTS` (you'll need to add a small ACCEPT rule before
`block_private_ranges`).

### Disk usage growing

```bash
docker system df              # see what's using space
docker builder prune          # clean build cache
docker image prune            # remove dangling images
```

---

## File layout

```
claude-box/
├── Dockerfile               # image definition (arm64, Ubuntu 24.04)
├── docker-compose.yml       # service config, mounts, env vars
├── Makefile                 # convenience targets
├── entrypoint.sh            # runs at container start (firewall, host-claude wiring)
├── init-firewall.sh         # iptables/ipset rules per mode
├── setup-host-claude.sh     # symlinks host ~/.claude artifacts into container
└── README.md                # this file
```
