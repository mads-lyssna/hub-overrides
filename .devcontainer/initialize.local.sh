#!/bin/bash
set -euo pipefail

service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$service_dir/.." && pwd)"
# initialize.sh regenerates .env before this hook runs.
printf '\nHOST_WORKTREE_PATH=%s\n' "$repo_root" >>"$service_dir/.env"
mkdir -p "$HOME/.pi/agent/sessions"

docker volume inspect pi-agent >/dev/null 2>&1 || docker volume create pi-agent >/dev/null
docker volume inspect nix >/dev/null 2>&1 || docker volume create nix >/dev/null
docker volume inspect mise-data >/dev/null 2>&1 || docker volume create mise-data >/dev/null

data_volume="lyssna-keyring-data"
runtime_volume="lyssna-keyring-runtime"
container_name="lyssna-keyring"
image_name="lyssna-keyring:local"

for volume in "$data_volume" "$runtime_volume"; do
  docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create "$volume" >/dev/null
done

container_label() {
  docker container inspect --format '{{ index .Config.Labels "com.lyssna.keyring" }}' "$container_name" 2>/dev/null || true
}

if ! docker container inspect "$container_name" >/dev/null 2>&1; then
  if ! docker image inspect "$image_name" >/dev/null 2>&1; then
    docker build --tag "$image_name" --file - "$service_dir" <<'DOCKERFILE'
FROM debian:bookworm-slim

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --yes \
    bash \
    coreutils \
    dbus-bin \
    dbus-daemon \
    gnome-keyring \
    passwd \
    util-linux \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --gid 1000 lyssna \
  && useradd --uid 1000 --gid 1000 --create-home lyssna

ENV HOME=/var/lib/lyssna-keyring \
    XDG_RUNTIME_DIR=/run/user/1000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

COPY keyring.local.sh /usr/local/bin/lyssna-keyring
RUN chmod 755 /usr/local/bin/lyssna-keyring

ENTRYPOINT ["/usr/local/bin/lyssna-keyring"]
DOCKERFILE
  fi

  # Concurrent initialize runs can race here; the winner creates the one global daemon.
  docker run --detach --name "$container_name" --restart unless-stopped \
    --label com.lyssna.keyring=true \
    --volume "$data_volume:/var/lib/lyssna-keyring" \
    --volume "$runtime_volume:/run/user/1000" \
    "$image_name" >/dev/null 2>&1 || true
fi

if [[ "$(container_label)" != "true" ]]; then
  echo "ERROR: Docker container $container_name already exists but is not the Lyssna keyring service." >&2
  exit 1
fi

if [[ "$(docker container inspect --format '{{ .State.Running }}' "$container_name")" != "true" ]]; then
  docker start "$container_name" >/dev/null 2>&1 || true
fi

for _ in {1..20}; do
  if docker exec --user 1000:1000 "$container_name" \
    dbus-send --session --type=method_call --dest=org.freedesktop.DBus / \
    org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

echo "ERROR: Lyssna keyring service did not become ready; inspect $container_name." >&2
exit 1
