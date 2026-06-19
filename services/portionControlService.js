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
  const onDialysis = Boolean(dialysisStatus) && /dialysis/i.test(String(dialysisStatus));
  const proteinPerKg = onDialysis ? 1.2 : 0.7;
  return Number((Number(weightKg || 0) * proteinPerKg).toFixed(1));
}

function mealCalories(calorieTarget, mealType) {
  const mealDistribution = {
    breakfast: 0.25,
    lunch: 0.35,
    dinner: 0.3,
    snack: 0.1,
  };

  const normalizedMealType = normalizeText(mealType);
  const isBreakfast = normalizedMealType.includes("breakfast");
  const isLunch = normalizedMealType.includes("lunch");
  const isDinner = normalizedMealType.includes("dinner");
  const isSnack = normalizedMealType.includes("snack");

  const ratio = isBreakfast
    ? mealDistribution.breakfast
    : isLunch
      ? mealDistribution.lunch
      : isDinner
        ? mealDistribution.dinner
        : isSnack
          ? mealDistribution.snack
          : 0.25;

  return Math.round(Number(calorieTarget || 0) * ratio);
}

function mealProteinTarget(weightKg, dialysisStatus, mealType) {
  const dailyProtein = getDailyProtein(weightKg, dialysisStatus);
  const normalizedMealType = normalizeText(mealType);
  const isSnack = normalizedMealType.includes("snack");
  const ratio = isSnack ? 0.1 : normalizedMealType.includes("lunch") ? 0.35 : normalizedMealType.includes("dinner") ? 0.3 : 0.25;
  return Number((dailyProtein * ratio).toFixed(1));
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
    } else if (/(rice|bread|pasta|noodle|oat|corn|barley|couscous|cracker|toast|pandesal)/.test(text)) {
      buckets.carbs.push(ingredient);
    } else if (/(cabbage|carrot|cauliflower|broccoli|lettuce|cucumber|pepper|spinach|okra|eggplant|asparagus|beans?)/.test(text)) {
      buckets.vegetables.push(ingredient);
    } else if (/(apple|banana|pear|orange|grape|strawberry|berries|peach|mango|melon|plum)/.test(text)) {
      buckets.fruits.push(ingredient);
    } else {
      buckets.others.push(ingredient);
    }
  }

  return buckets;
}

function proteinPortionEstimate(mealProtein, proteinNutrients = []) {
  const totalProteinPer100g = proteinNutrients.reduce((sum, item) => sum + (numberOrNull(item.proteinPer100g) || 0), 0);
  if (totalProteinPer100g > 0) {
    const averageProteinPer100g = totalProteinPer100g / proteinNutrients.length;
    return Math.max(25, Math.round((mealProtein / averageProteinPer100g) * 100));
  }
  return Math.max(25, Math.round(mealProtein * 3));
}

function handMeasureForCategory(category) {
  if (category === "protein") return "1 palm";
  if (category === "carb") return "1 cupped hand";
  if (category === "fruit") return "1 fist";
  if (category === "vegetable") return "2 fists";
  return "1 serving";
}

function buildIngredientPortion(item, category, share, mealCaloriesTarget, mealProteinTarget) {
  const baseCalories = numberOrNull(item.calories) || 0;
  const baseProtein = numberOrNull(item.protein) || 0;
  const scaledCalories = Math.max(0, Math.round(mealCaloriesTarget * share));
  const scaledProtein = Math.max(0, Number((mealProteinTarget * share).toFixed(1)));

  return {
    name: item.name || item.foodName || item.ingredient || "Ingredient",
    category,
    share: Number(share.toFixed(2)),
    targetCalories: scaledCalories,
    targetProtein: scaledProtein,
    estimatedPortion: category === "protein"
      ? `${proteinPortionEstimate(scaledProtein, [{ proteinPer100g: baseProtein }])} g`
      : handMeasureForCategory(category),
    handMeasure: handMeasureForCategory(category),
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
  const mealCaloriesTarget = mealCalories(calorieTarget, mealType);
  const mealProteinForMeal = mealProteinTarget(weightKg, dialysisStatus || ckdStage, mealType);
  const categorized = categorizeIngredients(ingredientList);
  const categoriesInOrder = [
    ["protein", categorized.proteins],
    ["carb", categorized.carbs],
    ["vegetable", categorized.vegetables],
    ["fruit", categorized.fruits],
  ];

  const portions = [];
  for (const [category, items] of categoriesInOrder) {
    if (!items.length) continue;
    const share = category === "protein" ? 0.25 : category === "carb" ? 0.25 : category === "vegetable" ? 0.5 : 0.25;
    items.forEach((item) => {
      const nutrientMatch = ingredientNutrients.find((entry) => normalizeText(entry.name) === normalizeText(item));
      portions.push(
        buildIngredientPortion(
          nutrientMatch || { name: item },
          category,
          share / items.length,
          mealCaloriesTarget,
          mealProteinForMeal,
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
    mealCaloriesTarget,
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