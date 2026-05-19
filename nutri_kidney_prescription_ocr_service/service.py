import base64
import logging
import os
import re
import shutil
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import RLock
from typing import Any

from config import settings
from parser import parse_prescription_text
from rxnorm_client import RxNormClient

logger = logging.getLogger(__name__)


class PrescriptionOcrService:
    def __init__(self):
        self.rxnorm_client = RxNormClient()
        self._rxnorm_cache: dict[str, dict] = {}
        self._rxnorm_cache_lock = RLock()
        self._rxnorm_cache_ttl_seconds = 30 * 24 * 60 * 60  # 30 days
        self._rxnorm_executor = ThreadPoolExecutor(max_workers=4)

    @staticmethod
    def _lazy_import_ocr_libs():
        # Lazy-load heavy libs so startup (/api/health) stays fast.
        import cv2  # type: ignore
        import numpy as np  # type: ignore
        import pytesseract  # type: ignore

        return cv2, np, pytesseract

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

        # Fast path: quick preprocess + single Tesseract run first.
        fast_image = self._preprocess_fast(image_data)
        fast_text, fast_quality = self._extract_text_once(fast_image, config="--oem 3 --psm 6")
        processing_mode = "fast"
        text = fast_text
        quality_score = fast_quality

        # Fallback: only do expensive preprocessing when needed.
        if fast_quality < 75:
            processing_mode = "fallback"
            processed_images = self._preprocess_image_variants(image_data, limit=3)
            text, quality_score = self._extract_best_text(
                processed_images,
                configs=["--oem 3 --psm 6", "--oem 3 --psm 11"],
                min_quality=75,
            )
            if quality_score < 75:
                # Last-resort configs if still poor.
                text, quality_score = self._extract_best_text(
                    processed_images,
                    configs=["--oem 3 --psm 4", "--oem 3 --psm 12"],
                    min_quality=75,
                )

        cleaned_text = self._clean_text(text)
        logger.info("OCR mode=%s quality=%s raw preview: %s", processing_mode, quality_score, self._preview_text(text))
        logger.info("OCR cleaned text preview: %s", self._preview_text(cleaned_text))

        parsed = parse_prescription_text(cleaned_text)
        medications = self._verify_medications(parsed)
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
            "processingMode": processing_mode,
            "ocrQuality": quality_score,
        }

    def _verify_medication(self, medication: dict) -> dict:
        medicine_name = str(medication.get("medicineName") or "").strip()
        logger.info("Verifying medication candidate: %s", medicine_name)
        if not medicine_name:
            medication["verified"] = False
            medication["confidence"] = 0
            medication["rxcui"] = None
            return medication

        if not self._should_verify_with_rxnorm(medicine_name, medication):
            medication["verified"] = False
            medication["rxcui"] = None
            medication["rxnormProperties"] = None
            medication["confidence"] = self._confidence_score(medication, False)
            return medication

        normalized_key = self._rxnorm_cache_key(medicine_name)
        cached = self._rxnorm_cache_get(normalized_key)
        if cached is not None:
            medication["rxcui"] = cached.get("rxcui")
            medication["verified"] = bool(cached.get("rxcui"))
            if cached.get("canonical_name"):
                medication["medicineName"] = cached["canonical_name"]
            medication["rxnormProperties"] = cached.get("rxnormProperties")
            medication["confidence"] = self._confidence_score(medication, bool(cached.get("rxcui")))
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

        self._rxnorm_cache_set(
            normalized_key,
            {
                "rxcui": medication.get("rxcui"),
                "canonical_name": medication.get("medicineName"),
                "rxnormProperties": medication.get("rxnormProperties"),
            },
        )
        medication["confidence"] = self._confidence_score(medication, bool(rxcui))
        return medication

    def _verify_medications(self, medications: list[dict]) -> list[dict]:
        # Verify concurrently after OCR+parsing.
        if not medications:
            return []
        futures = {
            self._rxnorm_executor.submit(self._verify_medication, med): index
            for index, med in enumerate(medications)
        }
        verified: list[dict | None] = [None] * len(medications)
        for future in as_completed(futures):
            index = futures[future]
            try:
                verified[index] = future.result()
            except Exception as error:
                logger.warning("Medication verification failed: %s", error)
                med = medications[index]
                med["verified"] = False
                med["rxcui"] = None
                med["confidence"] = self._confidence_score(med, False)
                verified[index] = med
        return [item for item in verified if item is not None]

    @staticmethod
    def _rxnorm_cache_key(name: str) -> str:
        return " ".join(str(name or "").strip().lower().split())

    def _rxnorm_cache_get(self, key: str) -> dict | None:
        now = time.time()
        with self._rxnorm_cache_lock:
            entry = self._rxnorm_cache.get(key)
            if not entry:
                return None
            if entry.get("expires_at", 0) <= now:
                self._rxnorm_cache.pop(key, None)
                return None
            return dict(entry.get("value") or {})

    def _rxnorm_cache_set(self, key: str, value: dict) -> None:
        now = time.time()
        with self._rxnorm_cache_lock:
            self._rxnorm_cache[key] = {
                "expires_at": now + self._rxnorm_cache_ttl_seconds,
                "value": dict(value or {}),
            }

    @staticmethod
    def _should_verify_with_rxnorm(name: str, medication: dict) -> bool:
        normalized = " ".join(str(name or "").strip().lower().split())
        if len(normalized) < 3:
            return False
        # Avoid verifying instruction-like text.
        if any(token in normalized for token in ["take", "after", "before", "daily", "bedtime", "needed", "prn"]):
            return False
        # If we have almost no context fields, skip to reduce false lookups.
        has_context = any(medication.get(field) for field in ["dosage", "frequency", "form"])
        return has_context

    def _preprocess_fast(self, image_data: bytes):
        cv2, np, _ = self._lazy_import_ocr_libs()
        image_array = np.frombuffer(image_data, dtype=np.uint8)
        image = cv2.imdecode(image_array, cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError("Unable to decode prescription image")

        h, w = image.shape[:2]
        if min(h, w) < 600:
            scale = 600.0 / float(min(h, w))
            image = cv2.resize(image, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        # Light contrast: normalize to spread histogram without heavy pipeline.
        gray = cv2.normalize(gray, None, 0, 255, cv2.NORM_MINMAX)
        return gray

    def _extract_text_once(self, image, config: str) -> tuple[str, int]:
        _, _, pytesseract = self._lazy_import_ocr_libs()
        if settings.tesseract_cmd:
            pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
        try:
            text = pytesseract.image_to_string(image, config=config)
        except Exception as error:
            logger.warning("Tesseract failed with config %s: %s", config, error)
            return "", 0
        quality = self._quality_score(text)
        return text, quality

    def _quality_score(self, text: str) -> int:
        # Normalize quality to 0..100-ish for easy thresholding.
        if not text:
            return 0
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        alpha_ratio = sum(char.isalpha() for char in text) / max(len(text), 1)
        dosage_hits = sum(
            1
            for line in lines
            if any(unit in line.lower() for unit in ["mg", "ml", "tablet", "capsule", "tab", "cap"])
        )
        noisy_symbol_penalty = len(re.findall(r"[^A-Za-z0-9\s,./()-]", text))
        raw = (len(lines) * 6) + (dosage_hits * 18) + int(alpha_ratio * 40) - int(noisy_symbol_penalty * 0.6)
        return int(max(0, min(100, raw)))

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

    def _preprocess_image_variants(self, image_data: bytes, limit: int = 3) -> list:
        cv2, np, _ = self._lazy_import_ocr_libs()
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
        variants = [contrast, otsu, adaptive, cleaned_binary]
        logger.info("Image preprocessing variants prepared: %s", len(variants))
        return variants[: max(1, int(limit))]

    def _crop_document_region(self, image) -> Any:
        cv2, np, _ = self._lazy_import_ocr_libs()
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

    def _deskew(self, gray_image) -> Any:
        cv2, np, _ = self._lazy_import_ocr_libs()
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

    def _extract_best_text(
        self,
        image_variants: list,
        *,
        configs: list[str],
        min_quality: int = 75,
    ) -> tuple[str, int]:
        best_text = ""
        best_quality = 0
        for image in image_variants:
            for config in configs:
                text, quality = self._extract_text_once(image, config=config)
                logger.info("OCR config %s quality=%s", config, quality)
                if quality > best_quality:
                    best_quality = quality
                    best_text = text
                if best_quality >= min_quality:
                    return best_text, best_quality
        return best_text, best_quality

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
            _, _, pytesseract = self._lazy_import_ocr_libs()
            if settings.tesseract_cmd:
                pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
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
