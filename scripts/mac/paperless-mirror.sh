#!/usr/bin/env bash
# =============================================================================
# paperless-mirror.sh
#
# Pulls the original files from the nightly Paperless export on TrueNAS
# into an iCloud Drive folder, so documents stay readable from Finder and the
# iPhone Files app while Paperless is down. originals/ rather than archive/,
# because Paperless only keeps an archived copy of documents it OCRed.
# One-way: Paperless is the source of truth, and anything changed in the
# mirror is overwritten on the next run.
#
# Guards against wiping the mirror from a broken export: aborts if the
# manifest is missing or the remote has far fewer files than the mirror.
#
# Usage (normally run by launchd, see com.example.paperless-mirror.plist):
#   ./scripts/mac/paperless-mirror.sh
#
# Environment overrides:
#   MIRROR_REMOTE   rsync source  (default: docmirror@10.0.14.10:/mnt/wd_green_pool/documents/export)
#   MIRROR_DEST     local target  (default: iCloud Drive/Paperless (read-only))
#   MIRROR_MIN_PCT  min remote/local file ratio in percent (default: 90)
# =============================================================================
set -euo pipefail

REMOTE="${MIRROR_REMOTE:-docmirror@10.0.14.10:/mnt/wd_green_pool/documents/export}"
DEST="${MIRROR_DEST:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Paperless (read-only)}"
MIN_PCT="${MIRROR_MIN_PCT:-90}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

if ! rsync --list-only "$REMOTE/manifest.json" >/dev/null 2>&1; then
  log "ERROR: $REMOTE/manifest.json not found, export looks broken; not syncing"
  exit 1
fi

if ! rsync --list-only "$REMOTE/originals/" >/dev/null 2>&1; then
  log "ERROR: $REMOTE/originals/ not found; was the export run with --use-folder-prefix?"
  exit 1
fi

remote_count=$(rsync -r --list-only "$REMOTE/originals/" | grep -c '^-' || true)
mkdir -p "$DEST"
local_count=$(find "$DEST" -type f ! -name '.*' | wc -l | tr -d ' ')

if (( local_count > 0 && remote_count * 100 < local_count * MIN_PCT )); then
  log "ERROR: remote has $remote_count files, mirror has $local_count (below ${MIN_PCT}%); not syncing"
  exit 1
fi

log "Syncing $remote_count files from $REMOTE/originals/"
rsync -rt --delete --exclude='.*' "$REMOTE/originals/" "$DEST/"
log "Done"
