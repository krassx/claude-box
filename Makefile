.PHONY: build up down shell tmux logs rebuild login status

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
