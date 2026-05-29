"""
Nutrition data normalizer.
Converts FatSecret API responses to NutriKidney nutrition model.
Handles missing fields, estimates, and CKD-specific logic.
"""
from typing import Optional, Dict, Any, List
from models import Nutrition
from config import get_config


class NutritionNormalizer:
    """
    Normalizes raw FatSecret nutrition data to NutriKidney format.
    
    Responsibilities:
    - Extract and map nutrition fields
    - Flag missing or estimated values
    - Identify CKD-critical nutrients
    - Mark items for manual review
    """

    # Field mapping: FatSecret key -> (NutriKidney key, is_critical_for_ckd)
    FIELD_MAPPING = {
        "food_name": ("food_name", False),
        "food_id": ("food_id", False),
        "serving_size": ("serving_size", False),
        "serving_description": ("serving_description", False),
        "calories": ("calories", False),
        "protein": ("protein", False),
        "fat": ("fat", False),
        "carbohydrates": ("carbohydrates", False),
        "carbs": ("carbohydrates", False),
        "fiber": ("fiber", False),
        "sugar": ("sugar", False),
        "sodium": ("sodium", True),  # CKD critical
        "potassium": ("potassium", True),  # CKD critical
        "phosphorus": ("phosphorus", True),  # CKD critical
        "calcium": ("calcium", True),  # CKD critical
    }

    # Required fields for a valid result
    REQUIRED_FIELDS = ["food_name", "food_id"]

    # Critical CKD nutrients that should trigger review if missing
    CKD_CRITICAL_NUTRIENTS = ["sodium", "potassium", "phosphorus", "calcium"]

    @staticmethod
    def normalize(
        raw_data: Dict[str, Any],
        source: str = "fatsecret",
        is_from_image: bool = False,
    ) -> Nutrition:
        """
        Normalize raw FatSecret data to Nutrition model.
        
        Args:
            raw_data: Raw response from FatSecret API
            source: Data source identifier
            is_from_image: Whether data came from image recognition
            
        Returns:
            Normalized Nutrition object
        """
        config = get_config()
        
        # Extract values
        extracted = NutritionNormalizer._extract_fields(raw_data)
        
        # Track missing fields
        missing_nutrients = NutritionNormalizer._identify_missing_fields(extracted)
        
        # Determine if manual review is needed
        needs_review = (
            is_from_image  # Image results always need review
            or bool(missing_nutrients)  # Missing CKD nutrients require review
        )
        
        # Create nutrition object
        nutrition = Nutrition(
            food_name=extracted.get("food_name", "Unknown"),
            food_id=extracted.get("food_id"),
            serving_description=extracted.get("serving_description"),
            serving_size=extracted.get("serving_size"),
            calories=extracted.get("calories"),
            protein=extracted.get("protein"),
            fat=extracted.get("fat"),
            carbohydrates=extracted.get("carbohydrates"),
            fiber=extracted.get("fiber"),
            sugar=extracted.get("sugar"),
            sodium=extracted.get("sodium"),
            potassium=extracted.get("potassium"),
            phosphorus=extracted.get("phosphorus"),
            calcium=extracted.get("calcium"),
            is_estimated=NutritionNormalizer._has_estimates(raw_data),
            needs_manual_review=needs_review,
            missing_nutrients=missing_nutrients,
            data_source=source,
            source=source,
        )
        
        return nutrition

    @staticmethod
    def _extract_fields(raw_data: Dict[str, Any]) -> Dict[str, Optional[float]]:
        """
        Extract and normalize nutrient fields from raw data.
        
        Handles:
        - Multiple naming conventions (e.g., "carbs" vs "carbohydrates")
        - Type conversion to float
        - Null/zero value handling
        """
        extracted = {}
        
        for raw_key, (normalized_key, _) in NutritionNormalizer.FIELD_MAPPING.items():
            value = raw_data.get(raw_key)
            
            # Skip missing values
            if value is None or value == "":
                continue
            
            # Convert to float, handle errors gracefully
            try:
                if isinstance(value, str):
                    # Remove common units (mg, g, etc.)
                    value = value.split()[0]
                float_value = float(value)
                
                # Only store positive values
                if float_value > 0:
                    extracted[normalized_key] = float_value
            except (ValueError, IndexError, AttributeError):
                # Skip values that can't be converted
                continue
        
        return extracted

    @staticmethod
    def _identify_missing_fields(extracted: Dict[str, Optional[float]]) -> List[str]:
        """
        Identify critical CKD nutrients that are missing.
        
        Returns list of missing nutrient names that should trigger review.
        """
        missing = []
        
        for nutrient in NutritionNormalizer.CKD_CRITICAL_NUTRIENTS:
            if nutrient not in extracted:
                missing.append(nutrient)
        
        return missing

    @staticmethod
    def _has_estimates(raw_data: Dict[str, Any]) -> bool:
        """
        Check if data contains estimated/calculated values.
        
        FatSecret may mark some values as estimates.
        This helps NutriKidney flag uncertain data.
        """
        # Check for estimate flags in raw data
        if raw_data.get("is_estimated") or raw_data.get("estimated"):
            return True
        
        # Check if any values appear to be rounded estimates
        # (This is a heuristic - very round numbers might be estimates)
        suspicious_fields = ["sodium", "potassium", "phosphorus"]
        for field in suspicious_fields:
            value = raw_data.get(field)
            if value and isinstance(value, (int, float)):
                # Values ending in 00 or 000 might be estimates
                if value > 100 and value % 100 == 0:
                    return True
        
        return False

    @staticmethod
    def normalize_batch(
        raw_data_list: List[Dict[str, Any]],
        source: str = "fatsecret",
        is_from_image: bool = False,
    ) -> List[Nutrition]:
        """
        Normalize multiple results at once.
        
        Args:
            raw_data_list: List of raw data objects
            source: Data source identifier
            is_from_image: Whether data came from image recognition
            
        Returns:
            List of normalized Nutrition objects
        """
        return [
            NutritionNormalizer.normalize(item, source, is_from_image)
            for item in raw_data_list
        ]

    @staticmethod
    def get_summary(nutrition: Nutrition) -> Dict[str, Any]:
        """
        Get a summary of nutrition data quality.
        Useful for CKD assessment.
        """
        ckd_nutrients = {
            "sodium": nutrition.sodium,
            "potassium": nutrition.potassium,
            "phosphorus": nutrition.phosphorus,
            "calcium": nutrition.calcium,
        }
        
        available_ckd = {k: v for k, v in ckd_nutrients.items() if v is not None}
        
        return {
            "total_fields": len([v for v in vars(nutrition).values() if v and v != False]),
            "missing_fields": len(nutrition.missing_nutrients),
            "ckd_nutrients_available": len(available_ckd),
            "ckd_nutrients_total": len(ckd_nutrients),
            "is_complete": len(nutrition.missing_nutrients) == 0,
            "needs_review": nutrition.needs_manual_review,
            "is_estimated": nutrition.is_estimated,
        }
