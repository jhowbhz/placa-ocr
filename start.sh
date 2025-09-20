#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
LOG_LEVEL="${LOG_LEVEL:-info}"
WORKERS="${WORKERS:-1}"
ENV_FILE="${ENV_FILE:-.env}"

usage() {
    cat <<'EOF'
Uso: ./start.sh [--dev | --prod]

Flags:
  --dev   Constroi e inicia a API em modo desenvolvimento (docker compose profile dev)
  --prod  Constroi e inicia a API em modo producao (docker compose profile prod, modo detach)

Variaveis aceitas:
  HOST, PORT, LOG_LEVEL, WORKERS, ENV_FILE
EOF
}

ensure_env_file() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        echo "[warn] Arquivo ${ENV_FILE} nao encontrado; prosseguindo sem carregar env_file." >&2
    fi
}

resolve_compose() {
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD=(docker-compose)
    else
        echo "Docker Compose nao encontrado. Instale Docker Desktop ou o plugin docker compose." >&2
        exit 1
    fi
}

export_runtime_env() {
    export HOST PORT LOG_LEVEL WORKERS ENV_FILE
}

start_dev() {
    export_runtime_env
    ensure_env_file
    "${DOCKER_COMPOSE_CMD[@]}" --profile dev up --build
}

start_prod() {
    export_runtime_env
    ensure_env_file
    "${DOCKER_COMPOSE_CMD[@]}" --profile prod up --build -d
    local compose_display="${DOCKER_COMPOSE_CMD[*]}"
    echo "API iniciada em modo producao. Execute '${compose_display} --profile prod logs -f api' para acompanhar logs."
}

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

resolve_compose

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
