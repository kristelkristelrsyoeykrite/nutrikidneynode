const { db } = require("../firebase/admin");
const fatSecretBridge = require("./fatSecretBridgeService");
const {
  decryptHealthDocument,
  decryptHealthProfile,
} = require("../utils/encryption");

function cleanObject(obj) {
  const cleaned = {};
  for (const key in obj) {
    if (obj[key] !== undefined && obj[key] !== null && obj[key] !== "") {
      cleaned[key] = obj[key];
    }
  }
  return cleaned;
}

function normalizeTextToken(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^\w\s/.-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value._seconds === "number") return value._seconds * 1000;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function dateKeyFromBody(body = {}) {
  const rawDate = body.date || body.planDate || body.mealPlanDate;
  if (rawDate) {
    const parsed = new Date(String(rawDate));
    if (!Number.isNaN(parsed.getTime())) return parsed.toISOString().slice(0, 10);
    const match = String(rawDate).match(/^\d{4}-\d{2}-\d{2}/);
    if (match) return match[0];
  }
  return new Date().toISOString().slice(0, 10);
}

function hashString(value) {
  let hash = 0;
  const text = String(value || "");
  for (let index = 0; index < text.length; index += 1) {
    hash = (hash * 31 + text.charCodeAt(index)) >>> 0;
  }
  return hash;
}

function seededPick(items, seed, offset = 0) {
  if (!Array.isArray(items) || items.length === 0) return null;
  return items[(seed + offset) % items.length];
}

function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

async function getDocData(collection, id) {
  if (!id) return null;
  const snap = await db.collection(collection).doc(id).get();
  return snap.exists ? { id: snap.id, ...snap.data() } : null;
}

function isFluidRestrictionEnabled(value) {
  const normalized = String(value ?? "").trim().toLowerCase();
  return ["yes", "true", "enabled", "restricted", "fluid_restricted"].includes(
    normalized,
  );
}

