from pydantic import BaseModel, Field


class MedicationDraft(BaseModel):
    medicineName: str = Field(..., min_length=2)
    dosage: str = ""
    form: str = ""
    frequency: str = ""
    duration: str = ""
    instructions: str = ""
    rxcui: str | None = None
    verified: bool = False
    confidence: float = 0
    rawLine: str = ""


class PrescriptionExtractRequest(BaseModel):
    image_base64: str = Field(..., min_length=10)
    content_type: str = Field(default="image/jpeg")


class MedicationScanResponse(BaseModel):
    success: bool
    contentType: str
    extractedText: str
    medications: list[MedicationDraft]
    count: int
