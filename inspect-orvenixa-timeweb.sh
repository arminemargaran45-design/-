#!/usr/bin/env bash
set -Eeuo pipefail

COMPOSE_DIR="/opt/orvenixa/supabase"

echo "=== ORVENIXA TIMEWEB READ-ONLY CHECK ==="
date -u +"UTC: %Y-%m-%d %H:%M:%S"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed"
  exit 2
fi

echo
echo "[Docker]"
docker --version
docker compose version || true

if [ ! -d "$COMPOSE_DIR" ]; then
  echo "ERROR: $COMPOSE_DIR not found"
  exit 3
fi

cd "$COMPOSE_DIR"

echo
echo "[Compose files]"
find . -maxdepth 1 -type f \( -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' -o -name 'compose*.yml' -o -name 'compose*.yaml' \) -printf '%f\n' | sort

echo
echo "[Containers]"
docker compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Health}}\t{{.Ports}}' || docker compose ps

echo
echo "[Configuration keys present — values hidden]"
if [ -f .env ]; then
  grep -E '^(SITE_URL|API_EXTERNAL_URL|SUPABASE_PUBLIC_URL|POSTGRES_PORT|KONG_HTTP_PORT|JWT_EXPIRY|ENABLE_EMAIL_SIGNUP|ENABLE_PHONE_SIGNUP)=' .env     | cut -d= -f1 | sort -u
else
  echo "WARN: .env not found"
fi

DB_CONTAINER="$(docker compose ps -q db 2>/dev/null || true)"
if [ -n "$DB_CONTAINER" ]; then
  echo
  echo "[Local database counts]"
  docker exec "$DB_CONTAINER" sh -lc '
    export PGPASSWORD="$POSTGRES_PASSWORD"
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At <<SQL
select '"'"'auth_users='"'"' || count(*) from auth.users;
select '"'"'profiles='"'"' || count(*) from public.profiles;
select '"'"'organizations='"'"' || count(*) from public.organizations;
select '"'"'platform_leads='"'"' || count(*) from public.platform_leads;
SQL
  ' || echo "WARN: database query failed"
else
  echo "WARN: db container not running"
fi

echo
echo "[Local HTTP health]"
for url in   http://127.0.0.1:8000/auth/v1/health   http://127.0.0.1:8000/rest/v1/   http://127.0.0.1:3000
do
  code="$(wget -q --server-response --spider "$url" 2>&1 | awk '/HTTP\/{c=$2} END{print c}')"
  echo "$url -> HTTP ${code:-unreachable}"
done

echo
echo "[Caddy ORVENIXA routes]"
if [ -f /etc/caddy/Caddyfile ]; then
  grep -nE 'orvenixa\.ru|supabase\.orvenixa\.ru|api\.orvenixa\.ru|root \*|reverse_proxy' /etc/caddy/Caddyfile || true
else
  echo "WARN: /etc/caddy/Caddyfile not found"
fi

echo
echo "[Capacity]"
df -h / /opt 2>/dev/null | awk 'NR==1 || !seen[$6]++'
free -h | sed -n '1,2p'

echo
echo "CHECK_COMPLETE"
