#!/usr/bin/env bash
# Resolve a safe OWASP CRS production candidate for the Fedora 44 bundle.
#
# Only patch releases from the bundle's current LTS line are applied
# automatically. A newer LTS line is reported for manual review but never
# written into production pins. The caller receives source-able metadata in the
# output file and remains responsible for build, review, release, and deploy.
set -euo pipefail

OUTPUT_FILE="${1:?usage: compute-production-crs-candidate.sh OUTPUT_FILE}"
VERSIONS_FILE="packaging/fedora44/versions.env"
FETCH_VERIFY=".github/scripts/fetch-verify.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

api() {
  local url="$1"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" "$url"
  else
    curl -fsSL "$url"
  fi
}

read_pin() {
  local key="$1" value
  value="$(grep -E "^${key}=" "$VERSIONS_FILE" | cut -d= -f2-)"
  if [ -z "$value" ]; then
    echo "::error::missing required pin ${key} in ${VERSIONS_FILE}" >&2
    exit 1
  fi
  printf '%s\n' "$value"
}

replace_pin() {
  local key="$1" value="$2"
  if ! grep -q "^${key}=" "$VERSIONS_FILE"; then
    echo "::error::missing required pin ${key} in ${VERSIONS_FILE}" >&2
    exit 1
  fi
  sed -i.bak "s|^${key}=.*$|${key}=${value}|" "$VERSIONS_FILE"
  rm -f "${VERSIONS_FILE}.bak"
}

validate_version() {
  local version="$1"
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "::error::invalid CRS release version: ${version}" >&2
    exit 1
  fi
}

version_gt() {
  local left="$1" right="$2"
  [ "$left" != "$right" ] &&
    [ "$(printf '%s\n%s\n' "$left" "$right" | sort -V | tail -n 1)" = "$left" ]
}

current_version="$(read_pin CRS_VERSION)"
current_sha256="$(read_pin CRS_SHA256)"
validate_version "$current_version"
if ! [[ "$current_sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "::error::invalid current CRS sha256 in ${VERSIONS_FILE}" >&2
  exit 1
fi

current_line="${current_version%.*}"
echo "resolving OWASP CRS LTS releases (current production line: ${current_line}.x)..."
releases_json="$(api 'https://api.github.com/repos/coreruleset/coreruleset/releases?per_page=100')"

latest_lts_tag="$(printf '%s' "$releases_json" | jq -r '
  map(select(.draft | not) | select(.prerelease | not)
      | select((.name // "") | test("\\(LTS\\)")))
  | .[0].tag_name // empty')"
same_line_tag="$(printf '%s' "$releases_json" | jq -r --arg prefix "v${current_line}." '
  map(select(.draft | not) | select(.prerelease | not)
      | select((.name // "") | test("\\(LTS\\)"))
      | select(.tag_name | startswith($prefix)))
  | .[0].tag_name // empty')"

if [ -z "$latest_lts_tag" ] || [ -z "$same_line_tag" ]; then
  echo "::error::failed to resolve current-line and latest CRS LTS releases" >&2
  exit 1
fi

latest_lts_version="${latest_lts_tag#v}"
candidate_version="${same_line_tag#v}"
validate_version "$latest_lts_version"
validate_version "$candidate_version"

if version_gt "$current_version" "$candidate_version"; then
  echo "::error::resolved CRS candidate ${candidate_version} is older than current ${current_version}" >&2
  exit 1
fi

newer_lts_line=false
if [ "${latest_lts_version%.*}" != "$current_line" ] && version_gt "$latest_lts_version" "$current_version"; then
  newer_lts_line=true
fi

candidate_sha256="$current_sha256"
if version_gt "$candidate_version" "$current_version"; then
  archive="$tmp/coreruleset-${candidate_version}.tar.gz"
  candidate_sha256="$(
    bash "$FETCH_VERIFY" \
      "https://github.com/coreruleset/coreruleset/archive/refs/tags/v${candidate_version}.tar.gz" \
      - "$archive" | awk 'END { print $1 }'
  )"
  if ! [[ "$candidate_sha256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "::error::failed to compute candidate CRS sha256" >&2
    exit 1
  fi
  replace_pin CRS_VERSION "$candidate_version"
  replace_pin CRS_SHA256 "$candidate_sha256"
fi

changed=false
if ! git diff --quiet -- "$VERSIONS_FILE"; then
  changed=true
fi

cat > "$OUTPUT_FILE" <<EOF
current_version=${current_version}
candidate_version=${candidate_version}
candidate_sha256=${candidate_sha256}
latest_lts_version=${latest_lts_version}
newer_lts_line=${newer_lts_line}
changed=${changed}
EOF

echo "current production CRS: ${current_version}"
echo "same-line candidate:     ${candidate_version}"
echo "latest LTS release:      ${latest_lts_version}"
echo "newer LTS line:          ${newer_lts_line}"
echo "production pin changed:  ${changed}"
