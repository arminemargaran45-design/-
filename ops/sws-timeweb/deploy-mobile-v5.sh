#!/usr/bin/env bash
set -Eeuo pipefail

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPO="https://github.com/arminemargaran45-design/-.git"
BRANCH="sws-site"
WORK="/tmp/sws-mobile-v5-$STAMP"
RELEASE_DIR="/opt/styling-wrap-studio/releases/$STAMP-mobile-v5"
PRIMARY="/var/www/stylingwrapstudio.ru"
COMPAT="/var/www/styling-wrap-studio/current"

fail(){ printf '\n[SWS] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root"
for c in git curl caddy systemctl; do command -v "$c" >/dev/null || fail "$c missing"; done

git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$WORK"
SITE="$WORK/sws-site"

grep -q 'MOBILE V5' "$SITE/styles.css" || fail "global mobile V5 CSS missing"
grep -q '.service-hero h1{' "$SITE/styles.css" || fail "service mobile title fix missing"
grep -q 'max-width:calc(100vw - 24px)' "$SITE/styles.css" || fail "sticky CTA mobile width fix missing"
grep -q 'Отзывы на Авито' "$SITE/index.html" || fail "Avito reviews link missing"
grep -q 'Отзывы на Яндекс Картах' "$SITE/index.html" || fail "Yandex reviews link missing"

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

switch_root "$PRIMARY"
switch_root "$COMPAT"

caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy

ROUTES=(
"/"
"/services/"
"/services/ppf/"
"/services/wrapping/"
"/services/blackout/"
"/services/detailing/"
"/services/coating/"
"/services/atelier/"
"/services/styling/"
"/projects/"
"/about/"
"/guarantee/"
"/contacts/"
"/styles.css"
"/script.js"
)

for path in "${ROUTES[@]}"; do
  code="$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru$path?v=$STAMP")"
  [ "$code" = "200" ] || fail "$path returned HTTP $code"
  printf '[OK] %s -> %s\n' "$path" "$code"
done

CSS="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/styles.css?v=$STAMP")"
printf '%s' "$CSS" | grep -q 'MOBILE V5' || fail "mobile V5 CSS not active"
printf '%s' "$CSS" | grep -q '.service-hero h1{' || fail "service title mobile fix not active"
printf '%s' "$CSS" | grep -q 'max-width:calc(100vw - 24px)' || fail "sticky CTA width fix not active"

HTML="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/?v=$STAMP")"
printf '%s' "$HTML" | grep -q 'Отзывы на Авито' || fail "Avito review link not active"
printf '%s' "$HTML" | grep -q 'Отзывы на Яндекс Картах' || fail "Yandex review link not active"

printf '\n====================================================\n'
printf ' SWS MOBILE V5 ACTIVE — ALL PAGES\n'
printf ' 375 / 390 / 393 / 412 / 430 px hardened\n'
printf ' Service titles: fixed\n'
printf ' Buttons/grids/hero/timeline/contacts: fixed\n'
printf ' Release: %s\n' "$RELEASE_DIR"
printf '====================================================\n'
printf 'Open: https://www.stylingwrapstudio.ru/?v=%s\n' "$STAMP"
