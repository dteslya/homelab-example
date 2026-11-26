#!/usr/bin/env bash
# =============================================================================
# import-talos-image.sh
#
# Fetches a Talos Linux image from the Image Factory (with the requested
# extensions baked in), converts it to the Incus split-image format, and
# imports it into the Incus image store.
#
# IMAGE TYPE: nocloud (not metal)
#   Talos has no incus-agent, so user.user-data passed via Incus config is
#   never seen by Talos. Instead Talos reads its machine config from a NoCloud
#   datasource: a CDROM/disk with volume label "cidata" containing user-data.
#   The nocloud image variant has the NoCloud datasource enabled; the metal
#   variant does not. Incus can attach a cloud-init config disk automatically
#   (source=cloud-init:config) which satisfies the NoCloud datasource.
#
# Incus VM images require a split tarball:
#   - metadata.tar.xz  → contains metadata.yaml
#   - rootfs.img       → qcow2-formatted disk image
#
# Usage:
#   ./scripts/import-talos-image.sh [OPTIONS]
#
# Options:
#   -v, --version      VERSION   Talos version          (default: v1.13.2)
#   -a, --arch         ARCH      amd64 | arm64          (default: amd64)
#   -e, --extension    NAME      Extension to include; repeatable
#                                (default: siderolabs/iscsi-tools)
#   -r, --remote       REMOTE    Incus remote            (default: local)
#   -p, --project      PROJECT   Incus project           (default: default)
#   -f, --factory-url  URL       Image Factory base URL
#                                (default: https://factory.talos.dev)
#   -t, --tmp-dir      DIR       Working directory for build artifacts
#                                (default: /tmp)
#   -d, --delete                 Delete the image instead of importing it
#   -h, --help                   Show this help and exit
#
# Output:
#   Prints the Incus image alias to stdout on success:
#
#     ALIAS=$(./scripts/import-talos-image.sh --version v1.13.2)
#
#   All progress messages go to stderr so stdout stays clean.
#
# Idempotency:
#   If an image with the computed alias already exists in Incus the script
#   exits 0 immediately, printing the alias, without re-downloading anything.
#
# Alias format:
#   talos-<first-12-chars-of-schematic-id>-<version>
#   e.g.  talos-a3f8c1d20e91-v1.13.2
#
# Dependencies:
#   curl, xz, qemu-img, tar, incus
# =============================================================================

set -euo pipefail

# Global working directory – set in import_image(), cleaned up by EXIT trap.
WORKDIR=""
trap '[[ -n "$WORKDIR" ]] && { info "Cleaning up ${WORKDIR}..."; rm -rf "$WORKDIR"; }' EXIT

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
TALOS_VERSION="v1.13.2"
ARCH="amd64"
FACTORY_URL="https://factory.talos.dev"
INCUS_REMOTE="local"
INCUS_PROJECT="default"
TMP_DIR="/tmp"
DELETE_MODE=false
EXTENSIONS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info() { echo "==> $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

usage() {
  sed -n '/^# Usage:/,/^# Dependencies:/{ /^# Dependencies:/d; s/^# \?//; p }' "$0"
  exit 0
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH. Install it and retry."
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)     TALOS_VERSION="$2"; shift 2 ;;
    -a|--arch)        ARCH="$2";          shift 2 ;;
    -e|--extension)   EXTENSIONS+=("$2"); shift 2 ;;
    -r|--remote)      INCUS_REMOTE="$2";  shift 2 ;;
    -p|--project)     INCUS_PROJECT="$2"; shift 2 ;;
    -f|--factory-url) FACTORY_URL="$2";   shift 2 ;;
    -t|--tmp-dir)     TMP_DIR="$2";       shift 2 ;;
    -d|--delete)      DELETE_MODE=true;   shift   ;;
    -h|--help)        usage ;;
    *) die "Unknown option: $1  (use --help for usage)" ;;
  esac
done

