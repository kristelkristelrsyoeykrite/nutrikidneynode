"""
Response formatter for NutriKidney service.
Formats all responses consistently for the Flutter app.
Handles both success and error cases.
"""
from typing import Dict, Any, Optional, List
from datetime import datetime
from models import (
    Nutrition,
    FoodSearchResult,
    ImageRecognitionResult,
    SuccessResponse,
    ErrorResponse,
)
from error_handler import NutriKidneyServiceError
import logging

logger = logging.getLogger(__name__)


class ResponseFormatter:
    """
    Formats service responses for API consumption.
    
    Ensures consistency across all endpoints:
    - Uniform success/error structure
    - Timestamps on all responses
    - Proper HTTP status codes
    - Safe error messages
    """

    @staticmethod
    def get_timestamp() -> str:
        """Get current timestamp in ISO format."""
        return datetime.utcnow().isoformat() + "Z"

    @staticmethod
    def food_search_response(
        foods: List[Nutrition],
        query: str,
        total_results: int,
    ) -> Dict[str, Any]:
        """
        Format food search response.
        
        Args:
            foods: List of normalized Nutrition objects
            query: Original search query
            total_results: Total matching results
            
        Returns:
            Formatted response dict
        """
        result = FoodSearchResult(
            foods=foods,
            total_results=total_results,
            query=query,
        )

        response = SuccessResponse(
            success=True,
            query_type="text_search",
            result=result.model_dump(),
            timestamp=ResponseFormatter.get_timestamp(),
        )

        logger.info(f"Food search response: {len(foods)} results for '{query}'")
        return response.model_dump()

    @staticmethod
    def success_response(query_type: str, result: Any) -> Dict[str, Any]:
        """Format a generic success response for newer meal-logging flows."""
        if hasattr(result, "model_dump"):
            result = result.model_dump()

        response = SuccessResponse(
            success=True,
            query_type=query_type,
            result=result,
            timestamp=ResponseFormatter.get_timestamp(),
        )
        return response.model_dump()

    @staticmethod
    def food_detail_response(nutrition: Nutrition) -> Dict[str, Any]:
        """
        Format food detail response.
        
        Args:
            nutrition: Normalized Nutrition object
            
        Returns:
            Formatted response dict
        """
        response = SuccessResponse(
            success=True,
            query_type="food_detail",
            result=nutrition.model_dump(),
            timestamp=ResponseFormatter.get_timestamp(),
        )

        logger.info(f"Food detail response: {nutrition.food_name}")
        return response.model_dump()

    @staticmethod
    def recipe_search_response(
        recipes: List[Nutrition],
        query: str,
        total_results: int,
    ) -> Dict[str, Any]:
        """
        Format recipe search response.
        
        Args:
            recipes: List of normalized Nutrition objects from recipes
            query: Original search query
            total_results: Total matching results
            
        Returns:
            Formatted response dict
        """
        result = FoodSearchResult(
            foods=recipes,  # Reuse FoodSearchResult since structure is similar
            total_results=total_results,
            query=query,
        )

        response = SuccessResponse(
            success=True,
            query_type="recipe_search",
            result=result.model_dump(),
            timestamp=ResponseFormatter.get_timestamp(),
        )

        logger.info(f"Recipe search response: {len(recipes)} results for '{query}'")
        return response.model_dump()

    @staticmethod
    def recipe_detail_response(
        nutrition: Nutrition,
        ingredients: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """
        Format recipe detail response.
        
        Args:
            nutrition: Normalized Nutrition object from recipe
            ingredients: List of ingredient objects if available
            
        Returns:
            Formatted response dict
        """
        result = nutrition.model_dump()
        if ingredients:
            result["ingredients"] = ingredients

        response = SuccessResponse(
            success=True,
            query_type="recipe_detail",
            result=result,
            timestamp=ResponseFormatter.get_timestamp(),
        )

        logger.info(f"Recipe detail response: {nutrition.food_name}")
        return response.model_dump()

    @staticmethod
    def image_recognition_response(
        detected_foods: List[Nutrition],
        confidence_scores: List[float],
        warnings: List[str],
    ) -> Dict[str, Any]:
        """
        Format image recognition response.
        
        Args:
            detected_foods: List of detected Nutrition objects
            confidence_scores: Confidence scores for each detection
            warnings: List of warning messages
            
        Returns:
            Formatted response dict
        """
        result = ImageRecognitionResult(
            detected_foods=detected_foods,
            confidence_scores=confidence_scores,
            warnings=warnings,
            needs_manual_review=True,
        )

        response = SuccessResponse(
            success=True,
            query_type="image_recognition",
            result=result.model_dump(),
            timestamp=ResponseFormatter.get_timestamp(),
        )

        logger.info(
            f"Image recognition response: {len(detected_foods)} foods detected, "
            f"{len(warnings)} warnings"
        )
        return response.model_dump()

    @staticmethod
    def error_response(error: Exception, status_code: int = 500) -> tuple:
        """
        Format error response.
        
        Args:
            error: Exception that occurred
            status_code: HTTP status code
            
        Returns:
            Tuple of (response_dict, http_status_code)
        """
        if isinstance(error, NutriKidneyServiceError):
            error_dict = error.to_dict()
            status_code = error.status_code
        else:
            # Generic error for unknown exceptions
            logger.error(f"Unexpected error: {str(error)}", exc_info=True)
            error_dict = {
                "success": False,
                "error": "An unexpected error occurred",
                "error_type": "unknown",
                "details": {},
            }

        response = ErrorResponse(
            success=False,
            error=error_dict.get("error", "Unknown error"),
            error_type=error_dict.get("error_type", "unknown"),
            details=error_dict.get("details", {}),
            timestamp=ResponseFormatter.get_timestamp(),
        )

        logger.warning(
            f"Error response: {response.error_type} - {response.error}"
        )
        return response.model_dump(), status_code

    @staticmethod
    def health_check_response(is_healthy: bool) -> Dict[str, Any]:
        """
        Format health check response.
        
        Args:
            is_healthy: Whether service is healthy
            
        Returns:
            Formatted response dict
        """
        if is_healthy:
            response = SuccessResponse(
                success=True,
                query_type="health_check",
                result={"status": "healthy"},
                timestamp=ResponseFormatter.get_timestamp(),
            )
        else:
            response = ErrorResponse(
                success=False,
                error="Service is not healthy",
                error_type="service_unhealthy",
                details={},
                timestamp=ResponseFormatter.get_timestamp(),
            )

        return response.model_dump()

    @staticmethod
    def batch_response(
        results: List[Dict[str, Any]],
        query_type: str,
    ) -> Dict[str, Any]:
        """
        Format batch response for multiple operations.
        
        Args:
            results: List of individual results
            query_type: Type of batch query
            
        Returns:
            Formatted response dict
        """
        response = SuccessResponse(
            success=True,
            query_type=query_type,
            result={
                "batch_results": results,
                "count": len(results),
            },
            timestamp=ResponseFormatter.get_timestamp(),
        )

        logger.info(f"Batch response: {len(results)} results")
        return response.model_dump()

    @staticmethod
    def format_for_flutter(data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Ensure response is Flutter-friendly.
        
        - No complex nested objects
        - Serializable types only
        - Consistent naming conventions
        
        Args:
            data: Response data
            
        Returns:
            Flutter-compatible response
        """
        # Already formatted by Pydantic models
        # This is a convenience method for any custom formatting
        return data
