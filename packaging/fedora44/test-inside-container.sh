#!/usr/bin/env bash
# Runs the finished bundle in a fresh Fedora 44 container. Tests module loading,
# DetectionOnly behavior, a real Coraza rule match, and privacy-safe logs.
set -euo pipefail

ARTIFACT_ROOT="${1:?usage: test-inside-container.sh ARTIFACT_ROOT}"
PREFIX=/opt/coraza-nginx/current
SECRET_MARKER=super-secret-query-value

dnf -y --setopt=install_weak_deps=False install \
  ca-certificates \
  curl \
  libgcc \
  openssl-libs \
  pcre2 \
  shadow-utils \
  zlib-ng-compat

mkdir -p "$PREFIX"
cp -a "$ARTIFACT_ROOT/." "$PREFIX/"
getent passwd nginx >/dev/null || useradd --system --home-dir /var/lib/nginx --shell /sbin/nologin nginx
chown -R nginx:nginx "$PREFIX/logs" "$PREFIX/run" "$PREFIX/tmp"

install -m0644 \
  /workspace/packaging/fedora44/config/ci-canary.conf \
  "$PREFIX/conf/overrides/ci-canary.conf"

export LD_LIBRARY_PATH="$PREFIX/lib"

cleanup() {
  if [ -f "$PREFIX/run/nginx.pid" ]; then
    "$PREFIX/bin/nginx" -s quit >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

(
  cd "$PREFIX"
  sha256sum -c SHA256SUMS
)
"$PREFIX/bin/nginx" -t
"$PREFIX/bin/nginx"

ready=false
for _ in $(seq 1 20); do
  if curl --fail --silent --show-error http://127.0.0.1:18093/livez >/dev/null; then
    ready=true
    break
  fi
  sleep 0.25
done
[ "$ready" = true ] || {
  echo "nginx did not become ready" >&2
  exit 1
}

benign_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  http://127.0.0.1:18093/benign)"
[ "$benign_status" = 204 ] || {
  echo "benign request returned $benign_status, expected 204" >&2
  exit 1
}

canary_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --get --data-urlencode "coraza_canary=$SECRET_MARKER" \
  http://127.0.0.1:18093/canary)"
[ "$canary_status" = 204 ] || {
  echo "DetectionOnly canary returned $canary_status, expected 204" >&2
  exit 1
}

audit_ready=false
for _ in $(seq 1 20); do
  if [ -s "$PREFIX/logs/coraza-audit.log" ]; then
    audit_ready=true
    break
  fi
  sleep 0.25
done
[ "$audit_ready" = true ] || {
  echo "canary rule did not create an audit record" >&2
  exit 1
}

grep -Fq 'libcoraza.so loaded via dynlib_open (bulk headers: yes)' "$PREFIX/logs/error.log"

if grep -R -Fq "$SECRET_MARKER" "$PREFIX/logs"; then
  echo "sensitive query value leaked into a log" >&2
  exit 1
fi

if ldd "$PREFIX/bin/nginx" "$PREFIX/modules/ngx_http_coraza_module.so" "$PREFIX/lib/libcoraza.so" \
  | grep -q 'not found'; then
  echo "bundle has an unresolved runtime library" >&2
  exit 1
fi

"$PREFIX/bin/nginx" -s quit
rm -f "$PREFIX/run/nginx.pid"
trap - EXIT

echo "Fedora 44 bundle smoke test passed"
