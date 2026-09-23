#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_URL="https://www.stylingwrapstudio.ru/"
APP="styling-wrap-studio"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="/tmp/sws-timeweb-sync-${STAMP}"
MIRROR="${WORK}/mirror"
RELEASE_ROOT="/opt/${APP}/releases"
RELEASE_DIR="${RELEASE_ROOT}/${STAMP}-live"
PRIMARY_ROOT="/var/www/stylingwrapstudio.ru"
COMPAT_ROOT="/var/www/styling-wrap-studio/current"
CADDYFILE="/etc/caddy/Caddyfile"
CADDY_BACKUP="/etc/caddy/Caddyfile.backup-${STAMP}"

log(){ printf '\n[SWS] %s\n' "$*"; }
fail(){ printf '\n[SWS] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run this script as root."
command -v wget >/dev/null 2>&1 || fail "wget is required."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."
command -v caddy >/dev/null 2>&1 || fail "Caddy is required."
[ -f "${CADDYFILE}" ] || fail "Caddyfile not found at ${CADDYFILE}."

log "Preflight: checking current live SWS source"
mkdir -p "${WORK}" "${MIRROR}" "${RELEASE_ROOT}"
wget -qO "${WORK}/source.html" "${SOURCE_URL}" || fail "Cannot download ${SOURCE_URL}"
grep -qi "Styling Wrap Studio" "${WORK}/source.html" || fail "Source does not look like Styling Wrap Studio."

log "Mirroring the current www site and same-host assets"
wget   --recursive   --level=inf   --page-requisites   --adjust-extension   --execute robots=off   --no-host-directories   --domains=www.stylingwrapstudio.ru   --directory-prefix="${MIRROR}"   "${SOURCE_URL}"

[ -f "${MIRROR}/index.html" ] || fail "Mirror is missing index.html."

log "Normalizing pretty routes so both /services and /services/index.html work"
python3 - "${MIRROR}" <<'PY'
from pathlib import Path
import shutil, sys
root = Path(sys.argv[1])
for p in list(root.rglob("*.html")):
    if p.name == "index.html":
        continue
    rel = p.relative_to(root)
    target = root / rel.with_suffix("") / "index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, target)
PY

[ -f "${MIRROR}/services/index.html" ] || fail "services/index.html was not created."
grep -qi "Услуг" "${MIRROR}/services/index.html" || fail "services/index.html content check failed."

IMAGE_COUNT="$(find "${MIRROR}" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' \) | wc -l | tr -d ' ')"
HTML_COUNT="$(find "${MIRROR}" -type f -name '*.html' | wc -l | tr -d ' ')"
log "Mirror ready: ${HTML_COUNT} HTML files, ${IMAGE_COUNT} local images"

log "Creating immutable release"
mkdir -p "${RELEASE_DIR}"
cp -a "${MIRROR}/." "${RELEASE_DIR}/"

point_alias() {
  local alias_path="$1"
  local parent
  parent="$(dirname "${alias_path}")"
  mkdir -p "${parent}"

  if [ -e "${alias_path}" ] && [ ! -L "${alias_path}" ]; then
    mv "${alias_path}" "${alias_path}.backup-${STAMP}"
  fi

  ln -s "${RELEASE_DIR}" "${alias_path}.new"
  mv -Tf "${alias_path}.new" "${alias_path}"
}

log "Atomically switching only Styling Wrap Studio web roots"
point_alias "${PRIMARY_ROOT}"
point_alias "${COMPAT_ROOT}"

log "Backing up Caddy configuration"
cp -a "${CADDYFILE}" "${CADDY_BACKUP}"

if ! grep -Eq '(^|[[:space:],])((www\.)?stylingwrapstudio\.ru)([[:space:],{]|$)' "${CADDYFILE}"; then
  log "Adding isolated SWS Caddy block (existing sites remain untouched)"
  cat >> "${CADDYFILE}" <<'CADDY'

# BEGIN SWS TIMEWEB
stylingwrapstudio.ru, www.stylingwrapstudio.ru {
    encode zstd gzip
    root * /var/www/stylingwrapstudio.ru
    try_files {path} {path}/index.html {path}.html
    file_server

    @static path /styles.css /script.js /images/* /assets/* /favicon.ico /robots.txt /sitemap.xml
    header @static Cache-Control "public, max-age=604800"

    header {
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        X-Frame-Options "SAMEORIGIN"
    }
}
# END SWS TIMEWEB
CADDY
else
  log "An SWS Caddy block already exists; leaving its structure unchanged."
fi

if ! caddy validate --config "${CADDYFILE}"; then
  cp -a "${CADDY_BACKUP}" "${CADDYFILE}"
  fail "Caddy validation failed. Original Caddyfile restored."
fi

systemctl reload caddy

log "Local content checks"
test -s "${PRIMARY_ROOT}/index.html"
test -s "${PRIMARY_ROOT}/services/index.html"

printf '\n[SWS] DEPLOYED SAFELY\n'
printf '[SWS] Release: %s\n' "${RELEASE_DIR}"
printf '[SWS] Backup Caddyfile: %s\n' "${CADDY_BACKUP}"
printf '[SWS] Main page: %s\n' "${PRIMARY_ROOT}/index.html"
printf '[SWS] Services page: %s\n' "${PRIMARY_ROOT}/services/index.html"
printf '[SWS] Server IP for DNS: 200.169.183.154\n'
printf '[SWS] ORVENIXA, Supabase and MedAlliance were not modified.\n'
