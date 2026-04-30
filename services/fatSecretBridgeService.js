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

  return {
    query,
    page,
    totalResults: result.total_results || result.totalResults || foods.length,
    foods: foods.map(normalizeFood),
    raw: response,
  };
}

async function getFoodDetails(foodId) {
  const response = await callPythonService(`/api/v1/foods/${foodId}`);
  const result = unwrapResult(response);
  const food = result.food || result.nutrition || result;
  return {
    food: normalizeFood(food),
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
  mealLoggingSearch,
  mealLoggingFoodDetails,
  mealLoggingPreview,
  mealLoggingRecognizeImage,
  normalizeFood,
};