async function buildChildContext(userId, requestedChildProfileId) {
  const rawUser = await getDocData("users", userId);
  const user = rawUser ? decryptHealthProfile(rawUser) : null;
  const childProfileId = requestedChildProfileId || userId;
  const rawChildUser =
    childProfileId && childProfileId !== userId
      ? await getDocData("users", childProfileId)
      : null;
  const childUser = rawChildUser ? decryptHealthProfile(rawChildUser) : null;
  const rawChildProfile = await getDocData("childProfiles", childProfileId);
  const childProfile = rawChildProfile
    ? decryptHealthDocument(rawChildProfile)
    : null;
  const profileOwner = childUser || childProfile || user || {};
  const medicalProfileId =
    profileOwner?.medicalProfileId ||
    profileOwner?.medical_profile_id ||
    user?.medicalProfileId ||
    user?.medical_profile_id ||
    requestedChildProfileId;
  const nutritionTargetId =
    profileOwner?.baselineNutritionTargetId ||
    profileOwner?.nutritionTargetId ||
    user?.baselineNutritionTargetId ||
    user?.nutritionTargetId;

  const rawMedicalProfile =
    (await getDocData("medicalProfile", medicalProfileId)) ||
    rawChildProfile ||
    {};
  const medicalProfile = decryptHealthDocument(rawMedicalProfile);
  const rawTargets =
    (await getDocData("nutritionTargets", nutritionTargetId)) || {};
  const targets = decryptHealthDocument(rawTargets);
  const fluidRestrictionStatus =
    medicalProfile?.fluidRestrictionStatus ||
    medicalProfile?.fluid_restriction_status ||
    "unknown";
  const dailyFluidLimitMl = isFluidRestrictionEnabled(fluidRestrictionStatus)
    ? numberOrNull(
        medicalProfile?.fluidLimitMl ??
          medicalProfile?.fluid_limit_ml ??
          targets.fluidLimitMl ??
          targets.fluid_limit_ml ??
          targets.dailyFluidLimitMl ??
          targets.daily_fluid_limit_ml,
      )
    : null;
  const postTransplantStatus =
    medicalProfile?.isPostTransplant ?? medicalProfile?.is_post_transplant;
  const sterileDietInput =
    medicalProfile?.requiresSterileDiet ?? medicalProfile?.requires_sterile_diet;
  const requiresSterileDiet =
    sterileDietInput !== undefined && sterileDietInput !== null
      ? sterileDietInput
      : postTransplantStatus === true ||
        String(postTransplantStatus || "").trim().toLowerCase() === "yes";

  return {
    child_profile_id: childProfileId,
    age: numberOrNull(profileOwner?.age ?? medicalProfile?.age),
    ckd_stage:
      medicalProfile?.ckdStage ||
      medicalProfile?.ckd_stage ||
      medicalProfile?.stage ||
      "unknown",
    dialysis_status:
      medicalProfile?.dialysisStatus ||
      medicalProfile?.dialysis_status ||
      (medicalProfile?.onDialysis === true ? "on_dialysis" : "unknown"),
    diet_pattern:
      medicalProfile?.dietPattern ||
      medicalProfile?.diet_pattern ||
      "unknown",
    fluid_restriction_status: fluidRestrictionStatus,
    is_post_transplant: postTransplantStatus,
    requires_sterile_diet: requiresSterileDiet,
    sterile_diet_weeks:
      medicalProfile?.sterileDietWeeks ?? medicalProfile?.sterile_diet_weeks,
    is_post_surgery:
      medicalProfile?.isPostSurgery ?? medicalProfile?.is_post_surgery,
    has_calcium_phosphorus_imbalance:
      medicalProfile?.hasCalciumPhosphorusImbalance ??
      medicalProfile?.has_calcium_phosphorus_imbalance,
    allergies: Array.isArray(medicalProfile?.allergies)
      ? medicalProfile.allergies
      : [],
    targets: cleanObject({
      sodium: numberOrNull(
        targets.sodium ??
          targets.sodiumLimitMg ??
          targets.sodium_limit_mg ??
          targets.maxSodiumMg,
      ),
      potassium: numberOrNull(
        targets.potassium ??
          targets.potassiumLimitMg ??
          targets.potassium_limit_mg ??
          targets.maxPotassiumMg,
      ),
      phosphorus: numberOrNull(
        targets.phosphorus ??
          targets.phosphorusLimitMg ??
          targets.phosphorus_limit_mg,
      ),
      protein_min: numberOrNull(
        targets.proteinMin ?? targets.protein_min ?? targets.minProteinG,
      ),
      protein_max: numberOrNull(
        targets.proteinMax ?? targets.protein_max ?? targets.maxProteinG,
      ),
      dailyFluidLimitMl,
    }),
  };
}

function firstPresent(source = {}, keys = []) {
  for (const key of keys) {
    if (source[key] !== undefined && source[key] !== null && source[key] !== "") {
      return source[key];
    }
  }
  return null;
}

function ckdStageFromEgfr(egfr, fallback) {
  const explicit = Number(String(fallback || "").replace(/[^\d.]/g, ""));
  if (Number.isFinite(explicit) && explicit > 0) return explicit;
  if (!Number.isFinite(egfr)) return null;
  if (egfr >= 90) return 1;
  if (egfr >= 60) return 2;
  if (egfr >= 30) return 3;
  if (egfr >= 15) return 4;
  return 5;
}

function labStatus(value, upperLimit) {
  const parsed = numberOrNull(value);
  if (parsed === null) return "Unknown";
  return parsed > upperLimit ? "High" : "Normal";
}

function bmiCategory(bmi) {
  const parsed = numberOrNull(bmi);
  if (parsed === null) return "Unknown";
  if (parsed < 18.5) return "Underweight";
  if (parsed < 25) return "Normal";
  return "Overweight";
}

function containsAny(text, words = []) {
  const normalized = normalizeTextToken(text);
  return words.some((word) => {
    const escaped = String(word).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`(^|[^a-z])${escaped}(?=[^a-z]|$)`, "i").test(normalized);
  });
}

