#!/usr/bin/env bash
# Build, test, and package the Fedora 44 x86_64 bundle through the same pinned
# container image locally and in GitHub Actions.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
OUTPUT_DIR="${1:-$REPO_ROOT/dist/fedora44}"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/versions.env"

if ! grep -Fqx "ARG FEDORA_IMAGE=$FEDORA_IMAGE" "$SCRIPT_DIR/Dockerfile.builder"; then
  echo "Dockerfile.builder Fedora pin differs from versions.env" >&2
  exit 1
fi

if [ -e "$OUTPUT_DIR" ] && [ -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  echo "output directory is not empty: $OUTPUT_DIR" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

CONNECTOR_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" show -s --format=%ct "$CONNECTOR_COMMIT")"
BUILDER_IMAGE="coraza-nginx-fedora44-builder:${FEDORA_AMD64_DIGEST#sha256:}"

docker build \
  --platform linux/amd64 \
  --build-arg "FEDORA_IMAGE=$FEDORA_IMAGE" \
  --file "$SCRIPT_DIR/Dockerfile.builder" \
  --tag "$BUILDER_IMAGE" \
  "$REPO_ROOT"

common_args=(
  --rm
  --platform linux/amd64
  --env "CONNECTOR_COMMIT=$CONNECTOR_COMMIT"
  --env "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
  --volume "$REPO_ROOT:/workspace:ro"
  --volume "$OUTPUT_DIR:/output"
  --workdir /workspace
)

docker run "${common_args[@]}" \
  "$BUILDER_IMAGE" \
  bash packaging/fedora44/build-inside-container.sh /output/root

docker run "${common_args[@]}" \
  "$FEDORA_IMAGE" \
  bash packaging/fedora44/test-inside-container.sh \
    /output/root/opt/coraza-nginx/current

docker run "${common_args[@]}" \
  "$BUILDER_IMAGE" \
  bash packaging/fedora44/package-inside-container.sh \
    /output/root/opt/coraza-nginx/current /output

echo "bundle output: $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -type f -print | sort
