.PHONY: build up down shell tmux logs rebuild login status \
        firewall-web firewall-strict firewall-off tunnel \
        sync-settings du prune-cache prune-history

build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

rebuild:
	docker compose build --no-cache && docker compose up -d

shell:
	docker exec -it claude-box bash

tmux:
	docker exec -it claude-box tmux new-session -A -s main

login:
	docker exec -it claude-box claude

logs:
	docker compose logs -f

status:
	docker ps --filter name=claude-box --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Re-apply firewall in a different mode without rebuilding.
firewall-web:
	docker exec -e FIREWALL_MODE=web    claude-box sudo -E /usr/local/bin/init-firewall.sh

firewall-strict:
	docker exec -e FIREWALL_MODE=strict claude-box sudo -E /usr/local/bin/init-firewall.sh

firewall-off:
	docker exec -e FIREWALL_MODE=off    claude-box sudo -E /usr/local/bin/init-firewall.sh

# Expose an in-container port via ngrok. Requires NGROK_AUTHTOKEN in env.
# Usage: make tunnel PORT=3000
tunnel:
	@test -n "$(PORT)" || (echo "usage: make tunnel PORT=3000" && exit 1)
	docker exec -it claude-box ngrok http $(PORT)

# Re-seed ~/.claude/settings.json from host. Preserves auth, sessions,
# todos, and other state in the named volume.
sync-settings:
	docker exec claude-box rm -f /home/dev/.claude/settings.json
	docker restart claude-box
	@echo "settings.json re-seeded from host."

# Show what's using disk inside the named volumes.
du:
	@echo "== Volume totals =="
	@docker exec claude-box du -sh /home/dev/.claude /home/dev/.local 2>/dev/null
	@echo
	@echo "== ~/.claude breakdown (top 15) =="
	@docker exec claude-box bash -c 'du -sh /home/dev/.claude/* 2>/dev/null | sort -hr | head -15'

# Clear ephemeral cache directories. Safe — Claude regenerates as needed.
# Does NOT touch projects/ (conversation history), sessions/, settings.json,
# credentials, skills, plugins.
prune-cache:
	@docker exec claude-box bash -c '\
		for d in paste-cache telemetry debug file-history shell-snapshots; do \
			[ -d "/home/dev/.claude/$$d" ] && rm -rf /home/dev/.claude/$$d/* 2>/dev/null; \
		done; true'
	@echo "cleared paste-cache, telemetry, debug, file-history, shell-snapshots."

# Delete conversation transcript files older than DAYS. Destructive.
# Usage: make prune-history DAYS=30
prune-history:
	@test -n "$(DAYS)" || (echo "usage: make prune-history DAYS=30" && exit 1)
	@docker exec claude-box bash -c '\
		count=$$(find /home/dev/.claude/projects -type f -name "*.jsonl" -mtime +$(DAYS) 2>/dev/null | wc -l); \
		find /home/dev/.claude/projects -type f -name "*.jsonl" -mtime +$(DAYS) -delete 2>/dev/null; \
		echo "deleted $$count session transcript(s) older than $(DAYS) days"'
