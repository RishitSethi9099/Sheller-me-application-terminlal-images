#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <ubuntu|kali> <image.qcow2> <password>" >&2
  exit 2
fi

OS_KEY=$1
IMAGE=$2
VM_PASSWORD=$3
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ASSET_DIR="$ROOT_DIR/assets"

if [[ "$OS_KEY" != ubuntu && "$OS_KEY" != kali ]]; then
  echo "Unsupported OS key: $OS_KEY" >&2
  exit 2
fi

export LIBGUESTFS_BACKEND=direct

args=(
  -a "$IMAGE"
  --no-network
  --mkdir /etc/ssh/sshd_config.d
  --mkdir /usr/local/sbin
  --copy-in "$ASSET_DIR/00-sheller-sshd.conf:/etc/ssh/sshd_config.d"
  --copy-in "$ASSET_DIR/sheller-home-setup:/usr/local/sbin"
  --copy-in "$ASSET_DIR/sheller-home.service:/etc/systemd/system"
  --run-command "command -v sshd >/dev/null"
  --run-command "command -v sudo >/dev/null"
  --run-command "command -v mkfs.ext4 >/dev/null"
  --run-command "id -u user >/dev/null 2>&1 || useradd -m -s /bin/bash user"
  --password "user:password:$VM_PASSWORD"
  --run-command "usermod -aG sudo user"
  --run-command "printf '%s\n' 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-sheller-user"
  --run-command "chmod 0440 /etc/sudoers.d/90-sheller-user"
  --run-command "chmod 0755 /usr/local/sbin/sheller-home-setup"
  --run-command "sshd -T | grep -qx 'passwordauthentication yes'"
  --run-command "systemctl enable ssh.service"
  --run-command "systemctl enable sheller-home.service"
  --run-command "passwd -l root || true"
  --run-command "rm -f /etc/ssh/ssh_host_*"
  --run-command "truncate -s 0 /etc/machine-id || true"
  --run-command "rm -rf /var/lib/cloud/instances/* /var/lib/cloud/instance 2>/dev/null || true"
  --run-command "apt-get clean"
  --run-command "rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"
)

if [[ "$OS_KEY" == ubuntu ]]; then
  virt-customize "${args[@]}" \
    --mkdir /etc/netplan \
    --copy-in "$ASSET_DIR/01-sheller.yaml:/etc/netplan" \
    --run-command "chmod 0600 /etc/netplan/01-sheller.yaml" \
    --run-command "touch /etc/cloud/cloud-init.disabled"
else
  virt-customize "${args[@]}"
fi

qemu-img check "$IMAGE"
