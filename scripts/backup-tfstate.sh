#!/usr/bin/env bash
# =============================================================================
# backup-tfstate.sh
#
# Saves a copy of the OpenTofu state (pulled from the B2 backend, decrypted)
# as an attachment on a Vaultwarden item, and keeps only the newest copies.
# This is the off-B2 copy: restore from it when B2 is down or the bucket is gone.
#
# The plaintext state only exists in a private temp dir for the duration of the
# run; bw encrypts the attachment client-side before upload.
#
# Usage:
#   ./scripts/backup-tfstate.sh [OPTIONS]
#
# Options:
#   -i, --item-id  ID     Vaultwarden item to attach to
#                         (default: $BW_TFSTATE_ITEM_ID)
#   -k, --keep     N      Number of state copies to keep (default: 5)
#   -h, --help            Show this help and exit
#
# Only attachments named homelab-tfstate-*.tfstate are pruned, so the item can
# hold other files too.
#
# Restore:
#   bw get attachment <fileName> --itemid "$BW_TFSTATE_ITEM_ID" --output ./restore.tfstate
#   tofu state push ./restore.tfstate
#
# Dependencies:
#   tofu (initialised against the backend, see README.md → State backend),
#   bw (logged in to Vaultwarden), jq
# =============================================================================

set -euo pipefail

WORKDIR=""
trap '[[ -n "$WORKDIR" ]] && rm -rf "$WORKDIR"' EXIT

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
ITEM_ID="${BW_TFSTATE_ITEM_ID:-}"
KEEP=5
PREFIX="homelab-tfstate-"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info() { echo "==> $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

usage() { sed -n '/^# Usage:/,/^# Dependencies:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-0}"; }

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--item-id) ITEM_ID="${2:?}"; shift 2 ;;
    -k|--keep)    KEEP="${2:?}"; shift 2 ;;
    -h|--help)    usage 0 ;;
    *)            echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$ITEM_ID" ]] || die "no item id: pass --item-id or set BW_TFSTATE_ITEM_ID"
[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || die "--keep must be a positive integer"
for cmd in tofu bw jq; do
  command -v "$cmd" >/dev/null || die "$cmd not found"
done

cd "$(dirname "$0")/.."

# ---------------------------------------------------------------------------
# Unlock the vault (reuses BW_SESSION if it is still valid)
# ---------------------------------------------------------------------------
case "$(bw status | jq -r .status)" in
  unauthenticated) die "bw is not logged in: run 'bw login' first" ;;
  locked)          info "Unlocking vault..."; BW_SESSION="$(bw unlock --raw)"; export BW_SESSION ;;
esac
bw sync >/dev/null
bw get item "$ITEM_ID" >/dev/null || die "item $ITEM_ID not found"

# ---------------------------------------------------------------------------
# Pull the state
# ---------------------------------------------------------------------------
WORKDIR="$(umask 077; mktemp -d)"
FILE="$WORKDIR/${PREFIX}$(date +%Y%m%d-%H%M%S).tfstate"

info "Pulling state..."
(umask 077; tofu state pull > "$FILE")
SERIAL="$(jq -er .serial "$FILE")" || die "pulled state is not valid JSON"
[[ "$(jq '.resources | length' "$FILE")" -gt 0 ]] || die "pulled state has no resources, not saving it"

# ---------------------------------------------------------------------------
# Upload and prune
# ---------------------------------------------------------------------------
info "Attaching $(basename "$FILE") (serial $SERIAL)..."
bw create attachment --file "$FILE" --itemid "$ITEM_ID" >/dev/null

# Names carry a sortable timestamp, so name order is age order.
bw get item "$ITEM_ID" |
  jq -r --arg p "$PREFIX" --argjson keep "$KEEP" \
    '[.attachments // [] | .[] | select(.fileName | startswith($p))]
     | sort_by(.fileName) | .[:-$keep][] | "\(.id) \(.fileName)"' |
  while read -r id name; do
    info "Deleting old copy $name..."
    bw delete attachment "$id" --itemid "$ITEM_ID" >/dev/null
  done

info "Done."
