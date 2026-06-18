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
import base64
import logging
import time
from typing import Dict, Any, List, Optional, Tuple, TYPE_CHECKING
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

if TYPE_CHECKING:  # pragma: no cover
    from PIL import Image  # noqa: F401


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
        self._fatsecret_access_token: Optional[str] = None
        self._fatsecret_token_expires_at = 0.0

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
            from PIL import Image
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
            from PIL import Image
            image = Image.open(io.BytesIO(image_data))
        except Exception as e:
            raise ImageError(f"Could not open image: {str(e)}")

        warnings = []
        image_processed, warning = self._preprocess_image(image)
        if warning:
            warnings.append(warning)

        image_bytes = self._image_to_bytes(image_processed)

        fatsecret_error = None
        fatsecret_candidates = []
        try:
            fatsecret_results = self._send_to_fatsecret_recognition(
                image_bytes,
                content_type,
            )
            fatsecret_candidates = self._normalize_fatsecret_candidates(
                fatsecret_results
            )
            if fatsecret_candidates:
                logger.info(
                    "Using %s FatSecret image candidates; Google Vision fallback skipped",
                    len(fatsecret_candidates),
                )
                return {
                    "source": "fatsecret",
                    "candidates": fatsecret_candidates,
                    "fatsecret_candidates": fatsecret_candidates,
                    "google_candidates": [],
                    "warnings": warnings,
                }
            warnings.append("FatSecret did not return any usable image matches.")
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
            "fatsecret_candidates": [],
            "google_candidates": google_candidates,
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

    def _preprocess_image(self, image: Any) -> Tuple[Any, Optional[str]]:
        """
        Preprocess image: resize if oversized, convert to RGB if needed.
        
        Args:
            image: PIL Image object
            
        Returns:
            Tuple of (processed_image, warning_message)
        """
        from PIL import Image

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

    def _image_to_bytes(self, image: Any) -> bytes:
        """Convert PIL Image to bytes."""
        from PIL import Image
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

            nested_food = item.get("food")
            food_data = nested_food if isinstance(nested_food, dict) else item
            food_name = (
                food_data.get("food_name")
                or food_data.get("food_entry_name")
                or food_data.get("food_label")
                or food_data.get("food_description")
                or food_data.get("name")
                or food_data.get("description")
                or food_data.get("label")
                or food_data.get("suggestion")
                or food_data.get("title")
            )
            food_id = food_data.get("food_id") or food_data.get("foodId")
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
                    "source": "fatsecret_image_recognition",
                    "raw": item,
                }
            )

        return normalized

    def _detect_with_google_vision(self, image_bytes: bytes) -> List[Dict[str, Any]]:
        """Use several Google Vision signals to build food search candidates."""
        vision_mod, client = self._google_vision_client()
        if client is None:
            return []

        try:
            image = vision_mod.Image(content=image_bytes)
            features = [
                vision_mod.Feature(
                    type_=vision_mod.Feature.Type.LABEL_DETECTION,
                    max_results=12,
                ),
                vision_mod.Feature(
                    type_=vision_mod.Feature.Type.OBJECT_LOCALIZATION,
                    max_results=10,
                ),
                vision_mod.Feature(
                    type_=vision_mod.Feature.Type.WEB_DETECTION,
                    max_results=10,
                ),
                vision_mod.Feature(
                    type_=vision_mod.Feature.Type.TEXT_DETECTION,
                    max_results=10,
                ),
            ]
            response = client.annotate_image(
                {
                    "image": image,
                    "features": features,
                }
            )
        except Exception as e:
            logger.error("Google Vision request failed: %s", str(e))
            return []

        if getattr(response, "error", None) and response.error.message:
            logger.error("Google Vision response error: %s", response.error.message)
            return []

        candidates_by_name: Dict[str, Dict[str, Any]] = {}

        def add_candidate(description: str, score: float, signal: str) -> None:
            description = " ".join(str(description or "").strip().split())
            normalized = description.lower()
            if not description or len(description) < 2:
                return

            existing = candidates_by_name.get(normalized)
            candidate = {
                "food_name": description,
                "confidence": round(max(0.0, min(1.0, float(score))), 4),
                "source": "google_vision",
                "vision_signal": signal,
            }
            if existing is None or candidate["confidence"] > existing["confidence"]:
                candidates_by_name[normalized] = candidate

        for label in (getattr(response, "label_annotations", []) or [])[:12]:
            score = float(getattr(label, "score", 0.0) or 0.0)
            if score >= 0.55:
                add_candidate(getattr(label, "description", ""), score, "label")

        for detected_object in (
            getattr(response, "localized_object_annotations", []) or []
        )[:10]:
            score = float(getattr(detected_object, "score", 0.0) or 0.0)
            if score >= 0.50:
                add_candidate(
                    getattr(detected_object, "name", ""),
                    score,
                    "object",
                )

        web_detection = getattr(response, "web_detection", None)
        for entity in (getattr(web_detection, "web_entities", []) or [])[:10]:
            score = float(getattr(entity, "score", 0.0) or 0.0)
            if score >= 0.45:
                add_candidate(
                    getattr(entity, "description", ""),
                    score,
                    "web",
                )

        # Text can identify packaged foods or menu labels. Keep only short lines so
        # receipts and long scene text do not become food search queries.
        text_annotations = getattr(response, "text_annotations", []) or []
        full_text = (
            str(getattr(text_annotations[0], "description", "") or "")
            if text_annotations
            else ""
        )
        text_noise_tokens = {
            "amount",
            "change",
            "date",
            "official receipt",
            "receipt",
            "subtotal",
            "tax",
            "total",
        }
        for line in full_text.splitlines()[:8]:
            words = line.split()
            normalized_line = " ".join(line.lower().split())
            if (
                1 <= len(words) <= 5
                and any(char.isalpha() for char in line)
                and normalized_line not in text_noise_tokens
            ):
                add_candidate(line, 0.60, "text")

        signal_bonus = {"web": 0.12, "text": 0.05, "label": 0.04, "object": 0.0}
        candidates = sorted(
            candidates_by_name.values(),
            key=lambda item: float(item.get("confidence") or 0.0)
            + signal_bonus.get(str(item.get("vision_signal")), 0.0),
            reverse=True,
        )[:20]

        logger.info(
            "Google Vision produced %s fused fallback candidates",
            len(candidates),
        )
        return candidates

    def _google_vision_client(self):
        """Build a Google Vision client if credentials and dependency are available."""
        try:
            from google.cloud import vision  # type: ignore
        except Exception:
            logger.warning("google-cloud-vision is not installed; Google Vision fallback unavailable")
            return None, None

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
            return vision, vision.ImageAnnotatorClient()
        except Exception as e:
            logger.error("Could not initialize Google Vision client: %s", str(e))
            return None, None

    def _send_to_fatsecret_recognition(
        self,
        image_bytes: bytes,
        content_type: str,
    ) -> List[Dict[str, Any]]:
        """Send an image to FatSecret's OAuth2 image-recognition v2 endpoint.

        Args:
            image_bytes: Image data in bytes
            content_type: MIME type
            
        Returns:
            List of detected food results
            
        Raises:
            FatSecretAPIError: If request fails
        """
        url = self.config.FATSECRET_IMAGE_UPLOAD_URL

        try:
            access_token = self._get_fatsecret_image_access_token()
            payload = {
                "image_b64": base64.b64encode(image_bytes).decode("ascii"),
                "include_food_data": True,
                "region": "US",
                "language": "en",
            }
            response = None
            attempts = max(1, self.config.FATSECRET_IMAGE_RETRIES + 1)
            for attempt in range(attempts):
                try:
                    response = requests.post(
                        url,
                        json=payload,
                        headers={
                            "Authorization": f"Bearer {access_token}",
                            "Content-Type": "application/json",
                        },
                        timeout=self.config.FATSECRET_IMAGE_TIMEOUT,
                    )
                    break
                except requests.exceptions.Timeout:
                    if attempt + 1 >= attempts:
                        raise
                    logger.warning(
                        "FatSecret image recognition timed out after %ss; "
                        "retrying once",
                        self.config.FATSECRET_IMAGE_TIMEOUT,
                    )

            if response is None:
                raise FatSecretAPIError(
                    "FatSecret image recognition did not return a response."
                )
            response.raise_for_status()

            data = response.json()
            fatsecret_error = self._fatsecret_api_error(data)
            if fatsecret_error:
                code, message = fatsecret_error
                logger.warning(
                    "FatSecret image recognition API error %s: %s",
                    code,
                    message,
                )
                raise FatSecretAPIError(
                    f"FatSecret image recognition API error {code}: {message}",
                    details={
                        "fatsecret_error": {
                            "code": code,
                            "message": message,
                        }
                    },
                )

            logger.info("Image sent to FatSecret successfully")

            results = self._extract_fatsecret_recognition_results(data)
            if not results:
                logger.warning(
                    "FatSecret returned no parseable foods. Response schema: %s",
                    self._fatsecret_response_schema(data),
                )
            return results

        except requests.exceptions.RequestException as e:
            logger.error("FatSecret image recognition request failed: %s", str(e))
            raise FatSecretAPIError(
                f"FatSecret image recognition request failed: {str(e)}"
            )
        except (TypeError, ValueError) as e:
            logger.error("FatSecret image recognition returned invalid JSON: %s", str(e))
            raise FatSecretAPIError(
                f"FatSecret image recognition returned invalid data: {str(e)}"
            )

    @staticmethod
    def _fatsecret_api_error(data: Any) -> Optional[Tuple[str, str]]:
        """Extract FatSecret errors returned inside an HTTP 200 JSON response."""
        if not isinstance(data, dict):
            return None

        error = data.get("error")
        if not isinstance(error, dict):
            return None

        code = str(error.get("code") or "unknown").strip()
        message = str(error.get("message") or "Unknown FatSecret error").strip()
        return code, message

    def _get_fatsecret_image_access_token(self) -> str:
        """Get and briefly cache an OAuth2 token with image-recognition scope."""
        now = time.time()
        if (
            self._fatsecret_access_token
            and now < self._fatsecret_token_expires_at
        ):
            return self._fatsecret_access_token

        try:
            response = requests.post(
                self.config.FATSECRET_OAUTH2_TOKEN_URL,
                auth=(
                    self.config.FATSECRET_CLIENT_ID,
                    self.config.FATSECRET_CLIENT_SECRET,
                ),
                data={
                    "grant_type": "client_credentials",
                    "scope": self.config.FATSECRET_IMAGE_RECOGNITION_SCOPE,
                },
                headers={
                    "Accept": "application/json",
                    "Content-Type": "application/x-www-form-urlencoded",
                },
                timeout=self.config.REQUEST_TIMEOUT,
            )
            if not response.ok:
                error_message = self._fatsecret_oauth_error_message(response)
                raise FatSecretAPIError(
                    "Could not authenticate FatSecret image recognition: "
                    f"{error_message}"
                )
            token_data = response.json()
        except FatSecretAPIError:
            raise
        except requests.exceptions.RequestException as e:
            raise FatSecretAPIError(
                f"Could not authenticate FatSecret image recognition: {str(e)}"
            )
        except (TypeError, ValueError) as e:
            raise FatSecretAPIError(
                f"FatSecret OAuth2 returned invalid data: {str(e)}"
            )

        access_token = token_data.get("access_token")
        if not access_token:
            raise FatSecretAPIError(
                "FatSecret OAuth2 response did not include an access token."
            )

        try:
            expires_in = max(60, int(token_data.get("expires_in", 3600)))
        except (TypeError, ValueError):
            expires_in = 3600

        self._fatsecret_access_token = str(access_token)
        self._fatsecret_token_expires_at = now + max(30, expires_in - 60)
        return self._fatsecret_access_token

    @staticmethod
    def _fatsecret_oauth_error_message(response: requests.Response) -> str:
        """Return useful OAuth error details without exposing credentials."""
        status = f"HTTP {response.status_code}"
        try:
            error_data = response.json()
        except (TypeError, ValueError):
            error_data = None

        if isinstance(error_data, dict):
            error = str(error_data.get("error") or "").strip()
            description = str(
                error_data.get("error_description")
                or error_data.get("message")
                or ""
            ).strip()
            details = ": ".join(part for part in (error, description) if part)
            if details:
                return f"{status} ({details})"

        return status

    @staticmethod
    def _extract_fatsecret_recognition_results(
        data: Any,
    ) -> List[Dict[str, Any]]:
        """Find food candidates across FatSecret's nested response containers."""
        results = []
        seen = set()
        name_keys = {
            "food_name",
            "food_entry_name",
            "food_label",
            "food_description",
            "name",
            "description",
            "label",
            "suggestion",
            "title",
        }
        id_keys = {"food_id", "foodId"}

        def visit(value: Any) -> None:
            if isinstance(value, list):
                for child in value:
                    visit(child)
                return
            if not isinstance(value, dict):
                return

            nested_food = value.get("food")
            candidate = nested_food if isinstance(nested_food, dict) else value
            has_name = any(candidate.get(key) for key in name_keys)
            has_id = any(candidate.get(key) for key in id_keys)
            if has_name or has_id:
                identity = (
                    str(candidate.get("food_id") or candidate.get("foodId") or ""),
                    str(
                        candidate.get("food_name")
                        or candidate.get("food_entry_name")
                        or candidate.get("food_label")
                        or candidate.get("food_description")
                        or candidate.get("name")
                        or candidate.get("description")
                        or candidate.get("label")
                        or candidate.get("suggestion")
                        or candidate.get("title")
                        or ""
                    ).lower(),
                )
                if identity not in seen:
                    seen.add(identity)
                    results.append(value)
                return

            for child in value.values():
                visit(child)

        visit(data)
        logger.info(
            "FatSecret image response contained %s usable candidate records",
            len(results),
        )
        return results

    @staticmethod
    def _fatsecret_response_schema(data: Any) -> str:
        """Summarize response paths without logging nutrition values or secrets."""
        paths = []

        def visit(value: Any, path: str, depth: int) -> None:
            if len(paths) >= 80 or depth > 6:
                return
            if isinstance(value, dict):
                keys = sorted(str(key) for key in value.keys())
                paths.append(f"{path or '$'}:object({','.join(keys[:20])})")
                for key, child in value.items():
                    normalized_key = str(key).lower()
                    if normalized_key in {
                        "access_token",
                        "client_id",
                        "client_secret",
                        "image",
                        "image_b64",
                    }:
                        continue
                    visit(child, f"{path}.{key}" if path else f"$.{key}", depth + 1)
            elif isinstance(value, list):
                paths.append(f"{path}:array[{len(value)}]")
                if value:
                    visit(value[0], f"{path}[0]", depth + 1)
            else:
                paths.append(f"{path}:{type(value).__name__}")

        visit(data, "", 0)
        return " | ".join(paths)
