#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: ./init.sh [--skip-training] [--force-download]

Flags:
  --skip-training    Prepara ambiente e dataset sem treinar o modelo.
  --force-download   Baixa novamente o dataset, sobrescrevendo arquivos existentes.

Variaveis de ambiente relevantes:
  PYTHON_BIN, VENV_DIR, REQUIREMENTS_FILE, DATA_DIR,
  DATASET_URL, TRAIN_EPOCHS, TRAIN_BATCH, BASE_MODEL,
  TRAIN_IMAGE_SIZE, ARTIFACTS_DIR, MODEL_OUTPUT_NAME,
  YOLO_RUN_NAME, YOLO_SPLIT_SEED.
EOF
}

log() {
    printf "[init] %s\n" "$1"
}

fail() {
    printf "[init] ERRO: %s\n" "$1" >&2
    exit 1
}

PYTHON_BIN=${PYTHON_BIN:-python3}
VENV_DIR=${VENV_DIR:-.venv}
REQUIREMENTS_FILE=${REQUIREMENTS_FILE:-requirements.txt}
DATA_DIR=${DATA_DIR:-data}
DATASET_URL=${DATASET_URL:-https://prod-dcd-datasets-cache-zipfiles.s3.eu-west-1.amazonaws.com/nx9xbs4rgx-2.zip}
DATASET_ZIP_NAME=${DATASET_ZIP_NAME:-artificial-mercosur.zip}
EXTRACT_ROOT=${EXTRACT_ROOT:-$DATA_DIR/raw/extracted}
YOLO_DATASET_NAME=${YOLO_DATASET_NAME:-mercosur-license-plates}
YOLO_SPLIT_SEED=${YOLO_SPLIT_SEED:-42}
TRAIN_EPOCHS=${TRAIN_EPOCHS:-1}
TRAIN_BATCH=${TRAIN_BATCH:-16}
TRAIN_IMAGE_SIZE=${TRAIN_IMAGE_SIZE:-640}
BASE_MODEL=${BASE_MODEL:-yolov8n.pt}
ARTIFACTS_DIR=${ARTIFACTS_DIR:-artifacts}
MODEL_OUTPUT_NAME=${MODEL_OUTPUT_NAME:-license-plate.pt}
YOLO_RUN_NAME=${YOLO_RUN_NAME:-mercosur}

FORCE_DOWNLOAD=0
SKIP_TRAINING=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force-download)
            FORCE_DOWNLOAD=1
            ;;
        --skip-training)
            SKIP_TRAINING=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            fail "flag desconhecida: $1"
            ;;
    esac
    shift
done

[[ -f "$REQUIREMENTS_FILE" ]] || fail "Execute o script a partir da raiz do projeto."
command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "Python nao encontrado em PYTHON_BIN=$PYTHON_BIN"

if [[ ! -d "$VENV_DIR" ]]; then
    log "Criando ambiente virtual em $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

ACTIVATE_SCRIPT="$VENV_DIR/bin/activate"
if [[ ! -f "$ACTIVATE_SCRIPT" ]]; then
    ACTIVATE_SCRIPT="$VENV_DIR/Scripts/activate"
fi
[[ -f "$ACTIVATE_SCRIPT" ]] || fail "Nao foi possivel localizar o script de ativacao do virtualenv."
# shellcheck disable=SC1090
source "$ACTIVATE_SCRIPT"

log "Atualizando pip"
python -m pip install --upgrade pip >/dev/null
log "Instalando dependencias"
python -m pip install -r "$REQUIREMENTS_FILE"

mkdir -p "$DATA_DIR/raw"
ZIP_PATH="$DATA_DIR/raw/$DATASET_ZIP_NAME"
if [[ $FORCE_DOWNLOAD -eq 1 ]]; then
    log "Removendo download anterior"
    rm -f "$ZIP_PATH"
    rm -rf "$EXTRACT_ROOT"
fi

