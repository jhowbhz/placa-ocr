from __future__ import annotations

import logging
from functools import lru_cache
from typing import Any, Dict, Optional

import httpx

from app.config import Settings, get_settings

logger = logging.getLogger(__name__)


class ApiBrasilClient:
    def __init__(self, settings: Settings):
        self._settings = settings
        self.base_url: Optional[str] = settings.apibrasil_base_url
        self.token: Optional[str] = settings.apibrasil_token
        self.timeout: float = float(settings.apibrasil_timeout or 10)

    @property
    def is_configured(self) -> bool:
        return bool(self.base_url)

    async def fetch_vehicle_data(self, placa: str, tipo: str, homolog: bool) -> Optional[Dict[str, Any]]:
        if not self.is_configured:
            logger.debug("API Brasil client not configured. Skipping request.")
            return None
        if not placa:
            logger.debug("Skipping API Brasil request because placa is empty.")
            return None

        payload = {
            "tipo": tipo,
            "placa": placa.upper(),
            "homolog": bool(homolog),
        }

        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(str(self.base_url), json=payload, headers=headers)
            response.raise_for_status()
        except httpx.HTTPError as exc:
            logger.warning("Falha ao consultar API Brasil: %s", exc)
            return None

        try:
            return response.json()
        except ValueError as exc:
            logger.warning("Resposta da API Brasil nao e JSON valido: %s", exc)
            return None


@lru_cache
def get_apibrasil_client() -> ApiBrasilClient:
    settings = get_settings()
    return ApiBrasilClient(settings)