async function getFirstUserDocument(collection, userId) {
  if (!userId) return null;
  const snapshot = await db.collection(collection).where("userId", "==", userId).get();
  const docs = snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => {
      const left = timestampMillis(
        a.resultDate || a.date || a.createdAt || a.updatedAt,
      );
      const right = timestampMillis(
        b.resultDate || b.date || b.createdAt || b.updatedAt,
      );
      return right - left;
    });
  return docs[0] || null;
}

function buildNutritionProfile({
  childContext = {},
  medicalProfile = {},
  labs = {},
  anthropometrics = {},
}) {
  const egfr = numberOrNull(
    firstPresent(labs, ["eGFR_CKD_EPI", "egfrCkdEpi", "egfr", "eGFR"]),
  );
  const stage = ckdStageFromEgfr(
    egfr,
    firstPresent(labs, ["CKD_Stage_eGFR", "ckdStageEgfr", "ckd_stage"]) ||
      childContext.ckd_stage,
  );
  const weightKg = numberOrNull(
    firstPresent(anthropometrics, ["weight_kg", "weightKg", "weight"]) ||
      firstPresent(medicalProfile, ["weight_kg", "weightKg", "weight"]),
  );
  const bmi = numberOrNull(
    firstPresent(anthropometrics, ["bmi", "BMI"]) ||
      firstPresent(medicalProfile, ["bmi", "BMI"]),
  );
  const dialysisStatus = String(childContext.dialysis_status || "").toLowerCase();
  const onDialysis = dialysisStatus.includes("dialysis") && !dialysisStatus.includes("pre");
  const proteinTarget = weightKg
    ? Number((weightKg * (onDialysis ? 1.2 : 0.8)).toFixed(1))
    : numberOrNull(childContext.targets?.protein_max);
  const glucose = numberOrNull(firstPresent(labs, ["glucose", "fastingGlucose"]));
  const hba1c = numberOrNull(firstPresent(labs, ["HbA1c", "hba1c", "hemoglobinA1c"]));
  const serumAlbumin = numberOrNull(
    firstPresent(labs, ["serum_albumin", "serumAlbumin", "albumin"]),
  );
  const totalProtein = numberOrNull(
    firstPresent(labs, ["total_protein", "totalProtein"]),
  );

  return {
    stage,
    egfr,
    potassiumStatus: labStatus(firstPresent(labs, ["potassium", "K"]), 5.0),
    phosphorusStatus: labStatus(firstPresent(labs, ["phosphorus", "phosphate"]), 4.5),
    sodiumStatus: labStatus(firstPresent(labs, ["sodium", "Na"]), 145),
    diabetesRisk:
      (hba1c !== null && hba1c >= 6.5) || (glucose !== null && glucose > 126),
    bmiCategory: bmiCategory(bmi),
    proteinTarget,
    calorieTarget:
      numberOrNull(childContext.targets?.calories_max) ||
      numberOrNull(childContext.targets?.calories) ||
      1800,
    riskMalnutrition:
      (serumAlbumin !== null && serumAlbumin < 3.5) ||
      (totalProtein !== null && totalProtein < 6.0),
    weightKg,
    bmi,
  };
}

function buildFoodRestrictions(profile) {
  const avoid = new Set(["soy sauce", "fish sauce", "bagoong", "processed", "fast food"]);
  const prefer = new Set(["apple", "grapes", "cabbage", "cauliflower", "lettuce", "radish"]);

  if (profile.potassiumStatus === "High") {
    ["banana", "avocado", "orange", "melon", "potato", "sweet potato", "spinach", "tomato paste"].forEach((item) => avoid.add(item));
  }
  if (profile.phosphorusStatus === "High") {
    ["nuts", "beans", "cola", "cheese", "organ meat"].forEach((item) => avoid.add(item));
  }
  if (profile.diabetesRisk) {
    ["dessert", "sweetened", "candy", "cake", "soda"].forEach((item) => avoid.add(item));
  }

  return {
    dailySodiumLimitMg: profile.sodiumLimitMg || 2000,
    dailyPotassiumLimitMg: profile.potassiumLimitMg || null,
    dailyPhosphorusLimitMg: profile.phosphorusLimitMg || null,
    avoid: [...avoid],
    prefer: [...prefer],
  };
}

