from __future__ import annotations

from io import BytesIO
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from PIL import Image

from app.schemas import DetectionResponse
from app.services.apibrasil import ApiBrasilClient, get_apibrasil_client
from app.services.detector import LicensePlateDetector, get_detector

router = APIRouter(prefix="/plates", tags=["plates"])


def _select_primary_detection(detections: List[Dict[str, float]]) -> Optional[Dict[str, float]]:
    if not detections:
        return None
    return max(detections, key=lambda item: item.get("confidence", 0.0))


def _extract_plate_text(_: Image.Image, detections: List[Dict[str, float]]) -> str:
    primary = _select_primary_detection(detections)
    if primary is None:
        return ""
    return ""


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
    if placa_text:
        vehicle_payload = await api_client.fetch_vehicle_data(placa=placa_text, tipo=tipo, homolog=homolog)

    return DetectionResponse.from_detections(
        detections,
        placa=placa_text,
        vehicle_data=vehicle_payload,
    )
