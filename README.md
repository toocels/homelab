# homelab

Docker Compose stacks for my homelab. One directory per service, each with its own `docker-compose.yml` (and `.env` where it needs secrets). Managed with [Dockge](https://github.com/louislam/dockge).

## Services

| Service | Purpose | Internal port(s) | Access |
|---|---|---|---|
| nginx | Reverse proxy + TLS termination, single ingress point | 80, 443 | Bound directly to host `0.0.0.0:80/443` |
| dockge | Stack management UI | 5001 | via nginx → `dockge.*` |
| beszel / beszel-agent | Server + container monitoring | 8090 (hub) | hub via nginx → `beszel.*`; agent on `homelab` |
| jellyfin | Media server | 8096/tcp, 8920/tcp, 7359/udp | via nginx → `jellyfin.*` |
| navidrome / rewind | Music server + web player | 4533, 4000 | via nginx → `navidrome.*`, `rewind.*` |
| nextcloud / db | File sync & storage | 80 (nextcloud); db is internal-only | via nginx → `nextcloud.*` |
| pihole | Network-wide DNS + ad-blocking | 53/tcp+udp (DNS), 80 (webui) | DNS bound directly to host `0.0.0.0:53`; webui via nginx → `pihole.*` |
| vaultwarden | Password manager (Bitwarden-compatible) | 80 | via nginx → `vaultwarden.*` |
| tailscale | VPN mesh access into the homelab | – | `network_mode: host`, not proxied (not HTTP) |
| minecraft | Minecraft server | 25565/tcp | Bound directly to host `0.0.0.0:25565`, not proxied (not HTTP) |

## Patterns

- **One stack per directory.** Each service gets its own folder, its own `docker-compose.yml`, and its own `.env` if it needs secrets. `.env` is gitignored everywhere — only `${VAR}` references are committed, never values.
- **Single shared network.** Every container joins the external `homelab` bridge network, created by the `network/` stack (bring that one up first on a fresh box). Every other stack references it as `external: true`. Containers reach each other by container name.
- **HTTP(S) services never publish a host port.** nginx is the only ingress — it terminates TLS and reverse-proxies to the container by name over `homelab`. Each service's compose file keeps its host port mapping present but commented out, e.g.:
  ```yaml
  # ports:
  #   - "127.0.0.1:8096:8096"
  ```
  so it can be uncommented for quick local debugging without having to look up the port again.
- **Non-HTTP or network-level services bind directly to the host** instead of going through nginx, since a reverse proxy can't do anything useful for them:
  - `pihole` — DNS (53/tcp+udp) needs to be reachable directly by every device on the LAN.
  - `tailscale` — needs `network_mode: host` + `/dev/net/tun` to run its own VPN interface.
  - `minecraft` — the Minecraft protocol isn't HTTP, so it binds host port 25565 directly instead of going through nginx.
- **TLS**: Let's Encrypt wildcard cert for `toocels.duckdns.org` (+ `toocelsts.duckdns.org`), issued via DNS-01 (`nginx/renew-certs.sh`), which works without exposing anything to the internet. Renewal runs on a monthly systemd timer (`renew-certs.timer`, `Persistent=true` so a missed run — laptop off, etc. — catches up on next boot). This is the one piece of the stack that runs on the host instead of in a container.
- **Data/state directories are bind-mounted locally** next to each compose file (e.g. `./vaultwarden_data`) and gitignored. Only compose files and non-secret static config (nginx conf, html) are tracked in git.
