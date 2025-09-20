#!/usr/bin/env bash
set -euo pipefail

############################################
# init.sh — Treino YOLO (Windows Bash OK) #
############################################

# Função para criar diretórios recursivamente (Windows-friendly)
mkd() {
  # uso: mkd caminho/para/criar
  # tenta mkdir -p; se falhar, usa Python para criar recursivamente
  local d="$1"
  if ! mkdir -p "$d" 2>/dev/null; then
    "$PYTHON_BIN" - <<PY
from pathlib import Path
Path(r"$d").mkdir(parents=True, exist_ok=True)
PY
  fi
}

usage() {
    cat <<'EOF'
Usage: ./init.sh [--skip-training] [--force-download] [-h|--help]

Flags:
  --skip-training     Prepara ambiente e dataset sem treinar o modelo.
  --force-download    Baixa novamente o dataset, sobrescrevendo arquivos existentes.
  -h, --help          Mostra esta ajuda.

Variáveis de ambiente (principais):
  # Ambiente / dependências
  PYTHON_BIN=python3|python
  VENV_DIR=.venv
  REQUIREMENTS_FILE=requirements.txt

  # Dados / dataset
  DATA_DIR=data
  DATASET_URL=https://prod-dcd-datasets-cache-zipfiles.s3.eu-west-1.amazonaws.com/nx9xbs4rgx-2.zip
  DATASET_ZIP_NAME=artificial-mercosur.zip
  EXTRACT_ROOT=$DATA_DIR/raw/extracted
  YOLO_DATASET_NAME=mercosur-license-plates
  YOLO_SPLIT_SEED=42

  # Artefatos / saída
  ARTIFACTS_DIR=artifacts
  MODEL_OUTPUT_NAME=license-plate.pt
  YOLO_RUN_NAME=mercosur

  # Perfil de treino
  # PROFILE=fast | max | custom
  PROFILE=custom

  # Hiperparâmetros (podem ser sobrescritos por env)
  BASE_MODEL=yolov8s.pt            # (fast) -> yolov8s.pt | (max) -> yolov8m.pt
  TRAIN_EPOCHS=100                 # (fast) 100 | (max) 150
  TRAIN_IMAGE_SIZE=960             # (fast) 960 | (max) 1280
  TRAIN_BATCH=-1                   # -1 = auto-batch
  TRAIN_WORKERS=8
  TRAIN_CACHE=ram                  # ram|disk|False
  TRAIN_AMP=True
  TRAIN_OPTIMIZER=AdamW
  TRAIN_LR0=0.002
  TRAIN_LRF=0.1
  TRAIN_MOMENTUM=0.9
  TRAIN_WD=0.0005
  TRAIN_WARMUP_E=3
  TRAIN_COSLR=True
  TRAIN_PATIENCE=50
  TRAIN_PLOTS=True

  # Augmentações
  TRAIN_MOSAIC=1.0
  TRAIN_COPYPASTE=0.1
  TRAIN_MIXUP=0.05
  TRAIN_HSV_H=0.015
  TRAIN_HSV_S=0.7
  TRAIN_HSV_V=0.4
  TRAIN_DEGREES=5.0
  TRAIN_TRANSLATE=0.1
  TRAIN_SCALE=0.5
  TRAIN_SHEAR=2.0
  TRAIN_PERSPECTIVE=0.0005

  # Dispositivo (auto detecta; se quiser forçar CPU/GPU, use TRAIN_DEVICE=cpu|0|0,1)
  TRAIN_DEVICE=auto
  CUDA_VISIBLE_DEVICES           # opcional
  PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:128"

Dicas:
  - PROFILE=fast ./init.sh
  - PROFILE=max  ./init.sh
  - Se faltar VRAM: reduza TRAIN_IMAGE_SIZE (960->896) ou fixe TRAIN_BATCH (16/8).
EOF
}

log() { printf "[init] %s\n" "$1"; }
fail() { printf "[init] ERRO: %s\n" "$1" >&2; exit 1; }

# ============================
# Variáveis base com defaults
# ============================
PYTHON_BIN=${PYTHON_BIN:-python}
# Tenta encontrar python3 ou python (Windows-friendly)
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
  else
    fail "Python não encontrado. Instale Python 3.x e verifique se está no PATH."
  fi