function buildGuideTags(profile) {
  const tags = ["kidney friendly", "low sodium"];
  if (profile.potassiumStatus === "High") tags.push("low potassium");
  if (profile.phosphorusStatus === "High") tags.push("low phosphorus");
  if (profile.diabetesRisk) tags.push("diabetic friendly");
  if (profile.riskMalnutrition) tags.push("high protein");
  return tags;
}

function perMealTargets(profile, restrictions, mealType) {
  const isSnack = mealType.includes("Snack");
  const calorieTarget = isSnack ? 150 : Math.round((profile.calorieTarget || 1800) / 4);
  const proteinTarget = profile.proteinTarget
    ? profile.proteinTarget * (isSnack ? 0.08 : 0.28)
    : null;
  return {
    calories: calorieTarget,
    sodium: Math.round((restrictions.dailySodiumLimitMg || 2000) * (isSnack ? 0.08 : 0.28)),
    potassium: restrictions.dailyPotassiumLimitMg
      ? Math.round(restrictions.dailyPotassiumLimitMg * (isSnack ? 0.08 : 0.28))
      : null,
    phosphorus: restrictions.dailyPhosphorusLimitMg
      ? Math.round(restrictions.dailyPhosphorusLimitMg * (isSnack ? 0.08 : 0.28))
      : null,
    protein: proteinTarget,
  };
}

function scoreMealCandidate(food, mealType, profile, restrictions) {
  const foodText = [
    food.name,
    food.description,
    food.servingDescription,
    food.servingSize,
    food.brandName,
    Array.isArray(food.ingredients) ? food.ingredients.join(" ") : "",
  ].join(" ");
  let score = 100;
  const sodium = numberOrNull(food.sodium) || 0;
  const protein = numberOrNull(food.protein) || 0;
  const calories = numberOrNull(food.calories) || 0;
  const potassium = numberOrNull(food.potassium) || 0;
  const phosphorus = numberOrNull(food.phosphorus) || 0;
  const targets = perMealTargets(profile, restrictions, mealType);
  const nutrientFields = [calories, protein, sodium, potassium, phosphorus];
  const knownNutrients = nutrientFields.filter((value) => value > 0).length;

  if (sodium > 600) score -= 20;
  if (containsAny(foodText, restrictions.avoid)) score -= 35;
  if (sodium > targets.sodium) score -= Math.min(35, Math.ceil((sodium - targets.sodium) / 40));
  if (targets.potassium && potassium > targets.potassium) score -= 24;
  if (targets.phosphorus && phosphorus > targets.phosphorus) score -= 24;
  if (profile.potassiumStatus === "High" && potassium > 500) score -= 20;
  if (profile.phosphorusStatus === "High" && phosphorus > 250) score -= 20;
  if (profile.diabetesRisk && containsAny(foodText, ["sweet", "sugar", "syrup", "dessert"])) score -= 20;
  if (profile.riskMalnutrition && protein >= 8) score += 15;
  if (targets.protein && protein > targets.protein * 1.4 && !profile.riskMalnutrition) score -= 10;
  if (knownNutrients >= 4) score += 10;
  if (knownNutrients <= 2) score -= 12;
  if (containsAny(foodText, restrictions.prefer)) score += 10;
  if (mealType.includes("Snack") && calories > 300) score -= 12;
  if (!mealType.includes("Snack") && calories < 120) score -= 8;
  if (Math.abs(calories - targets.calories) <= targets.calories * 0.3) score += 8;

  return score;
}

