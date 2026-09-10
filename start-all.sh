#!/bin/bash
set -e

SERVICES=(jellyfin navidrome nextcloud nginx pihole portainer tailscale vaultwarden)
for s in "${SERVICES[@]}"; do
  docker compose -f "./$s/docker-compose.yml" up -d
done
