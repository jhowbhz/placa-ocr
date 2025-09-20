from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class DetectionResumo(BaseModel):
    x_center: float = Field(..., ge=0, le=1)
    y_center: float = Field(..., ge=0, le=1)
    width: float = Field(..., ge=0, le=1)
    height: float = Field(..., ge=0, le=1)
    confidence: float = Field(..., ge=0, le=1)


class VehicleInfo(BaseModel):
    marca: str = ""
    modelo: str = ""
    detalhes: Optional[Dict[str, Any]] = None


class DetectionData(BaseModel):
    resumo: DetectionResumo
    veiculo: VehicleInfo = Field(default_factory=VehicleInfo)


class DetectionResponse(BaseModel):
    placa: str = ""
    data: List[DetectionData] = Field(default_factory=list)

    @classmethod
    def from_detections(
        cls,
        detections: List[Dict[str, float]],
        placa: str = "",
        vehicle_data: Optional[Dict[str, Any]] = None,
    ) -> "DetectionResponse":
        vehicle_info = VehicleInfo()
        if vehicle_data:
            vehicle_info = VehicleInfo(
                marca=_extract_field(vehicle_data, ["marca", "brand", "make"]),
                modelo=_extract_field(vehicle_data, ["modelo", "model"]),
                detalhes=vehicle_data,
            )
        items = [DetectionData(resumo=DetectionResumo(**item), veiculo=vehicle_info) for item in detections]
        return cls(placa=placa or "", data=items)


def _extract_field(payload: Any, keys: List[str]) -> str:
    result = _search_field(payload, set(keys))
    if result is None:
        return ""
    if isinstance(result, str):
        return result
    return str(result)


def _search_field(payload: Any, keys: set[str]) -> Optional[Any]:
    if isinstance(payload, dict):
        for key, value in payload.items():
            if key in keys and value not in (None, ""):
                return value
            found = _search_field(value, keys)
            if found not in (None, ""):
                return found
    elif isinstance(payload, list):
        for item in payload:
            found = _search_field(item, keys)
            if found not in (None, ""):
                return found
    return None