fi

VENV_DIR=${VENV_DIR:-.venv}
REQUIREMENTS_FILE=${REQUIREMENTS_FILE:-requirements.txt}

DATA_DIR=${DATA_DIR:-data}
DATASET_URL=${DATASET_URL:-https://prod-dcd-datasets-cache-zipfiles.s3.eu-west-1.amazonaws.com/nx9xbs4rgx-2.zip}
DATASET_ZIP_NAME=${DATASET_ZIP_NAME:-artificial-mercosur.zip}
EXTRACT_ROOT=${EXTRACT_ROOT:-$DATA_DIR/raw/extracted}
YOLO_DATASET_NAME=${YOLO_DATASET_NAME:-mercosur-license-plates}
YOLO_SPLIT_SEED=${YOLO_SPLIT_SEED:-42}

ARTIFACTS_DIR=${ARTIFACTS_DIR:-artifacts}
MODEL_OUTPUT_NAME=${MODEL_OUTPUT_NAME:-license-plate.pt}
YOLO_RUN_NAME=${YOLO_RUN_NAME:-mercosur}

PROFILE=${PROFILE:-custom}

# ============================
# Defaults de hiperparâmetros
# ============================
BASE_MODEL=${BASE_MODEL:-yolov8s.pt}
TRAIN_EPOCHS=${TRAIN_EPOCHS:-100}
TRAIN_IMAGE_SIZE=${TRAIN_IMAGE_SIZE:-960}
TRAIN_BATCH=${TRAIN_BATCH:--1}
TRAIN_WORKERS=${TRAIN_WORKERS:-8}
TRAIN_CACHE=${TRAIN_CACHE:-ram}
TRAIN_AMP=${TRAIN_AMP:-True}
TRAIN_OPTIMIZER=${TRAIN_OPTIMIZER:-AdamW}
TRAIN_LR0=${TRAIN_LR0:-0.002}
TRAIN_LRF=${TRAIN_LRF:-0.1}
TRAIN_MOMENTUM=${TRAIN_MOMENTUM:-0.9}
TRAIN_WD=${TRAIN_WD:-0.0005}
TRAIN_WARMUP_E=${TRAIN_WARMUP_E:-3}
TRAIN_COSLR=${TRAIN_COSLR:-True}
TRAIN_PATIENCE=${TRAIN_PATIENCE:-50}
TRAIN_PLOTS=${TRAIN_PLOTS:-True}

TRAIN_MOSAIC=${TRAIN_MOSAIC:-1.0}
TRAIN_COPYPASTE=${TRAIN_COPYPASTE:-0.1}
TRAIN_MIXUP=${TRAIN_MIXUP:-0.05}
TRAIN_HSV_H=${TRAIN_HSV_H:-0.015}
TRAIN_HSV_S=${TRAIN_HSV_S:-0.7}
TRAIN_HSV_V=${TRAIN_HSV_V:-0.4}
TRAIN_DEGREES=${TRAIN_DEGREES:-5.0}
TRAIN_TRANSLATE=${TRAIN_TRANSLATE:-0.1}
TRAIN_SCALE=${TRAIN_SCALE:-0.5}
TRAIN_SHEAR=${TRAIN_SHEAR:-2.0}
TRAIN_PERSPECTIVE=${TRAIN_PERSPECTIVE:-0.0005}

TRAIN_DEVICE=${TRAIN_DEVICE:-auto}
CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-}
PYTORCH_CUDA_ALLOC_CONF=${PYTORCH_CUDA_ALLOC_CONF:-max_split_size_mb:128}

