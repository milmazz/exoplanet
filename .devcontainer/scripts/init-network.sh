#!/bin/bash
set -e

echo "[devcontainer] Configuring network firewall rules..."

# ---------------------------------------------------------------------------
# Allowed domains (HTTPS outbound only)
#
#   Claude Code:
#     - api.anthropic.com        Claude API
#     - statsig.anthropic.com    Feature flags / monitoring
#     - sentry.io                Error reporting
#     - claude.ai                Authentication
#
#   Elixir packages:
#     - hex.pm                   Package index
#     - repo.hex.pm              Package tarballs
# ---------------------------------------------------------------------------
ALLOWED_DOMAINS=(
  api.anthropic.com
  statsig.anthropic.com
  sentry.io
  claude.ai
  hex.pm
  repo.hex.pm
)

# ---------------------------------------------------------------------------
# Resolve every domain to its current IP addresses and build an ipset
# ---------------------------------------------------------------------------
IPSET_NAME="allowed_https"

ipset create "$IPSET_NAME" hash:ip -exist

for domain in "${ALLOWED_DOMAINS[@]}"; do
  ips=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
  if [ -z "$ips" ]; then
    echo "[devcontainer]  WARNING: could not resolve $domain — skipping"
    continue
  fi
  for ip in $ips; do
    ipset add "$IPSET_NAME" "$ip" -exist
    echo "[devcontainer]  $domain -> $ip"
  done
done

# ---------------------------------------------------------------------------
# iptables rules
# ---------------------------------------------------------------------------

# Flush existing OUTPUT rules
iptables -F OUTPUT 2>/dev/null || true

# Default policy: drop everything not explicitly allowed
iptables -P OUTPUT DROP 2>/dev/null || true

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS (UDP + TCP for large responses)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow HTTPS only to resolved IPs in the ipset
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set "$IPSET_NAME" dst -j ACCEPT

# Log blocked connections (LOG target may be unavailable in Docker Desktop VMs)
iptables -A OUTPUT -j LOG --log-prefix "BLOCKED_OUTPUT: " --log-level 7 || true

# Final explicit DROP
iptables -A OUTPUT -j DROP

echo "[devcontainer] Firewall rules configured:"
iptables -L OUTPUT -n
echo ""
echo "[devcontainer] Allowed IPs ($IPSET_NAME):"
ipset list "$IPSET_NAME"

# ---------------------------------------------------------------------------
# Verify: allowed domains must be reachable, everything else must be blocked
# ---------------------------------------------------------------------------
echo ""
echo "[devcontainer] Verifying firewall rules..."

VERIFY_FAILED=0

for domain in "${ALLOWED_DOMAINS[@]}"; do
  if curl -sf --max-time 5 -o /dev/null "https://$domain" 2>/dev/null; then
    echo "[devcontainer]  PASS: $domain is reachable"
  else
    echo "[devcontainer]  WARN: $domain did not return HTTP 200 (may be expected depending on endpoint)"
  fi
done

# Verify that a non-allowlisted domain is blocked
BLOCKED_DOMAIN="www.example.com"
if curl -sf --max-time 5 -o /dev/null "https://$BLOCKED_DOMAIN" 2>/dev/null; then
  echo "[devcontainer]  FAIL: $BLOCKED_DOMAIN should be blocked but is reachable"
  VERIFY_FAILED=1
else
  echo "[devcontainer]  PASS: $BLOCKED_DOMAIN is blocked"
fi

if [ "$VERIFY_FAILED" -eq 1 ]; then
  echo "[devcontainer] ERROR: Firewall verification failed — outbound traffic is not properly restricted"
  exit 1
fi

echo "[devcontainer] Network setup complete."