function mealTemplateBank(profile) {
  const bank = {
    Breakfast: [
      { name: "Apple oatmeal", components: ["oatmeal", "apple"], target: 300 },
      { name: "Rice porridge with chicken", components: ["rice porridge", "chicken"], target: 300 },
      { name: "Egg white toast with grapes", components: ["egg white", "toast", "grapes"], target: 280 },
      { name: "Cream of wheat with berries", components: ["cream of wheat", "berries"], target: 280 },
    ],
    "AM Snack": [
      { name: "Apple slices", components: ["apple"], target: 150 },
      { name: "Grapes", components: ["grapes"], target: 150 },
      { name: "Unsalted crackers", components: ["unsalted crackers"], target: 150 },
      { name: "Cucumber with rice crackers", components: ["cucumber", "rice crackers"], target: 150 },
    ],
    Lunch: [
      { name: "Chicken rice with cabbage", components: ["chicken breast", "white rice", "cabbage"], target: 420 },
      { name: "Turkey lettuce rice bowl", components: ["turkey", "white rice", "lettuce"], target: 410 },
      { name: "Pasta with chicken and cauliflower", components: ["pasta", "chicken breast", "cauliflower"], target: 430 },
      { name: "Fish rice with cabbage", components: ["fish", "white rice", "cabbage"], target: 420 },
    ],
    "PM Snack": [
      { name: "Grapes and crackers", components: ["grapes", "unsalted crackers"], target: 150 },
      { name: "Apple with unsalted toast", components: ["apple", "toast"], target: 160 },
      { name: "Cucumber sticks with rice crackers", components: ["cucumber", "rice crackers"], target: 140 },
      { name: "Pear slices", components: ["pear"], target: 140 },
    ],
    Dinner: [
      { name: "Fish rice with cauliflower", components: ["fish", "white rice", "cauliflower"], target: 410 },
      { name: "Chicken pasta with cabbage", components: ["chicken breast", "pasta", "cabbage"], target: 430 },
      { name: "Turkey rice with green beans", components: ["turkey", "white rice", "green beans"], target: 410 },
      { name: "Chicken rice with lettuce", components: ["chicken breast", "white rice", "lettuce"], target: 410 },
    ],
  };

  if (profile.phosphorusStatus === "High") {
    Object.values(bank).forEach((templates) => {
      templates.forEach((template) => {
        template.guideRules = [...(template.guideRules || []), "lower_phosphorus"];
      });
    });
  }
  if (profile.potassiumStatus === "High") {
    Object.values(bank).forEach((templates) => {
      templates.forEach((template) => {
        template.guideRules = [...(template.guideRules || []), "lower_potassium"];
      });
    });
  }
  return bank;
}

function safeMealTemplates(mealType, profile, restrictions) {
  const templates = mealTemplateBank(profile)[mealType] || [];
  const safe = templates.filter((template) => {
    const text = [template.name, ...(template.components || [])].join(" ");
    return !containsAny(text, restrictions.avoid);
  });
  return safe.length ? safe : templates;
}

function plannedMealFor(mealType, profile, restrictions, seed, mealIndex) {
  const templates = safeMealTemplates(mealType, profile, restrictions);
  const selected = seededPick(templates, seed, mealIndex * 7) || templates[0];
  return {
    mealType,
    ...selected,
    source: "ckd_guide_rule_template",
  };
}

function usefulNutrition(food = {}) {
  const values = [
    numberOrNull(food.calories),
    numberOrNull(food.protein),
    numberOrNull(food.sodium),
    numberOrNull(food.potassium),
    numberOrNull(food.phosphorus),
  ];
  return values.filter((value) => value !== null && value > 0).length >= 3;
}

async function searchMealPlanRecipes(query, mealType, calorieTarget = null, page = 0) {
  try {
    const result = await fatSecretBridge.searchRecipes(
      query,
      page,
      calorieTarget ? Math.round(calorieTarget * 1.1) : null,
    );
    return result;
  } catch (error) {
    console.error("MEAL_PLAN_RECIPE_SEARCH_ERROR:", {
      mealType,
      query,
      error: error.message,
      statusCode: error.statusCode,
      details: error.data,
    });
    try {
      return await fatSecretBridge.searchFoods(query, 0);
    } catch (fallbackError) {
      console.error("MEAL_PLAN_RECIPE_FALLBACK_ERROR:", fallbackError.message);
      return { recipes: [], foods: [] };
    }
  }
}