# ============================
# Perfis (override amigável)
# ============================
case "$PROFILE" in
  fast)
    BASE_MODEL=${BASE_MODEL:-yolov8s.pt}
    TRAIN_EPOCHS=${TRAIN_EPOCHS:-100}
    TRAIN_IMAGE_SIZE=${TRAIN_IMAGE_SIZE:-960}
    TRAIN_BATCH=${TRAIN_BATCH:--1}
    ;;
  max)
    BASE_MODEL=${BASE_MODEL:-yolov8m.pt}
    TRAIN_EPOCHS=${TRAIN_EPOCHS:-150}
    TRAIN_IMAGE_SIZE=${TRAIN_IMAGE_SIZE:-1280}
    TRAIN_BATCH=${TRAIN_BATCH:--1}
    TRAIN_COPYPASTE=${TRAIN_COPYPASTE:-0.2}
    TRAIN_MIXUP=${TRAIN_MIXUP:-0.1}
    TRAIN_WD=${TRAIN_WD:-0.0007}
    ;;
  custom) : ;;
  *) log "AVISO: PROFILE desconhecido: $PROFILE (usando 'custom')" ;;
esac

# ============================
# Parse de flags
# ============================
FORCE_DOWNLOAD=0
SKIP_TRAINING=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-download) FORCE_DOWNLOAD=1 ;;
    --skip-training)  SKIP_TRAINING=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "flag desconhecida: $1" ;;
  esac
  shift
done

# ============================
# Pré-checagens
# ============================
[[ -f "$REQUIREMENTS_FILE" ]] || fail "Execute a partir da raiz do projeto (faltou $REQUIREMENTS_FILE)."
command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "Python não encontrado (PYTHON_BIN=$PYTHON_BIN)."

# ============================
# Virtualenv (Windows-friendly)
# ============================
if [[ ! -d "$VENV_DIR" ]]; then
  log "Criando ambiente virtual em $VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR" || fail "Falha ao criar o ambiente virtual."
fi

# Priorize Scripts/activate (Windows), depois bin/activate (Unix)
if [[ -f "$VENV_DIR/Scripts/activate" ]]; then
  ACTIVATE_SCRIPT="$VENV_DIR/Scripts/activate"
elif [[ -f "$VENV_DIR/bin/activate" ]]; then
  ACTIVATE_SCRIPT="$VENV_DIR/bin/activate"
else
  fail "Não foi possível localizar o script de ativação do virtualenv."
fi
# shellcheck disable=SC1090
# Use . (dot) para compatibilidade com Git Bash no Windows
. "$ACTIVATE_SCRIPT" || fail "Falha ao ativar o ambiente virtual."

log "Atualizando pip"
"$PYTHON_BIN" -m pip install --upgrade pip >/dev/null || fail "Falha ao atualizar pip."
log "Instalando dependências"
"$PYTHON_BIN" -m pip install -r "$REQUIREMENTS_FILE" || fail "Falha ao instalar dependências."

# ============================
# Download / Extração dataset
# ============================
mkd "$DATA_DIR/raw"
ZIP_PATH="$DATA_DIR/raw/$DATASET_ZIP_NAME"

if [[ $FORCE_DOWNLOAD -eq 1 ]]; then
  log "Removendo download/extração anteriores"
  rm -f "$ZIP_PATH"
  rm -rf "$EXTRACT_ROOT"
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  if command -v curl >/dev/null 2>&1; then
    log "Baixando dataset (curl)"
    curl -L --fail --progress-bar "$DATASET_URL" -o "$ZIP_PATH" || fail "Falha no download do dataset."
  elif command -v wget >/dev/null 2>&1; then
    log "Baixando dataset (wget)"
    wget -q --show-progress -O "$ZIP_PATH" "$DATASET_URL" || fail "Falha no download do dataset."
  else
    fail "Instale curl ou wget para baixar o dataset."
  fi
else
  log "Dataset já encontrado em $ZIP_PATH"
fi

if [[ ! -d "$EXTRACT_ROOT" ]]; then
  log "Extraindo dataset"
  "$PYTHON_BIN" <<PY
from pathlib import Path
import zipfile
zip_path = Path(r"$ZIP_PATH")
extract_dir = Path(r"$EXTRACT_ROOT")
extract_dir.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(zip_path, 'r') as zf:
    zf.extractall(extract_dir)
PY
else
  log "Extração já disponível em $EXTRACT_ROOT"
fi

# ============================
# Preparação do dataset YOLO
# ============================
YOLO_ROOT="$DATA_DIR/yolo"
PREPARED_DIR="$YOLO_ROOT/$YOLO_DATASET_NAME"
CONFIG_FILE="$YOLO_ROOT/${YOLO_DATASET_NAME}.yaml"
mkd "$PREPARED_DIR"

