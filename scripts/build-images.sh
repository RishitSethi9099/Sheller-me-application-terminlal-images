#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=${WORK_DIR:-"$ROOT_DIR/.image-work"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist"}
VM_PASSWORD=${SHELLER_VM_PASSWORD:-sheller}
UBUNTU_URL=${UBUNTU_IMAGE_URL:-https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img}
KALI_URL=${KALI_IMAGE_URL:-}

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

discover_kali_url() {
  local page="$WORK_DIR/get-kali.html"
  curl -fsSL --output "$page" https://www.kali.org/get-kali/
  grep -Eo \
    'https://kali\.download/cloud-images/kali-[0-9.]+/kali-linux-[0-9.]+-cloud-genericcloud-amd64\.tar\.xz' \
    "$page" | sed -n '1p'
}

verify_upstream_download() {
  local url=$1
  local file=$2
  local sums_url
  local sums_file
  local basename
  local expected
  local actual

  sums_url="$(dirname "$url")/SHA256SUMS"
  sums_file="$WORK_DIR/$(basename "$file").SHA256SUMS"
  basename=$(basename "$url")

  curl --fail --location --retry 5 --retry-all-errors \
    --output "$sums_file" "$sums_url"
  expected=$(awk -v wanted="$basename" '
    {
      file=$2
      sub(/^\*/, "", file)
      if (file == wanted) {
        print $1
        exit
      }
    }
  ' "$sums_file")
  if [[ -z "$expected" ]]; then
    echo "No checksum entry found for $basename in $sums_url" >&2
    exit 1
  fi
  actual=$(sha256sum "$file" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum mismatch for $basename" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
  echo "$basename: upstream checksum verified"
}

download_verified() {
  local url=$1
  local file=$2
  curl --fail --location --retry 5 --retry-all-errors \
    --output "$file" "$url"
  verify_upstream_download "$url" "$file"
}

if [[ -z "$KALI_URL" ]]; then
  KALI_URL=$(discover_kali_url)
fi
if [[ -z "$KALI_URL" ]]; then
  echo "Could not discover Kali's current official QEMU image." >&2
  exit 1
fi

echo "Ubuntu base: $UBUNTU_URL"
echo "Kali base:   $KALI_URL"

rm -f \
  "$OUTPUT_DIR/ubuntu-22.04-minimal.qcow2" \
  "$OUTPUT_DIR/kali-minimal.qcow2" \
  "$OUTPUT_DIR/SHA256SUMS" \
  "$OUTPUT_DIR/sheller-image-urls.env"

download_verified "$UBUNTU_URL" "$WORK_DIR/ubuntu-base.img"
qemu-img convert -p -O qcow2 "$WORK_DIR/ubuntu-base.img" "$WORK_DIR/ubuntu-working.qcow2"
rm -f "$WORK_DIR/ubuntu-base.img"
"$ROOT_DIR/scripts/configure-image.sh" ubuntu "$WORK_DIR/ubuntu-working.qcow2" "$VM_PASSWORD"
qemu-img convert -p -c -O qcow2 "$WORK_DIR/ubuntu-working.qcow2" \
  "$OUTPUT_DIR/ubuntu-22.04-minimal.qcow2"
rm -f "$WORK_DIR/ubuntu-working.qcow2"

download_verified "$KALI_URL" "$WORK_DIR/kali-cloud.tar.xz"
rm -rf "$WORK_DIR/kali-extracted"
mkdir -p "$WORK_DIR/kali-extracted"
tar -xJf "$WORK_DIR/kali-cloud.tar.xz" -C "$WORK_DIR/kali-extracted"
rm -f "$WORK_DIR/kali-cloud.tar.xz"

KALI_SOURCE=$(find "$WORK_DIR/kali-extracted" -type f \
  \( -iname '*.qcow2' -o -iname '*.img' -o -iname '*.raw' \) -print -quit)
if [[ -z "$KALI_SOURCE" ]]; then
  echo "The Kali archive did not contain a QEMU disk image." >&2
  exit 1
fi

qemu-img convert -p -O qcow2 "$KALI_SOURCE" "$WORK_DIR/kali-working.qcow2"
rm -rf "$WORK_DIR/kali-extracted"
"$ROOT_DIR/scripts/configure-image.sh" kali "$WORK_DIR/kali-working.qcow2" "$VM_PASSWORD"
qemu-img convert -p -c -O qcow2 "$WORK_DIR/kali-working.qcow2" \
  "$OUTPUT_DIR/kali-minimal.qcow2"
rm -f "$WORK_DIR/kali-working.qcow2"

qemu-img check "$OUTPUT_DIR/ubuntu-22.04-minimal.qcow2"
qemu-img check "$OUTPUT_DIR/kali-minimal.qcow2"
(cd "$OUTPUT_DIR" && sha256sum \
  ubuntu-22.04-minimal.qcow2 \
  kali-minimal.qcow2 > SHA256SUMS)
