#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

: "${SRC_DB_PASSWORD:?SRC_DB_PASSWORD is required}"

PROJECT_REF="hfcwgsnhwbloksifsgbz"
EXPORT_ROLE="orvenixa_timeweb_export"
DIRECT_HOST="db.${PROJECT_REF}.supabase.co"
POOLER_HOST="aws-0-eu-central-1.pooler.supabase.com"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/opt/orvenixa/backups"
WORK_DIR="${BACKUP_ROOT}/cloud-${STAMP}"
SUPABASE_DIR="/opt/orvenixa/supabase"

fail() {
  echo "MIGRATION_FAILED"
  echo "Диагностика и резервные файлы: ${WORK_DIR}"
}
trap fail ERR

if [[ ! -d "${SUPABASE_DIR}" ]]; then
  echo "Не найдена папка ${SUPABASE_DIR}"
  exit 1
fi

command -v docker >/dev/null
docker compose version >/dev/null
mkdir -p "${WORK_DIR}"
cd "${SUPABASE_DIR}"

echo "[1/6] Проверка приемника Timeweb"
docker compose ps --status running --services | sort > "${WORK_DIR}/running-services.txt"
for service in db auth rest storage realtime; do
  grep -qx "${service}" "${WORK_DIR}/running-services.txt" || {
    echo "Не запущен контейнер ${service}"
    exit 1
  }
done

echo "[2/6] Подготовка PostgreSQL 17 для совместимого дампа"
docker pull postgres:17-alpine >/dev/null

echo "[3/6] Подключение к действующей облачной базе только для чтения"
test_source() {
  local host="$1"
  local user="$2"
  docker run --rm --network host \
    -e PGPASSWORD="${SRC_DB_PASSWORD}" \
    postgres:17-alpine \
    psql "host=${host} port=5432 dbname=postgres user=${user} sslmode=require connect_timeout=12" \
    -v ON_ERROR_STOP=1 -Atqc "select count(*) from auth.users" 2>/dev/null
}

if SOURCE_USERS="$(test_source "${DIRECT_HOST}" "${EXPORT_ROLE}")"; then
  SOURCE_HOST="${DIRECT_HOST}"
  SOURCE_USER="${EXPORT_ROLE}"
elif SOURCE_USERS="$(test_source "${POOLER_HOST}" "${EXPORT_ROLE}.${PROJECT_REF}")"; then
  SOURCE_HOST="${POOLER_HOST}"
  SOURCE_USER="${EXPORT_ROLE}.${PROJECT_REF}"
else
  echo "Не удалось подключиться к Supabase Cloud"
  exit 1
fi
echo "Источник доступен. Пользователей: ${SOURCE_USERS}"

pg_dump_source() {
  docker run --rm --network host \
    -e PGPASSWORD="${SRC_DB_PASSWORD}" \
    -v "${WORK_DIR}:/backup" \
    postgres:17-alpine \
    pg_dump \
    --host="${SOURCE_HOST}" \
    --port=5432 \
    --username="${SOURCE_USER}" \
    --dbname=postgres \
    --no-owner \
    --no-privileges \
    --quote-all-identifiers \
    "$@"
}

echo "[4/6] Создание резервного комплекта без SET ROLE postgres"
pg_dump_source --schema=public --schema-only --file=/backup/schema-public.sql
pg_dump_source --schema=public --data-only --disable-triggers --file=/backup/data-public.sql
pg_dump_source --table=auth.users --table=auth.identities \
  --data-only --disable-triggers --file=/backup/data-auth.sql
pg_dump_source --table=storage.buckets \
  --data-only --disable-triggers --file=/backup/data-storage-buckets.sql
pg_dump_source --table=storage.objects \
  --data-only --disable-triggers --file=/backup/data-storage-objects-pending.sql
unset SRC_DB_PASSWORD

# The default public schema may be represented as a comment by pg_dump.
# Recreate it explicitly during restore and remove any duplicate CREATE line.
sed -i -E '/^CREATE SCHEMA ("public"|public);$/d' "${WORK_DIR}/schema-public.sql"

for file in schema-public.sql data-public.sql data-auth.sql data-storage-buckets.sql data-storage-objects-pending.sql; do
  [[ -s "${WORK_DIR}/${file}" ]] || {
    echo "Пустой файл ${file}"
    exit 1
  }
done
sha256sum "${WORK_DIR}"/*.sql > "${WORK_DIR}/SHA256SUMS"

echo "[5/6] Локальная контрольная копия и восстановление одной транзакцией"
docker compose exec -T db pg_dump \
  -U postgres -d postgres --schema=public --format=custom \
  > "${WORK_DIR}/timeweb-public-before.dump"

{
  echo "DROP SCHEMA IF EXISTS public CASCADE;"
  echo "CREATE SCHEMA public AUTHORIZATION pg_database_owner;"
  cat "${WORK_DIR}/schema-public.sql"
  echo "TRUNCATE TABLE auth.identities, auth.users CASCADE;"
  echo "TRUNCATE TABLE storage.objects, storage.buckets CASCADE;"
  echo "SET session_replication_role = replica;"
  cat "${WORK_DIR}/data-auth.sql"
  cat "${WORK_DIR}/data-storage-buckets.sql"
  cat "${WORK_DIR}/data-public.sql"
  echo "SET session_replication_role = origin;"
} | docker compose exec -T db psql \
  --single-transaction \
  --variable ON_ERROR_STOP=1 \
  -U postgres -d postgres

echo "[6/6] Перезапуск сервисов и проверка данных"
docker compose restart auth rest realtime storage >/dev/null
sleep 8
docker compose exec -T db psql -U postgres -d postgres -Atqc \
  "select 'auth_users='||(select count(*) from auth.users),
          'profiles='||(select count(*) from public.profiles),
          'organizations='||(select count(*) from public.organizations),
          'platform_leads='||(select count(*) from public.platform_leads),
          'storage_buckets='||(select count(*) from storage.buckets);"

echo "Резервная копия сохранена: ${WORK_DIR}"
echo "MIGRATION_STAGE_1_COMPLETE"
echo "Примечание: 4 закрытых файла Storage будут перенесены отдельным безопасным этапом."
