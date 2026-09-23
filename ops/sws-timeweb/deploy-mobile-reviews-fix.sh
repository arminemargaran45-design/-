#!/usr/bin/env bash
set -Eeuo pipefail

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPO="https://github.com/arminemargaran45-design/-.git"
BRANCH="sws-site"
WORK="/tmp/sws-mobile-reviews-$STAMP"
RELEASE_DIR="/opt/styling-wrap-studio/releases/$STAMP-mobile-reviews"
PRIMARY="/var/www/stylingwrapstudio.ru"
COMPAT="/var/www/styling-wrap-studio/current"

fail(){ printf '\n[SWS] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root"
for c in git curl caddy systemctl; do command -v "$c" >/dev/null || fail "$c missing"; done

git clone -q --depth 1 --branch "$BRANCH" "$REPO" "$WORK"
SITE="$WORK/sws-site"

grep -q 'Отзывы на Авито' "$SITE/index.html" || fail "Avito review link missing"
grep -q 'Отзывы на Яндекс Картах' "$SITE/index.html" || fail "Yandex review link missing"
grep -q 'atelier-media.clip-reveal{clip-path:inset(0)!important}' "$SITE/styles.css" || fail "mobile blank-gap fix missing"

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

HTML="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/?v=$STAMP")"
CSS="$(curl -ksS --resolve "www.stylingwrapstudio.ru:443:127.0.0.1" "https://www.stylingwrapstudio.ru/styles.css?v=$STAMP")"

printf '%s' "$HTML" | grep -q 'Отзывы на Авито' || fail "Avito link not served"
printf '%s' "$HTML" | grep -q 'Отзывы на Яндекс Картах' || fail "Yandex link not served"
printf '%s' "$CSS" | grep -q 'atelier-media.clip-reveal{clip-path:inset(0)!important}' || fail "mobile gap fix not served"

printf '\n=============================================\n'
printf ' SWS MOBILE SPACING + REVIEWS FIX ACTIVE\n'
printf ' Release: %s\n' "$RELEASE_DIR"
printf '=============================================\n'
printf 'Open: https://www.stylingwrapstudio.ru/?v=%s\n' "$STAMP"
