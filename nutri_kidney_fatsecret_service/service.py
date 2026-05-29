"""
NutriKidney FatSecret Service - Main service class.
Orchestrates all components for the complete food recognition and lookup workflow.

Service workflow:
1. Initialize with FatSecret client and handlers
2. Accept requests (text search, food details, image recognition)
3. Validate input
4. Call appropriate handler
5. Normalize results
6. Format response
7. Return to caller
"""
import logging
from typing import Dict, Any, List, Optional
from fatsecret_client import FatSecretClient
from nutrition_normalizer import NutritionNormalizer
from response_formatter import ResponseFormatter
from error_handler import NutriKidneyServiceError, ValidationError
from models import Nutrition
from usda_client import USDAFoodDataClient

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class NutriKidneyFatSecretService:
    """
    Main service class that orchestrates all FatSecret operations.
    
    Provides unified interface for:
    - Food text search
    - Food detail lookup
    - Food image recognition
    - Nutrition data normalization
    - Response formatting
    """

    def __init__(self):
        """Initialize service with all components."""
        logger.info("Initializing NutriKidney FatSecret Service...")
        
        try:
            self.fatsecret_client = FatSecretClient()
            self.usda_client = USDAFoodDataClient()
            # Lazy-init image handler only when image endpoints are called.
            self._image_handler = None
            logger.info("Service initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize service: {str(e)}")
            raise

    def search_foods(self, query: str, page: int = 0) -> Dict[str, Any]:
        """
        Search for foods by text query.
        
        Algorithm:
        1. Validate query input
        2. Call FatSecret API for text search
        3. Normalize results to Nutrition objects
        4. Format response for app
        
        Args:
            query: Food search query (e.g., "apple", "chicken breast")
            page: Page number for pagination (0-indexed)
            
        Returns:
            Formatted response with food results
            
        Raises:
            Various NutriKidneyServiceError subclasses
        """
        logger.info(f"Search foods: '{query}' (page {page})")
        
        try:
            normalized_foods = []
            total = 0

            fatsecret_error = None
            try:
                raw_results = self.fatsecret_client.search_foods(query, page)
                foods_list = raw_results.get("foods", [])
                total += raw_results.get("total_results", len(foods_list))
                normalized_foods.extend(
                    NutritionNormalizer.normalize_batch(
                        foods_list,
                        source="fatsecret",
                        is_from_image=False,
                    )
                )
            except NutriKidneyServiceError as e:
                fatsecret_error = e
                logger.warning("FatSecret search did not return results: %s", str(e))

            usda_error = None
            try:
                usda_results = self.usda_client.search_foods(query, page)
                usda_foods = usda_results.get("foods", [])
                total += usda_results.get("total_results", len(usda_foods))
                normalized_foods.extend(
                    NutritionNormalizer.normalize_batch(
                        usda_foods,
                        source="usda",
                        is_from_image=False,
                    )
                )
            except NutriKidneyServiceError as e:
                usda_error = e
                logger.warning("USDA search did not return results: %s", str(e))

            if not normalized_foods:
                raise fatsecret_error or usda_error or ValidationError("No foods found")
            
            # Format response
            response = ResponseFormatter.food_search_response(
                foods=normalized_foods,
                query=query,
                total_results=total,
            )
            
            logger.info(f"Food search complete: {len(normalized_foods)} results")
            return response
            
        except NutriKidneyServiceError:
            # Re-raise service errors as-is
            raise
        except Exception as e:
            logger.error(f"Food search failed: {str(e)}")
            raise

    def get_food_details(self, food_id: str) -> Dict[str, Any]:
        """
        Get detailed nutrition information for a specific food.
        
        Algorithm:
        1. Validate food ID
        2. Fetch food details from FatSecret
        3. Normalize nutrition data
        4. Check for missing CKD-critical nutrients
        5. Format response
        
        Args:
            food_id: FatSecret food ID (usually numeric string)
            
        Returns:
            Formatted response with complete nutrition data
            
        Raises:
            ValidationError: If food_id is invalid
            FatSecretAPIError: If API request fails
        """
        logger.info(f"Get food details: ID {food_id}")
        
        try:
            if USDAFoodDataClient.is_usda_food_id(food_id):
                raw_details = self.usda_client.get_food_details(food_id)
                source = "usda"
            else:
                raw_details = self.fatsecret_client.get_food_details(food_id)
                source = "fatsecret"
            
            # Normalize nutrition data
            nutrition = NutritionNormalizer.normalize(
                raw_details,
                source=source,
                is_from_image=False,
            )
            
            # Format response
            response = ResponseFormatter.food_detail_response(nutrition)
            
            logger.info(f"Food details retrieved: {nutrition.food_name}")
            return response
            
        except NutriKidneyServiceError:
            raise
        except Exception as e:
            logger.error(f"Get food details failed: {str(e)}")
            raise

    def recognize_food_from_image(
        self,
        image_data: bytes,
        content_type: str,
    ) -> Dict[str, Any]:
        """
        Recognize foods from an uploaded image.
        
        Algorithm:
        1. Validate image (size, type, format)
        2. Preprocess if needed (resize, quality)
        3. Send to FatSecret image recognition
        4. Parse results and rank by confidence
        5. Fetch nutrition for each detected food
        6. Normalize and flag for manual review
        7. Format response with warnings
        
        Args:
            image_data: Raw image bytes
            content_type: MIME type (e.g., "image/jpeg")
            
        Returns:
            Formatted response with detected foods and warnings
            
        Raises:
            ImageError: If image validation fails
            FatSecretAPIError: If recognition fails
            NoResultsError: If no foods detected
        """
        logger.info(
            f"Recognize food from image: {len(image_data)} bytes, {content_type}"
        )
        
        try:
            if self._image_handler is None:
                # Lazy import to keep startup fast (PIL/vision deps live here).
                from image_recognition import ImageRecognitionHandler  # local import

                self._image_handler = ImageRecognitionHandler(self.fatsecret_client)

            # Handle image recognition
            recognition_result = self._image_handler.recognize_food_from_image(
                image_data,
                content_type,
            )
            
            # Format response
            response = ResponseFormatter.image_recognition_response(
                detected_foods=recognition_result["detected_foods"],
                confidence_scores=recognition_result["confidence_scores"],
                warnings=recognition_result["warnings"],
            )
            
            logger.info(
                f"Image recognition complete: "
                f"{len(recognition_result['detected_foods'])} foods detected"
            )
            return response
            
        except NutriKidneyServiceError:
            raise
        except Exception as e:
            logger.error(f"Image recognition failed: {str(e)}")
            raise

    def get_nutrition_summary(self, nutrition: Nutrition) -> Dict[str, Any]:
        """
        Get a summary of nutrition data quality for CKD assessment.
        
        Useful for determining if a food result needs manual review
        before being added to a meal log.
        
        Args:
            nutrition: Nutrition object
            
        Returns:
            Summary dict with data quality metrics
        """
        return NutritionNormalizer.get_summary(nutrition)

    def health_check(self) -> Dict[str, Any]:
        """
        Check service health and FatSecret API connectivity.
        
        Returns:
            Health status response
        """
        logger.info("Health check requested")
        
        try:
            is_healthy = self.fatsecret_client.health_check()
            response = ResponseFormatter.health_check_response(is_healthy)
            logger.info(f"Health check: {'healthy' if is_healthy else 'unhealthy'}")
            return response
        except Exception as e:
            logger.error(f"Health check failed: {str(e)}")
            return ResponseFormatter.health_check_response(False)


