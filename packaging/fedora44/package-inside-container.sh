#!/usr/bin/env bash
# Produces a deterministic tarball after the fresh-container smoke test passes.
set -euo pipefail
umask 022

ARTIFACT_ROOT="${1:?usage: package-inside-container.sh ARTIFACT_ROOT OUTPUT_DIR}"
OUTPUT_DIR="${2:?usage: package-inside-container.sh ARTIFACT_ROOT OUTPUT_DIR}"

# shellcheck disable=SC1091
source /workspace/packaging/fedora44/versions.env
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"

ARTIFACT_NAME="coraza-nginx-${CONNECTOR_VERSION#v}-nginx${NGINX_VERSION}-fedora44-x86_64"
ARCHIVE="$OUTPUT_DIR/${ARTIFACT_NAME}.tar.gz"

tar \
  --sort=name \
  --format=posix \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  --mtime="@$SOURCE_DATE_EPOCH" \
  --pax-option=delete=atime,delete=ctime \
  -C "$ARTIFACT_ROOT" \
  -cf - . \
  | gzip -n -9 > "$ARCHIVE"

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
gzip -t "$ARCHIVE"
python3 /workspace/packaging/fedora44/extract-tar.py \
  "$ARCHIVE" "$VERIFY_DIR"
(
  cd "$VERIFY_DIR"
  sha256sum -c SHA256SUMS
)

(
  cd "$OUTPUT_DIR"
  sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)
cp "$ARTIFACT_ROOT/BUILD-MANIFEST.json" "$OUTPUT_DIR/${ARTIFACT_NAME}.manifest.json"
printf '%s\n' "$ARTIFACT_NAME" > "$OUTPUT_DIR/artifact-name.txt"

echo "created $ARCHIVE"
