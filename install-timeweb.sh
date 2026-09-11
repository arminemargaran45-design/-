#!/usr/bin/env bash
set -Eeuo pipefail

SITE_DIR="/var/www/arminee.ru"
TMP_DIR="$(mktemp -d)"
BACKUP_DIR="/var/backups/arminee.ru-$(date +%Y%m%d-%H%M%S)"
BASE_URL="https://raw.githubusercontent.com/arminemargaran45-design/-/arminee-portfolio/arminee-parts"

cleanup() {
  rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/parts" "$TMP_DIR/site"
for part in part-00 part-01 part-02 part-03; do
  wget -q --tries=4 --timeout=30 -O "$TMP_DIR/parts/$part" "$BASE_URL/$part"
done

cat "$TMP_DIR"/parts/part-* > "$TMP_DIR/arminee.tar.gz"
tar -xzf "$TMP_DIR/arminee.tar.gz" -C "$TMP_DIR/site"
test -s "$TMP_DIR/site/index.html"

if [ -d "$SITE_DIR" ] && [ -n "$(find "$SITE_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  mkdir -p "$BACKUP_DIR"
  cp -a "$SITE_DIR/." "$BACKUP_DIR/"
fi

install -d -m 755 "$SITE_DIR"
find "$SITE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
cp -a "$TMP_DIR/site/." "$SITE_DIR/"
chown -R root:root "$SITE_DIR"
find "$SITE_DIR" -type d -exec chmod 755 {} +
find "$SITE_DIR" -type f -exec chmod 644 {} +

caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
test -s "$SITE_DIR/index.html"

echo "ГОТОВО: файлы установлены, Caddy перезапущен — откройте https://arminee.ru"
