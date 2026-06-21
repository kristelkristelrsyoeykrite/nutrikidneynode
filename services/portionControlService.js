function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeText(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9\s/.-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const TITLE_ORDER = Object.freeze({
  protein: 1,
  carb: 2,
  vegetable: 3,
  fruit: 4,
  fat: 99,
  seasoning: 100,
  other: 999,
});

const INGREDIENT_ORDER = Object.freeze({
  protein: 1,
  vegetable: 2,
  fat: 3,
  seasoning: 4,
  carb: 5,
  fruit: 6,
  other: 999,
});

const CATEGORY_ALIASES = Object.freeze({
  proteins: "protein",
  carbohydrate: "carb",
  carbohydrates: "carb",
  carbs: "carb",
  grain: "carb",
  grains: "carb",
  vegetables: "vegetable",
  fruits: "fruit",
  fats: "fat",
  oil: "fat",
  oils: "fat",
  seasonings: "seasoning",
  spice: "seasoning",
  spices: "seasoning",
  others: "other",
});

function normalizeCategory(value) {
  const category = normalizeText(value).replace(/\s+/g, "_");
  return CATEGORY_ALIASES[category] || category || "other";
}

function getFoodName(food) {
  if (typeof food === "string") return food;
  return food?.displayName || food?.genericName || food?.searchName ||
    food?.name || food?.foodName || food?.food_name || food?.ingredient || "";
}

function titleCase(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function categoryFromMetadata(food) {
  if (!food || typeof food === "string") return null;
  const category = food.category || food.role || food.component ||
    food.foodCategory || food.food_category || food.type;
  return category ? normalizeCategory(category) : null;
}

// Compatibility fallback for old callers that still send ingredient names only.
// Category metadata is authoritative and should be supplied for new foods.
function inferCategoryFromName(food) {
  const text = normalizeText(getFoodName(food));
  if (/(chicken|fish|beef|turkey|tofu|egg|pork|shrimp|seafood|tilapia|salmon|tuna)/.test(text)) return "protein";
  if (/(rice|bread|pasta|noodle|oat|corn|barley|couscous|cracker|toast|pandesal|cereal|potato|root crop|suman)/.test(text)) return "carb";
  if (/(cabbage|carrot|cauliflower|broccoli|lettuce|cucumber|pepper|spinach|okra|eggplant|asparagus|beans?|ampalaya|pumpkin|squash|beets?|celery|onions?)/.test(text)) return "vegetable";
  if (/(apple|banana|pear|orange|grape|strawberry|berries|peach|mango|melon|plum|pineapple|avocado|chico)/.test(text)) return "fruit";
  if (/(oil|butter|margarine|mayonnaise)/.test(text)) return "fat";
  return "other";
}

function getFoodCategory(food) {
  return categoryFromMetadata(food) || inferCategoryFromName(food);
}

function sortFoods(foods = [], order = INGREDIENT_ORDER) {
  return foods
    .map((food, index) => ({ food, index }))
    .sort((a, b) => {
      const difference = (order[getFoodCategory(a.food)] || 999) -
        (order[getFoodCategory(b.food)] || 999);
      return difference || a.index - b.index;
    })
    .map(({ food }) => food);
}

function buildMealTitle(meal = {}) {
  if (meal.recipeName) {
    const carb = (meal.foods || []).find((food) => getFoodCategory(food) === "carb");
    return carb
      ? `${titleCase(meal.recipeName)} with ${titleCase(getFoodName(carb))}`
      : titleCase(meal.recipeName);
  }

  const names = sortFoods(meal.foods || [], TITLE_ORDER)
    .filter((food) => ["protein", "carb", "vegetable", "fruit"].includes(getFoodCategory(food)))
    .slice(0, 3)
    .map((food) => titleCase(getFoodName(food)))
    .filter(Boolean);

  if (!names.length) return "Meal";
  if (names.length === 1) return names[0];
  if (names.length === 2) return `${names[0]} with ${names[1]}`;
  return `${names[0]} with ${names[1]} and ${names[2]}`;
}

function buildIngredientList(meal = {}) {
  return sortFoods(meal.foods || []).map((food) => ({
    name: titleCase(getFoodName(food)),
    category: getFoodCategory(food),
    amount: typeof food === "object" ? food.amount : undefined,
    unit: typeof food === "object" ? food.unit : undefined,
  }));
}

function getDailyProtein(weightKg, dialysisStatus) {
  const status = normalizeText(dialysisStatus);
  const onDialysis = status.includes("dialysis") &&
    !status.includes("not on dialysis") &&
    !status.includes("no dialysis") &&
    !status.includes("pre-dialysis") &&
    !status.includes("pre dialysis");
  const proteinPerKg = onDialysis ? 1.2 : 0.7;
  return Number((Number(weightKg || 0) * proteinPerKg).toFixed(1));
}

function mealProteinTarget(weightKg, dialysisStatus, mealType) {
  const dailyProtein = getDailyProtein(weightKg, dialysisStatus);
  const normalizedMealType = normalizeText(mealType);
  if (normalizedMealType.includes("snack")) return 0;
  return Number((dailyProtein / 3).toFixed(1));
}

function categorizeIngredients(ingredients = []) {
  const buckets = {
    proteins: [],
    carbs: [],
    vegetables: [],
    fruits: [],
    fats: [],
    seasonings: [],
    others: [],
  };

  for (const ingredient of ingredients) {
    if (!getFoodName(ingredient)) continue;
    const category = getFoodCategory(ingredient);
    const bucket = `${category}s`;
    (buckets[bucket] || buckets.others).push(ingredient);
  }

  return buckets;
}

function handMeasureForCategory(category) {
  if (category === "protein") return "1 palm";
  if (category === "carb") return "1 cupped hand";
  if (category === "fruit") return "1 fist";
  if (category === "vegetable") return "2 fists";
  return "1 serving";
}

function buildIngredientPortion(item, category, targetProtein, mealType) {
  const baseCalories = numberOrNull(item.calories) || 0;
  const baseProtein = numberOrNull(item.protein) || 0;
  const name = getFoodName(item) || "Ingredient";
  const normalizedName = normalizeText(name);
  const isSnack = normalizeText(mealType).includes("snack");
  let estimatedPortion = "1 serving";
  let manualServing = "1 serving";
  let targetProteinForItem = 0;
  let fatSecretServingMultiplier = 1;

  if (category === "protein") {
    targetProteinForItem = Math.max(0, Number(targetProtein.toFixed(1)));
    const matchboxes = targetProteinForItem / 8;
    estimatedPortion = `about ${matchboxes.toFixed(1)} matchbox-sized portions`;
    manualServing = "1 matchbox is approximately 1 oz or 8 g protein";
    fatSecretServingMultiplier = null;
  } else if (category === "carb") {
    estimatedPortion = normalizedName.includes("rice")
      ? "1/2 cup rice"
      : /(noodle|oatmeal|pasta)/.test(normalizedName)
        ? "1 cup"
        : normalizedName.includes("pandesal")
          ? "3 pandesal"
          : "2 slices bread";
    manualServing = estimatedPortion;
    fatSecretServingMultiplier = normalizedName.includes("rice") ? 0.5 : 1;
  } else if (category === "vegetable") {
    estimatedPortion = isSnack ? "1/2 cup cooked vegetables" : "1 cup cooked vegetables";
    manualServing = "1 vegetable serving is 1/2 cup cooked";
    fatSecretServingMultiplier = isSnack ? 0.5 : 1;
  } else if (category === "fruit") {
    estimatedPortion = "1/2 cup or 1 small fruit";
    manualServing = estimatedPortion;
    fatSecretServingMultiplier = 1;
  } else if (category === "fat") {
    estimatedPortion = "1 tsp-1 tbsp";
    manualServing = estimatedPortion;
    fatSecretServingMultiplier = 1;
  }


  const suppliedPortion = item.estimatedPortion || item.manualServing ||
    item.servingDescription || item.servingSize;
  if (suppliedPortion) {
    estimatedPortion = suppliedPortion;
    manualServing = item.manualServing || suppliedPortion;
  }

  return {
    name,
    category,
    targetProtein: targetProteinForItem,
    matchboxes: category === "protein" ? Number((targetProteinForItem / 8).toFixed(1)) : null,
    estimatedPortion,
    manualServing,
    fatSecretServingMultiplier,
    handMeasure: category === "protein" ? "1 matchbox" : handMeasureForCategory(category),
    referenceNutrients: {
      calories: baseCalories,
      protein: baseProtein,
    },
  };
}

function validateRestrictions(ingredients = [], restrictions = {}) {
  const text = ingredients.map((item) => normalizeText(getFoodName(item))).join(" ");
  const blocked = [];

  for (const item of restrictions.highPotassium || []) {
    if (text.includes(normalizeText(item))) blocked.push(`high potassium: ${item}`);
  }
  for (const item of restrictions.highPhosphorus || []) {
    if (text.includes(normalizeText(item))) blocked.push(`high phosphorus: ${item}`);
  }
  for (const item of restrictions.highSodium || []) {
    if (text.includes(normalizeText(item))) blocked.push(`high sodium: ${item}`);
  }

  return {
    passed: blocked.length === 0,
    blocked,
  };
}

function generateMealPortions({
  weightKg,
  calorieTarget,
  ckdStage,
  dialysisStatus,
  prescribedProtein,
  mealType,
  ingredientList = [],
  ingredientNutrients = [],
  restrictions = {},
}) {
  const explicitProtein = numberOrNull(prescribedProtein);
  const dailyProtein = explicitProtein !== null && explicitProtein > 0
    ? explicitProtein
    : getDailyProtein(weightKg, dialysisStatus || ckdStage);
  const mealProteinForMeal = normalizeText(mealType).includes("snack")
    ? 0
    : Number((dailyProtein / 3).toFixed(1));
  const categorized = categorizeIngredients(ingredientList);
  const categoriesInOrder = [
    ["protein", categorized.proteins],
    ["vegetable", categorized.vegetables],
    ["fat", categorized.fats || []],
    ["seasoning", categorized.seasonings || []],
    ["carb", categorized.carbs],
    ["fruit", categorized.fruits],
    ["other", categorized.others],
  ];

  const portions = [];
  for (const [category, items] of categoriesInOrder) {
    if (!items.length) continue;
    items.forEach((item) => {
      const nutrientMatch = ingredientNutrients.find((entry) =>
        normalizeText(getFoodName(entry)) === normalizeText(getFoodName(item)));
      portions.push(
        buildIngredientPortion(
          nutrientMatch || (typeof item === "object" ? item : { name: item }),
          category,
          category === "protein" ? mealProteinForMeal / items.length : 0,
          mealType,
        ),
      );
    });
  }

  const validation = validateRestrictions(ingredientList, restrictions);

  return {
    ckdStage,
    dialysisStatus,
    weightKg: numberOrNull(weightKg),
    calorieTarget: numberOrNull(calorieTarget),
    dailyProteinTarget: dailyProtein,
    mealCaloriesTarget: null,
    mealProteinTarget: mealProteinForMeal,
    plateMethod: {
      vegetables: 0.5,
      protein: 0.25,
      carbs: 0.25,
    },
    handMeasures: {
      protein: "1 palm",
      carbs: "1 cupped hand",
      vegetables: "2 fists",
      fruit: "1 fist",
    },
    categorizedIngredients: categorized,
    portions,
    validation,
    summary: validation.passed
      ? "Portions estimated using CKD plate method, protein prescription, and hand measures."
      : `Portion review needed: ${validation.blocked.join(", ")}`,
  };
}

module.exports = {
  generateMealPortions,
  categorizeIngredients,
  getDailyProtein,
  buildMealTitle,
  buildIngredientList,
  getFoodCategory,
  TITLE_ORDER,
  INGREDIENT_ORDER,
};
