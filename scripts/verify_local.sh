#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/coordgeo-backend"
FRONTEND_DIR="$ROOT_DIR/coordgeo-frontend"

BACKEND_PY="$BACKEND_DIR/venv/bin/python"
GUNICORN_PID=""
PREVIEW_PID=""

log_step() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$1"
}

die() {
  echo "ERROR: $1" >&2
  exit 1
}

cleanup() {
  if [[ -n "$PREVIEW_PID" ]] && kill -0 "$PREVIEW_PID" 2>/dev/null; then
    kill "$PREVIEW_PID" || true
  fi

  if [[ -n "$GUNICORN_PID" ]] && kill -0 "$GUNICORN_PID" 2>/dev/null; then
    kill "$GUNICORN_PID" || true
  fi
}

trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

assert_http_status() {
  local expected="$1"
  local method="$2"
  local url="$3"
  local body="${4:-}"

  local status
  if [[ -n "$body" ]]; then
    status=$(curl -s -o /tmp/coordgeo_verify_response.txt -w "%{http_code}" -X "$method" "$url" -H "Content-Type: application/json" --data "$body")
  else
    status=$(curl -s -o /tmp/coordgeo_verify_response.txt -w "%{http_code}" -X "$method" "$url")
  fi

  if [[ "$status" != "$expected" ]]; then
    echo "Falha HTTP em $method $url: esperado $expected, recebido $status"
    cat /tmp/coordgeo_verify_response.txt || true
    exit 1
  fi

  echo "OK HTTP $method $url -> $status"
}

assert_http_status_one_of() {
  local expected_csv="$1"
  local method="$2"
  local url="$3"
  local body="${4:-}"

  local status
  if [[ -n "$body" ]]; then
    status=$(curl -s -o /tmp/coordgeo_verify_response.txt -w "%{http_code}" -X "$method" "$url" -H "Content-Type: application/json" --data "$body")
  else
    status=$(curl -s -o /tmp/coordgeo_verify_response.txt -w "%{http_code}" -X "$method" "$url")
  fi

  if [[ ",${expected_csv}," != *",${status},"* ]]; then
    echo "Falha HTTP em $method $url: esperado um de [${expected_csv}], recebido $status"
    cat /tmp/coordgeo_verify_response.txt || true
    exit 1
  fi

  echo "OK HTTP $method $url -> $status"
}

log_step "Pré-check de dependências"
require_command curl
require_command psql
require_command node
require_command npm

[[ -x "$BACKEND_PY" ]] || die "Python do backend não encontrado em $BACKEND_PY"

log_step "Versões"
"$BACKEND_PY" --version
node --version
npm --version

log_step "Validação backend: migrate + check + testes"
cd "$BACKEND_DIR"
"$BACKEND_PY" manage.py migrate --noinput
"$BACKEND_PY" manage.py check
"$BACKEND_PY" run_tests.py

log_step "Subindo backend com Gunicorn para smoke"
"$BACKEND_DIR/venv/bin/gunicorn" config.wsgi:application --bind 127.0.0.1:8000 --workers 2 --timeout 120 >/tmp/coordgeo_gunicorn.log 2>&1 &
GUNICORN_PID=$!

for _ in {1..20}; do
  if curl -s -o /dev/null http://127.0.0.1:8000/api/v1/user/organizations/; then
    break
  fi
  sleep 1
done

assert_http_status "401" "GET" "http://127.0.0.1:8000/api/v1/user/organizations/"
assert_http_status_one_of "400,401" "POST" "http://127.0.0.1:8000/api/v1/token/" '{"email":"invalid@example.com","password":"invalid"}'

log_step "Validação frontend: lint + build"
cd "$FRONTEND_DIR"
npm run lint
npm run build

log_step "Subindo frontend preview para smoke"
npm run preview -- --host 127.0.0.1 --port 4173 >/tmp/coordgeo_preview.log 2>&1 &
PREVIEW_PID=$!

for _ in {1..20}; do
  if curl -s -o /dev/null http://127.0.0.1:4173/; then
    break
  fi
  sleep 1
done

assert_http_status "200" "GET" "http://127.0.0.1:4173/"

log_step "Verificação local finalizada com sucesso"
echo "Backend log: /tmp/coordgeo_gunicorn.log"
echo "Frontend log: /tmp/coordgeo_preview.log"
