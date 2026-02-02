#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Adapted from Anthropic's claude-code devcontainer init-firewall.sh
# Extended with additional domains for Python/ML/Modal workflows

echo "=== CCW Firewall Init ==="

# 1. Preserve Docker DNS rules
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127.0.0.11" || true)

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Restore Docker DNS
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# 3. Allow DNS, SSH, and localhost before restrictions
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# 4. Create ipset for allowed domains
ipset create allowed-domains hash:net

# 5. Fetch and add GitHub IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        ipset add allowed-domains "$cidr" 2>/dev/null || true
    fi
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q 2>/dev/null || echo "$gh_ranges" | jq -r '(.web + .api + .git)[]')

# 6. Resolve and add allowed domains
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com" \
    "statsig.anthropic.com" \
    "sentry.io" \
    "statsig.com" \
    "pypi.org" \
    "files.pythonhosted.org" \
    "api.openai.com" \
    "huggingface.co" \
    "cdn-lfs.huggingface.co" \
    "modal.com" \
    "api.modal.com" \
    ; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" 2>/dev/null | awk '$4 == "A" {print $5}')
    if [ -n "$ips" ]; then
        while read -r ip; do
            if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                ipset add allowed-domains "$ip" 2>/dev/null || true
            fi
        done < <(echo "$ips")
    else
        echo "WARNING: Could not resolve $domain (non-fatal)"
    fi
done

# 7. Allow host network (for sibling containers: Postgres, Qdrant, etc.)
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -n "$HOST_IP" ]; then
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    echo "Host network: $HOST_NETWORK"
    iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

# Also allow Docker bridge networks (172.16.0.0/12)
iptables -A INPUT -s 172.16.0.0/12 -j ACCEPT
iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT

# 8. Set default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow outbound to whitelisted IPs
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Reject everything else with immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "=== Firewall configured ==="

# Verify
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "WARNING: Firewall may not be working (reached example.com)"
else
    echo "OK: example.com blocked as expected"
fi

if curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "OK: GitHub API reachable"
else
    echo "WARNING: GitHub API unreachable"
fi
