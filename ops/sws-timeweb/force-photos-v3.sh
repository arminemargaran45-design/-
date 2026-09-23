#!/usr/bin/env bash
set -Eeuo pipefail

APP="styling-wrap-studio"
REPO="https://github.com/arminemargaran45-design/-.git"
BRANCH="sws-site"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="/tmp/sws-force-photos-${STAMP}"
STAGE="${WORK}/stage"
RELEASE_ROOT="/opt/${APP}/releases"
RELEASE_DIR="${RELEASE_ROOT}/${STAMP}-photos-v3"
CADDYFILE="/etc/caddy/Caddyfile"
MARKER="SWS-PHOTOS-V3-20260923"

log(){ printf '\n[SWS] %s\n' "$*"; }
fail(){ printf '\n[SWS] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root"
command -v git >/dev/null || fail "git is required"
command -v curl >/dev/null || fail "curl is required"
command -v python3 >/dev/null || fail "python3 is required"
command -v caddy >/dev/null || fail "caddy is required"

log "Cloning latest SWS source"
git clone -q --depth 1 --branch "${BRANCH}" "${REPO}" "${WORK}/repo"
mkdir -p "${STAGE}"
cp -a "${WORK}/repo/sws-site/." "${STAGE}/"
mkdir -p "${STAGE}/assets/sws"

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/150 Safari/537.36"
REF="https://uslugi.yandex.ru/profile/StylingWrapStudio-1310152"

download_photo() {
  local url="$1" out="$2"
  log "Downloading $(basename "${out}")"
  curl -L --fail --silent --show-error --retry 3 --connect-timeout 15 --max-time 90 \
    -A "${UA}" -e "${REF}" "${url}" -o "${out}"
  local bytes
  bytes="$(wc -c < "${out}" | tr -d ' ')"
  [ "${bytes}" -gt 15000 ] || fail "Downloaded image is too small: ${out} (${bytes} bytes)"
}

download_photo "https://avatars.mds.yandex.net/get-ydo/11374192/2a0000018bce8166d612e82cb611d3281d36/diploma" "${STAGE}/assets/sws/range-rover.jpg"
download_photo "https://avatars.mds.yandex.net/get-ydo/4498943/2a0000018bcdb9fc5129290b5e9e17b3b5e3/diploma" "${STAGE}/assets/sws/mercedes-front.jpg"
download_photo "https://avatars.mds.yandex.net/get-ydo/11397567/2a0000018bcdba6878b9b769fdbec80fda64/diploma" "${STAGE}/assets/sws/mercedes-rear.jpg"
download_photo "https://avatars.mds.yandex.net/get-ydo/5575550/2a0000018bcd8524e296b1fad242e1352812/diploma" "${STAGE}/assets/sws/mercedes-lime.jpg"
download_photo "https://avatars.mds.yandex.net/get-ydo/4079136/2a0000018bcd7a63d59823c8e8f112273d7f/diploma" "${STAGE}/assets/sws/lexus.jpg"
download_photo "https://avatars.mds.yandex.net/get-ydo/4219998/2a0000018bc9a9d420f5b390918d9f4fc818/diploma" "${STAGE}/assets/sws/audi-q7.jpg"
download_photo "https://avatars.mds.yandex.net/get-ydo/4498943/2a00000182cd198a7c78a4b115d8c4de8fe2/diploma" "${STAGE}/assets/sws/mustang.jpg"

log "Rewriting site to LOCAL photo paths"
python3 - "${STAGE}" "${MARKER}" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); marker=sys.argv[2]
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
    for a,b in mapping.items(): s=s.replace(a,b)
    if marker not in s:
        s=s.replace("<head>",f"<head><!-- {marker} -->",1)
    p.write_text(s,encoding="utf-8")

needed=[
("index.html","/assets/sws/"),
("services/index.html","/assets/sws/"),
("projects/index.html","/assets/sws/"),
]
for rel,needle in needed:
    p=root/rel
    if not p.exists(): raise SystemExit(f"missing {rel}")
    s=p.read_text(encoding="utf-8")
    if needle not in s: raise SystemExit(f"local photos not referenced in {rel}")
PY

log "Creating immutable release"
mkdir -p "${RELEASE_DIR}"
cp -a "${STAGE}/." "${RELEASE_DIR}/"

log "Discovering the ACTIVE SWS web roots from Caddy"
mapfile -t ROOTS < <(python3 - "${CADDYFILE}" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1])
text=p.read_text(errors="ignore").splitlines()
roots=[]
i=0
while i<len(text):
    line=text[i]
    if "stylingwrapstudio.ru" in line and "{" in line:
        depth=line.count("{")-line.count("}")
        block=[line]; i+=1
        while i<len(text) and depth>0:
            block.append(text[i])
            depth+=text[i].count("{")-text[i].count("}")
            i+=1
        for b in block:
            m=re.search(r'^\s*root\s+\*\s+(\S+)',b)
            if m: roots.append(m.group(1))
        continue
    i+=1
for r in dict.fromkeys(roots): print(r)
PY
)

# Known roots used in previous SWS deployments.
ROOTS+=("/var/www/styling-wrap-studio/current" "/var/www/stylingwrapstudio.ru")

switch_root(){
  local target="$1"
  [ -n "${target}" ] || return 0
  mkdir -p "$(dirname "${target}")"
  if [ -L "${target}" ]; then
    ln -sfn "${RELEASE_DIR}" "${target}.new"
    mv -Tf "${target}.new" "${target}"
  elif [ -e "${target}" ]; then
    mv "${target}" "${target}.backup-${STAMP}"
    ln -s "${RELEASE_DIR}" "${target}"
  else
    ln -s "${RELEASE_DIR}" "${target}"
  fi
  log "Activated: ${target} -> ${RELEASE_DIR}"
}

# Deduplicate and activate every SWS root only.
declare -A seen=()
for r in "${ROOTS[@]}"; do
  [ -n "${r}" ] || continue
  if [ -z "${seen[${r}]+x}" ]; then
    seen["${r}"]=1
    switch_root "${r}"
  fi
done

log "Validating and reloading Caddy"
caddy validate --config "${CADDYFILE}"
systemctl reload caddy

log "Forcing server-side verification"
for host in stylingwrapstudio.ru www.stylingwrapstudio.ru; do
  body="$(curl -ksS --resolve "${host}:443:127.0.0.1" "https://${host}/services/index.html?v=${STAMP}")"
  printf '%s' "${body}" | grep -q "${MARKER}" || fail "${host} is still serving OLD HTML"
  code="$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "${host}:443:127.0.0.1" "https://${host}/assets/sws/range-rover.jpg?v=${STAMP}")"
  [ "${code}" = "200" ] || fail "${host} photo returned HTTP ${code}"
done

printf '\n===============================================\n'
printf ' SWS FIXED: NEW PHOTOS ARE ACTIVE ON TIMEWEB\n'
printf ' Marker: %s\n' "${MARKER}"
printf ' Release: %s\n' "${RELEASE_DIR}"
printf '===============================================\n'
printf 'Check: https://www.stylingwrapstudio.ru/services/index.html?v=%s\n' "${STAMP}"
printf 'Check: https://www.stylingwrapstudio.ru/projects/?v=%s\n' "${STAMP}"
printf 'ORVENIXA, Supabase and MedAlliance were not modified.\n'
