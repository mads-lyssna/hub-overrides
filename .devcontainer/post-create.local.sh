#!/bin/bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"
NIX_PROFILE="/nix/var/nix/profiles/devcontainer"
NIX_BIN="$NIX_PROFILE/bin/nix"

owner="$(id -u):$(id -g)"
sudo chown "$owner" /nix
# Credentials and session history are host-mounted; only adjust container-owned roots.
sudo chown "$owner" "$HOME/.pi" "$HOME/.pi/agent"

exec 9>/nix/.lyssna-personal-setup.lock
flock 9

if [[ ! -x "$NIX_BIN" ]]; then
  echo "→ Installing Nix into persistent /nix volume"
  curl --proto '=https' --tlsv1.2 -sSf -L https://nixos.org/nix/install \
    | sh -s -- --no-daemon --yes --no-channel-add --no-modify-profile

  installed_nix="$(readlink -f "$HOME/.nix-profile/bin/nix")"
  mkdir -p "$(dirname "$NIX_PROFILE")"
  ln -sfn "${installed_nix%/bin/nix}" "$NIX_PROFILE"
fi

export NIX_REMOTE=local
export PATH="$HOME/.nix-profile/bin:$NIX_PROFILE/bin:$PATH"

if ! "$NIX_BIN" store ping --store local >/dev/null 2>&1; then
  echo "ERROR: local Nix store is unavailable" >&2
  exit 1
fi

sudo rm -rf /homeless-shelter

echo "→ Activating home-manager configuration for lyssna"
out=$("$NIX_BIN" build --no-link --print-out-paths "$DOTFILES#homeConfigurations.lyssna.activationPackage")
HOME_MANAGER_BACKUP_EXT=hm-bak "$out/activate"

flock -u 9

git config --file "$HOME/.gitconfig" gc.auto 0
git config --file "$HOME/.gitconfig" maintenance.auto false
