#!/usr/bin/env bash
set -Eeuo pipefail

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="/tmp/sws-atelier-fix-$STAMP"
REPO="https://github.com/arminemargaran45-design/-.git"
BRANCH="sws-site"
RELEASE_ROOT="/opt/styling-wrap-studio/releases"
RELEASE_DIR="$RELEASE_ROOT/$STAMP-atelier-jeep"
PRIMARY="/var/www/stylingwrapstudio.ru"
COMPAT="/var/www/styling-wrap-studio/current"
MARKER="atelier-jeep-steering-20260923"

log(){ printf '\n[SWS] %s\n' "$*"; }
fail(){ printf '\n[SWS] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root"
command -v git >/dev/null || fail "git is required"
command -v caddy >/dev/null || fail "caddy is required"
command -v curl >/dev/null || fail "curl is required"

log "Cloning latest SWS branch"
git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$WORK"

SITE="$WORK/sws-site"
[ -s "$SITE/assets/sws/steering-wheel.webp" ] || fail "steering-wheel.webp missing in repository"
grep -q '/assets/sws/steering-wheel.webp' "$SITE/services/index.html" || fail "Auto Atelier HTML does not reference steering wheel"

log "Adding cache-bust marker"
python3 - "$SITE/services/index.html" "$MARKER" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); marker=sys.argv[2]
s=p.read_text(encoding="utf-8")
if marker not in s:
    s=s.replace("<head>", f"<head><!-- {marker} -->", 1)
p.write_text(s, encoding="utf-8")
PY

log "Creating immutable release"
mkdir -p "$RELEASE_DIR"
cp -a "$SITE/." "$RELEASE_DIR/"

switch_root(){
  local target="$1"
  mkdir -p "$(dirname "$target")"
  if [ -L "$target" ]; then
    ln -sfn "$RELEASE_DIR" "$target.new"
    mv -Tf "$target.new" "$target"
  elif [ -e "$target" ]; then
    mv "$target" "$target.backup-$STAMP"
    ln -s "$RELEASE_DIR" "$target"
  else
    ln -s "$RELEASE_DIR" "$target"
  fi
}

log "Switching SWS roots"
switch_root "$PRIMARY"
switch_root "$COMPAT"

log "Validating Caddy"
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy

log "Verifying page and image from localhost"
for host in stylingwrapstudio.ru www.stylingwrapstudio.ru; do
  html="$(curl -ksS --resolve "$host:443:127.0.0.1" "https://$host/services/index.html?v=$STAMP")"
  printf '%s' "$html" | grep -q "$MARKER" || fail "$host still serves old services HTML"
  printf '%s' "$html" | grep -q '/assets/sws/steering-wheel.webp' || fail "$host services page does not reference steering wheel"
  code="$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "$host:443:127.0.0.1" "https://$host/assets/sws/steering-wheel.webp?v=$STAMP")"
  [ "$code" = "200" ] || fail "$host steering image HTTP $code"
done

printf '\n===============================================\n'
printf ' SWS ATELIER FIXED: JEEP STEERING PHOTO ACTIVE\n'
printf ' Release: %s\n' "$RELEASE_DIR"
printf '===============================================\n'
printf 'Open: https://www.stylingwrapstudio.ru/services/index.html?v=%s\n' "$STAMP"
