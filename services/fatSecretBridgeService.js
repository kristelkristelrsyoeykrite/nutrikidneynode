const DEFAULT_PYTHON_BASE_URL = "https://nutrikidneyfatsecretpythonservice.onrender.com";

const pythonBaseUrl =
  process.env.FATSECRET_PYTHON_BASE_URL || DEFAULT_PYTHON_BASE_URL;

function buildPythonUrl(path, query = {}) {
  const url = new URL(path, pythonBaseUrl);
  Object.entries(query).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== "") {
      url.searchParams.set(key, String(value));
    }
  });
  return url;
}

async function callPythonService(path, options = {}) {
  const { query, method = "GET", body, headers } = options;
  const url = buildPythonUrl(path, query);

  let response;
  try {
    response = await fetch(url, {
      method,
      headers: body
        ? { "Content-Type": "application/json", ...(headers || {}) }
        : headers,
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch (error) {
    const wrapped = new Error(
      `FatSecret Python service unavailable at ${pythonBaseUrl}`,
    );
    wrapped.cause = error;
    wrapped.statusCode = 503;
    throw wrapped;
  }

  const text = await response.text();
  let data = {};
  if (text) {
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = { raw: text };
    }
  }

  console.log("PYTHON_SERVICE_RESPONSE:", {
    path,
    method,
    status: response.status,
    ok: response.ok,
    dataKeys: Object.keys(data),
    hasResult: "result" in data,
    resultType: typeof data.result,
  });

  if (!response.ok) {
    const detail = data?.detail;
    const error = new Error(
      data?.error?.message ||
        (typeof detail?.error === "string" ? detail.error : undefined) ||
        detail?.error?.message ||
        detail?.message ||
        data?.error ||
        data?.message ||
        "FatSecret Python service request failed",
    );
    error.statusCode = response.status;
    error.data = data;
    throw error;
  }

  return data;
}

function unwrapResult(response) {
  console.log("UNWRAP_RESULT_INPUT:", {
    hasResponse: !!response,
    responseKeys: response ? Object.keys(response) : [],
    hasResult: response && "result" in response,
    resultValue: response?.result,
  });
  
  if (response && typeof response === "object" && "result" in response) {
    return response.result || {};
  }
  return response || {};
}

function toNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeFood(food = {}) {
  return {
    foodId: String(food.food_id || food.foodId || food.id || ""),
    name: food.food_name || food.name || "Unknown food",
    description: food.food_description || food.description || "",
    brandName: food.brand_name || food.brandName || "",
    servingDescription:
      food.serving_description ||
      food.servingDescription ||
      food.serving_size ||
      "1 serving",
    calories: Math.round(toNumber(food.calories)),
    protein: toNumber(food.protein),
    carbohydrate: toNumber(food.carbohydrate ?? food.carbs),
    fat: toNumber(food.fat),
    sodium: toNumber(food.sodium),
    potassium: toNumber(food.potassium),
    phosphorus: toNumber(food.phosphorus),
    source: food.source || "fatsecret",
    needsManualReview: Boolean(
      food.needs_manual_review ?? food.needsManualReview,
    ),
    raw: food,
  };
}

async function healthCheck() {
  return callPythonService("/api/health");
}

async function searchFoods(query, page = 0) {
  const response = await callPythonService("/api/v1/foods/search", {
    method: "POST",
    query: { query, page },
  });
  const result = unwrapResult(response);
  const foods = Array.isArray(result.foods) ? result.foods : [];

  console.log("FATSECRET_BRIDGE_SEARCH:", {
    query,
    page,
    totalResults: result.total_results || result.totalResults || foods.length,
    numResults: foods.length,
    firstFoodRaw: foods[0] ? {
      food_id: foods[0].food_id,
      food_name: foods[0].food_name,
      calories: foods[0].calories,
      protein: foods[0].protein,
      sodium: foods[0].sodium,
      potassium: foods[0].potassium,
      phosphorus: foods[0].phosphorus,
    } : null,
  });

  const normalized = foods.map(normalizeFood);
  
  console.log("FATSECRET_BRIDGE_SEARCH_NORMALIZED:", {
    query,
    numNormalized: normalized.length,
    firstNormalized: normalized[0] ? {
      foodId: normalized[0].foodId,
      name: normalized[0].name,
      calories: normalized[0].calories,
      protein: normalized[0].protein,
      sodium: normalized[0].sodium,
      potassium: normalized[0].potassium,
      phosphorus: normalized[0].phosphorus,
    } : null,
  });

  return {
    query,
    page,
    totalResults: result.total_results || result.totalResults || foods.length,
    foods: normalized,
    raw: response,
  };
}

async function getFoodDetails(foodId) {
  const response = await callPythonService(`/api/v1/foods/${foodId}`);
  const result = unwrapResult(response);
  const food = result.food || result.nutrition || result;
  
  console.log("FATSECRET_BRIDGE_GET_DETAILS:", {
    foodId,
    responseKeys: Object.keys(response),
    resultKeys: Object.keys(result),
    resultFoodKeys: food ? Object.keys(food) : [],
    rawFoodNutrients: food ? {
      calories: food.calories,
      protein: food.protein,
      sodium: food.sodium,
      potassium: food.potassium,
      phosphorus: food.phosphorus,
    } : null,
  });
  
  const normalized = normalizeFood(food);
  console.log("FATSECRET_BRIDGE_NORMALIZED:", {
    foodId,
    normalizedNutrients: {
      calories: normalized.calories,
      protein: normalized.protein,
      sodium: normalized.sodium,
      potassium: normalized.potassium,
      phosphorus: normalized.phosphorus,
    }
  });
  
  return {
    food: normalized,
    raw: response,
  };
}

function normalizeRecipe(recipe = {}) {
  // Extract recipe_id, ensuring it's a string
  // Handle both old naming (recipe_id, recipe_name) and new naming (food_id, food_name)
  const recipeId = String(
    recipe.recipe_id || 
    recipe.recipeId || 
    recipe.food_id ||  // Python service uses food_id
    recipe.id || 
    ""
  );
  
  return {
    recipeId,
    name: 
      recipe.recipe_name || 
      recipe.name || 
      recipe.food_name ||  // Python service uses food_name
      recipe.title || 
      "Unknown recipe",
    description: recipe.recipe_description || recipe.description || "",
    servingSize: 
      recipe.serving_size || 
      recipe.servingSize || 
      recipe.serving_description ||  // Python service uses serving_description
      "1 serving",
    servings: toNumber(recipe.servings || recipe.number_of_servings),
    imageUrl: recipe.recipe_image || recipe.image_url || recipe.imageUrl || "",
    prepTime: toNumber(recipe.prep_time),
    cookTime: toNumber(recipe.cook_time),
    totalTime: toNumber(recipe.total_time),
    recipeTypes: recipe.recipe_types || recipe.recipeTypes || [],
    ingredients: recipe.ingredients || [],
    calories: Math.round(toNumber(recipe.calories)),
    protein: toNumber(recipe.protein),
    carbohydrate: toNumber(recipe.carbohydrate ?? recipe.carbs ?? recipe.carbohydrates),
    fat: toNumber(recipe.fat),
    sodium: toNumber(recipe.sodium),
    potassium: toNumber(recipe.potassium),
    phosphorus: toNumber(recipe.phosphorus),
    fiber: toNumber(recipe.fiber),
    sugar: toNumber(recipe.sugar),
    source: recipe.source || "fatsecret_recipe",
    needsManualReview: Boolean(
      recipe.needs_manual_review ?? recipe.needsManualReview ?? recipe.is_estimated ?? false
    ),
    raw: recipe,
  };
}

async function searchRecipes(query, page = 0, maxCalories = null) {
  const response = await callPythonService("/api/v1/recipes/search", {
    method: "GET",
    query: { query, page, ...(maxCalories && { max_calories: maxCalories }) },
  });
  const result = unwrapResult(response);
  // Python service returns 'foods' for recipe search (it reuses FoodSearchResult)
  const recipes = Array.isArray(result.recipes) 
    ? result.recipes 
    : Array.isArray(result.foods)
      ? result.foods
      : [];

  return {
    query,
    page,
    totalResults: result.total_results || result.totalResults || recipes.length,
    recipes: recipes.map(normalizeRecipe),
    raw: response,
  };
}

async function getRecipeDetails(recipeId) {
  const response = await callPythonService(`/api/v1/recipes/${recipeId}`);
  const result = unwrapResult(response);
  const recipe = result.recipe || result;
  return {
    recipe: normalizeRecipe(recipe),
    raw: response,
  };
}

async function mealLoggingSearch(query, page = 0) {
  const response = await callPythonService("/meal-logging/search", {
    method: "POST",
    body: { query, page },
  });
  return unwrapResult(response);
}

async function mealLoggingFoodDetails(foodId) {
  const response = await callPythonService(`/meal-logging/food/${foodId}`);
  return unwrapResult(response);
}

async function mealLoggingPreview(payload) {
  const response = await callPythonService("/meal-logging/preview", {
    method: "POST",
    body: payload,
  });
  return unwrapResult(response);
}

async function mealLoggingRecognizeImage(payload) {
  const response = await callPythonService("/meal-logging/recognize-image", {
    method: "POST",
    body: payload,
  });
  return unwrapResult(response);
}

module.exports = {
  healthCheck,
  searchFoods,
  getFoodDetails,
  searchRecipes,
  getRecipeDetails,
  mealLoggingSearch,
  mealLoggingFoodDetails,
  mealLoggingPreview,
  mealLoggingRecognizeImage,
  normalizeFood,
  normalizeRecipe,
};
