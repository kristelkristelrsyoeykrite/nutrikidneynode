#!/usr/bin/env python3
"""
Test to verify recipe normalization handles both field naming conventions.
"""
import json
from models import Nutrition
from nutrition_normalizer import NutritionNormalizer

# Test 1: FatSecret API response with recipe_* fields
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
}

# Test 2: Python Nutrition model response with food_* fields
python_nutrition_response = {
    "food_id": "12345",
    "food_name": "Grilled Chicken with Rice",
    "serving_description": "1 plate (250g)",
    "serving_size": 250.0,
    "calories": 450.0,
    "protein": 35.5,
    "fat": 12.0,
    "carbohydrates": 45.0,
    "fiber": 2.0,
    "sugar": 1.0,
    "sodium": 520.0,
    "potassium": 380.0,
    "phosphorus": 280.0,
    "calcium": 45.0,
    "source": "fatsecret_recipe",
    "is_estimated": False,
    "needs_manual_review": False,
}

def test_normalization(test_name, data):
    print(f"\n{'='*60}")
    print(f"Test: {test_name}")
    print(f"{'='*60}")
    
    try:
        nutrition = NutritionNormalizer.normalize(
            data,
            source="fatsecret_recipe",
            is_from_image=False,
        )
        
        print(f"✓ {test_name} successful!")
        print(f"\nKey fields:")
        print(f"  food_name: {nutrition.food_name}")
        print(f"  food_id: {nutrition.food_id}")
        print(f"  calories: {nutrition.calories}")
        print(f"  sodium: {nutrition.sodium}")
        print(f"  potassium: {nutrition.potassium}")
        print(f"  phosphorus: {nutrition.phosphorus}")
        
        # Verify no missing nutrients
        if nutrition.missing_nutrients:
            print(f"⚠ WARNING: Missing nutrients: {nutrition.missing_nutrients}")
        else:
            print(f"✓ All CKD nutrients present")
        
        return True
        
    except Exception as e:
        print(f"✗ {test_name} failed: {e}")
        import traceback
        traceback.print_exc()
        return False

# Run tests
print("Testing Recipe Normalization with Different Field Names")
print("="*60)

result1 = test_normalization("FatSecret API response (recipe_* fields)", fatsecret_recipe_response)
result2 = test_normalization("Python Nutrition response (food_* fields)", python_nutrition_response)

print(f"\n{'='*60}")
print("Summary:")
print(f"{'='*60}")
print(f"FatSecret format: {'✓ PASS' if result1 else '✗ FAIL'}")
print(f"Python format:   {'✓ PASS' if result2 else '✗ FAIL'}")
print(f"Overall:         {'✓ ALL TESTS PASSED' if (result1 and result2) else '✗ SOME TESTS FAILED'}")
