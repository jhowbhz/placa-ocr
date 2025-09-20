from __future__ import annotations

from functools import lru_cache
from typing import Dict, List

from PIL import Image
from ultralytics import YOLO

from app.config import Settings, get_settings


class LicensePlateDetector:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.model = self._load_model()

    def _load_model(self):
        if not self.settings.model_path.exists():
            return None
        return YOLO(self.settings.model_path.as_posix())

    def predict(self, image: Image.Image) -> List[Dict[str, float]]:
        if self.model is None:
            raise RuntimeError(
                "Modelo indisponivel. Informe um caminho valido em PLACAOCR_MODEL_PATH."
            )

        results = self.model.predict(
            image,
            conf=self.settings.confidence_threshold,
            imgsz=self.settings.image_size or 640,
            device=self.settings.device,
            verbose=False,
        )

        width, height = image.size
        detections: List[Dict[str, float]] = []

        for result in results:
            if result.boxes is None:
                continue
            for box in result.boxes:
                x1, y1, x2, y2 = box.xyxy[0].tolist()
                confidence = float(box.conf.item())
                detections.append(
                    {
                        "x_center": ((x1 + x2) / 2) / width,
                        "y_center": ((y1 + y2) / 2) / height,
                        "width": (x2 - x1) / width,
                        "height": (y2 - y1) / height,
                        "confidence": confidence,
                    }
                )

        return detections


@lru_cache
def get_detector() -> LicensePlateDetector:
    settings = get_settings()
    return LicensePlateDetector(settings)
