"""
Image recognition handler for food image processing.
Handles image validation, upload, and recognition.

Algorithm:
1. Validate uploaded image (file size, type, dimensions)
2. Preprocess if needed (resize, quality)
3. Send to FatSecret image recognition endpoint
4. Parse results and rank by confidence
5. Fetch nutrition data for each detected food
6. Return ranked list with warnings
"""
import os
import io
import logging
from typing import Dict, Any, List, Optional, Tuple
from PIL import Image
import requests
from error_handler import (
    ImageError,
    ValidationError,
    FatSecretAPIError,
    NoResultsError,
)
from config import get_config
from fatsecret_client import FatSecretClient
from nutrition_normalizer import NutritionNormalizer

logger = logging.getLogger(__name__)

try:
    from google.cloud import vision
except ImportError:  # pragma: no cover - optional dependency in some environments.
    vision = None


class ImageRecognitionHandler:
    """
    Handles food image recognition workflow.
    
    Responsibilities:
    - Validate image files
    - Preprocess images if needed
    - Send to FatSecret recognition endpoint
    - Rank and process results
    - Fetch nutrition data for detected foods
    """

    # Image validation
    MAX_IMAGE_SIZE = 5 * 1024 * 1024  # 5MB
    ALLOWED_FORMATS = {"JPEG", "PNG", "JPG"}
    MAX_DIMENSION = 4096

    # Image preprocessing
    TARGET_SIZE = 1024  # Resize to this dimension if needed
    QUALITY = 85  # JPEG quality for compression

    def __init__(self, fatsecret_client: FatSecretClient):
        """
        Initialize handler with FatSecret client.
        
        Args:
            fatsecret_client: Authenticated FatSecretClient instance
        """
        self.config = get_config()
        self.client = fatsecret_client

    def recognize_food_from_image(
        self,
        image_data: bytes,
        content_type: str,
    ) -> Dict[str, Any]:
        """
        Process food image and recognize foods.
        
        Algorithm:
        1. Validate image data and content type
        2. Open and validate image file
        3. Preprocess if oversized
        4. Send to FatSecret for recognition
        5. Parse results, rank by confidence
        6. Fetch nutrition for each detected food
        7. Return ranked results with warnings
        
        Args:
            image_data: Raw image bytes
            content_type: MIME type (e.g., "image/jpeg")
            
        Returns:
            Dict with detected_foods, confidence_scores, warnings
            
        Raises:
            ImageError: If image is invalid
            FatSecretAPIError: If recognition fails
        """
        logger.info(f"Processing image: {len(image_data)} bytes, {content_type}")
        
        # Validate image
        self._validate_image_file(image_data, content_type)
        
        # Open image
        try:
            image = Image.open(io.BytesIO(image_data))
        except Exception as e:
            raise ImageError(f"Could not open image: {str(e)}")
        
        # Preprocess if needed
        warnings = []
        image_processed, warning = self._preprocess_image(image)
        if warning:
            warnings.append(warning)
        
        # Convert to bytes
        image_bytes = self._image_to_bytes(image_processed)
        logger.info(f"Image ready for recognition: {len(image_bytes)} bytes")
        
        # Send to FatSecret
        recognition_results = self._send_to_fatsecret_recognition(
            image_bytes,
            content_type,
        )
        
        if not recognition_results:
            raise NoResultsError("No foods detected in image")
        
        # Process results
        detected_foods = []
        confidence_scores = []
        
        for idx, raw_result in enumerate(recognition_results):
            try:
                # Extract food info
                food_id = raw_result.get("food_id")
                confidence = raw_result.get("confidence", 1.0 / len(recognition_results))
                
                if not food_id:
                    logger.warning(f"Result {idx} has no food_id, skipping")
                    continue
                
                # Get full nutrition details
                food_details = self.client.get_food_details(str(food_id))
                
                # Normalize nutrition data
                nutrition = NutritionNormalizer.normalize(
                    food_details,
                    source="fatsecret_image_recognition",
                    is_from_image=True,
                )
                
                detected_foods.append(nutrition)
                confidence_scores.append(confidence)
                
            except Exception as e:
                logger.warning(f"Could not process detected food {idx}: {str(e)}")
                warnings.append(f"Incomplete data for detected food #{idx + 1}")
                continue
        
        # Add warnings
        if len(detected_foods) > 1:
            warnings.append("Multiple foods detected - review and select the correct one")
        if any(f.needs_manual_review for f in detected_foods):
            warnings.append("Some detected foods have incomplete nutrition data")
        
        logger.info(f"Image recognition complete: {len(detected_foods)} foods detected")
        
        return {
            "detected_foods": detected_foods,
            "confidence_scores": confidence_scores,
            "warnings": warnings,
        }

    def detect_food_candidates(
        self,
        image_data: bytes,
        content_type: str,
    ) -> Dict[str, Any]:
        """
        Try FatSecret image recognition first, then fall back to Google Vision.

        Returns:
            Dict with:
            - source: "fatsecret" or "google_vision"
            - candidates: [{"food_id"?, "food_name", "confidence"}]
            - warnings: [str]
        """
        logger.info("Detecting food candidates for meal logging flow")

        self._validate_image_file(image_data, content_type)
        try:
            image = Image.open(io.BytesIO(image_data))
        except Exception as e:
            raise ImageError(f"Could not open image: {str(e)}")

        warnings = []
        image_processed, warning = self._preprocess_image(image)
        if warning:
            warnings.append(warning)

        image_bytes = self._image_to_bytes(image_processed)

        fatsecret_error = None
        try:
            fatsecret_results = self._send_to_fatsecret_recognition(
                image_bytes,
                content_type,
            )
            candidates = self._normalize_fatsecret_candidates(fatsecret_results)
            if candidates:
                return {
                    "source": "fatsecret",
                    "candidates": candidates,
                    "warnings": warnings,
                }
            warnings.append("FatSecret did not return any image matches.")
        except Exception as e:
            fatsecret_error = e
            logger.warning("FatSecret image recognition failed; falling back to Google Vision: %s", str(e))
            warnings.append("FatSecret image recognition failed. Falling back to Google Vision.")

        google_candidates = self._detect_with_google_vision(image_bytes)
        if not google_candidates:
            if fatsecret_error is not None:
                logger.error("Google Vision fallback returned no labels after FatSecret failure")
            return {
                "source": "unknown",
                "candidates": [],
                "warnings": warnings,
            }

        return {
            "source": "google_vision",
            "candidates": google_candidates,
            "warnings": warnings,
        }

    def _validate_image_file(self, image_data: bytes, content_type: str) -> None:
        """
        Validate image file size and type.
        
        Raises:
            ImageError: If validation fails
        """
        # Check size
        if len(image_data) > self.MAX_IMAGE_SIZE:
            raise ImageError(
                f"Image is too large. "
                f"Max size: {self.config.MAX_IMAGE_SIZE_MB}MB, "
                f"provided: {len(image_data) / 1024 / 1024:.1f}MB"
            )
        
        # Check MIME type
        allowed_types = self.config.ALLOWED_IMAGE_TYPES
        if content_type not in allowed_types:
            raise ImageError(
                f"Unsupported image type: {content_type}. "
                f"Allowed types: {', '.join(allowed_types)}"
            )

    def _preprocess_image(self, image: Image.Image) -> Tuple[Image.Image, Optional[str]]:
        """
        Preprocess image: resize if oversized, convert to RGB if needed.
        
        Args:
            image: PIL Image object
            
        Returns:
            Tuple of (processed_image, warning_message)
        """
        warning = None
        
        # Convert RGBA to RGB if needed
        if image.mode == "RGBA":
            rgb_image = Image.new("RGB", image.size, (255, 255, 255))
            rgb_image.paste(image, mask=image.split()[3])
            image = rgb_image
        elif image.mode != "RGB":
            image = image.convert("RGB")
        
        # Check dimensions
        width, height = image.size
        max_dim = max(width, height)
        
        if max_dim > self.MAX_DIMENSION:
            warning = f"Image dimensions reduced from {width}x{height}"
            ratio = max_dim / self.MAX_DIMENSION
            new_width = int(width / ratio)
            new_height = int(height / ratio)
            image = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
        elif max_dim > self.TARGET_SIZE:
            ratio = max_dim / self.TARGET_SIZE
            new_width = int(width / ratio)
            new_height = int(height / ratio)
            image = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
            warning = f"Image resized from {width}x{height} to {new_width}x{new_height}"
        
        return image, warning

    def _image_to_bytes(self, image: Image.Image) -> bytes:
        """Convert PIL Image to bytes."""
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=self.QUALITY)
        return buffer.getvalue()

    def _normalize_fatsecret_candidates(
        self,
        recognition_results: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """Normalize FatSecret image-recognition results to a shared candidate shape."""
        normalized = []
        for index, item in enumerate(recognition_results or []):
            if not isinstance(item, dict):
                continue

            food_name = (
                item.get("food_name")
                or item.get("name")
                or item.get("description")
                or item.get("label")
            )
            food_id = item.get("food_id") or item.get("foodId")
            confidence = item.get("confidence") or item.get("score")
            if confidence is None:
                confidence = max(0.1, 1.0 - (index * 0.1))

            if not food_name and not food_id:
                continue

            normalized.append(
                {
                    "food_id": str(food_id) if food_id else None,
                    "food_name": str(food_name or "Food").strip(),
                    "confidence": float(confidence),
                    "raw": item,
                }
            )

        return normalized

    def _detect_with_google_vision(self, image_bytes: bytes) -> List[Dict[str, Any]]:
        """Use Google Vision label detection as a fallback when FatSecret fails."""
        client = self._google_vision_client()
        if client is None:
            return []

        try:
            image = vision.Image(content=image_bytes)
            response = client.label_detection(image=image)
        except Exception as e:
            logger.error("Google Vision request failed: %s", str(e))
            return []

        if getattr(response, "error", None) and response.error.message:
            logger.error("Google Vision response error: %s", response.error.message)
            return []

        label_annotations = getattr(response, "label_annotations", []) or []
        candidates = []
        for label in label_annotations[:8]:
            description = str(getattr(label, "description", "") or "").strip()
            score = float(getattr(label, "score", 0.0) or 0.0)
            if not description or score < 0.55:
                continue
            candidates.append(
                {
                    "food_name": description,
                    "confidence": score,
                    "source": "google_vision",
                }
            )

        logger.info("Google Vision produced %s fallback labels", len(candidates))
        return candidates

    def _google_vision_client(self):
        """Build a Google Vision client if credentials and dependency are available."""
        if vision is None:
            logger.warning("google-cloud-vision is not installed; Google Vision fallback unavailable")
            return None

        credentials_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
        if credentials_path:
            if not os.path.isabs(credentials_path):
                credentials_path = os.path.join(
                    os.path.dirname(__file__),
                    credentials_path,
                )
            if os.path.exists(credentials_path):
                os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = credentials_path
            else:
                logger.warning(
                    "Google Vision credentials file not found at %s",
                    credentials_path,
                )

        try:
            return vision.ImageAnnotatorClient()
        except Exception as e:
            logger.error("Could not initialize Google Vision client: %s", str(e))
            return None

    def _send_to_fatsecret_recognition(
        self,
        image_bytes: bytes,
        content_type: str,
    ) -> List[Dict[str, Any]]:
        """
        Send image to FatSecret image recognition endpoint.
        
        Note: This uses direct REST API calls since the fatsecret library
        may not support image recognition. FatSecret's exact image recognition
        endpoint may vary - check their current API documentation.
        
        Args:
            image_bytes: Image data in bytes
            content_type: MIME type
            
        Returns:
            List of detected food results
            
        Raises:
            FatSecretAPIError: If request fails
        """
        # Note: FatSecret's image recognition endpoint and parameters
        # may differ. This is a template - adjust based on actual API.
        
        url = self.config.FATSECRET_IMAGE_UPLOAD_URL
        
        try:
            files = {"image": (("image.jpg", image_bytes, content_type))}
            
            # Add OAuth headers if needed
            # This depends on FatSecret's specific image endpoint requirements
            response = requests.post(
                url,
                files=files,
                timeout=self.config.REQUEST_TIMEOUT,
            )
            response.raise_for_status()
            
            data = response.json()
            logger.info("Image sent to FatSecret successfully")
            
            # Extract detected foods from response
            # Format depends on FatSecret's actual API response
            detected = data.get("detected_foods", data.get("foods", []))
            
            if not isinstance(detected, list):
                detected = [detected] if detected else []
            
            return detected
            
        except Exception as e:
            logger.error(f"Image recognition failed: {str(e)}")
            raise FatSecretAPIError(f"Image recognition failed: {str(e)}")
