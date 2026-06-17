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

function addDays(dateKey, offset) {
  const date = new Date(`${dateKey}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + offset);
  return date.toISOString().slice(0, 10);
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

function positiveNumber(value) {
  const parsed = numberOrNull(value);
  return parsed !== null && parsed > 0 ? parsed : 0;
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

function nutrientsFromLog(log = {}) {
  const nutrients = log.finalNutrients || log.final_nutrients || log;
  return {
    calories: positiveNumber(nutrients.calories),
    protein: positiveNumber(nutrients.protein),
    carbohydrate: positiveNumber(nutrients.carbohydrate),
    fat: positiveNumber(nutrients.fat),
    sodium: positiveNumber(nutrients.sodium),
    potassium: positiveNumber(nutrients.potassium),
    phosphorus: positiveNumber(nutrients.phosphorus),
  };
}

async function getRecentFoodLogs(userId, requestedProfileId, daysBack = 45) {
  if (!userId) return [];
  const since = addDays(new Date().toISOString().slice(0, 10), -daysBack);
  const snapshots =
    requestedProfileId && requestedProfileId !== userId
      ? await Promise.all([
          db.collection("foodLogs").where("childProfileId", "==", requestedProfileId).get(),
          db.collection("foodLogs").where("userId", "==", requestedProfileId).get(),
        ])
      : [await db.collection("foodLogs").where("userId", "==", userId).get()];

  const docsById = new Map();
  snapshots.forEach((snapshot) => {
    snapshot.docs.forEach((doc) => docsById.set(doc.id, { id: doc.id, ...doc.data() }));
  });

  return [...docsById.values()]
    .filter((log) => {
      if (log.deletedAt) return false;
      if (requestedProfileId) {
        if (log.childProfileId !== requestedProfileId && log.userId !== requestedProfileId) {
          return false;
        }
      }
      return !log.date || log.date >= since;
    })
    .sort((a, b) => timestampMillis(b.createdAt || b.loggedAt) - timestampMillis(a.createdAt || a.loggedAt))
    .slice(0, 150);
}

function analyzeFoodHistory(logs = [], restrictions = {}) {
  const byFood = new Map();
  const byMealType = {};
  const sodiumLimit = numberOrNull(restrictions.dailySodiumLimitMg) || 2000;
  const potassiumLimit = numberOrNull(restrictions.dailyPotassiumLimitMg);
  const phosphorusLimit = numberOrNull(restrictions.dailyPhosphorusLimitMg);

  for (const log of logs) {
    const name = String(log.name || log.foodName || "").trim();
    if (!name) continue;
    const key = normalizeTextToken(name);
    const nutrients = nutrientsFromLog(log);
    const entry =
      byFood.get(key) ||
      {
        name,
        count: 0,
        mealTypes: new Set(),
        nutrients: {
          calories: 0,
          protein: 0,
          carbohydrate: 0,
          fat: 0,
          sodium: 0,
          potassium: 0,
          phosphorus: 0,
        },
        portions: new Map(),
      };
    entry.count += 1;
    if (log.mealType) entry.mealTypes.add(String(log.mealType));
    const portion = String(log.portion || log.selectedServingDescription || "1 serving");
    entry.portions.set(portion, (entry.portions.get(portion) || 0) + 1);
    Object.keys(entry.nutrients).forEach((nutrient) => {
      entry.nutrients[nutrient] += nutrients[nutrient] || 0;
    });
    byFood.set(key, entry);
  }

  const foods = [...byFood.values()].map((entry) => {
    const average = {};
    Object.entries(entry.nutrients).forEach(([key, value]) => {
      average[key] = entry.count ? value / entry.count : 0;
    });
    const portion = [...entry.portions.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] || "1 serving";
    const highSodium = average.sodium > Math.min(600, sodiumLimit * 0.3);
    const highPotassium = potassiumLimit ? average.potassium > potassiumLimit * 0.3 : false;
    const highPhosphorus = phosphorusLimit ? average.phosphorus > phosphorusLimit * 0.3 : false;
    return {
      name: entry.name,
      count: entry.count,
      mealTypes: [...entry.mealTypes],
      portion,
      average,
      highSodium,
      highPotassium,
      highPhosphorus,
    };
  });

  const avoid = foods
    .filter((food) => food.highSodium || food.highPotassium || food.highPhosphorus)
    .sort((a, b) => b.count - a.count)
    .slice(0, 10);
  const prefer = foods
    .filter((food) => !food.highSodium && !food.highPotassium && !food.highPhosphorus)
    .sort((a, b) => b.count - a.count)
    .slice(0, 12);

  prefer.forEach((food) => {
    food.mealTypes.forEach((mealType) => {
      byMealType[mealType] = byMealType[mealType] || [];
      byMealType[mealType].push(food);
    });
  });

  return {
    logCount: logs.length,
    prefer,
    avoid,
    byMealType,
    messages: [
      ...(prefer.length
        ? [`Reusable foods from recent logs: ${prefer.slice(0, 5).map((food) => food.name).join(", ")}.`]
        : []),
      ...(avoid.length
        ? [`Foods to limit from recent logs: ${avoid.slice(0, 5).map((food) => food.name).join(", ")}.`]
        : []),
    ],
  };
}

function personalizeRestrictions(restrictions, history) {
  const avoid = new Set(restrictions.avoid || []);
  const prefer = new Set(restrictions.prefer || []);
  (history.avoid || []).forEach((food) => avoid.add(food.name));
  (history.prefer || []).forEach((food) => prefer.add(food.name));
  return {
    ...restrictions,
    avoid: [...avoid],
    prefer: [...prefer],
    historyAvoid: history.avoid || [],
    historyPrefer: history.prefer || [],
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

function mealTemplateBank(profile, history = {}) {
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

  Object.entries(history.byMealType || {}).forEach(([mealType, foods]) => {
    const targetMealType = mealType === "Snacks" ? "PM Snack" : mealType;
    if (!bank[targetMealType]) return;
    foods.slice(0, 4).forEach((food) => {
      bank[targetMealType].push({
        name: food.name,
        components: [food.name],
        target: Math.round(food.average?.calories || 250),
        portion: food.portion,
        source: "recent_food_log_template",
      });
    });
  });
  return bank;
}

function safeMealTemplates(mealType, profile, restrictions, history) {
  const templates = mealTemplateBank(profile, history)[mealType] || [];
  const safe = templates.filter((template) => {
    const text = [template.name, ...(template.components || [])].join(" ");
    return !containsAny(text, restrictions.avoid);
  });
  return safe.length ? safe : templates;
}

function plannedMealFor(mealType, profile, restrictions, seed, mealIndex, history) {
  const templates = safeMealTemplates(mealType, profile, restrictions, history);
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

function roundNutrients(nutrients = {}) {
  return {
    calories: Math.round(positiveNumber(nutrients.calories)),
    protein: Number(positiveNumber(nutrients.protein).toFixed(1)),
    carbohydrate: Number(positiveNumber(nutrients.carbohydrate).toFixed(1)),
    fat: Number(positiveNumber(nutrients.fat).toFixed(1)),
    sodium: Math.round(positiveNumber(nutrients.sodium)),
    potassium: Math.round(positiveNumber(nutrients.potassium)),
    phosphorus: Math.round(positiveNumber(nutrients.phosphorus)),
  };
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

function importantTokens(text) {
  const stop = new Set(["with", "and", "the", "rice", "bowl", "meal", "friendly", "low"]);
  return normalizeTextToken(text)
    .split(/\s+/)
    .filter((token) => token.length > 2 && !stop.has(token));
}

function matchConfidence(plannedMeal, candidate) {
  const candidateText = normalizeTextToken([
    candidate.name,
    candidate.description,
    candidate.servingDescription,
    candidate.servingSize,
    Array.isArray(candidate.ingredients) ? candidate.ingredients.join(" ") : "",
  ].join(" "));
  const tokens = importantTokens([
    plannedMeal.name,
    ...(plannedMeal.components || []),
  ].join(" "));
  if (!tokens.length) return "unknown";
  const matched = tokens.filter((token) => candidateText.includes(token)).length;
  const ratio = matched / tokens.length;
  if (ratio >= 0.75) return "exact_or_close";
  if (ratio >= 0.4) return "partial";
  return "weak";
}

function componentBreakdownFromFoods(componentFoods = []) {
  return componentFoods.map((food) => ({
    component: food.component || food.name,
    matchedName: food.name,
    foodId: food.foodId,
    portion: food.servingDescription || food.servingSize || "1 serving",
    nutrients: roundNutrients(food),
    source: food.source || "fatsecret",
    needsManualReview: food.needsManualReview === true,
  }));
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
  const componentBreakdown = componentBreakdownFromFoods(componentFoods);
  return {
    foodId: componentFoods.map((food) => food.foodId).filter(Boolean).join(","),
    name: plannedMeal.name,
    portion: "1 planned serving",
    servingDescription: "1 planned serving",
    ...totals,
    componentBreakdown,
    nutrientPreview: roundNutrients(totals),
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
  const confidence = wholeMeal ? matchConfidence(plannedMeal, wholeMeal) : null;

  if (wholeMeal && confidence === "exact_or_close") {
    const preview = roundNutrients(wholeMeal);
    return {
      ...wholeMeal,
      name: plannedMeal.name,
      nutrientPreview: preview,
      componentBreakdown: [],
      matchConfidence: confidence,
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

  if (wholeMeal) {
    const preview = roundNutrients(wholeMeal);
    return {
      ...wholeMeal,
      name: plannedMeal.name,
      nutrientPreview: preview,
      componentBreakdown: [],
      matchConfidence: confidence,
      source:
        wholeMeal.sourceType === "food"
          ? "fatsecret_partial_food_meal_plan"
          : "fatsecret_partial_recipe_meal_plan",
      needsManualReview: true,
      reason:
        "Meal idea selected by CKD guide rules; FatSecret returned only a partial whole-meal match, so review nutrition before logging.",
      raw: {
        ...(wholeMeal.raw || {}),
        plannedMeal,
      },
    };
  }

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
    nutrientPreview: roundNutrients({}),
    componentBreakdown: [],
    matchConfidence: "unresolved",
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
  const requestedDays = Number(body.days || body.planDays || body.durationDays || 7);
  const planDays = Math.min(7, Math.max(1, Number.isFinite(requestedDays) ? requestedDays : 7));
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
  const history = analyzeFoodHistory(
    await getRecentFoodLogs(userId, requestedProfileId),
    buildFoodRestrictions(nutritionProfile),
  );
  const restrictions = personalizeRestrictions(
    buildFoodRestrictions(nutritionProfile),
    history,
  );
  const mealTypes = ["Breakfast", "AM Snack", "Lunch", "PM Snack", "Dinner"];

  const days = [];
  for (let dayIndex = 0; dayIndex < planDays; dayIndex += 1) {
    const currentDate = addDays(planDate, dayIndex);
    const daySeed = seed + dayIndex * 97;
    const meals = [];
    for (const [mealIndex, mealType] of mealTypes.entries()) {
      const plannedMeal = plannedMealFor(
        mealType,
        nutritionProfile,
        restrictions,
        daySeed,
        mealIndex + dayIndex,
        history,
      );
      const selected = await resolvePlannedMeal(
        plannedMeal,
        nutritionProfile,
        restrictions,
        daySeed + mealIndex,
      );

      if (selected) {
        const nutrients = roundNutrients(selected.nutrientPreview || selected);
        meals.push({
          date: currentDate,
          mealType,
          foodId: selected.foodId || selected.recipeId,
          name: selected.name,
          portion:
            selected.portion ||
            selected.servingDescription ||
            selected.servingSize ||
            plannedMeal.portion ||
            "1 serving",
          quantity: 1,
          ...nutrients,
          nutrientPreview: nutrients,
          componentBreakdown: selected.componentBreakdown || [],
          matchConfidence: selected.matchConfidence || "component_resolved",
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

    days.push({
      date: currentDate,
      meals,
      totals: roundNutrients(nutrientTotals(meals)),
    });
  }

  const meals = days[0]?.meals || [];
  const totals = days[0]?.totals || roundNutrients({});
  const weeklyTotals = roundNutrients(
    nutrientTotals(days.flatMap((day) => day.meals || [])),
  );

  return {
    planDate,
    planDays,
    nutritionProfile,
    restrictions,
    historyRecommendations: {
      logCount: history.logCount,
      prefer: history.prefer,
      avoid: history.avoid,
      messages: history.messages,
    },
    mealStructure: ["Breakfast", "AM Snack", "Lunch", "PM Snack", "Dinner"],
    days,
    meals,
    totals,
    weeklyTotals,
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
        "previous_food_logs",
        "personalized_history_recommendations",
        "ckd_guide_rules",
        "seven_day_seeded_selection",
      ],
    },
    displayMessage:
      "Meal ideas are selected from CKD guide rules and recent food logs, then nutrition is resolved from FatSecret. If a whole meal is not an exact database match, the service breaks it into foods and totals the nutrients for preview.",
  };
}

module.exports = {
  generateMealPlan,
};
