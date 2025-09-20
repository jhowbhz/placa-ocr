#!/usr/bin/env bash
set -euo pipefail

APP_MODULE="app.main:app"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
LOG_LEVEL="${LOG_LEVEL:-info}"
WORKERS="${WORKERS:-1}"
ENV_FILE="${ENV_FILE:-.env}"

usage() {
    cat <<EOF
Uso: ./start.sh [--dev | --prod]

Flags:
  --dev   Inicia a API em modo desenvolvimento (uvicorn --reload)
  --prod  Inicia a API em modo producao (uvicorn multiprocess)

Variaveis aceitas:
  HOST, PORT, LOG_LEVEL, WORKERS, ENV_FILE
EOF
}

start_dev() {
    exec python -m uvicorn "${APP_MODULE}" \
        --host "${HOST}" \
        --port "${PORT}" \
        --log-level "${LOG_LEVEL}" \
        --reload \
        --env-file "${ENV_FILE}"
}

start_prod() {
    exec python -m uvicorn "${APP_MODULE}" \
        --host "${HOST}" \
        --port "${PORT}" \
        --log-level "${LOG_LEVEL}" \
        --workers "${WORKERS}"
}

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

case "$1" in
    --dev)
        start_dev
        ;;
    --prod)
        start_prod
        ;;
    *)
        usage
        exit 1
        ;;
esac
