#!/usr/bin/env bash
set -Eeuo pipefail

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="/tmp/sws-final-mobile-$STAMP"
REPO="https://github.com/arminemargaran45-design/-.git"
BRANCH="sws-site"
RELEASE_ROOT="/opt/styling-wrap-studio/releases"
RELEASE_DIR="$RELEASE_ROOT/$STAMP-final-mobile"
PRIMARY="/var/www/stylingwrapstudio.ru"
COMPAT="/var/www/styling-wrap-studio/current"
CADDY="/etc/caddy/Caddyfile"
BACKUP="/etc/caddy/Caddyfile.sws-backup-$STAMP"
MARKER="# SWS CANONICAL WWW"

log(){ printf '\n[SWS] %s\n' "$*"; }
fail(){ printf '\n[SWS] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root"
for cmd in git python3 curl caddy systemctl; do command -v "$cmd" >/dev/null || fail "$cmd is required"; done

log "Cloning latest SWS source"
git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$WORK"
SITE="$WORK/sws-site"

[ -s "$SITE/index.html" ] || fail "index.html missing"
[ -s "$SITE/styles.css" ] || fail "styles.css missing"
[ -s "$SITE/script.js" ] || fail "script.js missing"

log "Checking requested changes before deploy"
! grep -q 'Автомобили<br>в работе' "$SITE/index.html" || fail "Unwanted cars-in-work section still exists"
! grep -q 'class="photo-section"' "$SITE/index.html" || fail "Unwanted photo-section still exists"
grep -q 'href="https://www.stylingwrapstudio.ru/"' "$SITE/index.html" || fail "Canonical home link missing"
grep -q "location.hostname==='stylingwrapstudio.ru'" "$SITE/script.js" || fail "Canonical-host redirect missing in JS"
grep -q "IntersectionObserver" "$SITE/script.js" || fail "Scroll animation observer missing"
grep -q "swsGridDrift" "$SITE/styles.css" || fail "Mobile continuous animation missing"
! grep -q '@media(prefers-reduced-motion:reduce)' "$SITE/styles.css" || fail "Reduced-motion override still disables animation"

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

log "Switching only Styling Wrap Studio"
switch_root "$PRIMARY"
switch_root "$COMPAT"

log "Making www the canonical host in Caddy"
cp -a "$CADDY" "$BACKUP"
python3 - "$CADDY" "$MARKER" <<'PY'
from pathlib import Path
import sys,re
p=Path(sys.argv[1]); marker=sys.argv[2]
lines=p.read_text().splitlines()
if marker in "\n".join(lines):
    raise SystemExit(0)

out=[]
i=0
patched=False
while i < len(lines):
    line=lines[i]
    stripped=line.strip()
    if '{' in line and not stripped.startswith('#'):
        head=line.split('{',1)[0]
        labels=[x.strip() for x in re.split(r'[ ,]+',head) if x.strip()]
        if 'stylingwrapstudio.ru' in labels:
            out.append(line)
            indent=re.match(r'\s*',line).group(0)+'  '
            out.append(indent+marker)
            out.append(indent+'@swsApex host stylingwrapstudio.ru')
            out.append(indent+'redir @swsApex https://www.stylingwrapstudio.ru{uri} 308')
            patched=True
            i+=1
            continue
    out.append(line)
    i+=1

if not patched:
    raise SystemExit("SWS Caddy block not found")
p.write_text("\n".join(out)+"\n")
PY

if ! caddy validate --config "$CADDY"; then
  cp -a "$BACKUP" "$CADDY"
  fail "Caddy validation failed; backup restored"
fi
systemctl reload caddy

log "Server-side checks"
for host in stylingwrapstudio.ru www.stylingwrapstudio.ru; do
  code="$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "$host:443:127.0.0.1" "https://$host/")"
  [ "$code" = "200" ] || [ "$code" = "308" ] || fail "$host returned HTTP $code"
done

html="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/?v=$STAMP")"
! printf '%s' "$html" | grep -q 'Автомобили<br>в работе' || fail "Old unwanted section is still being served"
printf '%s' "$html" | grep -q 'https://www.stylingwrapstudio.ru/' || fail "Canonical home link not served"

css="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/styles.css?v=$STAMP")"
printf '%s' "$css" | grep -q 'swsGridDrift' || fail "New mobile CSS not served"
! printf '%s' "$css" | grep -q '@media(prefers-reduced-motion:reduce)' || fail "Old reduced-motion disabling rule still served"

js="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/script.js?v=$STAMP")"
printf '%s' "$js" | grep -q "location.hostname==='stylingwrapstudio.ru'" || fail "New canonical JS not served"
printf '%s' "$js" | grep -q 'IntersectionObserver' || fail "New scroll animation JS not served"

redirect="$(curl -ksSI --resolve "stylingwrapstudio.ru:443:127.0.0.1" "https://stylingwrapstudio.ru/" | tr -d '\r')"
printf '%s' "$redirect" | grep -qi '^location: https://www.stylingwrapstudio.ru/' || fail "Apex domain does not redirect to www"

printf '\n====================================================\n'
printf ' SWS FINAL FIX ACTIVE: DESKTOP + MOBILE\n'
printf ' Removed: Автомобили в работе\n'
printf ' Main: https://www.stylingwrapstudio.ru/\n'
printf ' Mobile animations: forced ON\n'
printf ' Release: %s\n' "$RELEASE_DIR"
printf '====================================================\n'
printf 'Open: https://www.stylingwrapstudio.ru/?v=%s\n' "$STAMP"
printf 'ORVENIXA, Supabase and MedAlliance were not modified.\n'
