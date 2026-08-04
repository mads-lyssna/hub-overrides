#!/bin/bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"
NIX_PROFILE="/nix/var/nix/profiles/devcontainer"
NIX_BIN="$NIX_PROFILE/bin/nix"

owner="$(id -u):$(id -g)"
sudo chown "$owner" /nix "$HOME/.local/share/pnpm" "$HOME/.config/linear"
sudo chown -R "$owner" "$HOME/.pi"

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
export PATH="$HOME/.nix-profile/bin:$NIX_PROFILE/bin:$HOME/.local/share/pnpm:$PATH"

if ! "$NIX_BIN" store ping --store local >/dev/null 2>&1; then
  echo "ERROR: local Nix store is unavailable" >&2
  exit 1
fi

sudo rm -rf /homeless-shelter

echo "→ Activating home-manager configuration for lyssna"
out=$("$NIX_BIN" build --no-link --print-out-paths "$DOTFILES#homeConfigurations.lyssna.activationPackage")
HOME_MANAGER_BACKUP_EXT=hm-bak "$out/activate"

flock -u 9

if [[ -f /tmp/host-pi-auth.json ]]; then
  mkdir -p "$HOME/.pi/agent"
  cp /tmp/host-pi-auth.json "$HOME/.pi/agent/auth.json"
  chmod 600 "$HOME/.pi/agent/auth.json"
fi

if [[ -f /tmp/host-pipkin-auth.json ]]; then
  mkdir -p "$HOME/.pi/agent/pipkin"
  cp /tmp/host-pipkin-auth.json "$HOME/.pi/agent/pipkin/auth.json"
  chmod 600 "$HOME/.pi/agent/pipkin/auth.json"
fi

git config --file "$HOME/.gitconfig" gc.auto 0
git config --file "$HOME/.gitconfig" maintenance.auto false
