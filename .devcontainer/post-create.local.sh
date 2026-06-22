#!/bin/bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"

# Named volumes mount as root:root; these must be writable before the
# home-manager activation below writes Pi config and installs global CLIs.
sudo chown vscode:vscode "$HOME/.local/share/pnpm"
sudo chown -R vscode:vscode "$HOME/.pi"

if ! command -v nix >/dev/null 2>&1; then
  echo "→ Installing Nix into persistent /nix volume"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install linux --init none --no-confirm
fi

if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  # shellcheck disable=SC1091
  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
export NIX_REMOTE="${NIX_REMOTE:-daemon}"

if ! command -v nix >/dev/null 2>&1; then
  echo "ERROR: nix is still unavailable after install/source" >&2
  exit 1
fi

sudo rm -rf /homeless-shelter

sudo mkdir -p /etc/nix
sudo touch /etc/nix/nix.conf
if ! grep -Eq '^trusted-users = .*\b'"$(whoami)"'\b' /etc/nix/nix.conf; then
  echo "trusted-users = root $(whoami)" | sudo tee -a /etc/nix/nix.conf >/dev/null
fi

if ! getent group nixbld >/dev/null 2>&1; then
  sudo groupadd --gid 30000 nixbld
fi

for i in $(seq 1 32); do
  if ! getent passwd "nixbld${i}" >/dev/null 2>&1; then
    sudo useradd \
      --uid "$((30000 + i))" \
      --gid 30000 \
      --groups nixbld \
      --home-dir /var/empty \
      --shell /sbin/nologin \
      --comment "Nix build user ${i}" \
      "nixbld${i}"
  fi
done

sudo sed -i '/^build-users-group =/d' /etc/nix/nix.conf
printf 'build-users-group = nixbld\n' | sudo tee -a /etc/nix/nix.conf >/dev/null

if ! nix --extra-experimental-features nix-command store ping --store daemon >/dev/null 2>&1; then
  echo "→ Starting nix-daemon"
  sudo mkdir -p /nix/var/nix/daemon-socket
  sudo rm -f /nix/var/nix/daemon-socket/socket
  : >/tmp/nix-daemon.log
  sudo -n nohup /nix/var/nix/profiles/default/bin/nix-daemon --daemon >>/tmp/nix-daemon.log 2>&1 &

  for _ in $(seq 1 100); do
    if nix --extra-experimental-features nix-command store ping --store daemon >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

if ! nix --extra-experimental-features nix-command store ping --store daemon >/dev/null 2>&1; then
  echo "ERROR: nix-daemon did not become ready" >&2
  cat /tmp/nix-daemon.log >&2 || true
  exit 1
fi

echo "→ Activating home-manager configuration for vscode"
out=$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths "$DOTFILES#homeConfigurations.vscode.activationPackage")
HOME_MANAGER_BACKUP_EXT=hm-bak "$out/activate"

if [[ -f /tmp/host-pi-auth.json ]]; then
  mkdir -p "$HOME/.pi/agent"
  cp /tmp/host-pi-auth.json "$HOME/.pi/agent/auth.json"
  chmod 600 "$HOME/.pi/agent/auth.json"
fi

# Auto-gc/maintenance inside the container runs `git worktree prune` against the
# shared repo, deleting sibling worktrees whose host paths aren't mounted here.
git config --file "$HOME/.gitconfig" gc.auto 0
git config --file "$HOME/.gitconfig" maintenance.auto false
