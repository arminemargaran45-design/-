#!/usr/bin/env bash
set -Eeuo pipefail

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
APP="styling-wrap-studio"
REPO="https://github.com/arminemargaran45-design/-.git"
BRANCH="sws-site"
WORK="/tmp/sws-premium-$STAMP"
STAGE="$WORK/stage"
RELEASE_ROOT="/opt/$APP/releases"
RELEASE_DIR="$RELEASE_ROOT/$STAMP-premium-v4"
PRIMARY="/var/www/stylingwrapstudio.ru"
COMPAT="/var/www/styling-wrap-studio/current"
CADDY="/etc/caddy/Caddyfile"
CADDY_BACKUP="/etc/caddy/Caddyfile.sws-premium-$STAMP"
MARKER="# SWS CANONICAL WWW"

log(){ printf '\n[SWS] %s\n' "$*"; }
fail(){ printf '\n[SWS] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root"
for cmd in git curl python3 caddy systemctl; do command -v "$cmd" >/dev/null || fail "$cmd is required"; done

PREV_PRIMARY="$(readlink -f "$PRIMARY" 2>/dev/null || true)"
log "Current SWS release: $PREV_PRIMARY"

log "Cloning latest existing SWS project"
git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$WORK/repo"
mkdir -p "$STAGE"
cp -a "$WORK/repo/sws-site/." "$STAGE/"

[ -s "$STAGE/index.html" ] || fail "index.html missing"
[ -s "$STAGE/styles.css" ] || fail "styles.css missing"
[ -s "$STAGE/script.js" ] || fail "script.js missing"
grep -q 'STYLING<span>WRAP STUDIO</span>' "$STAGE/index.html" || fail "new cinematic homepage marker missing"
grep -q 'class="topbar"' "$STAGE/index.html" || fail "new top navigation missing"
! grep -q 'class="sidebar"' "$STAGE/index.html" || fail "old sidebar still present"
grep -q 'class="story"' "$STAGE/index.html" || fail "pinned scroll scene missing"
grep -q '@media(max-width:980px)' "$STAGE/styles.css" || fail "mobile design missing"
! grep -q 'prefers-reduced-motion' "$STAGE/styles.css" || fail "animation disabling rule found"

log "Localizing real SWS project photos"
mkdir -p "$STAGE/assets/sws"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150 Safari/537.36"
REF="https://uslugi.yandex.ru/profile/StylingWrapStudio-1310152"
download(){
  local url="$1" out="$2"
  curl -L --fail --silent --show-error --retry 3 --connect-timeout 15 --max-time 90 -A "$UA" -e "$REF" "$url" -o "$out"
  local n
  n="$(wc -c < "$out" | tr -d ' ')"
  [ "$n" -gt 10000 ] || fail "Downloaded photo too small: $out ($n bytes)"
}
download "https://avatars.mds.yandex.net/get-ydo/11374192/2a0000018bce8166d612e82cb611d3281d36/diploma" "$STAGE/assets/sws/range-rover.jpg"
download "https://avatars.mds.yandex.net/get-ydo/4498943/2a0000018bcdb9fc5129290b5e9e17b3b5e3/diploma" "$STAGE/assets/sws/mercedes-front.jpg"
download "https://avatars.mds.yandex.net/get-ydo/11397567/2a0000018bcdba6878b9b769fdbec80fda64/diploma" "$STAGE/assets/sws/mercedes-rear.jpg"
download "https://avatars.mds.yandex.net/get-ydo/5575550/2a0000018bcd8524e296b1fad242e1352812/diploma" "$STAGE/assets/sws/mercedes-lime.jpg"
download "https://avatars.mds.yandex.net/get-ydo/4079136/2a0000018bcd7a63d59823c8e8f112273d7f/diploma" "$STAGE/assets/sws/lexus.jpg"
download "https://avatars.mds.yandex.net/get-ydo/4219998/2a0000018bc9a9d420f5b390918d9f4fc818/diploma" "$STAGE/assets/sws/audi-q7.jpg"
download "https://avatars.mds.yandex.net/get-ydo/4498943/2a00000182cd198a7c78a4b115d8c4de8fe2/diploma" "$STAGE/assets/sws/mustang.jpg"
[ -s "$STAGE/assets/sws/steering-wheel.webp" ] || fail "dark atelier image missing"

python3 - "$STAGE" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
mapping={
"https://avatars.mds.yandex.net/get-ydo/11374192/2a0000018bce8166d612e82cb611d3281d36/diploma":"/assets/sws/range-rover.jpg",
"https://avatars.mds.yandex.net/get-ydo/4498943/2a0000018bcdb9fc5129290b5e9e17b3b5e3/diploma":"/assets/sws/mercedes-front.jpg",
"https://avatars.mds.yandex.net/get-ydo/11397567/2a0000018bcdba6878b9b769fdbec80fda64/diploma":"/assets/sws/mercedes-rear.jpg",
"https://avatars.mds.yandex.net/get-ydo/5575550/2a0000018bcd8524e296b1fad242e1352812/diploma":"/assets/sws/mercedes-lime.jpg",
"https://avatars.mds.yandex.net/get-ydo/4079136/2a0000018bcd7a63d59823c8e8f112273d7f/diploma":"/assets/sws/lexus.jpg",
"https://avatars.mds.yandex.net/get-ydo/4219998/2a0000018bc9a9d420f5b390918d9f4fc818/diploma":"/assets/sws/audi-q7.jpg",
"https://avatars.mds.yandex.net/get-ydo/4498943/2a00000182cd198a7c78a4b115d8c4de8fe2/diploma":"/assets/sws/mustang.jpg",
}
for p in root.rglob("*.html"):
    s=p.read_text(encoding="utf-8")
    for old,new in mapping.items(): s=s.replace(old,new)
    s=s.replace('content="/assets/sws/','content="https://www.stylingwrapstudio.ru/assets/sws/')
    p.write_text(s,encoding="utf-8")
PY

log "Creating immutable release"
mkdir -p "$RELEASE_DIR"
cp -a "$STAGE/." "$RELEASE_DIR/"

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
log "Switching only Styling Wrap Studio web roots"
switch_root "$PRIMARY"
switch_root "$COMPAT"

log "Backing up and validating Caddy"
cp -a "$CADDY" "$CADDY_BACKUP"
python3 - "$CADDY" "$MARKER" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); marker=sys.argv[2]
lines=p.read_text().splitlines()
if marker not in "\n".join(lines):
    out=[]; patched=False
    for line in lines:
        out.append(line)
        if "stylingwrapstudio.ru" in line and "{" in line and not line.lstrip().startswith("#") and not patched:
            indent=re.match(r'\s*',line).group(0)+"  "
            out += [indent+marker,indent+"@swsApex host stylingwrapstudio.ru",indent+"redir @swsApex https://www.stylingwrapstudio.ru{uri} 308"]
            patched=True
    if not patched: raise SystemExit("SWS Caddy block not found")
    p.write_text("\n".join(out)+"\n")
