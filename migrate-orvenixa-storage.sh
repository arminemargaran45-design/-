#!/usr/bin/env bash
set -Eeuo pipefail

umask 077
: "${MIGRATION_TOKEN:?MIGRATION_TOKEN is required}"

SUPABASE_DIR="/opt/orvenixa/supabase"
cd "${SUPABASE_DIR}"

read_env_value() {
  local key="$1"
  sed -n -E "s/^${key}=(.*)$/\\1/p" .env | tail -n 1 | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

SERVICE_KEY="$(read_env_value SERVICE_ROLE_KEY)"
if [[ -z "${SERVICE_KEY}" ]]; then
  SERVICE_KEY="$(read_env_value SUPABASE_SECRET_KEY)"
fi
if [[ -z "${SERVICE_KEY}" ]]; then
  echo "Не найден локальный серверный ключ Storage"
  exit 1
fi

export SERVICE_KEY MIGRATION_TOKEN
python3 <<'PY'
import hashlib
import json
import os
import urllib.parse
import urllib.request

manifest_url = "https://hfcwgsnhwbloksifsgbz.supabase.co/functions/v1/timeweb-storage-export"
request = urllib.request.Request(
    manifest_url,
    headers={"x-migration-token": os.environ["MIGRATION_TOKEN"]},
)
with urllib.request.urlopen(request, timeout=30) as response:
    manifest = json.load(response)

objects = manifest.get("objects") or []
if len(objects) != 4:
    raise RuntimeError(f"Ожидалось 4 файла, получено {len(objects)}")

for index, item in enumerate(objects, start=1):
    with urllib.request.urlopen(item["signedUrl"], timeout=120) as source:
        body = source.read()

    path = urllib.parse.quote(item["name"], safe="/")
    destination = f"http://127.0.0.1:8000/storage/v1/object/{item['bucket']}/{path}"
    upload = urllib.request.Request(
        destination,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {os.environ['SERVICE_KEY']}",
            "apikey": os.environ["SERVICE_KEY"],
            "Content-Type": item.get("contentType") or "application/octet-stream",
            "x-upsert": "true",
        },
    )
    with urllib.request.urlopen(upload, timeout=120) as response:
        if response.status not in (200, 201):
            raise RuntimeError(f"Storage upload HTTP {response.status}")

    digest = hashlib.sha256(body).hexdigest()[:12]
    print(f"[{index}/4] {item['bucket']}/{item['name']} — {len(body)} bytes — sha256:{digest}")
PY
unset SERVICE_KEY MIGRATION_TOKEN

OBJECT_COUNT="$(docker compose exec -T db psql -U postgres -d postgres -Atqc 'select count(*) from storage.objects')"
if [[ "${OBJECT_COUNT}" != "4" ]]; then
  echo "Ожидалось 4 объекта в локальном Storage, найдено ${OBJECT_COUNT}"
  exit 1
fi

echo "storage_objects=${OBJECT_COUNT}"
echo "STORAGE_MIGRATION_COMPLETE"
