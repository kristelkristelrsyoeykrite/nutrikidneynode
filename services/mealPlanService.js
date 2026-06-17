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

function fallbackMealCandidate(mealType, restrictions, seed = 0) {
  const fallbackByMeal = {
    Breakfast: [
      { name: "Apple oatmeal", calories: 260, protein: 6, carbohydrate: 48, fat: 5, sodium: 90, potassium: 170, phosphorus: 90 },
      { name: "Rice porridge with chicken", calories: 290, protein: 14, carbohydrate: 46, fat: 5, sodium: 180, potassium: 220, phosphorus: 150 },
      { name: "Egg white toast with grapes", calories: 245, protein: 12, carbohydrate: 38, fat: 4, sodium: 210, potassium: 190, phosphorus: 95 },
    ],
    "AM Snack": [
      { name: "Apple slices", calories: 95, protein: 0.5, carbohydrate: 25, fat: 0.3, sodium: 2, potassium: 195, phosphorus: 20 },
      { name: "Grapes", calories: 104, protein: 1, carbohydrate: 27, fat: 0.2, sodium: 3, potassium: 288, phosphorus: 30 },
      { name: "Unsalted crackers", calories: 120, protein: 2, carbohydrate: 22, fat: 3, sodium: 70, potassium: 45, phosphorus: 35 },
    ],
    Lunch: [
      { name: "Chicken rice with cabbage", calories: 430, protein: 24, carbohydrate: 58, fat: 10, sodium: 280, potassium: 360, phosphorus: 210 },
      { name: "Turkey lettuce rice bowl", calories: 405, protein: 23, carbohydrate: 52, fat: 9, sodium: 300, potassium: 330, phosphorus: 190 },
      { name: "Pasta with chicken and cauliflower", calories: 420, protein: 22, carbohydrate: 60, fat: 8, sodium: 260, potassium: 310, phosphorus: 200 },
    ],
    "PM Snack": [
      { name: "Grapes and crackers", calories: 150, protein: 2, carbohydrate: 30, fat: 3, sodium: 120, potassium: 150, phosphorus: 45 },
      { name: "Apple with unsalted toast", calories: 165, protein: 3, carbohydrate: 34, fat: 2, sodium: 95, potassium: 170, phosphorus: 55 },
      { name: "Cucumber sticks with rice crackers", calories: 135, protein: 2, carbohydrate: 26, fat: 3, sodium: 90, potassium: 130, phosphorus: 40 },
    ],
    Dinner: [
      { name: "Fish rice with cauliflower", calories: 390, protein: 25, carbohydrate: 50, fat: 9, sodium: 260, potassium: 380, phosphorus: 230 },
      { name: "Chicken pasta with cabbage", calories: 410, protein: 24, carbohydrate: 55, fat: 9, sodium: 280, potassium: 340, phosphorus: 205 },
      { name: "Turkey rice with green beans", calories: 395, protein: 25, carbohydrate: 51, fat: 8, sodium: 290, potassium: 360, phosphorus: 210 },
    ],
  };
  const options = fallbackByMeal[mealType] || fallbackByMeal.Breakfast;
  const selected = seededPick(options, seed) || options[0];
  return {
    mealType,
    foodId: null,
    name: selected.name,
    portion: "1 serving",
    servingDescription: "1 serving",
    quantity: 1,
    ...selected,
    score: containsAny(selected.name, restrictions.avoid) ? 55 : 75,
    source: "ckd_meal_plan_fallback",
    raw: {
      generatedBy: "ckd_meal_plan_fallback",
      mealType,
    },
  };
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

async function enrichCandidate(item) {
  if (!item?.recipeId) return item;
  const hasUsefulNutrients =
    numberOrNull(item.calories) > 0 &&
    (numberOrNull(item.sodium) > 0 ||
      numberOrNull(item.potassium) > 0 ||
      numberOrNull(item.phosphorus) > 0);
  if (hasUsefulNutrients) return item;

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

function mealQueryBank(profile) {
  const guideTags = buildGuideTags(profile).join(" ");
  return [
    {
      mealType: "Breakfast",
      target: 300,
      queries: [
        `oatmeal apple ${guideTags}`,
        `rice porridge chicken ${guideTags}`,
        `egg white toast grapes ${guideTags}`,
        `cream of wheat berries ${guideTags}`,
      ],
    },
    {
      mealType: "AM Snack",
      target: 150,
      queries: [
        `apple snack ${guideTags}`,
        `grapes snack ${guideTags}`,
        `unsalted crackers snack ${guideTags}`,
        `cucumber rice crackers ${guideTags}`,
      ],
    },
    {
      mealType: "Lunch",
      target: 400,
      queries: [
        `grilled chicken rice cabbage ${guideTags}`,
        `turkey rice lettuce ${guideTags}`,
        `chicken pasta cauliflower ${guideTags}`,
        `fish rice cabbage ${guideTags}`,
      ],
    },
    {
      mealType: "PM Snack",
      target: 150,
      queries: [
        `fresh fruit crackers ${guideTags}`,
        `apple toast ${guideTags}`,
        `grapes crackers ${guideTags}`,
        `cucumber snack ${guideTags}`,
      ],
    },
    {
      mealType: "Dinner",
      target: 450,
      queries: [
        `fish rice cauliflower ${guideTags}`,
        `chicken rice green beans ${guideTags}`,
        `turkey rice vegetables ${guideTags}`,
        `pasta chicken cabbage ${guideTags}`,
      ],
    },
  ];
}

async function candidatesForMeal(meal, nutritionProfile, restrictions, seed, mealIndex) {
  const start = seed + mealIndex * 17;
  const primary = seededPick(meal.queries, start) || meal.queries[0];
  const secondary = seededPick(meal.queries, start, 1) || primary;
  const pages = [start % 2, (start + 1) % 2];
  const searchRequests = [
    searchMealPlanRecipes(primary, meal.mealType, meal.target, pages[0]),
    secondary !== primary
      ? searchMealPlanRecipes(secondary, meal.mealType, meal.target, pages[1])
      : null,
  ].filter(Boolean);
  const results = await Promise.all(searchRequests);
  const rawCandidates = results.flatMap((result) =>
    (result.recipes || result.foods || []).map((item) => ({
      ...item,
      mealType: meal.mealType,
      sourceType: result.recipes ? "recipe" : "food",
      queryUsed: result.query,
    })),
  );
  const uniqueCandidates = [];
  const seen = new Set();
  for (const candidate of rawCandidates) {
    const key = normalizeTextToken(candidate.recipeId || candidate.foodId || candidate.name);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    uniqueCandidates.push(candidate);
  }
  const enriched = await Promise.all(uniqueCandidates.slice(0, 8).map(enrichCandidate));
  return enriched
    .map((item) => ({
      ...item,
      score: scoreMealCandidate(item, meal.mealType, nutritionProfile, restrictions),
      reason: "Ranked by CKD guide rules, profile targets, labs, and FatSecret nutrient content.",
    }))
    .filter((item) => item.score >= 45)
    .sort((a, b) => b.score - a.score);
}

function selectDailyCandidate(candidates, seed, mealIndex) {
  if (!candidates.length) return null;
  const bestScore = candidates[0].score;
  const topSafe = candidates.filter((candidate) => candidate.score >= bestScore - 12).slice(0, 4);
  return seededPick(topSafe, seed, mealIndex) || candidates[0];
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
  const mealQueries = mealQueryBank(nutritionProfile);

  const meals = [];
  for (const [mealIndex, meal] of mealQueries.entries()) {
    const candidates = await candidatesForMeal(
      meal,
      nutritionProfile,
      restrictions,
      seed,
      mealIndex,
    );
    const selected =
      selectDailyCandidate(candidates, seed, mealIndex) ||
      fallbackMealCandidate(meal.mealType, restrictions, seed + mealIndex);

    if (selected) {
      meals.push({
        mealType: meal.mealType,
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
        score: selected.score || 50,
        selectionReason:
          selected.reason ||
          "Fallback selected from CKD-friendly meals because FatSecret did not return a usable candidate.",
        source:
          selected.sourceType === "food"
            ? "fatsecret_food_meal_plan"
            : selected.source || "fatsecret_recipe_meal_plan",
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
        "fatsecret_recipe_search",
        "ckd_guide_rules",
        "daily_seeded_selection",
      ],
    },
    displayMessage:
      "Meal plans are generated from profile, latest labs, CKD guide rules, and FatSecret nutrient data. The search and final pick rotate by date so meals can change each day.",
  };
}

module.exports = {
  generateMealPlan,
};
