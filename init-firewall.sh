#!/usr/bin/env bash
# Configures the container's egress firewall.
#
#   FIREWALL_MODE=web     (default) Outbound 80/443 to anywhere, plus DNS.
#                                   Blocks all other ports, all UDP (except
#                                   DNS), and all RFC1918 destinations.
#                                   Suitable for interactive dev / research.
#   FIREWALL_MODE=strict            Outbound 80/443 only to a small allowlist
#                                   of domains (Anthropic, npm, GitHub, etc.).
#                                   Suitable for unattended agents / hostile
#                                   code review.
#   FIREWALL_MODE=off               No firewall. Everything allowed.
#
# Adapted from anthropics/claude-code/.devcontainer/init-firewall.sh.

set -euo pipefail
IFS=$'\n\t'

MODE="${FIREWALL_MODE:-web}"

ALLOWED_DOMAINS=(
  api.anthropic.com
  statsig.anthropic.com
  console.anthropic.com
  registry.npmjs.org
  registry.yarnpkg.com
  github.com
  api.github.com
  codeload.github.com
  objects.githubusercontent.com
  raw.githubusercontent.com
  ghcr.io
  pypi.org
  files.pythonhosted.org
  deb.nodesource.com
  archive.ubuntu.com
  security.ubuntu.com
  ports.ubuntu.com
  deb.debian.org
)

# RFC1918 + link-local + CGNAT — block egress to these in web/strict modes
# so a compromised container can't reach your home LAN or scan internal
# Docker networks. Loopback (127/8) is allowed via the lo rule.
PRIVATE_RANGES=(
  10.0.0.0/8
  172.16.0.0/12
  192.168.0.0/16
  169.254.0.0/16
  100.64.0.0/10
)

if ! command -v iptables >/dev/null 2>&1; then
  echo "[firewall] iptables not available; skipping."
  exit 0
fi
if ! sudo -n iptables -L >/dev/null 2>&1; then
  echo "[firewall] no NET_ADMIN; skipping."
  exit 0
fi

reset_chains() {
  sudo iptables -F
  sudo iptables -X
  sudo iptables -P INPUT   ACCEPT
  sudo iptables -P FORWARD DROP
  sudo iptables -P OUTPUT  ACCEPT  # default; tightened below per mode
  sudo ipset destroy allowed-domains 2>/dev/null || true
}

base_rules() {
  # Loopback + return traffic
  sudo iptables -A INPUT  -i lo -j ACCEPT
  sudo iptables -A OUTPUT -o lo -j ACCEPT
  sudo iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  # DNS (always needed)
  sudo iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
  sudo iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
}

block_private_ranges() {
  for cidr in "${PRIVATE_RANGES[@]}"; do
    sudo iptables -A OUTPUT -d "$cidr" -j REJECT --reject-with icmp-net-unreachable
  done
}

case "$MODE" in
  off)
    echo "[firewall] mode=off — flushing all rules, allowing everything."
    reset_chains
    sudo iptables -P OUTPUT ACCEPT
    exit 0
    ;;

  web)
    echo "[firewall] mode=web — open 80/443 to anywhere, block other ports + RFC1918."
    reset_chains
    sudo iptables -P OUTPUT DROP
    base_rules
    block_private_ranges
    # Allow outbound web + ICMP (ping/traceroute) to public addresses.
    # UDP/443 covers QUIC / HTTP/3; private ranges still blocked by the
    # earlier REJECT rules regardless of protocol.
    sudo iptables -A OUTPUT -p tcp --dport 80  -j ACCEPT
    sudo iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
    sudo iptables -A OUTPUT -p udp --dport 443 -j ACCEPT
    sudo iptables -A OUTPUT -p icmp -j ACCEPT
    ;;

  strict)
    echo "[firewall] mode=strict — allowlist only."
    reset_chains
    sudo iptables -P OUTPUT DROP
    base_rules
    block_private_ranges
    sudo ipset create allowed-domains hash:ip family inet hashsize 1024 maxelem 65536
    for domain in "${ALLOWED_DOMAINS[@]}"; do
      ips=$(getent ahostsv4 "$domain" | awk '{print $1}' | sort -u || true)
      if [[ -z "$ips" ]]; then
        echo "  ! could not resolve $domain"
        continue
      fi
      while IFS= read -r ip; do
        [[ -n "$ip" ]] && sudo ipset add allowed-domains "$ip" -exist
      done <<< "$ips"
      echo "  + $domain"
    done
    sudo iptables -A OUTPUT -m set --match-set allowed-domains dst -p tcp --dport 443 -j ACCEPT
    sudo iptables -A OUTPUT -m set --match-set allowed-domains dst -p tcp --dport 80  -j ACCEPT
    ;;

  *)
    echo "[firewall] unknown FIREWALL_MODE=$MODE (expected: web|strict|off)" >&2
    exit 1
    ;;
esac

echo "[firewall] ready (mode=$MODE)."