log "Preparando dataset para YOLO"
"$PYTHON_BIN" <<PY
import random
import shutil
from pathlib import Path

extract_root = Path(r"$EXTRACT_ROOT")
target = Path(r"$PREPARED_DIR")
seed = int("$YOLO_SPLIT_SEED")
random.seed(seed)

images_dir = None
labels_dir = None
for candidate in extract_root.rglob("images"):
    brother = candidate.parent / "labels"
    if brother.exists():
        images_dir = candidate
        labels_dir = brother
        break

if images_dir is None or labels_dir is None:
    raise SystemExit("Não foi possível localizar pastas images/labels no dataset extraído")

train_dir = target / "images/train"
if train_dir.exists() and any(train_dir.iterdir()):
    print("[init] Dataset já preparado, mantendo split existente.")
else:
    pairs = []
    valid_ext = {".jpg", ".jpeg", ".png", ".bmp"}
    for img in images_dir.rglob("*"):
        if img.suffix.lower() not in valid_ext:
            continue
        label = labels_dir / (img.stem + ".txt")
        if label.exists():
            pairs.append((img, label))

    if not pairs:
        raise SystemExit("Nenhum par imagem/label encontrado no dataset")

    random.shuffle(pairs)
    count = len(pairs)
    train_end = int(count * 0.8)
    val_end = train_end + int(count * 0.1)

    splits = {
        "train": pairs[:train_end],
        "val": pairs[train_end:val_end],
        "test": pairs[val_end:],
    }

    for split in splits:
        (target / f"images/{split}").mkdir(parents=True, exist_ok=True)
        (target / f"labels/{split}").mkdir(parents=True, exist_ok=True)

    for split, items in splits.items():
        for img, label in items:
            dst_img = target / f"images/{split}/{img.name}"
            dst_label = target / f"labels/{split}/{label.name}"
            if not dst_img.exists():
                shutil.copy2(img, dst_img)
            if not dst_label.exists():
                shutil.copy2(label, dst_label)

    if not any((target / "labels/test").glob("*")):
        (target / "images/test").mkdir(parents=True, exist_ok=True)
        (target / "labels/test").mkdir(parents=True, exist_ok=True)
        for img in (target / "images/val").glob("*"):
            label = target / "labels/val" / (img.stem + ".txt")
            shutil.copy2(img, target / "images/test" / img.name)
            shutil.copy2(label, target / "labels/test" / label.name)

    print(f"[init] Dataset preparado com {count} pares "
          f"(train={len(splits['train'])}, val={len(splits['val'])}, test={len(splits['test'])}).")
PY

log "Gerando configuração YAML do dataset"
"$PYTHON_BIN" <<PY
from pathlib import Path
config_path = Path(r"$CONFIG_FILE")
dataset_dir = Path(r"$PREPARED_DIR").resolve()
config = (
    f"path: {dataset_dir.as_posix()}\n"
    "train: images/train\n"
    "val: images/val\n"
    "test: images/test\n"
    "names:\n"
    "  0: plate\n"
)
config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(config, encoding="utf-8")
PY

if [[ $SKIP_TRAINING -eq 1 ]]; then
  log "Preparação concluída (treino inicial pulado)."
  exit 0
fi

# ============================
# Descoberta do binário YOLO (Windows-friendly)
# ============================
YOLO_BIN=""
# Ordem: Scripts/yolo.exe -> Scripts/yolo -> bin/yolo -> yolo (PATH)
for cand in \
  "$VENV_DIR/Scripts/yolo.exe" \
  "$VENV_DIR/Scripts/yolo" \
  "$VENV_DIR/bin/yolo" \
  yolo
do
  if [[ -f "$cand" ]] && [[ -x "$cand" ]] || command -v "$cand" >/dev/null 2>&1; then
    YOLO_BIN="$cand"
    break
  fi
done
[[ -n "$YOLO_BIN" ]] || fail "Comando 'yolo' não encontrado. Verifique a instalação do pacote ultralytics."

