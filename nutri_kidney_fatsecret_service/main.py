"""
FastAPI application for NutriKidney FatSecret Service.
Provides REST endpoints for the Flutter app to consume.

Endpoints:
- POST /api/v1/foods/search - Search foods by text
- GET /api/v1/foods/{food_id} - Get food details
- POST /api/v1/foods/recognize-image - Recognize foods from image
- GET /api/health - Health check
"""
import base64
from fastapi import FastAPI, HTTPException, File, UploadFile, Query, Body
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import logging
from typing import Optional

from service import get_service
from meal_logging import get_meal_logging_service
from models import MealPreviewRequest
from response_formatter import ResponseFormatter
from error_handler import NutriKidneyServiceError, ValidationError

logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="NutriKidney FatSecret Service",
    description="Food recognition and nutrition lookup service for pediatric CKD management",
    version="1.0.0",
)

# Enable CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to your app domains
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ==========================================
# ENDPOINTS
# ==========================================

@app.get("/api/health", tags=["Health"])
async def health_check():
    """
    Check service health and FatSecret API connectivity.
    
    Returns:
        Health status
    """
    try:
        service = get_service()
        result = service.health_check()
        return result
    except Exception as e:
        logger.error(f"Health check error: {str(e)}")
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)


@app.post("/api/v1/foods/search", tags=["Food Search"])
async def search_foods(
    query: str = Query(..., min_length=2, max_length=100, description="Food search query"),
    page: int = Query(0, ge=0, description="Page number for pagination"),
):
    """
    Search for foods by text query.
    
    Algorithm:
    1. Validate query
    2. Search FatSecret database
    3. Normalize results
    4. Return food list with nutrition data
    
    Args:
        query: Food name or description to search (e.g., "apple", "grilled chicken")
        page: Results page number (0-indexed)
        
    Returns:
        List of matching foods with nutrition information
        
    Example:
        GET /api/v1/foods/search?query=apple&page=0
    """
    try:
        service = get_service()
        result = service.search_foods(query, page)
        return result
    except NutriKidneyServiceError as e:
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)
    except Exception as e:
        logger.error(f"Search foods error: {str(e)}")
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)


@app.get("/api/v1/foods/{food_id}", tags=["Food Details"])
async def get_food_details(food_id: str):
    """
    Get detailed nutrition information for a specific food.
    
    Algorithm:
    1. Validate food ID
    2. Fetch from FatSecret
    3. Normalize all nutrition fields
    4. Flag if CKD-critical nutrients missing
    5. Return complete data
    
    Args:
        food_id: FatSecret food ID (from search results)
        
    Returns:
        Complete nutrition data for the food
        
    Example:
        GET /api/v1/foods/12345
    """
    try:
        service = get_service()
        result = service.get_food_details(food_id)
        return result
    except NutriKidneyServiceError as e:
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)
    except Exception as e:
        logger.error(f"Get food details error: {str(e)}")
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)


@app.post("/api/v1/foods/recognize-image", tags=["Image Recognition"])
async def recognize_food_from_image(file: UploadFile = File(...)):
    """
    Recognize foods from an uploaded image.
    
    Algorithm:
    1. Validate image file
    2. Preprocess if needed
    3. Send to FatSecret image recognition
    4. Fetch nutrition for detected foods
    5. Rank by confidence
    6. Flag for manual review
    
    Args:
        file: Image file (JPEG, PNG; max 5MB)
        
    Returns:
        List of detected foods ranked by confidence, with warnings
        
    Important:
        - Image recognition results are typically uncertain
        - Always marked as "needs_manual_review": true
        - App should show all candidates and let user select
        - Not recommended for automatic meal logging
        
    Example:
        POST /api/v1/foods/recognize-image
        (multipart form with image file)
    """
    try:
        service = get_service()
        
        # Read image data
        image_data = await file.read()
        content_type = file.content_type or "image/jpeg"
        
        # Recognize food
        result = service.recognize_food_from_image(image_data, content_type)
        return result
        
    except NutriKidneyServiceError as e:
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)
    except Exception as e:
        logger.error(f"Image recognition error: {str(e)}")
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)


@app.post("/meal-logging/search", tags=["Meal Logging"])
async def meal_logging_search(payload: dict = Body(...)):
    """Search foods for the staged meal-logging flow."""
    try:
        query = str(payload.get("query", "")).strip()
        page = int(payload.get("page", 0) or 0)
        service = get_meal_logging_service()
        return service.search(query, page)
    except NutriKidneyServiceError as e:
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)
    except Exception as e:
        logger.error(f"Meal logging search error: {str(e)}", exc_info=True)
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)


@app.get("/meal-logging/food/{food_id}", tags=["Meal Logging"])
async def meal_logging_food_details(food_id: str):
    """Return food details with servings for the staged meal-logging flow."""
    try:
        service = get_meal_logging_service()
        return service.food_details(food_id)
    except NutriKidneyServiceError as e:
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)
    except Exception as e:
        logger.error(f"Meal logging food details error: {str(e)}", exc_info=True)
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)


@app.post("/meal-logging/recognize-image", tags=["Meal Logging"])
async def meal_logging_recognize_image(payload: dict = Body(...)):
    """Recognize a food image from base64 JSON for the staged meal-logging flow."""
    try:
        image_base64 = payload.get("image_base64") or payload.get("imageBase64")
        content_type = payload.get("content_type") or payload.get("contentType") or "image/jpeg"
        if not image_base64:
            raise ValidationError("image_base64 is required")

        try:
            image_data = base64.b64decode(image_base64, validate=True)
        except Exception as e:
            raise ValidationError(
                f"image_base64 must be valid base64 data: {str(e)}"
            ) from e

        service = get_meal_logging_service()
        return service.recognize_image(image_data, content_type)
    except NutriKidneyServiceError as e:
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)
    except Exception as e:
        logger.error(f"Meal logging recognize image error: {str(e)}", exc_info=True)
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)


@app.post("/meal-logging/preview", tags=["Meal Logging"])
async def meal_logging_preview(payload: dict = Body(...)):
    """Preview meal nutrients before saving."""
    try:
        service = get_meal_logging_service()
        request = MealPreviewRequest(**payload)
        return service.preview(request)
    except NutriKidneyServiceError as e:
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)
    except Exception as e:
        logger.error(f"Meal logging preview error: {str(e)}", exc_info=True)
        error_response, status_code = ResponseFormatter.error_response(e)
        raise HTTPException(status_code=status_code, detail=error_response)


# ==========================================
# ROOT ENDPOINT
# ==========================================

@app.get("/", tags=["Info"])
async def root():
    """
    Root endpoint - returns service information.
    """
    return {
        "service": "NutriKidney FatSecret Service",
        "version": "1.0.0",
        "description": "Food recognition and nutrition lookup for pediatric CKD",
        "documentation": "/docs",
        "endpoints": {
            "health": "GET /api/health",
            "search_foods": "POST /api/v1/foods/search?query=<food>&page=<page>",
            "food_details": "GET /api/v1/foods/<food_id>",
            "image_recognition": "POST /api/v1/foods/recognize-image",
        },
    }


# ==========================================
# ERROR HANDLERS
# ==========================================

@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    """Handle HTTP exceptions."""
    return JSONResponse(
        status_code=exc.status_code,
        content=exc.detail,
    )


if __name__ == "__main__":
    import uvicorn
    
    # Run development server
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level="info",
    )
