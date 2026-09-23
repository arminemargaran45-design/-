#!/usr/bin/env bash
set -Eeuo pipefail

APP="styling-wrap-studio"
REPO="https://github.com/arminemargaran45-design/-.git"
BRANCH="sws-site"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="/tmp/sws-branch-deploy-${STAMP}"
RELEASE_ROOT="/opt/${APP}/releases"
RELEASE_DIR="${RELEASE_ROOT}/${STAMP}-branch"
PRIMARY_ROOT="/var/www/stylingwrapstudio.ru"
COMPAT_ROOT="/var/www/styling-wrap-studio/current"

log(){ printf '\n[SWS] %s\n' "$*"; }
fail(){ printf '\n[SWS] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root"
command -v git >/dev/null || fail "git is required"

log "Cloning latest SWS branch"
git clone --depth 1 --branch "${BRANCH}" "${REPO}" "${WORK}"
[ -f "${WORK}/sws-site/index.html" ] || fail "sws-site/index.html not found"
[ -f "${WORK}/sws-site/services/index.html" ] || fail "services/index.html not found"
[ -f "${WORK}/sws-site/projects/index.html" ] || fail "projects/index.html not found"

# Ensure the seven requested real SWS images are present in page source.
EXPECTED=(
  "2a0000018bce8166d612e82cb611d3281d36"
  "2a0000018bcdb9fc5129290b5e9e17b3b5e3"
  "2a0000018bcdba6878b9b769fdbec80fda64"
  "2a0000018bcd8524e296b1fad242e1352812"
  "2a0000018bcd7a63d59823c8e8f112273d7f"
  "2a0000018bc9a9d420f5b390918d9f4fc818"
  "2a00000182cd198a7c78a4b115d8c4de8fe2"
)
for id in "${EXPECTED[@]}"; do
  grep -Rqs "${id}" "${WORK}/sws-site" || fail "Expected SWS photo missing: ${id}"
done

log "Creating immutable release"
mkdir -p "${RELEASE_DIR}"
cp -a "${WORK}/sws-site/." "${RELEASE_DIR}/"

switch_link() {
  local link="$1"
  mkdir -p "$(dirname "${link}")"
  if [ -e "${link}" ] && [ ! -L "${link}" ]; then
    mv "${link}" "${link}.backup-${STAMP}"
  fi
  ln -s "${RELEASE_DIR}" "${link}.new"
  mv -Tf "${link}.new" "${link}"
}

log "Switching only Styling Wrap Studio roots"
switch_link "${PRIMARY_ROOT}"
switch_link "${COMPAT_ROOT}"

log "Reloading Caddy without changing configuration"
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy

log "Verifying local files"
test -s "${PRIMARY_ROOT}/index.html"
test -s "${PRIMARY_ROOT}/services/index.html"
test -s "${PRIMARY_ROOT}/projects/index.html"

printf '\n[SWS] UPDATED WITH 7 REAL PROJECT PHOTOS\n'
printf '[SWS] Release: %s\n' "${RELEASE_DIR}"
printf '[SWS] Commit: %s\n' "$(git -C "${WORK}" rev-parse --short=12 HEAD)"
printf '[SWS] ORVENIXA, Supabase and MedAlliance were not modified.\n'