async function searchMealPlanFoods(query, mealType, page = 0) {
  try {
    return await fatSecretBridge.searchFoods(query, page);
  } catch (error) {
    console.error("MEAL_PLAN_FOOD_SEARCH_ERROR:", {
      mealType,
      query,
      error: error.message,
      statusCode: error.statusCode,
      details: error.data,
    });
    return { foods: [] };
  }
}

async function enrichCandidate(item) {
  if (!item?.recipeId) return item;
  if (usefulNutrition(item)) return item;

  try {
    const details = await fatSecretBridge.getRecipeDetails(item.recipeId);
    return {
      ...item,
      ...(details.recipe || {}),
      raw: {
        ...(item.raw || {}),
        recipeDetails: details.raw || details.recipe,
      },
    };
  } catch (error) {
    console.error("MEAL_PLAN_RECIPE_DETAILS_ERROR:", {
      recipeId: item.recipeId,
      error: error.message,
    });
    return item;
  }
}

async function resolveFoodDetails(food) {
  if (!food?.foodId) return food;
  if (usefulNutrition(food)) return food;
  try {
    const details = await fatSecretBridge.getFoodDetails(food.foodId);
    return {
      ...food,
      ...(details.food || {}),
      raw: {
        ...(food.raw || {}),
        foodDetails: details.raw || details.food,
      },
    };
  } catch (error) {
    console.error("MEAL_PLAN_FOOD_DETAILS_ERROR:", {
      foodId: food.foodId,
      error: error.message,
    });
    return food;
  }
}

function nutrientTotals(items = []) {
  return items.reduce(
    (sum, item) => ({
      calories: sum.calories + (numberOrNull(item.calories) || 0),
      protein: sum.protein + (numberOrNull(item.protein) || 0),
      carbohydrate: sum.carbohydrate + (numberOrNull(item.carbohydrate) || 0),
      fat: sum.fat + (numberOrNull(item.fat) || 0),
      sodium: sum.sodium + (numberOrNull(item.sodium) || 0),
      potassium: sum.potassium + (numberOrNull(item.potassium) || 0),
      phosphorus: sum.phosphorus + (numberOrNull(item.phosphorus) || 0),
    }),
    { calories: 0, protein: 0, carbohydrate: 0, fat: 0, sodium: 0, potassium: 0, phosphorus: 0 },
  );
}

function bestScoredCandidate(candidates, mealType, nutritionProfile, restrictions) {
  const uniqueCandidates = [];
  const seen = new Set();
  for (const candidate of candidates) {
    const key = normalizeTextToken(candidate.recipeId || candidate.foodId || candidate.name);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    uniqueCandidates.push(candidate);
  }
  return uniqueCandidates
    .map((item) => ({
      ...item,
      score: scoreMealCandidate(item, mealType, nutritionProfile, restrictions),
    }))
    .filter((item) => usefulNutrition(item) && item.score >= 45)
    .sort((a, b) => b.score - a.score)[0] || null;
}

async function resolveWholeMealNutrition(plannedMeal, nutritionProfile, restrictions, seed) {
  const guideTags = buildGuideTags(nutritionProfile).join(" ");
  const queries = [
    plannedMeal.name,
    `${plannedMeal.name} ${guideTags}`,
    (plannedMeal.components || []).join(" "),
  ];
  const searches = await Promise.all(
    queries.map(async (query, index) => {
      const [recipes, foods] = await Promise.all([
        searchMealPlanRecipes(query, plannedMeal.mealType, plannedMeal.target, (seed + index) % 2),
        searchMealPlanFoods(query, plannedMeal.mealType, (seed + index) % 2),
      ]);
      return [
        ...(recipes.recipes || []).map((item) => ({
          ...item,
          sourceType: "recipe",
          queryUsed: query,
        })),
        ...(foods.foods || []).map((item) => ({
          ...item,
          sourceType: "food",
          queryUsed: query,
        })),
      ];
    }),
  );
  const enriched = await Promise.all(
    searches.flat().slice(0, 10).map(async (candidate) => {
      if (candidate.recipeId) return enrichCandidate(candidate);
      return resolveFoodDetails(candidate);
    }),
  );
  return bestScoredCandidate(
    enriched,
    plannedMeal.mealType,
    nutritionProfile,
    restrictions,
  );
}

