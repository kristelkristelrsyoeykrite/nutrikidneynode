import base64
import logging
import os
import re
import shutil

import cv2
import numpy as np
import pytesseract

from config import settings
from parser import parse_prescription_text
from rxnorm_client import RxNormClient

logger = logging.getLogger(__name__)


class PrescriptionOcrService:
    def __init__(self):
        if settings.tesseract_cmd:
            pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
        self.rxnorm_client = RxNormClient()

    def health_check(self) -> dict:
        tesseract_available = self._is_tesseract_available()
        return {
            "success": tesseract_available,
            "service": settings.service_name,
            "version": settings.service_version,
            "tesseractConfigured": bool(settings.tesseract_cmd),
            "tesseractAvailable": tesseract_available,
            "tesseractCommand": settings.tesseract_cmd,
        }

    def extract_from_base64(self, image_base64: str, content_type: str) -> dict:
        logger.info("Prescription OCR request received. content_type=%s", content_type)
        image_data = base64.b64decode(image_base64, validate=True)
        return self.extract_from_bytes(image_data, content_type)

    def extract_from_bytes(self, image_data: bytes, content_type: str) -> dict:
        logger.info("Starting OCR extraction from %s bytes", len(image_data))
        processed_images = self._preprocess_image_variants(image_data)
        text = self._extract_best_text(processed_images)
        cleaned_text = self._clean_text(text)
        logger.info("OCR raw text preview: %s", self._preview_text(text))
        logger.info("OCR cleaned text preview: %s", self._preview_text(cleaned_text))
        medications = [
            self._verify_medication(medication)
            for medication in parse_prescription_text(cleaned_text)
        ]
        logger.info("Medication candidates parsed: %s", len(medications))
        for medication in medications:
            logger.info(
                "Candidate: name=%s dosage=%s verified=%s rxcui=%s confidence=%s",
                medication.get("medicineName"),
                medication.get("dosage"),
                medication.get("verified"),
                medication.get("rxcui"),
                medication.get("confidence"),
            )

        return {
            "success": True,
            "contentType": content_type,
            "extractedText": cleaned_text.strip(),
            "medications": medications,
            "count": len(medications),
        }

    def _verify_medication(self, medication: dict) -> dict:
        medicine_name = str(medication.get("medicineName") or "").strip()
        logger.info("Verifying medication candidate: %s", medicine_name)
        if not medicine_name:
            medication["verified"] = False
            medication["confidence"] = 0
            medication["rxcui"] = None
            return medication

        try:
            rxnorm_match = self.rxnorm_client.find_rxcui(medicine_name)
        except Exception as error:
            logger.warning(
                "RxNorm lookup failed for %s: %s",
                medicine_name,
                error,
            )
            medication["verified"] = False
            medication["confidence"] = self._confidence_score(medication, False)
            medication["rxcui"] = None
            return medication

        rxcui = rxnorm_match.get("rxcui")
        medication["rxcui"] = rxcui
        medication["verified"] = bool(rxcui)

        if rxcui:
            try:
                properties = self.rxnorm_client.get_properties(rxcui)
                if properties.get("name"):
                    medication["medicineName"] = properties["name"]
                medication["rxnormProperties"] = {
                    "name": properties.get("name"),
                    "synonym": properties.get("synonym"),
                    "tty": properties.get("tty"),
                    "language": properties.get("language"),
                }
            except Exception as error:
                logger.warning(
                    "RxNorm properties lookup failed for rxcui=%s: %s",
                    rxcui,
                    error,
                )
                medication["rxnormProperties"] = None
        else:
            medication["rxnormProperties"] = None

        medication["confidence"] = self._confidence_score(medication, bool(rxcui))
        return medication

    def _confidence_score(self, medication: dict, verified: bool) -> float:
        score = 0.25
        if verified:
            score += 0.35
        if medication.get("dosage"):
            score += 0.15
        if medication.get("frequency"):
            score += 0.1
        if medication.get("form"):
            score += 0.05
        if medication.get("duration"):
            score += 0.05
        if medication.get("instructions"):
            score += 0.05
        return round(min(score, 0.95), 2)

    def _preprocess_image_variants(self, image_data: bytes) -> list[np.ndarray]:
        image_array = np.frombuffer(image_data, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError("Unable to decode prescription image")
        logger.info("Image decoded successfully. shape=%s", image.shape)

        cropped = self._crop_document_region(image)
        resized = cv2.resize(
            cropped,
            None,
            fx=2.2,
            fy=2.2,
            interpolation=cv2.INTER_CUBIC,
        )
        gray = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
        blur_score = cv2.Laplacian(gray, cv2.CV_64F).var()
        logger.info("Image blur score: %.2f", blur_score)

        deskewed = self._deskew(gray)
        denoised = cv2.fastNlMeansDenoising(deskewed, None, 12, 7, 21)
        clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
        contrast = clahe.apply(denoised)
        sharpened = cv2.addWeighted(contrast, 1.6, cv2.GaussianBlur(contrast, (0, 0), 1.2), -0.6, 0)

        otsu = cv2.threshold(
            sharpened,
            0,
            255,
            cv2.THRESH_BINARY + cv2.THRESH_OTSU,
        )[1]
        adaptive = cv2.adaptiveThreshold(
            sharpened,
            255,
            cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            cv2.THRESH_BINARY,
            31,
            9,
        )
        inverted_otsu = cv2.threshold(
            sharpened,
            0,
            255,
            cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU,
        )[1]
        cleaned_mask = cv2.morphologyEx(
            inverted_otsu,
            cv2.MORPH_OPEN,
            np.ones((2, 2), np.uint8),
        )
        cleaned_binary = cv2.bitwise_not(cleaned_mask)
        logger.info("Image preprocessing variants prepared: contrast, otsu, adaptive, cleaned_binary")
        return [contrast, otsu, adaptive, cleaned_binary]

    def _crop_document_region(self, image: np.ndarray) -> np.ndarray:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edged = cv2.Canny(blurred, 50, 150)
        contours, _ = cv2.findContours(edged, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            logger.info("No document contour detected; using full image")
            return image

        largest = max(contours, key=cv2.contourArea)
        x, y, w, h = cv2.boundingRect(largest)
        image_h, image_w = image.shape[:2]
        area_ratio = (w * h) / float(image_w * image_h)
        if area_ratio < 0.35:
            logger.info("Detected contour too small for crop (ratio=%.2f); using full image", area_ratio)
            return image

        padding = 12
        x0 = max(x - padding, 0)
        y0 = max(y - padding, 0)
        x1 = min(x + w + padding, image_w)
        y1 = min(y + h + padding, image_h)
        logger.info("Cropping image to detected document region x=%s y=%s w=%s h=%s", x0, y0, x1 - x0, y1 - y0)
        return image[y0:y1, x0:x1]

    def _deskew(self, gray_image: np.ndarray) -> np.ndarray:
        inverted = cv2.bitwise_not(gray_image)
        threshold = cv2.threshold(
            inverted,
            0,
            255,
            cv2.THRESH_BINARY + cv2.THRESH_OTSU,
        )[1]
        coords = np.column_stack(np.where(threshold > 0))
        if len(coords) < 50:
            logger.info("Not enough foreground pixels for deskew; using original grayscale image")
            return gray_image

        angle = cv2.minAreaRect(coords)[-1]
        if angle < -45:
            angle = 90 + angle
        else:
            angle = angle

        if abs(angle) < 0.5:
            logger.info("Deskew skipped; angle %.2f is negligible", angle)
            return gray_image

        center = (gray_image.shape[1] // 2, gray_image.shape[0] // 2)
        matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
        rotated = cv2.warpAffine(
            gray_image,
            matrix,
            (gray_image.shape[1], gray_image.shape[0]),
            flags=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_REPLICATE,
        )
        logger.info("Deskew applied with angle %.2f", angle)
        return rotated

    def _extract_best_text(self, image_variants: list[np.ndarray]) -> str:
        configs = [
            "--oem 3 --psm 6",
            "--oem 3 --psm 11",
            "--oem 3 --psm 4",
            "--oem 3 --psm 12",
        ]
        best_text = ""
        best_score = -1

        for image in image_variants:
            for config in configs:
                try:
                    text = pytesseract.image_to_string(image, config=config)
                except Exception as error:
                    logger.warning("Tesseract failed with config %s: %s", config, error)
                    continue
                score = self._score_text(text)
                logger.info("OCR config %s scored %s", config, score)
                if score > best_score:
                    best_score = score
                    best_text = text
                    logger.info("OCR config %s is current best", config)

        return best_text

    def _score_text(self, text: str) -> int:
        if not text:
            return -1
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        alpha_ratio = sum(char.isalpha() for char in text) / max(len(text), 1)
        dosage_hits = sum(
            1
            for line in lines
            if any(unit in line.lower() for unit in ["mg", "ml", "tablet", "capsule", "tab", "cap"])
        )
        noisy_symbol_penalty = len(re.findall(r"[^A-Za-z0-9\s,./()-]", text))
        return int((len(lines) * 2) + (dosage_hits * 4) + (alpha_ratio * 20) - noisy_symbol_penalty)

    def _clean_text(self, text: str) -> str:
        lines = []
        for raw_line in (text or "").splitlines():
            line = raw_line.strip()
            if not line:
                continue
            line = re.sub(r"[ \t]+", " ", line)
            if not re.search(r"\d", line):
                line = line.replace("0", "o")
            line = line.replace("|", "l")
            line = re.sub(r"\brn(?=[a-z])", "m", line, flags=re.IGNORECASE)
            lines.append(line)
        return "\n".join(lines)

    def _preview_text(self, text: str, limit: int = 240) -> str:
        compact = " | ".join(line.strip() for line in (text or "").splitlines() if line.strip())
        if len(compact) <= limit:
            return compact
        return f"{compact[:limit]}..."

    def _is_tesseract_available(self) -> bool:
        configured_cmd = settings.tesseract_cmd
        if not configured_cmd:
            return False

        if configured_cmd != "tesseract" and not shutil.which(configured_cmd) and not os.path.exists(configured_cmd):
            return False

        try:
            pytesseract.get_tesseract_version()
            return True
        except Exception as error:
            logger.warning("Tesseract health check failed: %s", error)
            return False


_service: PrescriptionOcrService | None = None


def get_service() -> PrescriptionOcrService:
    global _service
    if _service is None:
        _service = PrescriptionOcrService()
    return _service
