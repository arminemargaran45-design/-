#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

: "${SRC_DB_PASSWORD:?SRC_DB_PASSWORD is required}"

PROJECT_REF="hfcwgsnhwbloksifsgbz"
EXPORT_ROLE="orvenixa_timeweb_export"
DIRECT_HOST="db.${PROJECT_REF}.supabase.co"
POOLER_HOST="aws-0-eu-central-1.pooler.supabase.com"
CLI_VERSION="2.81.3"
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

echo "[2/6] Установка совместимого Supabase CLI"
if ! command -v supabase >/dev/null 2>&1; then
  wget -qO "${WORK_DIR}/supabase-cli.tar.gz" \
    "https://github.com/supabase/cli/releases/download/v${CLI_VERSION}/supabase_linux_amd64.tar.gz"
  tar -xzf "${WORK_DIR}/supabase-cli.tar.gz" -C /usr/local/bin supabase
  chmod 0755 /usr/local/bin/supabase
fi
supabase --version
supabase db dump --help >/dev/null

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

SOURCE_URL="postgresql://${SOURCE_USER}:${SRC_DB_PASSWORD}@${SOURCE_HOST}:5432/postgres?sslmode=require"

echo "[4/6] Создание совместимого резервного комплекта"
supabase db dump --db-url "${SOURCE_URL}" -f "${WORK_DIR}/roles.sql" --role-only
supabase db dump --db-url "${SOURCE_URL}" -f "${WORK_DIR}/schema.sql"
supabase db dump --db-url "${SOURCE_URL}" -f "${WORK_DIR}/data.sql" --use-copy --data-only
unset SOURCE_URL SRC_DB_PASSWORD

for file in roles.sql schema.sql data.sql; do
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
  cat "${WORK_DIR}/roles.sql"
  cat "${WORK_DIR}/schema.sql"
  echo "SET session_replication_role = replica;"
  cat "${WORK_DIR}/data.sql"
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
          'platform_leads='||(select count(*) from public.platform_leads);"

echo "Резервная копия сохранена: ${WORK_DIR}"
echo "MIGRATION_STAGE_1_COMPLETE"
