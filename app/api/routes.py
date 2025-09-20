from __future__ import annotations

import logging
import re
from io import BytesIO
from typing import Dict, List, Optional

import cv2
import numpy as np
import pytesseract

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from PIL import Image

from app.schemas import DetectionResponse
from app.services.apibrasil import ApiBrasilClient, get_apibrasil_client
from app.services.detector import LicensePlateDetector, get_detector

router = APIRouter(prefix="/plates", tags=["plates"])


logger = logging.getLogger(__name__)


def _select_primary_detection(detections: List[Dict[str, float]]) -> Optional[Dict[str, float]]:
    if not detections:
        return None
    return max(detections, key=lambda item: item.get("confidence", 0.0))


def _extract_plate_text(image: Image.Image, detections: List[Dict[str, float]]) -> str:
    primary = _select_primary_detection(detections)
    if primary is None:
        logger.info("Nenhuma deteccao encontrada para OCR.")
        return ""

    width, height = image.size
    x_center = primary.get("x_center", 0.0) * width
    y_center = primary.get("y_center", 0.0) * height
    box_width = primary.get("width", 0.0) * width
    box_height = primary.get("height", 0.0) * height

    x1 = max(int(round(x_center - box_width / 2)), 0)
    y1 = max(int(round(y_center - box_height / 2)), 0)
    x2 = min(int(round(x_center + box_width / 2)), width)
    y2 = min(int(round(y_center + box_height / 2)), height)

    if x2 <= x1 or y2 <= y1:
        logger.warning("Coordenadas invalidas para OCR: (%s, %s, %s, %s)", x1, y1, x2, y2)
        return ""

    crop = image.crop((x1, y1, x2, y2))

    crop_array = np.array(crop)
    if crop_array.size == 0:
        logger.warning("Recorte de OCR vazio.")
        return ""

    crop_bgr = cv2.cvtColor(crop_array, cv2.COLOR_RGB2BGR)
    gray = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2GRAY)
    scaled = cv2.resize(gray, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
    blurred = cv2.GaussianBlur(scaled, (3, 3), 0)
    _, thresh = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

    if np.mean(thresh) > 127:
        thresh = cv2.bitwise_not(thresh)

    ocr_config = "--psm 7 --oem 3 -c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    try:
        raw_text = pytesseract.image_to_string(thresh, config=ocr_config)
    except pytesseract.TesseractNotFoundError:
        logger.error("Tesseract OCR nao encontrado. Instale o binario para habilitar OCR.")
        return ""

    cleaned = re.sub(r"[^A-Z0-9]", "", raw_text.upper())
    logger.info(
        "OCR placa (raw=%r, cleaned=%s, bbox=(%s,%s,%s,%s), conf=%.4f)",
        raw_text,
        cleaned,
        x1,
        y1,
        x2,
        y2,
        primary.get("confidence", 0.0),
    )

    return cleaned


@router.post("/detect", response_model=DetectionResponse)
async def detect_license_plate(
    file: UploadFile = File(...),
    tipo: str = Form("agregados-basica"),
    homolog: bool = Form(False),
    placa_manual: Optional[str] = Form(None),
    detector: LicensePlateDetector = Depends(get_detector),
    api_client: ApiBrasilClient = Depends(get_apibrasil_client),
):
    if detector.model is None:
        raise HTTPException(status_code=503, detail="Modelo de deteccao nao carregado. Verifique o arquivo configurado em PLACAOCR_MODEL_PATH.")

    contents = await file.read()
    try:
        image = Image.open(BytesIO(contents)).convert("RGB")
    except Exception as exc:  # pragma: no cover - logging futuro
        raise HTTPException(status_code=400, detail="Arquivo enviado nao e uma imagem valida.") from exc

    try:
        detections = detector.predict(image)
    except RuntimeError as exc:  # pragma: no cover
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    placa_text = (placa_manual or "").strip().upper()
    if not placa_text:
        placa_text = _extract_plate_text(image, detections)
    if not placa_text and homolog:
        placa_text = "ABC1234"

    vehicle_payload = None
    apibrasil_debug = None
    if placa_text:
        vehicle_payload, apibrasil_debug = await api_client.fetch_vehicle_data(placa=placa_text, tipo=tipo, homolog=homolog)

    debug_payload = None
    if detector.settings.debug:
        primary = _select_primary_detection(detections)
        debug_payload = {
            "image": {
                "size": {"width": image.width, "height": image.height},
                "mode": image.mode,
                "format": getattr(image, "format", None),
            },
            "detections": {
                "total": len(detections),
                "primary": primary,
            },
            "placa": {
                "manual": placa_manual.strip().upper() if placa_manual else None,
                "final": placa_text,
            },
        }
        if apibrasil_debug:
            debug_payload["apibrasil"] = apibrasil_debug

    return DetectionResponse.from_detections(
        detections,
        placa=placa_text,
        vehicle_data=vehicle_payload,
        debug=debug_payload,
    )