# ============================
# Detecção de dispositivo (GPU/CPU) segura
# ============================
if [[ "${TRAIN_DEVICE}" == "auto" || -z "${TRAIN_DEVICE}" ]]; then
  DETECTED_DEVICE="$("$PYTHON_BIN" - <<'PY'
import os, torch
cuda = torch.cuda.is_available()
n = torch.cuda.device_count() if cuda else 0
if cuda and n > 0:
    cvd = os.environ.get("CUDA_VISIBLE_DEVICES")
    if cvd and cvd.strip():
        print(cvd.strip())
    else:
        print("0")
else:
    print("cpu")
PY
)"
  TRAIN_DEVICE="$DETECTED_DEVICE"
fi

# Info útil pro usuário
"$PYTHON_BIN" - <<PY
import torch, os
print("[init] torch:", torch.__version__, "cuda:", torch.version.cuda)
print("[init] cuda_available:", torch.cuda.is_available(), "device_count:", torch.cuda.device_count())
print("[init] using device env (TRAIN_DEVICE):", "${TRAIN_DEVICE}")
cvd=os.environ.get("CUDA_VISIBLE_DEVICES")
print("[init] CUDA_VISIBLE_DEVICES:", cvd if cvd is not None else "(unset)")
PY

export CUDA_VISIBLE_DEVICES
export PYTORCH_CUDA_ALLOC_CONF

mkd "$ARTIFACTS_DIR/runs"

log "Iniciando treinamento (profile=$PROFILE, epochs=$TRAIN_EPOCHS, batch=$TRAIN_BATCH, imgsz=$TRAIN_IMAGE_SIZE, model=$BASE_MODEL, device=$TRAIN_DEVICE)"

"$YOLO_BIN" detect train \
  data="$CONFIG_FILE" \
  model="$BASE_MODEL" \
  epochs="$TRAIN_EPOCHS" \
  batch="$TRAIN_BATCH" \
  imgsz="$TRAIN_IMAGE_SIZE" \
  device="$TRAIN_DEVICE" \
  workers="$TRAIN_WORKERS" \
  cache="$TRAIN_CACHE" \
  amp="$TRAIN_AMP" \
  optimizer="$TRAIN_OPTIMIZER" \
  lr0="$TRAIN_LR0" \
  lrf="$TRAIN_LRF" \
  momentum="$TRAIN_MOMENTUM" \
  weight_decay="$TRAIN_WD" \
  warmup_epochs="$TRAIN_WARMUP_E" \
  cos_lr="$TRAIN_COSLR" \
  seed="$YOLO_SPLIT_SEED" \
  mosaic="$TRAIN_MOSAIC" \
  copy_paste="$TRAIN_COPYPASTE" \
  mixup="$TRAIN_MIXUP" \
  hsv_h="$TRAIN_HSV_H" \
  hsv_s="$TRAIN_HSV_S" \
  hsv_v="$TRAIN_HSV_V" \
  degrees="$TRAIN_DEGREES" \
  translate="$TRAIN_TRANSLATE" \
  scale="$TRAIN_SCALE" \
  shear="$TRAIN_SHEAR" \
  perspective="$TRAIN_PERSPECTIVE" \
  project="$ARTIFACTS_DIR/runs" \
  name="$YOLO_RUN_NAME" \
  exist_ok=True \
  patience="$TRAIN_PATIENCE" \
  plots="$TRAIN_PLOTS"

# ============================
# Coleta do best.pt
# ============================
BEST_WEIGHTS="$ARTIFACTS_DIR/runs/detect/$YOLO_RUN_NAME/weights/best.pt"
[[ -f "$BEST_WEIGHTS" ]] || fail "Arquivo de pesos 'best.pt' não encontrado após o treino (verifique logs)."

mkd "$ARTIFACTS_DIR"
cp -f "$BEST_WEIGHTS" "$ARTIFACTS_DIR/$MODEL_OUTPUT_NAME" || fail "Falha ao copiar pesos para $ARTIFACTS_DIR/$MODEL_OUTPUT_NAME"
log "Treino concluído. Pesos salvos em $ARTIFACTS_DIR/$MODEL_OUTPUT_NAME"