async function resolveComponentNutrition(plannedMeal, nutritionProfile, restrictions) {
  const componentFoods = [];
  for (const component of plannedMeal.components || []) {
    const result = await searchMealPlanFoods(component, plannedMeal.mealType, 0);
    const detailed = await Promise.all(
      (result.foods || []).slice(0, 4).map(resolveFoodDetails),
    );
    const selected = bestScoredCandidate(
      detailed,
      plannedMeal.mealType,
      nutritionProfile,
      restrictions,
    );
    if (selected) componentFoods.push({ ...selected, component });
  }
  if (!componentFoods.length) return null;
  const totals = nutrientTotals(componentFoods);
  return {
    foodId: componentFoods.map((food) => food.foodId).filter(Boolean).join(","),
    name: plannedMeal.name,
    portion: "1 planned serving",
    servingDescription: "1 planned serving",
    ...totals,
    score: scoreMealCandidate(
      { ...totals, name: plannedMeal.name },
      plannedMeal.mealType,
      nutritionProfile,
      restrictions,
    ),
    source: "fatsecret_component_meal_plan",
    reason:
      "Meal idea selected by CKD guide rules; nutrition resolved by searching FatSecret one food at a time.",
    raw: {
      plannedMeal,
      componentFoods,
    },
  };
}

async function resolvePlannedMeal(plannedMeal, nutritionProfile, restrictions, seed) {
  const wholeMeal = await resolveWholeMealNutrition(
    plannedMeal,
    nutritionProfile,
    restrictions,
    seed,
  );
  if (wholeMeal) {
    return {
      ...wholeMeal,
      name: plannedMeal.name,
      source:
        wholeMeal.sourceType === "food"
          ? "fatsecret_food_meal_plan"
          : "fatsecret_recipe_meal_plan",
      reason:
        "Meal idea selected by CKD guide rules; nutrition resolved from FatSecret whole-meal search.",
      raw: {
        ...(wholeMeal.raw || {}),
        plannedMeal,
      },
    };
  }

  const components = await resolveComponentNutrition(
    plannedMeal,
    nutritionProfile,
    restrictions,
  );
  if (components) return components;

  return {
    foodId: null,
    name: plannedMeal.name,
    portion: "1 planned serving",
    servingDescription: "1 planned serving",
    calories: 0,
    protein: 0,
    carbohydrate: 0,
    fat: 0,
    sodium: 0,
    potassium: 0,
    phosphorus: 0,
    score: 0,
    source: "unresolved_guide_meal_plan",
    needsManualReview: true,
    reason:
      "Meal idea selected by CKD guide rules, but FatSecret did not return whole-meal or component nutrition.",
    raw: {
      plannedMeal,
    },
  };
}

