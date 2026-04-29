import os
import shutil
from dotenv import load_dotenv

load_dotenv()


def _resolve_tesseract_cmd() -> str | None:
    configured = (os.getenv("TESSERACT_CMD") or "").strip()
    if configured:
        return configured

    for candidate in ("/usr/bin/tesseract", "tesseract"):
        resolved = shutil.which(candidate) if os.path.sep not in candidate else candidate
        if resolved and os.path.exists(resolved):
            return resolved
        if candidate == "tesseract" and shutil.which(candidate):
            return shutil.which(candidate)

    return None


class Settings:
    service_name: str = "NutriKidney Prescription OCR Service"
    service_version: str = "1.0.0"
    tesseract_cmd: str | None = _resolve_tesseract_cmd()
    port: int = int(os.getenv("PORT", "8002"))


settings = Settings()
