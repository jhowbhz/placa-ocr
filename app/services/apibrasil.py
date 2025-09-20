from __future__ import annotations

import logging
from functools import lru_cache
from typing import Any, Dict, Optional, Tuple

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

    async def fetch_vehicle_data(
        self,
        placa: str,
        tipo: str,
        homolog: bool,
    ) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
        debug_enabled = self._settings.debug
        debug_info: Optional[Dict[str, Any]] = None

        if debug_enabled:
            debug_info = {
                "request": {
                    "url": self.base_url,
                    "payload": {
                        "tipo": tipo,
                        "placa": placa.upper() if placa else placa,
                        "homolog": bool(homolog),
                    },
                    "token_configured": bool(self.token),
                }
            }

        if not self.is_configured:
            if debug_info is not None:
                debug_info["status"] = "client_not_configured"
            logger.debug("API Brasil client not configured. Skipping request.")
            return None, debug_info
        if not placa:
            if debug_info is not None:
                debug_info["status"] = "empty_plate"
            logger.debug("Skipping API Brasil request because placa is empty.")
            return None, debug_info

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
            if debug_info is not None:
                debug_info["http"] = {
                    "status_code": response.status_code,
                    "reason": response.reason_phrase,
                    "elapsed": getattr(response, "elapsed", None).total_seconds() if getattr(response, "elapsed", None) else None,
                }
            response.raise_for_status()
        except httpx.HTTPError as exc:
            if debug_info is not None:
                debug_info.setdefault("http", {})
                debug_info["http"]["error"] = str(exc)
            logger.warning("Falha ao consultar API Brasil: %s", exc)
            return None, debug_info

        try:
            data = response.json()
            if debug_info is not None:
                debug_info.setdefault("http", {})
                debug_info["http"]["response_preview"] = response.text[:500]
            return data, debug_info
        except ValueError as exc:
            if debug_info is not None:
                debug_info.setdefault("http", {})
                debug_info["http"]["parse_error"] = str(exc)
                debug_info["http"]["response_preview"] = response.text[:500]
            logger.warning("Resposta da API Brasil nao e JSON valido: %s", exc)
            return None, debug_info


@lru_cache
def get_apibrasil_client() -> ApiBrasilClient:
    settings = get_settings()
    return ApiBrasilClient(settings)
