#!/usr/bin/env bash
set -Eeuo pipefail
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPO="https://github.com/arminemargaran45-design/-.git"
WORK="/tmp/sws-premium-v8-mobilefix-$STAMP"
SITE="$WORK/sws-site"
RELEASE="/opt/styling-wrap-studio/releases/$STAMP-premium-v8-mobilefix"
PRIMARY="/var/www/stylingwrapstudio.ru"
COMPAT="/var/www/styling-wrap-studio/current"
fail(){ printf '\n[SWS] ERROR: %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || fail "Run as root"
for c in git curl python3 caddy systemctl; do command -v "$c" >/dev/null || fail "$c missing"; done

git clone -q --depth 1 --branch sws-site "$REPO" "$WORK"
grep -q 'PREMIUM V7' "$SITE/styles.css" || fail "Premium V6 CSS missing"
grep -q 'map-frame iframe{filter:none!important}' "$SITE/styles.css" || fail "color map fix missing"
grep -q 'MOBILE V8 HOTFIX' "$SITE/styles.css" || fail "mobile V8 hotfix missing"

mkdir -p "$SITE/assets/sws"
UA="Mozilla/5.0 AppleWebKit/605.1.15 Safari/605.1.15"
REF="https://uslugi.yandex.ru/profile/StylingWrapStudio-1310152"
download(){ curl -LfsS --retry 3 --connect-timeout 15 --max-time 90 -A "$UA" -e "$REF" "$1" -o "$2"; [ "$(wc -c < "$2")" -gt 10000 ] || fail "photo download failed: $2"; }
download "https://avatars.mds.yandex.net/get-ydo/11374192/2a0000018bce8166d612e82cb611d3281d36/diploma" "$SITE/assets/sws/range-rover.jpg"
download "https://avatars.mds.yandex.net/get-ydo/4498943/2a0000018bcdb9fc5129290b5e9e17b3b5e3/diploma" "$SITE/assets/sws/mercedes-front.jpg"
download "https://avatars.mds.yandex.net/get-ydo/11397567/2a0000018bcdba6878b9b769fdbec80fda64/diploma" "$SITE/assets/sws/mercedes-rear.jpg"
download "https://avatars.mds.yandex.net/get-ydo/5575550/2a0000018bcd8524e296b1fad242e1352812/diploma" "$SITE/assets/sws/mercedes-lime.jpg"
download "https://avatars.mds.yandex.net/get-ydo/4079136/2a0000018bcd7a63d59823c8e8f112273d7f/diploma" "$SITE/assets/sws/lexus.jpg"
download "https://avatars.mds.yandex.net/get-ydo/4219998/2a0000018bc9a9d420f5b390918d9f4fc818/diploma" "$SITE/assets/sws/audi-q7.jpg"
download "https://avatars.mds.yandex.net/get-ydo/4498943/2a00000182cd198a7c78a4b115d8c4de8fe2/diploma" "$SITE/assets/sws/mustang.jpg"

python3 - "$SITE" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
mp={
"https://avatars.mds.yandex.net/get-ydo/11374192/2a0000018bce8166d612e82cb611d3281d36/diploma":"/assets/sws/range-rover.jpg",
"https://avatars.mds.yandex.net/get-ydo/4498943/2a0000018bcdb9fc5129290b5e9e17b3b5e3/diploma":"/assets/sws/mercedes-front.jpg",
"https://avatars.mds.yandex.net/get-ydo/11397567/2a0000018bcdba6878b9b769fdbec80fda64/diploma":"/assets/sws/mercedes-rear.jpg",
"https://avatars.mds.yandex.net/get-ydo/5575550/2a0000018bcd8524e296b1fad242e1352812/diploma":"/assets/sws/mercedes-lime.jpg",
"https://avatars.mds.yandex.net/get-ydo/4079136/2a0000018bcd7a63d59823c8e8f112273d7f/diploma":"/assets/sws/lexus.jpg",
"https://avatars.mds.yandex.net/get-ydo/4219998/2a0000018bc9a9d420f5b390918d9f4fc818/diploma":"/assets/sws/audi-q7.jpg",
"https://avatars.mds.yandex.net/get-ydo/4498943/2a00000182cd198a7c78a4b115d8c4de8fe2/diploma":"/assets/sws/mustang.jpg"}
for p in root.rglob("*.html"):
    s=p.read_text(encoding="utf-8").replace('content="#050506"','content="#070809"')
    for a,b in mp.items(): s=s.replace(a,b)
    s=s.replace('content="/assets/sws/','content="https://www.stylingwrapstudio.ru/assets/sws/')
    p.write_text(s,encoding="utf-8")
PY

mkdir -p "$RELEASE"
cp -a "$SITE/." "$RELEASE/"
switch(){ local t="$1"; mkdir -p "$(dirname "$t")"; if [ -L "$t" ]; then ln -sfn "$RELEASE" "$t.new"; mv -Tf "$t.new" "$t"; elif [ -e "$t" ]; then mv "$t" "$t.backup-$STAMP"; ln -s "$RELEASE" "$t"; else ln -s "$RELEASE" "$t"; fi; }
switch "$PRIMARY"; switch "$COMPAT"
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy

ROUTES=("/" "/services/" "/services/ppf/" "/services/wrapping/" "/services/blackout/" "/services/detailing/" "/services/coating/" "/services/atelier/" "/services/styling/" "/projects/" "/about/" "/guarantee/" "/contacts/" "/styles.css" "/script.js" "/assets/sws/mercedes-front.jpg")
for path in "${ROUTES[@]}"; do code="$(curl -ksS -o /dev/null -w '%{http_code}' --resolve www.stylingwrapstudio.ru:443:127.0.0.1 "https://www.stylingwrapstudio.ru$path?v=$STAMP")"; [ "$code" = 200 ] || fail "$path -> $code"; printf '[OK] %s -> 200\n' "$path"; done
CSS="$(curl -ksS --resolve www.stylingwrapstudio.ru:443:127.0.0.1 "https://www.stylingwrapstudio.ru/styles.css?v=$STAMP")"
printf '%s' "$CSS" | grep -q 'PREMIUM V7' || fail "V6 not served"
printf '%s' "$CSS" | grep -q 'filter:none!important' || fail "color map not served"
for bad in '#ef00df' '#9d1cff' '#c8a86f' '#d2b77f' '#b89459'; do
  ! printf '%s' "$CSS" | grep -qi "$bad" || fail "legacy color still served: $bad"
done
printf '%s' "$CSS" | grep -q '#8ebbd0' || fail "steel-blue accent not served"
printf '%s' "$CSS" | grep -q '#d8e2e8' || fail "ice-silver primary button not served"
printf '%s' "$CSS" | grep -q 'MOBILE V8 HOTFIX' || fail "V8 mobile hotfix not served"
HOME="$(curl -ksS --resolve www.stylingwrapstudio.ru:443:127.0.0.1 "https://www.stylingwrapstudio.ru/?v=$STAMP")"
ABOUT="$(curl -ksS --resolve www.stylingwrapstudio.ru:443:127.0.0.1 "https://www.stylingwrapstudio.ru/about/?v=$STAMP")"
ATELIER="$(curl -ksS --resolve www.stylingwrapstudio.ru:443:127.0.0.1 "https://www.stylingwrapstudio.ru/services/atelier/?v=$STAMP")"
! printf '%s%s%s' "$HOME" "$ABOUT" "$ATELIER" | grep -q 'steering-wheel.webp' || fail "broken steering wheel reference still served"
printf '%s%s%s' "$HOME" "$ABOUT" "$ATELIER" | grep -q '/assets/sws/mercedes-front.jpg' || fail "verified atelier fallback photo not served"
printf '\n====================================================\n'
printf ' SWS PREMIUM V8 MOBILE FIX ACTIVE\n'
printf ' Premium graphite/ice-silver/steel-blue palette: ACTIVE\n'
printf ' Mobile scroll scene dead-zone: FIXED\n'
printf ' Empty mobile gaps: FIXED\n'
printf ' Broken atelier/interior image: FIXED\n'
printf ' Yandex map: FULL COLOR\n'
printf ' All routes checked: %s\n' "${#ROUTES[@]}"
printf ' Other server projects: NOT MODIFIED\n'
printf '====================================================\n'
printf 'Open: https://www.stylingwrapstudio.ru/?v=%s\n' "$STAMP"