async function generateMealPlan(body = {}) {
  const userId = body.userId || body.uid;
  const requestedProfileId = body.childProfileId || body.profileUserId || userId;
  const planDate = dateKeyFromBody(body);
  const seed = hashString(`${requestedProfileId}:${planDate}`);
  if (!userId) {
    const error = new Error("userId is required");
    error.statusCode = 400;
    throw error;
  }

  const rawUser = await getDocData("users", requestedProfileId);
  const user = rawUser ? decryptHealthProfile(rawUser) : {};
  const childContext = await buildChildContext(userId, requestedProfileId);
  const medicalProfile = decryptHealthDocument(
    (await getDocData("medicalProfile", user.medicalProfileId || user.medical_profile_id)) || {},
  );
  const latestLabs = decryptHealthDocument(
    (await getDocData("labResults", user.labResultId || user.lab_result_id)) ||
      (await getFirstUserDocument("labResults", requestedProfileId)) ||
      {},
  );
  const anthropometrics = decryptHealthDocument(
    (await getFirstUserDocument("anthropometrics", requestedProfileId)) || {},
  );
  const nutritionProfile = buildNutritionProfile({
    childContext,
    medicalProfile,
    labs: latestLabs,
    anthropometrics,
  });
  nutritionProfile.sodiumLimitMg = numberOrNull(childContext.targets?.sodium);
  nutritionProfile.potassiumLimitMg = numberOrNull(childContext.targets?.potassium);
  nutritionProfile.phosphorusLimitMg = numberOrNull(childContext.targets?.phosphorus);
  const restrictions = buildFoodRestrictions(nutritionProfile);
  const mealTypes = ["Breakfast", "AM Snack", "Lunch", "PM Snack", "Dinner"];

  const meals = [];
  for (const [mealIndex, mealType] of mealTypes.entries()) {
    const plannedMeal = plannedMealFor(
      mealType,
      nutritionProfile,
      restrictions,
      seed,
      mealIndex,
    );
    const selected = await resolvePlannedMeal(
      plannedMeal,
      nutritionProfile,
      restrictions,
      seed + mealIndex,
    );

    if (selected) {
      meals.push({
        mealType,
        foodId: selected.foodId || selected.recipeId,
        name: selected.name,
        portion: selected.servingDescription || selected.servingSize || "1 serving",
        quantity: 1,
        calories: Math.round(numberOrNull(selected.calories) || 0),
        protein: numberOrNull(selected.protein) || 0,
        carbohydrate: numberOrNull(selected.carbohydrate) || 0,
        fat: numberOrNull(selected.fat) || 0,
        sodium: numberOrNull(selected.sodium) || 0,
        potassium: numberOrNull(selected.potassium) || 0,
        phosphorus: numberOrNull(selected.phosphorus) || 0,
        score: selected.score ?? 50,
        selectionReason:
          selected.reason ||
          "Meal selected by CKD guide rules and resolved with FatSecret nutrition data.",
        source: selected.source || "fatsecret_meal_plan",
        needsManualReview: selected.needsManualReview === true,
        raw: selected.raw || selected,
      });
    }
  }

  const totals = meals.reduce(
    (sum, meal) => ({
      calories: sum.calories + meal.calories,
      protein: sum.protein + meal.protein,
      carbohydrate: sum.carbohydrate + meal.carbohydrate,
      fat: sum.fat + meal.fat,
      sodium: sum.sodium + meal.sodium,
      potassium: sum.potassium + meal.potassium,
      phosphorus: sum.phosphorus + meal.phosphorus,
    }),
    { calories: 0, protein: 0, carbohydrate: 0, fat: 0, sodium: 0, potassium: 0, phosphorus: 0 },
  );

  return {
    planDate,
    nutritionProfile,
    restrictions,
    mealStructure: ["Breakfast", "AM Snack", "Lunch", "PM Snack", "Dinner"],
    meals,
    totals,
    validation: {
      sodiumWithinLimit: totals.sodium <= restrictions.dailySodiumLimitMg,
      proteinWithinTarget:
        !nutritionProfile.proteinTarget || totals.protein <= nutritionProfile.proteinTarget,
      generatedFrom: [
        "profile",
        "latest_labs",
        "nutrition_targets",
        "guide_rule_meal_templates",
        "fatsecret_nutrition_resolution",
        "fatsecret_component_fallback",
        "ckd_guide_rules",
        "daily_seeded_selection",
      ],
    },
    displayMessage:
      "Meal ideas are selected from CKD guide rules, then nutrition is resolved from FatSecret. If a whole meal is not found, the service searches each food in the meal one by one.",
  };
}

module.exports = {
  generateMealPlan,
};