# Module-level instance for easy importing
_service_instance: Optional[NutriKidneyFatSecretService] = None


def get_service() -> NutriKidneyFatSecretService:
    """Get or create singleton service instance."""
    global _service_instance
    if _service_instance is None:
        _service_instance = NutriKidneyFatSecretService()
    return _service_instance


# Example usage and testing
if __name__ == "__main__":
    print("NutriKidney FatSecret Service")
    print("=" * 50)
    
    # Initialize service
    service = get_service()
    
    # Example 1: Health check
    print("\n1. Health Check")
    try:
        health = service.health_check()
        print(f"   Status: {health.get('result', {}).get('status', 'unknown')}")
    except Exception as e:
        print(f"   Error: {str(e)}")
    
    # Example 2: Search foods
    print("\n2. Food Search")
    try:
        results = service.search_foods("apple")
        foods = results.get("result", {}).get("foods", [])
        print(f"   Found {len(foods)} results")
        if foods:
            first_food = foods[0]
            print(f"   First result: {first_food.get('food_name')}")
            print(f"   Calories: {first_food.get('calories')} kcal")
            print(f"   Protein: {first_food.get('protein')}g")
            print(f"   Needs review: {first_food.get('needs_manual_review')}")
    except Exception as e:
        print(f"   Error: {str(e)}")
    
    # Example 3: Get food details
    print("\n3. Food Details")
    print("   (Requires valid food ID from search)")
    
    print("\n" + "=" * 50)
    print("Service demonstration complete")