# Apply default extensions when none were specified
if [[ ${#EXTENSIONS[@]} -eq 0 ]]; then
  EXTENSIONS=(
    "siderolabs/iscsi-tools"
  )
fi

[[ "$ARCH" == "amd64" || "$ARCH" == "arm64" ]] \
  || die "--arch must be 'amd64' or 'arm64', got: '$ARCH'"

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
require_cmd curl
require_cmd qemu-img
require_cmd tar
require_cmd incus

if command -v xz >/dev/null 2>&1; then
  XZ_DECOMP="xz --decompress --keep"
elif command -v unxz >/dev/null 2>&1; then
  XZ_DECOMP="unxz --keep"
else
  die "'xz' not found. Install xz-utils (Debian/Ubuntu) or xz (Fedora/Arch)."
fi

# ---------------------------------------------------------------------------
# Map Go-style arch names → kernel arch names (required by metadata.yaml)
# ---------------------------------------------------------------------------
kernel_arch() {
  case "$1" in
    amd64) echo "x86_64"  ;;
    arm64) echo "aarch64" ;;
  esac
}

# ---------------------------------------------------------------------------
# Image Factory: POST schematic → schematic ID
# ---------------------------------------------------------------------------
build_schematic_yaml() {
  local yaml="customization:"$'\n'
  yaml+="  systemExtensions:"$'\n'
  yaml+="    officialExtensions:"$'\n'
  for ext in "${EXTENSIONS[@]}"; do
    yaml+="      - ${ext}"$'\n'
  done
  printf '%s' "$yaml"
}

fetch_schematic_id() {
  local schematic_yaml="$1"

  info "Posting schematic to Image Factory: ${FACTORY_URL}/schematics"
  for ext in "${EXTENSIONS[@]}"; do info "  extension: ${ext}"; done

  local response http_code body
  response=$(curl --silent --show-error --write-out '\n%{http_code}' \
    --request POST \
    --header 'Content-Type: application/yaml' \
    --data "$schematic_yaml" \
    "${FACTORY_URL}/schematics")

  # Split off the last line with parameter expansion: macOS head has no -n-1
  http_code=${response##*$'\n'}
  body=${response%$'\n'*}

  [[ "$http_code" == "201" ]] \
    || die "Image Factory returned HTTP ${http_code}: ${body}"

  local schematic_id
  schematic_id=$(echo "$body" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [[ -n "$schematic_id" ]] \
    || die "Could not parse schematic ID from response: ${body}"

  echo "$schematic_id"
}

# ---------------------------------------------------------------------------
# Alias / remote helpers
# ---------------------------------------------------------------------------
make_alias()   { echo "talos-${1:0:12}-${TALOS_VERSION}"; }
project_flag() { echo "--project ${INCUS_PROJECT}"; }
remote_alias() {
  [[ "$INCUS_REMOTE" == "local" ]] && echo "$1" || echo "${INCUS_REMOTE}:$1"
}
image_exists() { incus image info "$1" $(project_flag) >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Delete mode
# ---------------------------------------------------------------------------
delete_image() {
  local alias; alias=$(make_alias "$1")
  local ra;    ra=$(remote_alias "$alias")

  info "Removing image '${alias}' from Incus..."
  if incus image delete "$ra" $(project_flag) 2>/dev/null; then
    info "Removed."
  else
    info "Image not found or already removed – nothing to do."
  fi
}

# ---------------------------------------------------------------------------
# Build the Incus split image and import
#
# We use the *nocloud* artifact from the Image Factory, not *metal*.
#
# Why nocloud?
#   Talos reads its machine config via the NoCloud datasource: a CDROM/vfat
#   disk attached to the VM with volume label "cidata". The nocloud image
#   variant has this datasource compiled in; the metal variant does not.
#   Incus can generate this disk automatically via source=cloud-init:config,
#   which passes user.user-data / user.network-config as nocloud user-data.
#
# Incus split-image format:
#   FILE 1  metadata.tar.xz  – tar of metadata.yaml
#   FILE 2  rootfs.img       – qcow2 disk (any filename, passed as 2nd arg)
# ---------------------------------------------------------------------------
import_image() {
  local schematic_id="$1"
  local alias; alias=$(make_alias "$schematic_id")
  local ra;    ra=$(remote_alias "$alias")

  if image_exists "$ra"; then
    info "Image '${alias}' already present in Incus – skipping."
    echo "$alias"
    return 0
  fi

  WORKDIR=$(mktemp -d -p "$TMP_DIR" "talos-build-XXXXXXXX")

  # nocloud artifact: nocloud-<arch>.raw.xz
  local image_url="${FACTORY_URL}/image/${schematic_id}/${TALOS_VERSION}/nocloud-${ARCH}.raw.xz"
  info "Downloading: ${image_url}"

  local raw_xz="${WORKDIR}/nocloud-${ARCH}.raw.xz"
  local raw="${WORKDIR}/nocloud-${ARCH}.raw"
  local qcow2="${WORKDIR}/rootfs.img"
  local metadata_yaml="${WORKDIR}/metadata.yaml"
  local metadata_tar="${WORKDIR}/metadata.tar.xz"

  # 1. Download
  curl --fail --location --progress-bar --output "$raw_xz" "$image_url"

  # 2. Decompress .raw.xz → .raw
  info "Decompressing..."
  $XZ_DECOMP "$raw_xz"
  [[ -f "$raw" ]] || die "Decompression produced no output at ${raw}"

  # 3. Convert raw → qcow2
  info "Converting to qcow2..."
  qemu-img convert -f raw -O qcow2 "$raw" "$qcow2"

  # 4. Build metadata.yaml
  info "Building metadata..."
  cat > "$metadata_yaml" << YAML
architecture: "$(kernel_arch "$ARCH")"
creation_date: $(date +%s)
properties:
  architecture: "$(kernel_arch "$ARCH")"
  description: "Talos Linux ${TALOS_VERSION} (${ARCH}) – schematic ${schematic_id:0:12}"
  name: "${alias}"
  os: "talos"
  release: "${TALOS_VERSION}"
  variant: "nocloud"
templates: {}
YAML

  # 5. Pack metadata tarball (metadata.yaml only, no path prefix)
  info "Packing metadata tarball..."
  tar -cJf "$metadata_tar" -C "$WORKDIR" metadata.yaml

  # 6. Import: split-image format = metadata tarball + disk image
  info "Importing into Incus (remote: ${INCUS_REMOTE}, project: ${INCUS_PROJECT})..."
  local target=()
  [[ "$INCUS_REMOTE" == "local" ]] || target=("${INCUS_REMOTE}:")
  incus image import "$metadata_tar" "$qcow2" ${target[@]+"${target[@]}"} \
    $(project_flag) \
    --alias "$alias"

  info "Image '${alias}' imported successfully."
  echo "$alias"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
  local schematic_yaml schematic_id
  schematic_yaml=$(build_schematic_yaml)
  schematic_id=$(fetch_schematic_id "$schematic_yaml")
  info "Schematic ID: ${schematic_id}"

  if [[ "$DELETE_MODE" == true ]]; then
    delete_image "$schematic_id"
  else
    import_image "$schematic_id"
  fi
}

main

