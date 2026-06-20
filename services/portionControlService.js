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
    others: [],
  };

  for (const ingredient of ingredients) {
    const text = normalizeText(ingredient);
    if (!text) continue;
    if (/(chicken|fish|beef|turkey|tofu|egg|pork|shrimp|seafood|tilapia|salmon|tuna)/.test(text)) {
      buckets.proteins.push(ingredient);
    } else if (/(rice|bread|pasta|noodle|oat|corn|barley|couscous|cracker|toast|pandesal|cereal|potato|root crop|suman)/.test(text)) {
      buckets.carbs.push(ingredient);
    } else if (/(cabbage|carrot|cauliflower|broccoli|lettuce|cucumber|pepper|spinach|okra|eggplant|asparagus|beans?|ampalaya|pumpkin|squash|beets?|celery|onions?)/.test(text)) {
      buckets.vegetables.push(ingredient);
    } else if (/(apple|banana|pear|orange|grape|strawberry|berries|peach|mango|melon|plum|pineapple|avocado|chico)/.test(text)) {
      buckets.fruits.push(ingredient);
    } else if (/(oil|butter|margarine|mayonnaise)/.test(text)) {
      buckets.fats = buckets.fats || [];
      buckets.fats.push(ingredient);
    } else {
      buckets.others.push(ingredient);
    }
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
  const name = item.name || item.foodName || item.ingredient || "Ingredient";
  const normalizedName = normalizeText(name);
  const isSnack = normalizeText(mealType).includes("snack");
  let estimatedPortion = "1 serving";
  let manualServing = "1 serving";
  let targetProteinForItem = 0;

  if (category === "protein") {
    targetProteinForItem = Math.max(0, Number(targetProtein.toFixed(1)));
    const matchboxes = targetProteinForItem / 8;
    estimatedPortion = `about ${matchboxes.toFixed(1)} matchbox-sized portions`;
    manualServing = "1 matchbox is approximately 1 oz or 8 g protein";
  } else if (category === "carb") {
    estimatedPortion = normalizedName.includes("rice")
      ? "1/2 cup rice"
      : /(noodle|oatmeal|pasta)/.test(normalizedName)
        ? "1 cup"
        : normalizedName.includes("pandesal")
          ? "3 pandesal"
          : "2 slices bread";
    manualServing = estimatedPortion;
  } else if (category === "vegetable") {
    estimatedPortion = isSnack ? "1/2 cup cooked vegetables" : "1 cup cooked vegetables";
    manualServing = "1 vegetable serving is 1/2 cup cooked";
  } else if (category === "fruit") {
    estimatedPortion = "1/2 cup or 1 small fruit";
    manualServing = estimatedPortion;
  } else if (category === "fat") {
    estimatedPortion = "1 tsp-1 tbsp";
    manualServing = estimatedPortion;
  }

  return {
    name,
    category,
    targetProtein: targetProteinForItem,
    matchboxes: category === "protein" ? Number((targetProteinForItem / 8).toFixed(1)) : null,
    estimatedPortion,
    manualServing,
    handMeasure: category === "protein" ? "1 matchbox" : handMeasureForCategory(category),
    referenceNutrients: {
      calories: baseCalories,
      protein: baseProtein,
    },
  };
}

function validateRestrictions(ingredients = [], restrictions = {}) {
  const text = ingredients.map((item) => normalizeText(item)).join(" ");
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
  mealType,
  ingredientList = [],
  ingredientNutrients = [],
  restrictions = {},
}) {
  const dailyProtein = getDailyProtein(weightKg, dialysisStatus || ckdStage);
  const mealProteinForMeal = mealProteinTarget(weightKg, dialysisStatus || ckdStage, mealType);
  const categorized = categorizeIngredients(ingredientList);
  const categoriesInOrder = [
    ["protein", categorized.proteins],
    ["carb", categorized.carbs],
    ["vegetable", categorized.vegetables],
    ["fruit", categorized.fruits],
    ["fat", categorized.fats || []],
  ];

  const portions = [];
  for (const [category, items] of categoriesInOrder) {
    if (!items.length) continue;
    items.forEach((item) => {
      const nutrientMatch = ingredientNutrients.find((entry) => normalizeText(entry.name) === normalizeText(item));
      portions.push(
        buildIngredientPortion(
          nutrientMatch || { name: item },
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
};
