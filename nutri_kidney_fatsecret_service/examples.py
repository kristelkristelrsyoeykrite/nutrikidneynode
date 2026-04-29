"""
Quick start examples for NutriKidney FatSecret Service.
Shows common usage patterns for the Flutter app and backend.
"""

# ==========================================
# EXAMPLE 1: Direct Service Usage
# ==========================================

def example_direct_service():
    """Using the service directly in Python."""
    from service import get_service
    
    print("=" * 60)
    print("EXAMPLE 1: Direct Service Usage")
    print("=" * 60)
    
    # Initialize service
    service = get_service()
    
    # 1. Health check
    print("\n1. Health Check")
    health = service.health_check()
    print(f"   Service Status: {health['result']['status']}")
    
    # 2. Search foods
    print("\n2. Search Foods")
    search_result = service.search_foods("apple", page=0)
    foods = search_result["result"]["foods"]
    print(f"   Found {len(foods)} results")
    
    if foods:
        first_food = foods[0]
        print(f"\n   First Result:")
        print(f"   - Name: {first_food['food_name']}")
        print(f"   - ID: {first_food['food_id']}")
        print(f"   - Calories: {first_food.get('calories', 'N/A')} kcal")
        print(f"   - Protein: {first_food.get('protein', 'N/A')}g")
        print(f"   - Sodium: {first_food.get('sodium', 'N/A')}mg (CKD CRITICAL)")
        print(f"   - Potassium: {first_food.get('potassium', 'N/A')}mg (CKD CRITICAL)")
        print(f"   - Missing nutrients: {first_food['missing_nutrients']}")
        print(f"   - Needs manual review: {first_food['needs_manual_review']}")
        
        # 3. Get food details
        print(f"\n3. Get Food Details for ID: {first_food['food_id']}")
        try:
            details_result = service.get_food_details(first_food['food_id'])
            food_detail = details_result["result"]
            
            print(f"   - Serving: {food_detail['serving_description']}")
            print(f"   - Carbs: {food_detail.get('carbohydrates', 'N/A')}g")
            print(f"   - Fat: {food_detail.get('fat', 'N/A')}g")
            print(f"   - Fiber: {food_detail.get('fiber', 'N/A')}g")
            print(f"   - Calcium: {food_detail.get('calcium', 'N/A')}mg (CKD CRITICAL)")
            print(f"   - Phosphorus: {food_detail.get('phosphorus', 'N/A')}mg (CKD CRITICAL)")
        except Exception as e:
            print(f"   Error: {str(e)}")


# ==========================================
# EXAMPLE 2: REST API Usage (cURL)
# ==========================================

def example_rest_api():
    """Using the REST API with HTTP requests."""
    print("\n" + "=" * 60)
    print("EXAMPLE 2: REST API Usage (cURL)")
    print("=" * 60)
    
    print("""
1. Start the server:
   $ uvicorn main:app --reload --host 0.0.0.0 --port 8000

2. Health check:
   $ curl "http://localhost:8000/api/health"

3. Search foods:
   $ curl "http://localhost:8000/api/v1/foods/search?query=apple&page=0"

4. Get food details:
   $ curl "http://localhost:8000/api/v1/foods/12345"

5. Recognize from image:
   $ curl -X POST "http://localhost:8000/api/v1/foods/recognize-image" \\
     -F "file=@/path/to/meal.jpg"

6. View API documentation:
   Open browser to: http://localhost:8000/docs
    """)


# ==========================================
# EXAMPLE 3: Flutter Integration
# ==========================================

def example_flutter_integration():
    """Example of how Flutter app would use this service."""
    print("\n" + "=" * 60)
    print("EXAMPLE 3: Flutter Integration")
    print("=" * 60)
    
    print("""
// In your Flutter app (Dart):

// 1. Search foods
Future<void> searchFoods(String query) async {
  try {
    final response = await http.get(
      Uri.parse('http://api.example.com/api/v1/foods/search')
          .replace(queryParameters: {'query': query, 'page': '0'}),
    );
    
    final data = json.decode(response.body);
    if (data['success']) {
      final foods = data['result']['foods'];
      // Display foods in ListView
      // User selects one
    }
  } catch (e) {
    showError('Search failed: $e');
  }
}

// 2. Get food details
Future<void> getFoodDetails(String foodId) async {
  try {
    final response = await http.get(
      Uri.parse('http://api.example.com/api/v1/foods/$foodId'),
    );
    
    final data = json.decode(response.body);
    if (data['success']) {
      final nutrition = data['result'];
      
      // Check if manual review needed
      if (nutrition['needs_manual_review']) {
        showWarning('Please verify nutrition information');
      }
      
      // Check for missing CKD nutrients
      if (nutrition['missing_nutrients'].isNotEmpty) {
        showWarning(
          'Missing data: ${nutrition["missing_nutrients"].join(", ")}'
        );
      }
      
      // Display nutrition data
      displayNutrition(nutrition);
    }
  } catch (e) {
    showError('Could not load food details: $e');
  }
}

// 3. Image recognition
Future<void> recognizeFoodFromImage(File imageFile) async {
  try {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://api.example.com/api/v1/foods/recognize-image'),
    );
    
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        await imageFile.readAsBytes(),
        filename: 'meal.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    );
    
    final response = await request.send();
    final responseData = await response.stream.bytesToString();
    final data = json.decode(responseData);
    
    if (data['success']) {
      final detectedFoods = data['result']['detected_foods'];
      final warnings = data['result']['warnings'];
      
      // Show all detected foods to user
      // Warnings: "Multiple foods detected", etc.
      // User selects the correct one
      showWarnings(warnings);
      showFoodCandidates(detectedFoods);
    }
  } catch (e) {
    showError('Image recognition failed: $e');
  }
}

// 4. Add to meal log after user confirms
Future<void> addToMealLog(Nutrition nutrition) async {
  // User confirmed food is correct
  // Can now log the nutrition data to health metrics
  // Pass nutrition object to your meal logging endpoint
  
  // Important: Image recognition results should always
  // show warnings and require manual confirmation
}
    """)