if [[ ! -f "$ZIP_PATH" ]]; then
    if command -v curl >/dev/null 2>&1; then
        log "Baixando dataset (via curl)"
        curl -L --fail --progress-bar "$DATASET_URL" -o "$ZIP_PATH" || fail "Falha no download do dataset."
    elif command -v wget >/dev/null 2>&1; then
        log "Baixando dataset (via wget)"
        wget -O "$ZIP_PATH" "$DATASET_URL" || fail "Falha no download do dataset."
    else
        fail "Instale curl ou wget para baixar o dataset."
    fi
else
    log "Dataset ja encontrado em $ZIP_PATH"
fi

if [[ ! -d "$EXTRACT_ROOT" ]]; then
    log "Extraindo dataset"
    python <<PY
from pathlib import Path
import zipfile
zip_path = Path(r"$ZIP_PATH")
extract_dir = Path(r"$EXTRACT_ROOT")
extract_dir.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(zip_path) as zf:
    zf.extractall(extract_dir)
PY
else
    log "Extracao ja disponivel em $EXTRACT_ROOT"
fi

YOLO_ROOT="$DATA_DIR/yolo"
PREPARED_DIR="$YOLO_ROOT/$YOLO_DATASET_NAME"
CONFIG_FILE="$YOLO_ROOT/${YOLO_DATASET_NAME}.yaml"
mkdir -p "$PREPARED_DIR"

log "Preparando dataset para YOLO"
python <<PY
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
    raise SystemExit("nao foi possivel localizar pastas images/labels no dataset extraido")

train_dir = target / "images/train"
if train_dir.exists() and any(train_dir.iterdir()):
    print("[init] Dataset ja preparado, mantendo split existente.")
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
        raise SystemExit("nenhum par imagem/label encontrado no dataset")

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

    print("[init] Dataset preparado com {} pares (train={}, val={}, test={}).".format(
        count,
        len(splits["train"]),
        len(splits["val"]),
        len(splits["test"]),
    ))
PY

log "Gerando configuracao YAML do dataset"
python <<PY
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
    log "Preparacao concluida (treino inicial pulado)."
    exit 0
fi

YOLO_BIN="$VENV_DIR/bin/yolo"
if [[ ! -x "$YOLO_BIN" ]]; then
    YOLO_BIN="$VENV_DIR/Scripts/yolo"
fi
if [[ ! -x "$YOLO_BIN" && -x "$YOLO_BIN.exe" ]]; then
    YOLO_BIN="$YOLO_BIN.exe"
fi
if [[ ! -x "$YOLO_BIN" ]]; then
    YOLO_BIN="yolo"
fi
command -v "$YOLO_BIN" >/dev/null 2>&1 || fail "Comando yolo nao encontrado. Verifique a instalacao do pacote ultralytics."

mkdir -p "$ARTIFACTS_DIR/runs"
log "Iniciando treinamento (epochs=$TRAIN_EPOCHS, batch=$TRAIN_BATCH)"
"$YOLO_BIN" detect train \
    data="$CONFIG_FILE" \
    model="$BASE_MODEL" \
    epochs="$TRAIN_EPOCHS" \
    batch="$TRAIN_BATCH" \
    imgsz="$TRAIN_IMAGE_SIZE" \
    project="$ARTIFACTS_DIR/runs" \
    name="$YOLO_RUN_NAME" \
    exist_ok=True

BEST_WEIGHTS="$ARTIFACTS_DIR/runs/detect/$YOLO_RUN_NAME/weights/best.pt"
[[ -f "$BEST_WEIGHTS" ]] || fail "Arquivo de pesos best.pt nao encontrado apos o treino."
mkdir -p "$ARTIFACTS_DIR"
cp "$BEST_WEIGHTS" "$ARTIFACTS_DIR/$MODEL_OUTPUT_NAME"
log "Treino concluido. Pesos salvos em $ARTIFACTS_DIR/$MODEL_OUTPUT_NAME"
