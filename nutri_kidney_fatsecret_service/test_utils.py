"""
Testing utilities for NutriKidney FatSecret Service.
Provides mock clients and test fixtures for unit testing.
"""
from typing import Dict, Any, List, Optional
from unittest.mock import Mock, MagicMock
from models import Nutrition


class MockFatSecretClient:
    """Mock FatSecret client for testing without API calls."""

    def __init__(self):
        self.search_calls = []
        self.detail_calls = []

    def search_foods(self, query: str, page: int = 0) -> Dict[str, Any]:
        """Mock search that returns test data."""
        self.search_calls.append((query, page))
        
        # Return mock results based on query
        if query.lower() == "apple":
            return {
                "foods": [
                    {
                        "food_name": "Apple, medium",
                        "food_id": "12345",
                        "serving_size": 182,
                        "calories": 95,
                        "protein": 0.5,
                        "fat": 0.3,
                        "carbohydrates": 25.1,
                        "fiber": 4.4,
                        "sodium": 2.0,
                        "potassium": 195.0,
                        "phosphorus": 11.0,
                        "calcium": 11.0,
                    }
                ],
                "total_results": 1,
                "query": query,
            }
        
        return {
            "foods": [],
            "total_results": 0,
            "query": query,
        }

    def get_food_details(self, food_id: str) -> Dict[str, Any]:
        """Mock food details."""
        self.detail_calls.append(food_id)
        
        if food_id == "12345":
            return {
                "food_name": "Apple, medium",
                "food_id": "12345",
                "serving_size": 182,
                "serving_description": "1 medium apple (182g)",
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
            }
        
        raise ValueError(f"Food not found: {food_id}")

    def health_check(self) -> bool:
        """Mock health check."""
        return True


def create_test_nutrition(**overrides) -> Nutrition:
    """Create a test Nutrition object with sensible defaults."""
    defaults = {
        "food_name": "Test Food",
        "food_id": "test_123",
        "serving_description": "1 serving",
        "serving_size": 100.0,
        "calories": 100.0,
        "protein": 5.0,
        "fat": 3.0,
        "carbohydrates": 15.0,
        "fiber": 2.0,
        "sugar": 5.0,
        "sodium": 50.0,
        "potassium": 100.0,
        "phosphorus": 50.0,
        "calcium": 20.0,
        "is_estimated": False,
        "needs_manual_review": False,
        "missing_nutrients": [],
        "data_source": "test",
    }
    
    defaults.update(overrides)
    return Nutrition(**defaults)


def create_test_nutrition_missing_ckd_nutrients() -> Nutrition:
    """Create a test nutrition with missing CKD nutrients."""
    return create_test_nutrition(
        sodium=None,
        potassium=None,
        phosphorus=None,
        calcium=None,
        missing_nutrients=["sodium", "potassium", "phosphorus", "calcium"],
        needs_manual_review=True,
    )


def create_test_nutrition_from_image() -> Nutrition:
    """Create a test nutrition from image recognition."""
    return create_test_nutrition(
        food_name="Detected Food",
        needs_manual_review=True,
        is_estimated=True,
        phosphorus=None,
        missing_nutrients=["phosphorus"],
    )


# ==========================================
# EXAMPLE TEST SUITE
# ==========================================

def test_nutrition_normalizer():
    """Example test for nutrition normalizer."""
    from nutrition_normalizer import NutritionNormalizer
    
    print("Testing NutritionNormalizer...")
    
    # Test data extraction
    raw_data = {
        "food_name": "Apple",
        "calories": "95",
        "protein": "0.5",
        "sodium": 2.0,
    }
    
    nutrition = NutritionNormalizer.normalize(raw_data)
    
    assert nutrition.food_name == "Apple"
    assert nutrition.calories == 95.0
    assert nutrition.protein == 0.5
    assert nutrition.sodium == 2.0
    assert "potassium" in nutrition.missing_nutrients
    assert "phosphorus" in nutrition.missing_nutrients
    assert nutrition.needs_manual_review == True
    
    print("  ✓ Normalization works correctly")


def test_error_handling():
    """Example test for error handling."""
    from error_handler import ValidationError, ImageError, NoResultsError
    
    print("Testing error handling...")
    
    # Test validation error
    error = ValidationError("Test error", error_type="test_error")
    assert error.status_code == 400
    assert error.error_type == "test_error"
    
    error_dict = error.to_dict()
    assert error_dict["success"] == False
    assert error_dict["error"] == "Test error"
    
    print("  ✓ Error handling works correctly")


def test_response_formatter():
    """Example test for response formatting."""
    from response_formatter import ResponseFormatter
    
    print("Testing ResponseFormatter...")
    
    nutrition = create_test_nutrition()
    response = ResponseFormatter.food_detail_response(nutrition)
    
    assert response["success"] == True
    assert response["query_type"] == "food_detail"
    assert response["result"]["food_name"] == "Test Food"
    assert "timestamp" in response
    
    print("  ✓ Response formatting works correctly")


def test_mock_client():
    """Example test with mock client."""
    from nutrition_normalizer import NutritionNormalizer
    
    print("Testing with mock client...")
    
    client = MockFatSecretClient()
    
    # Test search
    results = client.search_foods("apple")
    assert len(results["foods"]) == 1
    assert results["foods"][0]["food_name"] == "Apple, medium"
    
    # Test details
    details = client.get_food_details("12345")
    assert details["food_name"] == "Apple, medium"
    
    # Normalize
    nutrition = NutritionNormalizer.normalize(details)
    assert nutrition.food_name == "Apple, medium"
    
    print("  ✓ Mock client works correctly")


def run_all_tests():
    """Run all example tests."""
    print("\n" + "=" * 60)
    print("Running Unit Tests")
    print("=" * 60 + "\n")
    
    tests = [
        test_nutrition_normalizer,
        test_error_handling,
        test_response_formatter,
        test_mock_client,
    ]
    
    passed = 0
    failed = 0
    
    for test in tests:
        try:
            test()
            passed += 1
        except AssertionError as e:
            print(f"  ✗ Test failed: {str(e)}")
            failed += 1
        except Exception as e:
            print(f"  ✗ Error: {str(e)}")
            failed += 1
    
    print("\n" + "=" * 60)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 60)
    
    return failed == 0


if __name__ == "__main__":
    import sys
    success = run_all_tests()
    sys.exit(0 if success else 1)
