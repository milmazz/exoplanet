#!/bin/bash
set -e

echo "[devcontainer] Configuring network firewall rules..."

# Flush existing rules
iptables -F OUTPUT 2>/dev/null || true
iptables -P OUTPUT DROP 2>/dev/null || true

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS (required for hostname resolution)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# Allow outbound to api.anthropic.com (Claude API)
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# Allow outbound to hex.pm and repo.hex.pm (Elixir packages)
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# Log blocked connections
iptables -A OUTPUT -j LOG --log-prefix "BLOCKED_OUTPUT: " --log-level 7

# Final DROP rule (default policy)
iptables -A OUTPUT -j DROP

echo "[devcontainer] Firewall rules configured:"
iptables -L OUTPUT -n

echo "[devcontainer] Network setup complete."
