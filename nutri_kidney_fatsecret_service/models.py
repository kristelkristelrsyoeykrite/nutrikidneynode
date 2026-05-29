"""
Data models and schemas for NutriKidney FatSecret service.
Uses Pydantic for validation and serialization.
"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field


class Nutrition(BaseModel):
    """Normalized nutrition data for a food."""
    food_name: str = Field(..., description="Name of the food")
    food_id: Optional[str] = Field(None, description="FatSecret food ID")
    serving_description: Optional[str] = Field(None, description="Serving size description (e.g., '1 medium apple')")
    serving_size: Optional[float] = Field(None, description="Serving size in grams or units")

    # Primary nutrients
    calories: Optional[float] = Field(None, description="Energy in kcal")
    protein: Optional[float] = Field(None, description="Protein in grams")
    fat: Optional[float] = Field(None, description="Fat in grams")
    carbohydrates: Optional[float] = Field(None, description="Carbohydrates in grams")
    fiber: Optional[float] = Field(None, description="Fiber in grams")
    sugar: Optional[float] = Field(None, description="Sugar in grams")

    # CKD-critical nutrients
    sodium: Optional[float] = Field(None, description="Sodium in mg (CRITICAL for CKD)")
    potassium: Optional[float] = Field(None, description="Potassium in mg (CRITICAL for CKD)")
    phosphorus: Optional[float] = Field(None, description="Phosphorus in mg (CRITICAL for CKD)")
    calcium: Optional[float] = Field(None, description="Calcium in mg (CRITICAL for CKD)")

    # Quality flags
    is_estimated: bool = Field(default=False, description="True if any values are estimated")
    needs_manual_review: bool = Field(default=False, description="True if manual verification recommended")
    missing_nutrients: List[str] = Field(default_factory=list, description="List of missing nutrient fields")
    data_source: str = Field(default="fatsecret", description="Source of data (fatsecret, image_recognition, etc.)")
    source: str = Field(default="fatsecret", description="Short source identifier for app clients")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "example": {
                "food_name": "Apple, medium",
                "food_id": "12345",
                "serving_description": "1 medium apple (182g)",
                "serving_size": 182.0,
                "calories": 95,
                "protein": 0.5,
                "fat": 0.3,
                "carbohydrates": 25.1,
                "fiber": 4.4,
                "sugar": 19.0,
                "sodium": 2.0,
                "potassium": 195.0,
                "phosphorus": 11.0,
                "calcium": 11.0,
                "is_estimated": False,
                "needs_manual_review": False,
                "missing_nutrients": [],
                "data_source": "fatsecret"
            }
        }


class FoodSearchResult(BaseModel):
    """Result from food text search."""
    foods: List[Nutrition] = Field(..., description="List of matching foods")
    total_results: int = Field(..., description="Total number of results found")
    query: str = Field(..., description="Original search query")
    source: str = Field(default="fatsecret_text_search")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "example": {
                "foods": [],  # See Nutrition.Config.json_schema_extra
                "total_results": 10,
                "query": "apple",
                "source": "fatsecret_text_search"
            }
        }


class ImageRecognitionResult(BaseModel):
    """Result from food image recognition."""
    detected_foods: List[Nutrition] = Field(..., description="List of detected foods ranked by confidence")
    confidence_scores: Optional[List[float]] = Field(None, description="Confidence scores (0-1) for each detection")
    warnings: List[str] = Field(default_factory=list, description="Warnings about image quality or accuracy")
    source: str = Field(default="fatsecret_image_recognition")
    needs_manual_review: bool = Field(default=True, description="Recommend manual review for image results")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "example": {
                "detected_foods": [],  # See Nutrition.Config.json_schema_extra
                "confidence_scores": [0.95, 0.78],
                "warnings": ["Multiple foods detected", "Consider manual verification"],
                "source": "fatsecret_image_recognition",
                "needs_manual_review": True
            }
        }


class SuccessResponse(BaseModel):
    """Successful API response."""
    success: bool = Field(default=True)
    query_type: str = Field(..., description="Type of query: 'text_search', 'food_detail', 'image_recognition'")
    result: Optional[Any] = Field(None, description="The actual result (FoodSearchResult, Nutrition, ImageRecognitionResult, etc.)")
    timestamp: str = Field(..., description="ISO format timestamp")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "example": {
                "success": True,
                "query_type": "text_search",
                "result": {
                    "foods": [],
                    "total_results": 1,
                    "query": "apple",
                    "source": "fatsecret_text_search"
                },
                "timestamp": "2024-04-23T10:30:00Z"
            }
        }


class ErrorResponse(BaseModel):
    """Error API response."""
    success: bool = Field(default=False)
    error: str = Field(..., description="Error message")
    error_type: str = Field(..., description="Error type for programmatic handling")
    details: Dict[str, Any] = Field(default_factory=dict, description="Additional error details")
    timestamp: str = Field(..., description="ISO format timestamp")

    class Config:
        """Pydantic config."""
        json_schema_extra = {
            "example": {
                "success": False,
                "error": "Invalid food ID",
                "error_type": "invalid_food_id",
                "details": {"food_id": "abc123"},
                "timestamp": "2024-04-23T10:30:00Z"
            }
        }


class MealNutrients(BaseModel):
    """Normalized nutrient values for a single serving or final meal."""
    calories: Optional[float] = None
    protein: Optional[float] = None
    fat: Optional[float] = None
    carbohydrate: Optional[float] = None
    sodium: Optional[float] = None
    potassium: Optional[float] = None
    phosphorus: Optional[float] = None
    fiber: Optional[float] = None
    sugar: Optional[float] = None
    calcium: Optional[float] = None
    iron: Optional[float] = None
    cholesterol: Optional[float] = None
    saturated_fat: Optional[float] = None
    vitamin_a: Optional[float] = None
    vitamin_c: Optional[float] = None
    vitamin_d: Optional[float] = None


class MealServing(BaseModel):
    """A selectable serving returned from FatSecret."""
    serving_id: str
    serving_description: Optional[str] = None
    metric_serving_amount: Optional[float] = None
    metric_serving_unit: Optional[str] = None
    number_of_units: Optional[float] = None
    measurement_description: Optional[str] = None
    display_text: str = "Serving"
    nutrients: MealNutrients = Field(default_factory=MealNutrients)
    raw_serving: Dict[str, Any] = Field(default_factory=dict)
    is_derived_display_only: bool = False


class ChildProfileContext(BaseModel):
    """Child-specific CKD context used for meal interpretation."""
    child_profile_id: str
    age: Optional[float] = None
    ckd_stage: str = "unknown"
    dialysis_status: str = "unknown"
    diet_pattern: str = "unknown"
    fluid_restriction_status: str = "unknown"
    allergies: List[str] = Field(default_factory=list)
    targets: Dict[str, float] = Field(default_factory=dict)


class MealLoggingFoodChoice(BaseModel):
    """Compact search result for the staged meal-logging flow."""
    food_id: str
    food_name: str
    brand_name: Optional[str] = None
    food_type: Optional[str] = None
    food_url: Optional[str] = None
    preview_description: Optional[str] = None


class MealLoggingSearchResult(BaseModel):
    """Search response for the meal-logging flow."""
    query: str
    normalized_query: str
    choices: List[MealLoggingFoodChoice] = Field(default_factory=list)
    total_results: int = 0


class MealFoodDetailsResult(BaseModel):
    """Detailed food response with selectable servings."""
    food_id: str
    food_name: str
    brand_name: Optional[str] = None
    food_type: Optional[str] = None
    servings: List[MealServing] = Field(default_factory=list)
    phosphorus_tag: str = "phosphorus data unavailable, use caution"
    phosphorus_confidence: str = "unknown"
    phosphorus_note: str = ""
    phosphorus: Dict[str, Any] = Field(default_factory=dict)
    potassium_reliability_note: str = ""
    safety_flags: List[Dict[str, Any]] = Field(default_factory=list)


class MealPreviewRequest(BaseModel):
    """Input payload for previewing a meal log before save."""
    user_id: str
    child_profile_id: str
    food_id: str
    serving_id: str
    quantity: float
    meal_type: str
    logged_at: datetime
    user_notes: Optional[str] = None
    child_context: Optional[ChildProfileContext] = None


class MealPreviewResult(BaseModel):
    """Preview response with calculated nutrients and safety notes."""
    preview_id: str
    user_id: str
    child_profile_id: str
    meal_type: str
    logged_at: datetime
    food_id: str
    food_name: str
    brand_name: Optional[str] = None
    food_type: Optional[str] = None
    selected_serving_id: str
    selected_serving_description: Optional[str] = None
    selected_quantity: float
    base_serving: MealServing
    base_serving_nutrients: MealNutrients
    final_nutrients: MealNutrients
    phosphorus_tag: str
    phosphorus_confidence: str
    phosphorus_note: str
    potassium_reliability_note: str
    safety_flags: List[Dict[str, Any]] = Field(default_factory=list)
    insights: List[Dict[str, Any]] = Field(default_factory=list)
    fluid_contribution: Dict[str, Any] = Field(default_factory=dict)
    child_context_snapshot: ChildProfileContext
    user_notes: Optional[str] = None


class MealLogRecord(MealPreviewResult):
    """Persisted meal log record."""
    meal_log_id: str
    created_at: datetime
    updated_at: datetime
    deleted_at: Optional[datetime] = None


class MealSaveRequest(MealPreviewRequest):
    """Input payload for saving a finalized meal log."""
    pass


class MealSaveResult(BaseModel):
    """Response after saving a meal log."""
    meal_log: MealLogRecord
    daily_summary_status: str
    audit_status: str
