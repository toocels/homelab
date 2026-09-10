#!/bin/bash
set -e

SERVICES=(beszel jellyfin navidrome nextcloud nginx pihole portainer tailscale vaultwarden)
for s in "${SERVICES[@]}"; do
  docker compose -f "./$s/docker-compose.yml" pull
done
