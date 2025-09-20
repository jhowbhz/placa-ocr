#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-server}"
APP_MODULE="${APP_MODULE:-app.main:app}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
LOG_LEVEL="${LOG_LEVEL:-info}"
WORKERS="${WORKERS:-1}"
RELOAD_FLAG="${UVICORN_RELOAD:-0}"

if [[ "${MODE}" == "dev" ]]; then
    exec uvicorn "${APP_MODULE}" \
        --host "${HOST}" \
        --port "${PORT}" \
        --log-level "${LOG_LEVEL}" \
        --reload
fi

if [[ "${MODE}" == "server" ]]; then
    if [[ "${RELOAD_FLAG}" == "1" ]]; then
        exec uvicorn "${APP_MODULE}" \
            --host "${HOST}" \
            --port "${PORT}" \
            --log-level "${LOG_LEVEL}" \
            --reload
    fi

    exec uvicorn "${APP_MODULE}" \
        --host "${HOST}" \
        --port "${PORT}" \
        --log-level "${LOG_LEVEL}" \
        --workers "${WORKERS}"
fi

exec "$@"
