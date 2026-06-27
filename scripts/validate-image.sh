#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <image.qcow2> <ssh-port> <password>" >&2
  exit 2
fi

IMAGE=$(realpath "$1")
SSH_PORT=$2
VM_PASSWORD=$3
WORK_DIR=$(mktemp -d)
HOME_DISK="$WORK_DIR/home.qcow2"
QEMU_LOG="$WORK_DIR/qemu.log"
QEMU_PID=

cleanup_vm() {
  if [[ -n "${QEMU_PID:-}" ]]; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
    QEMU_PID=
  fi
}

cleanup() {
  cleanup_vm
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

qemu-img check "$IMAGE"
qemu-img create -f qcow2 "$HOME_DISK" 1G

ACCEL=tcg
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  ACCEL=kvm
fi

boot_and_run() {
  local command=$1
  : > "$QEMU_LOG"

  qemu-system-x86_64 \
    -accel "$ACCEL" \
    -m 512 \
    -smp 1 \
    -drive "file=$IMAGE,if=virtio,format=qcow2,readonly=on,snapshot=on" \
    -drive "file=$HOME_DISK,if=virtio,format=qcow2" \
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" \
    -device virtio-net-pci,netdev=net0 \
    -display none \
    -serial none \
    -monitor none \
    -no-reboot \
    >"$QEMU_LOG" 2>&1 &
  QEMU_PID=$!

  for attempt in $(seq 1 90); do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      echo "QEMU exited before SSH became ready:" >&2
      cat "$QEMU_LOG" >&2
      return 1
    fi

    if sshpass -p "$VM_PASSWORD" ssh \
      -p "$SSH_PORT" \
      -o ConnectTimeout=3 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      user@127.0.0.1 "$command"
    then
      cleanup_vm
      return 0
    fi
    sleep 4
  done

  echo "Timed out waiting for Sheller SSH:" >&2
  cat "$QEMU_LOG" >&2
  return 1
}

boot_and_run \
  'test "$(id -un)" = user && mountpoint -q /home/user && echo persistent > /home/user/.sheller-validation && sync'
boot_and_run \
  'mountpoint -q /home/user && test "$(cat /home/user/.sheller-validation)" = persistent'

echo "SSH login and persistent-home reboot validation passed."