# ==========================================
# EXAMPLE 4: CKD-Aware Nutrition Handling
# ==========================================

def example_ckd_awareness():
    """How the service handles CKD-critical nutrients."""
    print("\n" + "=" * 60)
    print("EXAMPLE 4: CKD-Aware Nutrition Handling")
    print("=" * 60)
    
    from service import get_service
    
    service = get_service()
    
    # Search for a food
    results = service.search_foods("chicken")
    if results["success"]:
        foods = results["result"]["foods"]
        
        for food in foods[:3]:  # Show first 3
            print(f"\nFood: {food['food_name']}")
            print(f"  Serving: {food['serving_description']}")
            
            # Display CKD-critical nutrients
            ckd_nutrients = {
                'sodium': ('Sodium', 'mg'),
                'potassium': ('Potassium', 'mg'),
                'phosphorus': ('Phosphorus', 'mg'),
                'calcium': ('Calcium', 'mg'),
            }
            
            print("  CKD-Critical Nutrients:")
            for key, (name, unit) in ckd_nutrients.items():
                value = food.get(key)
                if value:
                    print(f"    ✓ {name}: {value} {unit}")
                else:
                    print(f"    ✗ {name}: Missing")
            
            if food['missing_nutrients']:
                print(f"  ⚠ Missing: {', '.join(food['missing_nutrients'])}")
            
            if food['needs_manual_review']:
                print(f"  ⚠ Needs manual review")


# ==========================================
# EXAMPLE 5: Error Handling
# ==========================================

def example_error_handling():
    """Demonstrating error handling patterns."""
    print("\n" + "=" * 60)
    print("EXAMPLE 5: Error Handling")
    print("=" * 60)
    
    from service import get_service
    from error_handler import NutriKidneyServiceError
    
    service = get_service()
    
    # Example 1: Invalid query
    print("\n1. Invalid Query:")
    try:
        service.search_foods("")  # Empty query
    except NutriKidneyServiceError as e:
        print(f"   Error type: {e.error_type}")
        print(f"   Message: {e.message}")
        print(f"   HTTP Status: {e.status_code}")
    
    # Example 2: Invalid food ID
    print("\n2. Invalid Food ID:")
    try:
        service.get_food_details("not_a_number")
    except NutriKidneyServiceError as e:
        print(f"   Error type: {e.error_type}")
        print(f"   Message: {e.message}")
    
    # Example 3: Image too large
    print("\n3. Image Too Large:")
    try:
        large_image = b"x" * (10 * 1024 * 1024)  # 10MB
        service.recognize_food_from_image(large_image, "image/jpeg")
    except NutriKidneyServiceError as e:
        print(f"   Error type: {e.error_type}")
        print(f"   Message: {e.message}")


# ==========================================
# EXAMPLE 6: Nutrition Quality Assessment
# ==========================================

def example_nutrition_quality():
    """Assessing nutrition data quality."""
    print("\n" + "=" * 60)
    print("EXAMPLE 6: Nutrition Quality Assessment")
    print("=" * 60)
    
    from service import get_service
    from nutrition_normalizer import NutritionNormalizer
    
    service = get_service()
    
    # Get a food
    results = service.search_foods("apple")
    if results["success"]:
        food = results["result"]["foods"][0]
        print(f"\nFood: {food['food_name']}")
        
        # Get full details
        details = service.get_food_details(food['food_id'])
        nutrition = details["result"]
        
        # Assess quality
        summary = NutritionNormalizer.get_summary(nutrition)
        
        print(f"  Total fields: {summary['total_fields']}")
        print(f"  Missing fields: {summary['missing_fields']}")
        print(f"  CKD nutrients available: {summary['ckd_nutrients_available']}/{summary['ckd_nutrients_total']}")
        print(f"  Is complete: {summary['is_complete']}")
        print(f"  Needs review: {summary['needs_review']}")
        print(f"  Is estimated: {summary['is_estimated']}")


# ==========================================
# MAIN
# ==========================================

if __name__ == "__main__":
    import sys
    
    examples = {
        "1": ("Direct Service Usage", example_direct_service),
        "2": ("REST API Usage (cURL)", example_rest_api),
        "3": ("Flutter Integration", example_flutter_integration),
        "4": ("CKD-Aware Nutrition", example_ckd_awareness),
        "5": ("Error Handling", example_error_handling),
        "6": ("Nutrition Quality Assessment", example_nutrition_quality),
    }
    
    print("\n" + "=" * 60)
    print("NutriKidney FatSecret Service - Examples")
    print("=" * 60)
    print("\nSelect an example to run:")
    
    for key, (name, _) in examples.items():
        print(f"  {key}. {name}")
    print("  q. Quit")
    
    choice = input("\nEnter your choice: ").strip().lower()
    
    if choice == "q":
        sys.exit(0)
    elif choice in examples:
        name, func = examples[choice]
        try:
            func()
        except Exception as e:
            print(f"\nError running example: {str(e)}")
            import traceback
            traceback.print_exc()
    else:
        print("\nInvalid choice")
    
    print("\n" + "=" * 60)
