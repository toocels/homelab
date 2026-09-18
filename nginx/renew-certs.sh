#!/bin/bash
# Renews the toocels.duckdns.org Let's Encrypt certs (wildcard + apex) via DNS-01
# and deploys them into nginx/certs/ for nginx. Run with sudo.
#
# Usage: sudo ./renew-certs.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
fi

if ! command -v certbot >/dev/null; then
    echo "certbot not found. Install it first (e.g. pacman -S certbot)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/nginx/certs"
ENV_FILE="${SCRIPT_DIR}/.env"
DUCKDNS_SUBDOMAINS=("toocels" "toocelsvpn")   # the "domains=" values duckdns.org/spec.jsp expects
HOOK_DIR="/etc/letsencrypt/duckdns"
TOKEN_FILE="${HOOK_DIR}/token"
AUTH_HOOK="${HOOK_DIR}/auth.sh"
CLEANUP_HOOK="${HOOK_DIR}/cleanup.sh"

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE (need DUCKDNS_TOKEN=...)." >&2; exit 1; }
set -a
source "$ENV_FILE"
set +a
DUCKDNS_TOKEN="${DUCKDNS_TOKEN:-}"
[[ -n "$DUCKDNS_TOKEN" ]] || { echo "DUCKDNS_TOKEN not set in $ENV_FILE." >&2; exit 1; }

mkdir -p "$HOOK_DIR"
chmod 700 "$HOOK_DIR"
printf '%s' "$DUCKDNS_TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

cat > "$AUTH_HOOK" <<EOF
#!/bin/bash
set -e
TOKEN=\$(cat "$TOKEN_FILE")
case "\$CERTBOT_DOMAIN" in
    *.toocelsvpn.duckdns.org|toocelsvpn.duckdns.org) SUB="toocelsvpn" ;;
    *.toocels.duckdns.org|toocels.duckdns.org)     SUB="toocels" ;;
    *) echo "no duckdns subdomain mapped for \$CERTBOT_DOMAIN" >&2; exit 1 ;;
esac
curl -s "https://www.duckdns.org/update?domains=\${SUB}&token=\${TOKEN}&txt=\${CERTBOT_VALIDATION}" >/dev/null
sleep 30
EOF

cat > "$CLEANUP_HOOK" <<EOF
#!/bin/bash
set -e
TOKEN=\$(cat "$TOKEN_FILE")
case "\$CERTBOT_DOMAIN" in
    *.toocelsvpn.duckdns.org|toocelsvpn.duckdns.org) SUB="toocelsvpn" ;;
    *.toocels.duckdns.org|toocels.duckdns.org)     SUB="toocels" ;;
    *) exit 0 ;;
esac
curl -s "https://www.duckdns.org/update?domains=\${SUB}&token=\${TOKEN}&txt=removed&clear=true" >/dev/null
EOF
chmod 700 "$AUTH_HOOK" "$CLEANUP_HOOK"

# Quick sanity check the token actually works before spending an ACME order on it.
for sub in "${DUCKDNS_SUBDOMAINS[@]}"; do
    if ! curl -s "https://www.duckdns.org/update?domains=${sub}&token=${DUCKDNS_TOKEN}&txt=renewcheck&verbose=true" | grep -q OK; then
        echo "DuckDNS rejected that token for '${sub}'." >&2
        exit 1
    fi
done

issue() {
    local cert_name="$1" domain="$2" dest_dir="$3"
    echo "== ${domain} =="
    certbot certonly \
        --manual \
        --preferred-challenges dns \
        --manual-auth-hook "$AUTH_HOOK" \
        --manual-cleanup-hook "$CLEANUP_HOOK" \
        --cert-name "$cert_name" \
        -d "$domain" \
        --key-type ecdsa \
        --agree-tos \
        --non-interactive \
        --force-renewal

    mkdir -p "$dest_dir"
    install -m 644 "/etc/letsencrypt/live/${cert_name}/fullchain.pem" "${dest_dir}/fullchain.pem"
    install -m 644 "/etc/letsencrypt/live/${cert_name}/privkey.pem" "${dest_dir}/privkey.pem"
    chown "$(stat -c '%U:%G' "$CERTS_DIR")" "${dest_dir}/fullchain.pem" "${dest_dir}/privkey.pem"
}

issue "toocels.duckdns.org" "toocels.duckdns.org,*.toocels.duckdns.org,toocelsvpn.duckdns.org,*.toocelsvpn.duckdns.org" "${CERTS_DIR}/toocels.duckdns.org"

shred -u "$TOKEN_FILE" 2>/dev/null || rm -f "$TOKEN_FILE"

echo "Done. Restarting nginx..."
if docker ps --format '{{.Names}}' | grep -qx nginx; then
    docker restart nginx
else
    echo "nginx container not running, skipped restart."
fi

echo
echo "New expiry date:"
openssl x509 -enddate -noout -in "${CERTS_DIR}/toocels.duckdns.org/fullchain.pem"
