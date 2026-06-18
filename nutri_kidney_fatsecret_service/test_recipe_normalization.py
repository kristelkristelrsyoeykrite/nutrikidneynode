#!/usr/bin/env python3
"""
Quick test to verify recipe normalization from NutritionNormalizer.
"""
import json
from models import Nutrition
from nutrition_normalizer import NutritionNormalizer

# Simulate a recipe response from FatSecret's recipe.get
fatsecret_recipe_response = {
    "recipe_id": "12345",
    "recipe_name": "Grilled Chicken with Rice",
    "recipe_description": "A healthy meal",
    "serving_size": 250,
    "serving_description": "1 plate (250g)",
    "calories": 450,
    "protein": 35.5,
    "fat": 12.0,
    "carbohydrates": 45.0,
    "fiber": 2.0,
    "sugar": 1.0,
    "sodium": 520,
    "potassium": 380,
    "phosphorus": 280,
    "calcium": 45,
    "source": "fatsecret_recipe",
    "ingredients": [
        {"food_name": "Chicken Breast", "serving_description": "150g"},
        {"food_name": "White Rice", "serving_description": "100g"},
    ]
}

# Test normalization
print("Testing NutritionNormalizer.normalize()...")
print("=" * 60)

try:
    nutrition = NutritionNormalizer.normalize(
        fatsecret_recipe_response,
        source="fatsecret_recipe",
        is_from_image=False,
    )
    
    print("✓ Normalization successful!")
    print("\nNormalized Nutrition object:")
    print(json.dumps(nutrition.model_dump(), indent=2))
    
    # Verify critical fields
    print("\n" + "=" * 60)
    print("Verification of critical CKD nutrients:")
    print("=" * 60)
    critical_nutrients = {
        "sodium": nutrition.sodium,
        "potassium": nutrition.potassium,
        "phosphorus": nutrition.phosphorus,
        "calcium": nutrition.calcium,
    }
    
    for nutrient, value in critical_nutrients.items():
        status = "✓" if value and value > 0 else "✗"
        print(f"{status} {nutrient}: {value}")
    
    print("\nOther key nutrients:")
    print(f"  calories: {nutrition.calories}")
    print(f"  protein: {nutrition.protein}")
    print(f"  carbohydrates: {nutrition.carbohydrates}")
    print(f"  fat: {nutrition.fat}")
    
    print("\nMetadata:")
    print(f"  needs_manual_review: {nutrition.needs_manual_review}")
    print(f"  is_estimated: {nutrition.is_estimated}")
    print(f"  missing_nutrients: {nutrition.missing_nutrients}")
    
except Exception as e:
    print(f"✗ Normalization failed: {e}")
    import traceback
    traceback.print_exc()

print("\n" + "=" * 60)
print("Test complete!")
