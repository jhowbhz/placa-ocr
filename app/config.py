from functools import lru_cache
from pathlib import Path
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', env_prefix='PLACAOCR_', extra='ignore')

    model_path: Path = Path('artifacts/license-plate.pt')
    confidence_threshold: float = 0.25
    device: str = 'cpu'
    image_size: Optional[int] = None

    apibrasil_base_url: Optional[str] = 'https://gateway.apibrasil.io/api/v2/vehicles/base/001/consulta'
    apibrasil_token: Optional[str] = None
    apibrasil_timeout: float = 15.0

    debug: bool = False


@lru_cache
def get_settings() -> Settings:
    return Settings()
