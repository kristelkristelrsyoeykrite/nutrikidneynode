import logging

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from config import settings
from models import MedicationScanResponse, PrescriptionExtractRequest
from service import get_service

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

logger = logging.getLogger(__name__)

app = FastAPI(
    title="NutriKidney Prescription OCR Service",
    description="Prescription OCR and medication extraction service",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
async def health_check():
    try:
        return get_service().health_check()
    except Exception as error:
        logger.error("Prescription OCR health check failed: %s", error, exc_info=True)
        raise HTTPException(status_code=500, detail=str(error))


@app.post("/api/v1/medications/scan", response_model=MedicationScanResponse)
async def scan_medications(payload: PrescriptionExtractRequest):
    try:
        return get_service().extract_from_base64(
            payload.image_base64,
            payload.content_type,
        )
    except Exception as error:
        logger.error("Prescription OCR extraction failed: %s", error, exc_info=True)
        raise HTTPException(status_code=400, detail=str(error))


@app.post("/api/v1/prescriptions/extract", response_model=MedicationScanResponse)
async def extract_prescription(payload: PrescriptionExtractRequest):
    return await scan_medications(payload)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=settings.port,
        log_level="info",
    )
