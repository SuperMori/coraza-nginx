#!/usr/bin/env bash
# Runs inside the pinned Fedora image. Produces a relocatable release tree under
# /opt/coraza-nginx/current; deployment can extract it into a versioned directory
# and point /opt/coraza-nginx/current at that directory.
set -euo pipefail
umask 022

OUTPUT_ROOT="${1:?usage: build-inside-container.sh OUTPUT_ROOT}"
WORKSPACE=/workspace
PREFIX=/opt/coraza-nginx/current
STAGED_PREFIX="$OUTPUT_ROOT$PREFIX"

# shellcheck disable=SC1091
source "$WORKSPACE/packaging/fedora44/versions.env"

: "${CONNECTOR_COMMIT:?CONNECTOR_COMMIT is required}"
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"
[[ "$CONNECTOR_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo "invalid CONNECTOR_COMMIT: $CONNECTOR_COMMIT" >&2
  exit 1
}
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || {
  echo "invalid SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH" >&2
  exit 1
}
[ "$(uname -m)" = x86_64 ] || {
  echo "this bundle must be built on x86_64" >&2
  exit 1
}
[ ! -e "$STAGED_PREFIX" ] || {
  echo "staged prefix already exists: $STAGED_PREFIX" >&2
  exit 1
}

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

fetch_verify() {
  local url="$1"
  local sha256="$2"
  local output="$3"
  bash "$WORKSPACE/.github/scripts/fetch-verify.sh" "$url" "$sha256" "$output"
}

fetch_verify \
  "https://github.com/corazawaf/libcoraza/archive/refs/tags/${LIBCORAZA_VERSION}.zip" \
  "$LIBCORAZA_SHA256" \
  "$BUILD_DIR/libcoraza.zip"
unzip -q "$BUILD_DIR/libcoraza.zip" -d "$BUILD_DIR"
LIBCORAZA_DIR="$BUILD_DIR/libcoraza-${LIBCORAZA_VERSION#v}"
(
  cd "$LIBCORAZA_DIR"
  ./build.sh
  ./configure
  make -j"$(nproc)"
  make check
  make install
)
ldconfig

fetch_verify \
  "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
  "$NGINX_SHA256" \
  "$BUILD_DIR/nginx.tar.gz"
python3 "$WORKSPACE/packaging/fedora44/extract-tar.py" \
  "$BUILD_DIR/nginx.tar.gz" "$BUILD_DIR"
NGINX_DIR="$BUILD_DIR/nginx-${NGINX_VERSION}"
(
  cd "$NGINX_DIR"
  ./configure \
    --prefix="$PREFIX" \
    --sbin-path="$PREFIX/bin/nginx" \
    --modules-path="$PREFIX/modules" \
    --conf-path="$PREFIX/conf/nginx.conf" \
    --error-log-path="$PREFIX/logs/error.log" \
    --http-log-path="$PREFIX/logs/access.log" \
    --pid-path="$PREFIX/run/nginx.pid" \
    --lock-path="$PREFIX/run/nginx.lock" \
    --http-client-body-temp-path="$PREFIX/tmp/client_body" \
    --http-proxy-temp-path="$PREFIX/tmp/proxy" \
    --http-fastcgi-temp-path="$PREFIX/tmp/fastcgi" \
    --http-uwsgi-temp-path="$PREFIX/tmp/uwsgi" \
    --http-scgi-temp-path="$PREFIX/tmp/scgi" \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_auth_request_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-http_slice_module \
    --with-cc-opt='-O2 -g -fstack-protector-strong -fstack-clash-protection -fcf-protection -fPIC -Wformat -Werror=format-security -D_FORTIFY_SOURCE=3' \
    --with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed' \
    --add-dynamic-module="$WORKSPACE"
  make -j"$(nproc)"
  make DESTDIR="$OUTPUT_ROOT" install
)

install -Dm0755 /usr/local/lib/libcoraza.so "$STAGED_PREFIX/lib/libcoraza.so"
install -Dm0644 "$WORKSPACE/LICENSE" "$STAGED_PREFIX/licenses/coraza-nginx-LICENSE"
install -Dm0644 "$LIBCORAZA_DIR/LICENSE" "$STAGED_PREFIX/licenses/libcoraza-LICENSE"
install -Dm0644 "$NGINX_DIR/LICENSE" "$STAGED_PREFIX/licenses/nginx-LICENSE"

fetch_verify \
  "https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CRS_VERSION}.tar.gz" \
  "$CRS_SHA256" \
  "$BUILD_DIR/crs.tar.gz"
python3 "$WORKSPACE/packaging/fedora44/extract-tar.py" \
  "$BUILD_DIR/crs.tar.gz" "$BUILD_DIR"
CRS_DIR="$BUILD_DIR/coreruleset-${CRS_VERSION}"
mkdir -p "$STAGED_PREFIX/share/coraza/crs"
cp -a "$CRS_DIR/rules" "$STAGED_PREFIX/share/coraza/crs/"
cp -a "$CRS_DIR/plugins" "$STAGED_PREFIX/share/coraza/crs/"
install -Dm0644 "$CRS_DIR/LICENSE" "$STAGED_PREFIX/licenses/owasp-crs-LICENSE"
install -Dm0644 \
  "$CRS_DIR/crs-setup.conf.example" \
  "$STAGED_PREFIX/conf/crs-setup.conf"

install -Dm0644 \
  "$WORKSPACE/packaging/fedora44/config/nginx.conf" \
  "$STAGED_PREFIX/conf/nginx.conf"
install -Dm0644 \
  "$WORKSPACE/packaging/fedora44/config/coraza.conf" \
  "$STAGED_PREFIX/conf/coraza.conf"
install -Dm0644 \
  "$WORKSPACE/packaging/fedora44/config/coraza-rules.conf" \
  "$STAGED_PREFIX/conf/coraza-rules.conf"
mkdir -p \
  "$STAGED_PREFIX/conf/config.d" \
  "$STAGED_PREFIX/conf/overrides" \
  "$STAGED_PREFIX/logs" \
  "$STAGED_PREFIX/run" \
  "$STAGED_PREFIX/tmp/client_body" \
  "$STAGED_PREFIX/tmp/proxy" \
  "$STAGED_PREFIX/tmp/fastcgi" \
  "$STAGED_PREFIX/tmp/uwsgi" \
  "$STAGED_PREFIX/tmp/scgi"

test -x "$STAGED_PREFIX/bin/nginx"
test -f "$STAGED_PREFIX/modules/ngx_http_coraza_module.so"
test -f "$STAGED_PREFIX/lib/libcoraza.so"
file "$STAGED_PREFIX/bin/nginx" | grep -q 'x86-64'
file "$STAGED_PREFIX/modules/ngx_http_coraza_module.so" | grep -q 'x86-64'
readelf -lW "$STAGED_PREFIX/bin/nginx" | grep -q 'GNU_RELRO'
readelf -dW "$STAGED_PREFIX/bin/nginx" | grep -q 'BIND_NOW'

BUILD_TIMESTAMP="$(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')"
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "$BUILD_DIR/packages.txt"
jq -Rn '[inputs | select(length > 0)]' < "$BUILD_DIR/packages.txt" > "$BUILD_DIR/packages.json"

jq -n \
  --arg connector_version "$CONNECTOR_VERSION" \
  --arg connector_commit "$CONNECTOR_COMMIT" \
  --arg nginx_version "$NGINX_VERSION" \
  --arg nginx_sha256 "$NGINX_SHA256" \
  --arg libcoraza_version "$LIBCORAZA_VERSION" \
  --arg libcoraza_sha256 "$LIBCORAZA_SHA256" \
  --arg crs_version "$CRS_VERSION" \
  --arg crs_sha256 "$CRS_SHA256" \
  --arg fedora_image "$FEDORA_IMAGE" \
  --arg fedora_amd64_digest "$FEDORA_AMD64_DIGEST" \
  --arg built_at "$BUILD_TIMESTAMP" \
  --argjson source_date_epoch "$SOURCE_DATE_EPOCH" \
  --slurpfile packages "$BUILD_DIR/packages.json" \
  '{
    schema_version: 1,
    target: {os: "linux", distribution: "fedora", release: "44", architecture: "x86_64"},
    source: {
      repository: "https://github.com/SuperMori/coraza-nginx",
      connector_version: $connector_version,
      connector_commit: $connector_commit
    },
    components: {
      nginx: {version: $nginx_version, sha256: $nginx_sha256},
      libcoraza: {version: $libcoraza_version, sha256: $libcoraza_sha256},
      owasp_crs: {version: $crs_version, sha256: $crs_sha256}
    },
    builder: {
      image: $fedora_image,
      platform_digest: $fedora_amd64_digest,
      source_date_epoch: $source_date_epoch,
      built_at: $built_at,
      packages: $packages[0]
    }
  }' > "$STAGED_PREFIX/BUILD-MANIFEST.json"

{
  echo 'nginx -V:'
  LD_LIBRARY_PATH="$STAGED_PREFIX/lib" "$STAGED_PREFIX/bin/nginx" -V 2>&1
  echo
  echo 'nginx runtime libraries:'
  ldd "$STAGED_PREFIX/bin/nginx"
  echo
  echo 'connector runtime libraries:'
  ldd "$STAGED_PREFIX/modules/ngx_http_coraza_module.so"
  echo
  echo 'libcoraza runtime libraries:'
  ldd "$STAGED_PREFIX/lib/libcoraza.so"
} > "$STAGED_PREFIX/BUILD-ENVIRONMENT.txt"

if find "$STAGED_PREFIX" -xdev -type f -perm /0002 -print -quit | grep -q .; then
  echo "world-writable file found in bundle" >&2
  exit 1
fi

(
  cd "$STAGED_PREFIX"
  CHECKSUMS_TMP="$BUILD_DIR/SHA256SUMS"
  find . -type f ! -name SHA256SUMS -print0 \
    | sort -z \
    | xargs -0 sha256sum > "$CHECKSUMS_TMP"
  mv "$CHECKSUMS_TMP" SHA256SUMS
  sha256sum -c SHA256SUMS
)