PY
if ! caddy validate --config "$CADDY"; then
  cp -a "$CADDY_BACKUP" "$CADDY"
  fail "Caddy validation failed; original configuration restored"
fi
systemctl reload caddy

log "Production verification from localhost"
ROUTES=("/" "/services/" "/services/ppf/" "/services/wrapping/" "/services/blackout/" "/services/detailing/" "/services/coating/" "/services/atelier/" "/services/styling/" "/projects/" "/about/" "/guarantee/" "/contacts/" "/robots.txt" "/sitemap.xml" "/styles.css" "/script.js" "/assets/sws/range-rover.jpg" "/assets/sws/steering-wheel.webp")
for path in "${ROUTES[@]}"; do
  code="$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru$path?v=$STAMP")"
  [ "$code" = "200" ] || fail "$path returned HTTP $code"
  printf '[OK] %s -> %s\n' "$path" "$code"
done

HOME="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/?v=$STAMP")"
printf '%s' "$HOME" | grep -q 'STYLING<span>WRAP STUDIO</span>' || fail "New homepage is not active"
! printf '%s' "$HOME" | grep -q 'class="sidebar"' || fail "Old sidebar is still served"
printf '%s' "$HOME" | grep -q 'class="story"' || fail "Scroll scene missing in production"

JS="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/script.js?v=$STAMP")"
printf '%s' "$JS" | grep -q 'IntersectionObserver' || fail "Scroll reveal JS missing"
printf '%s' "$JS" | grep -q 'story-word' || fail "Pinned story JS missing"

CSS="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/styles.css?v=$STAMP")"
printf '%s' "$CSS" | grep -q '@media(max-width:980px)' || fail "Mobile CSS missing"
printf '%s' "$CSS" | grep -q '@keyframes marquee' || fail "Marquee animation missing"
! printf '%s' "$CSS" | grep -q 'prefers-reduced-motion' || fail "Animation disabling rule found"

REDIR="$(curl -ksSI --resolve "stylingwrapstudio.ru:443:127.0.0.1" "https://stylingwrapstudio.ru/" | tr -d '\r')"
printf '%s' "$REDIR" | grep -qi '^location: https://www.stylingwrapstudio.ru/' || fail "Apex domain does not redirect to www"

printf '\n=======================================================\n'
printf ' SWS PREMIUM V4 IS ACTIVE ON EXISTING DOMAIN\n'
printf ' Main: https://www.stylingwrapstudio.ru/\n'
printf ' Release: %s\n' "$RELEASE_DIR"
printf ' Previous primary release: %s\n' "${PREV_PRIMARY:-none}"
printf ' Caddy backup: %s\n' "$CADDY_BACKUP"
printf ' Pages/assets checked: %s\n' "${#ROUTES[@]}"
printf ' Mobile animation code: ACTIVE\n'
printf ' Other server projects: NOT MODIFIED\n'
printf '=======================================================\n'
printf 'Open: https://www.stylingwrapstudio.ru/?v=%s\n' "$STAMP"
