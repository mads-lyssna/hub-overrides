#!/bin/bash
set -euo pipefail

docker volume inspect pi-agent >/dev/null 2>&1 || docker volume create pi-agent >/dev/null
docker volume inspect nix >/dev/null 2>&1 || docker volume create nix >/dev/null
docker volume inspect pnpm-global >/dev/null 2>&1 || docker volume create pnpm-global >/dev/null
