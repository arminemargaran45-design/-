#!/usr/bin/env bash
set -euo pipefail

APP_NAME="styling-wrap-studio"
REPO_URL="https://github.com/arminemargaran45-design/-.git"
BRANCH="sws-site"
SRC_DIR="${SRC_DIR:-/opt/${APP_NAME}/source}"
RELEASE_ROOT="${RELEASE_ROOT:-/opt/${APP_NAME}/releases}"
WEB_ROOT="${WEB_ROOT:-/var/www/${APP_NAME}}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root" >&2
  exit 1
fi

if [ ! -d "${SRC_DIR}/.git" ]; then
  mkdir -p "$(dirname "${SRC_DIR}")"
  git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${SRC_DIR}"
fi

cd "${SRC_DIR}"
git fetch origin "${BRANCH}" --prune
git checkout "${BRANCH}"
git pull --ff-only origin "${BRANCH}"

if [ ! -f "${SRC_DIR}/sws-site/index.html" ]; then
  echo "SWS static site not found at ${SRC_DIR}/sws-site" >&2
  exit 1
fi

SHA="$(git rev-parse --short=12 HEAD)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RELEASE_DIR="${RELEASE_ROOT}/${STAMP}-${SHA}"

mkdir -p "${RELEASE_DIR}" "${WEB_ROOT}"
cp -a "${SRC_DIR}/sws-site/." "${RELEASE_DIR}/"
ln -sfn "${RELEASE_DIR}" "${WEB_ROOT}/current"

echo "Deployed ${APP_NAME} commit ${SHA}"
echo "Web root: ${WEB_ROOT}/current"
echo "Next: merge ops/sws-timeweb/Caddyfile.sws into /etc/caddy/Caddyfile, validate, then reload Caddy."
