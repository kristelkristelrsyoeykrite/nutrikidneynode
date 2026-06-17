const express = require("express");
const router = express.Router();
const { admin, db } = require("../firebase/admin");
const fatSecretBridge = require("../services/fatSecretBridgeService");
const {
  recomputeGamificationForDate,
} = require("../services/gamificationService");
const { generatePhase2DecisionSupport } = require("../services/phase2DecisionSupport");
const {
  decryptHealthDocument,
  decryptHealthProfile,
} = require("../utils/encryption");
const {
  consumeAiUsage,
  getAiUsageStatus,
} = require("../utils/aiUsageLimiter");

const FOOD_LOG_COLLECTION = "foodLogs";
const HYDRATION_LOG_COLLECTION = "hydrationLog";
const DAILY_SUMMARY_COLLECTION = "dailyIntakeSummaries";
const LINKED_ADOLESCENT_NUTRITION_ALERT_TYPE =
  "linked_adolescent_nutrition_limit_alert";
const KNOWN_ALLERGY_ALIASES = {
  milk: ["milk", "dairy", "cheese", "butter", "cream", "whey", "casein", "yogurt"],
  egg: ["egg", "eggs", "albumin", "mayonnaise", "mayo"],
  peanut: ["peanut", "peanuts", "peanut butter"],
  "tree nuts": [
    "tree nuts",
    "almond",
    "almonds",
    "cashew",
    "cashews",
    "walnut",
    "walnuts",
    "pecan",
    "pecans",
    "pistachio",
    "pistachios",
    "hazelnut",
    "hazelnuts",
    "macadamia",
    "brazil nut",
  ],
  soy: ["soy", "soya", "soybean", "soybeans", "tofu", "edamame", "miso"],
  "wheat / gluten": ["wheat", "gluten", "barley", "rye", "bread", "pasta", "flour"],
  fish: ["fish", "tuna", "salmon", "sardine", "cod", "tilapia", "anchovy"],
  shellfish: ["shellfish", "shrimp", "prawn", "crab", "lobster", "clam", "mussel", "oyster", "scallop"],
  sesame: ["sesame", "tahini", "sesame oil"],
};
const ALLERGY_CANONICAL_MAP = Object.entries(KNOWN_ALLERGY_ALIASES).reduce(
  (map, [canonical, aliases]) => {
    map[canonical] = canonical;
    aliases.forEach((alias) => {
      map[alias] = canonical;
    });
    return map;
  },
  { "no known allergies": "no known allergies", "not sure": "not sure", other: "other" },
);

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

function normalizeAllergiesInput(value) {
  const rawItems = Array.isArray(value)
    ? value
    : typeof value === "string"
      ? value.split(/[,;\n]+/)
      : [];

  const normalized = [];
  const seen = new Set();
  for (const item of rawItems) {
    const token = normalizeTextToken(item);
    if (!token) continue;
    const canonical = ALLERGY_CANONICAL_MAP[token] || token;
    if (canonical === "no known allergies") {
      return [];
    }
    if (!seen.has(canonical)) {
      seen.add(canonical);
      normalized.push(canonical);
    }
  }
  return normalized;
}

function buildFoodTextForAllergyCheck(payload = {}) {
  const raw = payload.raw && typeof payload.raw === "object" ? payload.raw : {};
  const recognizedFoods = Array.isArray(raw.recognizedFoods) ? raw.recognizedFoods : [];
  const servingText = [
    payload.name,
    payload.foodName,
    payload.brandName,
    payload.foodType,
    payload.portion,
    payload.selectedServingDescription,
    raw.brand_name,
    raw.brandName,
    raw.food_name,
    raw.foodName,
    raw.display_food_name,
    raw.ingredients,
    raw.ingredient_list,
    raw.ingredientList,
    raw.allergens,
    raw.allergen_info,
    raw.allergenInfo,
    raw.description,
    ...recognizedFoods.map((item) => item?.name || item?.food_name || ""),
  ];
  return normalizeTextToken(servingText.filter(Boolean).join(" "));
}

function detectAllergyMatches(savedAllergies, payload) {
  const profileAllergies = normalizeAllergiesInput(savedAllergies).filter(
    (item) => item !== "not sure" && item !== "other",
  );
  if (!profileAllergies.length) {
    return {
      allergyChecked: profileAllergies.length === 0,
      profileAllergies,
      allergyAlert: false,
      matchedAllergens: [],
      message: null,
    };
  }

  const foodText = buildFoodTextForAllergyCheck(payload);
  const matchedAllergens = profileAllergies.filter((allergy) => {
    const aliases = KNOWN_ALLERGY_ALIASES[allergy] || [allergy];
    return aliases.some((alias) => {
      const pattern = new RegExp(`(^|[^a-z])${alias.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?=[^a-z]|$)`, "i");
      return pattern.test(foodText);
    });
  });

  return {
    allergyChecked: true,
    profileAllergies,
    allergyAlert: matchedAllergens.length > 0,
    matchedAllergens,
    message:
      matchedAllergens.length > 0
        ? `Warning: This meal may contain ${matchedAllergens.join(", ")}, which ${matchedAllergens.length === 1 ? "is" : "are"} listed in the child profile.`
        : null,
  };
}

async function evaluateAllergyAlert({ userId, childProfileId, payload }) {
  const childContext = await buildChildContext(userId, childProfileId || userId);
  const allergyCheck = detectAllergyMatches(childContext.allergies, payload);
  return {
    childContext,
    allergyCheck,
  };
}

function addAllergyMetadataToPayload(payload, allergyCheck, userConfirmedAllergyWarning) {
  return {
    ...payload,
    allergyChecked: allergyCheck.allergyChecked,
    profileAllergiesAtLogTime: allergyCheck.profileAllergies,
    allergyAlert: allergyCheck.allergyAlert,
    matchedAllergens: allergyCheck.matchedAllergens,
    userConfirmedAllergyWarning:
      allergyCheck.allergyAlert === true ? userConfirmedAllergyWarning === true : false,
  };
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value._seconds === "number") return value._seconds * 1000;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function serializeTimestamp(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate().toISOString();
  if (typeof value._seconds === "number") {
    return new Date(value._seconds * 1000).toISOString();
  }
  return value;
}

function serializeFoodLog(doc) {
  const data = doc.data() || {};
  const createdAt = serializeTimestamp(data.createdAt);
  return {
    id: doc.id,
    ...data,
    createdAt,
    updatedAt: serializeTimestamp(data.updatedAt),
    // Use createdAt as the source of truth for "logged time" in the app UI.
    // This avoids timezone parsing issues for historical logs where loggedAt
    // may have been stored with an ambiguous timezone.
    loggedAt: createdAt,
    deletedAt: serializeTimestamp(data.deletedAt),
  };
}

function parseLogDateTime(value) {
  if (!value) {
    const error = new Error("loggedAt is required");
    error.statusCode = 400;
    throw error;
  }

  const raw = String(value).trim();
  // If the client sends an ISO string without timezone (common on mobile when using
  // `toIso8601String()`), JS interprets it in the server's local timezone.
  // The app uses Manila time; treat timezone-less ISO timestamps as Asia/Manila (+08:00)
  // to preserve the intended clock time.
  const hasTimezone = /([zZ]|[+-]\d{2}:\d{2})$/.test(raw);
  const looksIsoWithoutTz =
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?$/.test(raw) && !hasTimezone;
  const normalized = looksIsoWithoutTz ? `${raw}+08:00` : raw;

  const date = new Date(normalized);
  if (Number.isNaN(date.getTime())) {
    const error = new Error("loggedAt must be a valid date-time");
    error.statusCode = 400;
    throw error;
  }
  return date;
}

function logDateKey(date) {
  return date.toISOString().slice(0, 10);
}

function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function isFluidRestrictionEnabled(value) {
  const normalized = String(value ?? "").trim().toLowerCase();
  return ["yes", "true", "enabled", "restricted", "fluid_restricted"].includes(
    normalized,
  );
}

function phosphorusGuideFromRaw(raw) {
  if (!raw || typeof raw !== "object") return null;
  const guide = raw.phosphorusGuide || raw.phosphorus_guide || raw.phosphorus;
  return guide && typeof guide === "object" ? guide : null;
}

function phosphorusValueFromGuide(guide) {
  if (!guide || typeof guide !== "object") return null;
  const phosphorus = guide.phosphorus || guide;
  return numberOrNull(
    phosphorus.value_mg ??
      phosphorus.valueMg ??
      phosphorus.phosphorus_mg ??
      phosphorus.phosphorusMg,
  );
}

function resolvedPhosphorusValue(phosphorus, raw) {
  return numberOrNull(phosphorus) ?? phosphorusValueFromGuide(phosphorusGuideFromRaw(raw)) ?? 0;
}

function inferredFoodCategory(payload = {}, body = {}) {
  const explicit =
    body.category ??
    body.foodCategory ??
    body.food_category ??
    payload.category ??
    payload.foodCategory ??
    payload.food_category ??
    payload.raw?.category ??
    payload.raw?.food_category ??
    payload.raw?.foodCategory;
  if (explicit) return explicit;

  const name = String(payload.name || payload.foodName || "").toLowerCase();
  if (/(cola|dark soda|dark soft drink|root beer)/.test(name)) {
    return "Dark-colored carbonated drink";
  }
  if (/(hotdog|hot dog|sausage|ham|bacon|salami|luncheon meat|corned beef)/.test(name)) {
    return "Processed Meat";
  }
  if (/(instant|canned|chips|cracker|processed|fast food)/.test(name)) {
    return "Processed Food";
  }
  return "";
}

function phase2FoodItemFromPayload(payload = {}, body = {}) {
  const raw = payload.raw && typeof payload.raw === "object" ? payload.raw : {};
  const nutrients = payload.finalNutrients || {};
  const sodium = numberOrNull(nutrients.sodium ?? payload.sodium);

  return cleanObject({
    name: payload.name || payload.foodName,
    category: inferredFoodCategory(payload, body),
    containsSaltAdditive:
      body.containsSaltAdditive ??
      body.contains_salt_additive ??
      raw.containsSaltAdditive ??
      raw.contains_salt_additive,
    isHighSodium:
      body.isHighSodium ??
      body.is_high_sodium ??
      raw.isHighSodium ??
      raw.is_high_sodium ??
      (sodium !== null ? sodium >= 400 : undefined),
    containsPotassiumAdditive:
      body.containsPotassiumAdditive ??
      body.contains_potassium_additive ??
      raw.containsPotassiumAdditive ??
      raw.contains_potassium_additive,
    containsPhosphateAdditive:
      body.containsPhosphateAdditive ??
      body.contains_phosphate_additive ??
      raw.containsPhosphateAdditive ??
      raw.contains_phosphate_additive,
  });
}

function phase2ProfileFromChildContext(childContext = {}) {
  return cleanObject({
    age_years: childContext.age,
    ckd_stage: childContext.ckd_stage,
    dialysis_status: childContext.dialysis_status,
    diet_pattern: childContext.diet_pattern,
    fluid_restriction_status: childContext.fluid_restriction_status,
    has_hypertension: childContext.has_hypertension,
    has_edema: childContext.has_edema,
    is_post_transplant: childContext.is_post_transplant,
    requires_sterile_diet: childContext.requires_sterile_diet,
    sterile_diet_weeks: childContext.sterile_diet_weeks,
    is_post_surgery: childContext.is_post_surgery,
    has_calcium_phosphorus_imbalance:
      childContext.has_calcium_phosphorus_imbalance,
  });
}

function phase2LabsFromBody(body = {}) {
  return cleanObject({
    albumin_status: body.albumin_status ?? body.albuminStatus,
    BUN_status: body.BUN_status ?? body.bun_status ?? body.bunStatus,
    urea_status: body.urea_status ?? body.ureaStatus,
    hemoglobin_status: body.hemoglobin_status ?? body.hemoglobinStatus,
    sodium_status: body.sodium_status ?? body.sodiumStatus,
    potassium_status: body.potassium_status ?? body.potassiumStatus,
    phosphorus_status: body.phosphorus_status ?? body.phosphorusStatus,
    calcium_status: body.calcium_status ?? body.calciumStatus,
  });
}

function phase2DecisionSupportForFoodLog({ childContext, payload, body }) {
  return generatePhase2DecisionSupport(
    phase2ProfileFromChildContext(childContext),
    phase2LabsFromBody(body),
    [phase2FoodItemFromPayload(payload, body)],
  );
}

function nutrientTotalsFromPreview(preview = {}) {
  const nutrients = preview.final_nutrients || preview.finalNutrients || {};
  return {
    calories: numberOrNull(nutrients.calories),
    protein: numberOrNull(nutrients.protein),
    carbohydrate: numberOrNull(nutrients.carbohydrate),
    fat: numberOrNull(nutrients.fat),
    sodium: numberOrNull(nutrients.sodium),
    potassium: numberOrNull(nutrients.potassium),
    phosphorus: numberOrNull(nutrients.phosphorus),
  };
}

function extractWaterMlFromLog(data = {}) {
  const explicitWaterMl = numberOrNull(
    data.totalFluidContributionMl ??
      data.total_fluid_contribution_ml ??
      data.waterMl ??
      data.water_ml ??
      data.fluid_ml,
  );
  if (explicitWaterMl !== null && explicitWaterMl > 0) {
    return explicitWaterMl;
  }

  const normalizedName = String(
    data.name ?? data.foodName ?? data.food_name ?? "",
  )
    .trim()
    .toLowerCase();

  // List of beverages that should be counted toward hydration
  const hydrationKeywords = [
    "water",
    "juice",
    "milk",
    "tea",
    "coffee",
    "smoothie",
    "drink",
    "beverage",
    "liquid",
    "coconut water",
    "sports drink",
    "electrolyte",
  ];

  const isHydrationItem = hydrationKeywords.some((keyword) =>
    normalizedName.includes(keyword),
  );

  if (!isHydrationItem) {
    return 0;
  }

  const portionText = String(
    data.portion ??
      data.selectedServingDescription ??
      data.selected_serving_description ??
      "",
  );
  
  // Try to extract ML from portion text (e.g., "250 mL", "250ml", "250 ml")
  const mlMatch = portionText.match(/(\d+(?:\.\d+)?)\s*m\s*l\b/i);
  if (mlMatch) {
    const parsedPortion = Number(mlMatch[1]);
    return Number.isFinite(parsedPortion) ? parsedPortion : 0;
  }

  // Try to extract from cup measurements (1 cup = 240 mL)
  const cupMatch = portionText.match(/(\d+(?:\.\d+)?)\s*(?:cup|c\b)/i);
  if (cupMatch) {
    const cups = Number(cupMatch[1]);
    return Number.isFinite(cups) ? Math.round(cups * 240) : 0;
  }

  // Try to extract from oz measurements (1 oz = 29.57 mL, approx 30 mL)
  const ozMatch = portionText.match(/(\d+(?:\.\d+)?)\s*(?:oz|fl\s*oz|fluid\s*oz)\b/i);
  if (ozMatch) {
    const oz = Number(ozMatch[1]);
    return Number.isFinite(oz) ? Math.round(oz * 30) : 0;
  }

  return 0;
}

async function getDocData(collection, id) {
  if (!id) return null;
  const snap = await db.collection(collection).doc(id).get();
  return snap.exists ? { id: snap.id, ...snap.data() } : null;
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
    medicalProfile?.isPostTransplant ??
    medicalProfile?.is_post_transplant ??
    medicalProfile?.postTransplant ??
    medicalProfile?.post_transplant;
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
      medicalProfile?.sterileDietWeeks ??
      medicalProfile?.sterile_diet_weeks ??
      medicalProfile?.weeksPostTransplant ??
      medicalProfile?.weeks_post_transplant,
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
        targets.proteinMin ??
          targets.protein_min ??
          targets.minProteinG,
      ),
      protein_max: numberOrNull(
        targets.proteinMax ??
          targets.protein_max ??
          targets.maxProteinG,
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

function buildNutritionProfile({ childContext = {}, medicalProfile = {}, labs = {}, anthropometrics = {} }) {
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
    dailySodiumLimitMg: 2000,
    avoid: [...avoid],
    prefer: [...prefer],
  };
}

function scoreMealCandidate(food, mealType, profile, restrictions) {
  const foodText = [food.name, food.description, food.servingDescription, food.brandName].join(" ");
  let score = 100;
  const sodium = numberOrNull(food.sodium) || 0;
  const protein = numberOrNull(food.protein) || 0;
  const calories = numberOrNull(food.calories) || 0;

  if (sodium > 600) score -= 20;
  if (containsAny(foodText, restrictions.avoid)) score -= 35;
  if (profile.potassiumStatus === "High" && numberOrNull(food.potassium) > 500) score -= 20;
  if (profile.phosphorusStatus === "High" && numberOrNull(food.phosphorus) > 250) score -= 20;
  if (profile.diabetesRisk && containsAny(foodText, ["sweet", "sugar", "syrup", "dessert"])) score -= 20;
  if (profile.riskMalnutrition && protein >= 8) score += 15;
  if (containsAny(foodText, restrictions.prefer)) score += 10;
  if (mealType.includes("Snack") && calories > 300) score -= 12;
  if (!mealType.includes("Snack") && calories < 120) score -= 8;

  return score;
}

function fallbackMealCandidate(mealType, restrictions) {
  const fallbackByMeal = {
    Breakfast: {
      name: "Apple oatmeal",
      calories: 260,
      protein: 6,
      carbohydrate: 48,
      fat: 5,
      sodium: 90,
      potassium: 170,
      phosphorus: 90,
    },
    "AM Snack": {
      name: "Apple slices",
      calories: 95,
      protein: 0.5,
      carbohydrate: 25,
      fat: 0.3,
      sodium: 2,
      potassium: 195,
      phosphorus: 20,
    },
    Lunch: {
      name: "Chicken rice with cabbage",
      calories: 430,
      protein: 24,
      carbohydrate: 58,
      fat: 10,
      sodium: 280,
      potassium: 360,
      phosphorus: 210,
    },
    "PM Snack": {
      name: "Grapes and crackers",
      calories: 150,
      protein: 2,
      carbohydrate: 30,
      fat: 3,
      sodium: 120,
      potassium: 150,
      phosphorus: 45,
    },
    Dinner: {
      name: "Fish rice with cauliflower",
      calories: 390,
      protein: 25,
      carbohydrate: 50,
      fat: 9,
      sodium: 260,
      potassium: 380,
      phosphorus: 230,
    },
  };
  const selected = fallbackByMeal[mealType] || fallbackByMeal.Breakfast;
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

async function searchMealPlanRecipes(query, mealType, calorieTarget = null) {
  try {
    // Use recipe search for meal planning instead of individual foods
    // Recipes provide better nutrient data per serving
    const result = await fatSecretBridge.searchRecipes(
      query,
      0,
      calorieTarget ? Math.round(calorieTarget * 1.1) : null // Allow 10% flexibility
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
    // Fallback: try food search if recipe search fails
    try {
      return await fatSecretBridge.searchFoods(query, 0);
    } catch (fallbackError) {
      console.error("MEAL_PLAN_RECIPE_FALLBACK_ERROR:", fallbackError.message);
      return { recipes: [], foods: [] };
    }
  }
}

async function generateMealPlan(body = {}) {
  const userId = body.userId || body.uid;
  const requestedProfileId = body.childProfileId || body.profileUserId || userId;
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
  const restrictions = buildFoodRestrictions(nutritionProfile);
  
  // Recipe queries for meal planning (better results than individual foods)
  const mealQueries = [
    { mealType: "Breakfast", query: "oatmeal with berries and low sodium", target: 300 },
    { mealType: "AM Snack", query: "apple or grapes with low sodium", target: 150 },
    { mealType: "Lunch", query: "grilled chicken with rice and vegetables low sodium", target: 400 },
    { mealType: "PM Snack", query: "fresh fruit or crackers low sodium", target: 150 },
    { mealType: "Dinner", query: "fish with rice and low sodium vegetables", target: 450 },
  ];

  const meals = [];
  for (const meal of mealQueries) {
    // Search for recipes (primary) or foods (fallback)
    const result = await searchMealPlanRecipes(meal.query, meal.mealType, meal.target);
    
    // Handle both recipe and food results
    const candidates = (result.recipes || result.foods || [])
      .map((item) => ({
        ...item,
        mealType: meal.mealType,
        score: scoreMealCandidate(item, meal.mealType, nutritionProfile, restrictions),
        reason: "Ranked by CKD sodium, potassium, phosphorus, diabetes, and protein needs.",
      }))
      .filter((item) => item.score >= 45)
      .sort((a, b) => b.score - a.score);
    
    const selected = candidates[0] || 
      (result.recipes && result.recipes[0]) || 
      (result.foods && result.foods[0]) || 
      fallbackMealCandidate(meal.mealType, restrictions);
    
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
        source: result.recipes ? "fatsecret_recipe_meal_plan" : "fatsecret_food_meal_plan",
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
    nutritionProfile,
    restrictions,
    mealStructure: ["Breakfast", "AM Snack", "Lunch", "PM Snack", "Dinner"],
    meals,
    totals,
    validation: {
      sodiumWithinLimit: totals.sodium <= restrictions.dailySodiumLimitMg,
      proteinWithinTarget:
        !nutritionProfile.proteinTarget || totals.protein <= nutritionProfile.proteinTarget,
      generatedFrom: ["profile", "latest_labs", "fatsecret_recipe_search", "ckd_rules"],
    },
    displayMessage:
      "Meal plans are generated based on your profile and latest laboratory results. Recipes are sourced from FatSecret and filtered according to CKD dietary guidelines.",
  };
}

async function buildPreviewRequest(body) {
  const userId = body.userId || body.user_id;
  const childProfileId = body.childProfileId || body.child_profile_id || userId;
  const foodId = body.foodId || body.food_id;
  const servingId = body.servingId || body.serving_id;
  const mealType = body.mealType || body.meal_type;
  const loggedAtDate = parseLogDateTime(body.loggedAt || body.logged_at);
  const quantity = Number(body.quantity);

  if (!userId || !childProfileId || !foodId || !servingId || !mealType) {
    const error = new Error(
      "userId, childProfileId, foodId, servingId, mealType, and loggedAt are required",
    );
    error.statusCode = 400;
    throw error;
  }

  if (!Number.isFinite(quantity) || quantity <= 0 || quantity > 20) {
    const error = new Error("quantity must be greater than 0 and no more than 20");
    error.statusCode = 400;
    throw error;
  }

  const childContext = await buildChildContext(userId, childProfileId);
  const summaryId = `${childProfileId}_${logDateKey(loggedAtDate)}`;
  const summaryDoc = await db
    .collection(DAILY_SUMMARY_COLLECTION)
    .doc(summaryId)
    .get();
  const summaryData = summaryDoc.exists ? summaryDoc.data() || {} : {};
  childContext.targets.currentDailyFluidConsumedMl = numberOrNull(
    summaryData.waterMl ?? summaryData.water_ml ?? summaryData.fluid_ml,
  ) ?? 0;

  return {
    user_id: userId,
    child_profile_id: childProfileId,
    food_id: String(foodId),
    serving_id: String(servingId),
    quantity,
    meal_type: mealType,
    logged_at: loggedAtDate.toISOString(),
    user_notes: body.userNotes || body.user_notes || null,
    child_context: childContext,
  };
}

async function getMealPreview(body) {
  const previewRequest = await buildPreviewRequest(body);
  return fatSecretBridge.mealLoggingPreview(previewRequest);
}

async function recomputeDailySummary(childProfileId, date) {
  const snapshot = await db
    .collection(FOOD_LOG_COLLECTION)
    .where("childProfileId", "==", childProfileId)
    .where("date", "==", date)
    .get();

  const totals = {
    calories: 0,
    protein: 0,
    carbohydrate: 0,
    fat: 0,
    sodium: 0,
    potassium: 0,
    phosphorus: 0,
  };
  let count = 0;
  let waterMl = 0;

  snapshot.docs.forEach((doc) => {
    const data = doc.data() || {};
    if (data.deletedAt) return;
    count += 1;
    waterMl += extractWaterMlFromLog(data);
    const nutrients = data.finalNutrients || {};
    for (const key of Object.keys(totals)) {
      const value = numberOrNull(nutrients[key]);
      if (value !== null) totals[key] += value;
    }
  });

  const summaryId = `${childProfileId}_${date}`;
  const summary = {
    childProfileId,
    date,
    mealCount: count,
    waterMl,
    water_ml: waterMl,
    fluid_ml: waterMl,
    totals,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.collection(DAILY_SUMMARY_COLLECTION).doc(summaryId).set(summary, {
    merge: true,
  });

  return summary;
}

function fluidContributionFromBody(body = {}) {
  const raw =
    body.fluidContribution ||
    body.fluid_contribution ||
    body.fluidContributionPreview ||
    {};
  const source = raw && typeof raw === "object" ? raw : {};
  const totalFluidContributionMl = numberOrNull(
    source.totalFluidContributionMl ??
      source.total_fluid_contribution_ml ??
      body.totalFluidContributionMl ??
      body.total_fluid_contribution_ml,
  );
  const waterContentMl = numberOrNull(
    source.waterContentMl ??
      source.water_content_ml ??
      body.waterContentMl ??
      body.water_content_ml,
  );
  const drinkFluidMl = numberOrNull(
    source.drinkFluidMl ??
      source.drink_fluid_ml ??
      body.drinkFluidMl ??
      body.drink_fluid_ml,
  );

  return cleanObject({
    usdaWaterContentGrams: numberOrNull(
      source.usdaWaterContentGrams ??
        source.usda_water_content_grams ??
        body.usdaWaterContentGrams ??
        body.usda_water_content_grams,
    ),
    waterContentMl,
    isLiquidOrDrink:
      source.isLiquidOrDrink === true ||
      source.is_liquid_or_drink === true ||
      body.isLiquidOrDrink === true,
    drinkFluidMl,
    totalFluidContributionMl,
    fluidContributionPercent: numberOrNull(
      source.fluidContributionPercent ??
        source.fluid_contribution_percent ??
        body.fluidContributionPercent ??
        body.fluid_contribution_percent,
    ),
    showFluidWarning:
      source.showFluidWarning === true ||
      source.show_fluid_warning === true ||
      body.showFluidWarning === true,
    waterDataAvailable:
      source.waterDataAvailable === true ||
      source.water_data_available === true ||
      body.waterDataAvailable === true,
    fluidContributionPreview: source,
  });
}

async function createHydrationLogFromFood({
  userId,
  childProfileId,
  foodLogId,
  fluidFields,
  loggedAtDate,
}) {
  const amountMl = numberOrNull(fluidFields.totalFluidContributionMl);
  if (amountMl === null || amountMl <= 0) return null;

  const payload = {
    userId,
    childProfileId,
    source: "foodLog",
    foodLogId,
    amountMl,
    type: fluidFields.isLiquidOrDrink ? "drink" : "food_water",
    loggedAt: admin.firestore.Timestamp.fromDate(loggedAtDate),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const docRef = await db.collection(HYDRATION_LOG_COLLECTION).add(payload);
  return { id: docRef.id, ...payload };
}

function deviceTokensFromProfile(profile = {}) {
  const raw = profile.deviceTokens;
  if (!raw || typeof raw !== "object") return [];
  return [
    ...new Set(
      Object.values(raw)
        .filter((entry) => entry && typeof entry.token === "string")
        .map((entry) => entry.token.trim())
        .filter(Boolean),
    ),
  ];
}

function linkedCaregiverIdForAdolescent(profile = {}) {
  if (String(profile.role || "").trim().toLowerCase() !== "adolescent") {
    return null;
  }
  const settings = profile.caregiverSettings || {};
  if (settings.caregiverLinked === true && settings.caregiverId) {
    return String(settings.caregiverId);
  }
  if (profile.caregiverUserId) return String(profile.caregiverUserId);
  return null;
}

function exceededNutrients(summary = {}, childContext = {}) {
  const totals = summary.totals || {};
  const targets = childContext.targets || {};
  return [
    { key: "sodium", label: "Sodium", total: totals.sodium, limit: targets.sodium },
    {
      key: "potassium",
      label: "Potassium",
      total: totals.potassium,
      limit: targets.potassium,
    },
    {
      key: "phosphorus",
      label: "Phosphorus",
      total: totals.phosphorus,
      limit: targets.phosphorus,
    },
  ].filter((item) => {
    const total = numberOrNull(item.total);
    const limit = numberOrNull(item.limit);
    return total !== null && limit !== null && limit > 0 && total > limit;
  });
}

async function notifyLinkedCaregiverForNutritionLimits(childProfileId, date, summary) {
  try {
    if (!childProfileId || !date || !summary) return;

    const adolescentDoc = await db.collection("users").doc(childProfileId).get();
    if (!adolescentDoc.exists) return;

    const adolescent = adolescentDoc.data() || {};
    const caregiverId = linkedCaregiverIdForAdolescent(adolescent);
    if (!caregiverId) return;

    const caregiverDoc = await db.collection("users").doc(caregiverId).get();
    if (!caregiverDoc.exists) return;

    const caregiver = caregiverDoc.data() || {};
    const tokens = deviceTokensFromProfile(caregiver);
    const childContext = await buildChildContext(childProfileId, childProfileId);
    const exceeded = exceededNutrients(summary, childContext);
    if (exceeded.length === 0) return;

    const childName =
      adolescent.childFullName ||
      adolescent.fullName ||
      adolescent.displayName ||
      adolescent.name ||
      "Your child";

    for (const nutrient of exceeded) {
      const stateId = `${caregiverId}_${childProfileId}_${date}_${nutrient.key}`;
      const stateRef = db
        .collection("notificationState")
        .doc(`${LINKED_ADOLESCENT_NUTRITION_ALERT_TYPE}_${stateId}`);
      const stateDoc = await stateRef.get();
      if (stateDoc.exists) continue;

      const body = `${childName} has exceeded the ${nutrient.label}. Please check your child.`;
      const notificationPayload = {
        userId: caregiverId,
        profileUserId: childProfileId,
        childProfileId,
        type: LINKED_ADOLESCENT_NUTRITION_ALERT_TYPE,
        title: "Nutrition Alert",
        body,
        nutrient: nutrient.key,
        nutrientLabel: nutrient.label,
        total: numberOrNull(nutrient.total),
        limit: numberOrNull(nutrient.limit),
        date,
        read: false,
        priority: "high",
        color: "red",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db.collection("notifications").add(notificationPayload);

      if (tokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
          tokens,
          notification: {
            title: "Nutrition Alert",
            body,
          },
          data: {
            type: LINKED_ADOLESCENT_NUTRITION_ALERT_TYPE,
            userId: caregiverId,
            profileUserId: childProfileId,
            childProfileId,
            nutrient: nutrient.key,
            date,
          },
          android: {
            priority: "high",
            notification: {
              channelId: "nutrikidney_reminders",
            },
          },
        });
      }

      await stateRef.set({
        caregiverId,
        childProfileId,
        date,
        nutrient: nutrient.key,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  } catch (error) {
    console.error("LINKED_CAREGIVER_NUTRITION_ALERT ERROR:", error.message);
  }
}

async function recomputeGamification(userId, date) {
  if (!userId || !date) return;
  try {
    await recomputeGamificationForDate({ admin, db, userId, date });
  } catch (error) {
    console.error("GAMIFICATION_RECOMPUTE ERROR:", error.message);
  }
}

router.get("/health", async (_req, res) => {
  try {
    const python = await fatSecretBridge.healthCheck();
    res.status(200).json({
      success: true,
      service: "NutriKidney Food Log Bridge",
      python,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      success: false,
      error: error.message,
      details: error.data,
    });
  }
});

router.post("/search", async (req, res) => {
  try {
    const { query, page = 0 } = req.body;

    if (!query || String(query).trim().length < 1) {
      return res.status(400).json({
        success: false,
        error: "Food search query cannot be empty",
      });
    }

    const result = await fatSecretBridge.mealLoggingSearch(
      String(query).trim(),
      page,
    );

    return res.status(200).json({
      success: true,
      ...result,
      foods: result.choices || [],
    });
  } catch (error) {
    console.error("FOOD_SEARCH ERROR:", error.message);
    return res.status(error.statusCode || 500).json({
      success: false,
      error: "Food search is temporarily unavailable. Please try again.",
      details: error.data,
    });
  }
});

router.get("/details/:foodId", async (req, res) => {
  try {
    const result = await fatSecretBridge.mealLoggingFoodDetails(
      String(req.params.foodId),
    );
    return res.status(200).json({ success: true, food: result, ...result });
  } catch (error) {
    console.error("FOOD_DETAILS ERROR:", error.message);
    return res.status(error.statusCode || 500).json({
      success: false,
      error: "Food details are temporarily unavailable. Please try again.",
      details: error.data,
    });
  }
});

router.post("/details", async (req, res) => {
  try {
    const { foodId, food_id } = req.body;
    const id = foodId || food_id;

    if (!id) {
      return res.status(400).json({
        success: false,
        error: "foodId is required",
      });
    }

    const result = await fatSecretBridge.mealLoggingFoodDetails(String(id));
    return res.status(200).json({ success: true, food: result, ...result });
  } catch (error) {
    console.error("FOOD_DETAILS ERROR:", error.message);
    return res.status(error.statusCode || 500).json({
      success: false,
      error: "Food details are temporarily unavailable. Please try again.",
      details: error.data,
    });
  }
});

router.post("/recognize-image", async (req, res) => {
  let aiUsage = null;
  try {
    const { imageBase64, image_base64, contentType, content_type, userId, uid } = req.body;
    const image = imageBase64 || image_base64;
    const scanUserId = userId || uid;

    if (!image) {
      return res.status(400).json({
        success: false,
        error: "imageBase64 is required",
      });
    }

    aiUsage = await consumeAiUsage({
      db,
      admin,
      uid: scanUserId,
      feature: "food_image",
    });

    const result = await fatSecretBridge.mealLoggingRecognizeImage({
      image_base64: image,
      content_type: contentType || content_type || "image/jpeg",
    });
    const recognizedFood = result.food || result.recognizedFood;

    return res.status(200).json({
      success: true,
      ...result,
      food: recognizedFood,
      recognizedFood,
      aiUsage,
      nextStep: "review_recognized_food",
      message:
        result.message ||
        "Food recognized. Review the nutrition information before adding.",
    });
  } catch (error) {
    console.error("FOOD_IMAGE_RECOGNITION ERROR:", error.message);
    return res.status(error.statusCode || 500).json({
      success: false,
      error:
        error.message ||
        "The image could not be identified as food. Please try another image.",
      aiUsage: error.aiUsage || aiUsage,
      details: error.data,
    });
  }
});

router.post("/ai-usage/status", async (req, res) => {
  try {
    const { userId, uid, feature } = req.body;
    const aiUsage = await getAiUsageStatus({
      db,
      uid: userId || uid,
      feature: feature || "food_image",
    });

    return res.status(200).json({
      success: true,
      aiUsage,
    });
  } catch (error) {
    return res.status(error.statusCode || 400).json({
      success: false,
      error: error.message,
    });
  }
});

router.post("/preview", async (req, res) => {
  try {
    const preview = await getMealPreview(req.body);
    return res.status(200).json({ success: true, preview });
  } catch (error) {
    console.error("FOOD_PREVIEW ERROR:", error.message);
    return res.status(error.statusCode || 500).json({
      success: false,
      error: error.message || "Failed to preview meal",
      details: error.data,
    });
  }
});

router.post("/meal-plan/generate", async (req, res) => {
  try {
    const mealPlan = await generateMealPlan(req.body);
    return res.status(200).json({
      success: true,
      mealPlan,
    });
  } catch (error) {
    console.error("MEAL_PLAN_GENERATE ERROR:", error.message);
    return res.status(error.statusCode || 500).json({
      success: false,
      error: error.message || "Failed to generate meal plan",
      details: error.data,
    });
  }
});

router.post("/logs/list", async (req, res) => {
  try {
    const {
      userId,
      profileUserId,
      childProfileId,
      date,
      dateFrom,
      dateTo,
      limit = 100,
      includeDeleted = false,
    } =
      req.body;

    if (!userId) {
      return res.status(400).json({
        success: false,
        error: "userId is required",
      });
    }

    const requestedLimit = Number(limit) || 100;
    let logs = [];

    const requestedProfileId = childProfileId || profileUserId;
    let snapshots;
    if (requestedProfileId) {
      snapshots = await Promise.all([
        db
          .collection(FOOD_LOG_COLLECTION)
          .where("childProfileId", "==", requestedProfileId)
          .get(),
        db
          .collection(FOOD_LOG_COLLECTION)
          .where("userId", "==", requestedProfileId)
          .get(),
      ]);
    } else {
      snapshots = [
        await db
          .collection(FOOD_LOG_COLLECTION)
          .where("userId", "==", userId)
          .get(),
      ];
    }

    const docsById = new Map();
    snapshots.forEach((snapshot) => {
      snapshot.docs.forEach((doc) => docsById.set(doc.id, doc));
    });

    logs = [...docsById.values()].map(serializeFoodLog).filter((log) => {
      if (requestedProfileId) {
        if (
          log.childProfileId !== requestedProfileId &&
          log.userId !== requestedProfileId
        ) {
          return false;
        }
      } else if (log.userId !== userId) {
        return false;
      }
      if (date && log.date !== date) return false;
      if (dateFrom && (!log.date || log.date < dateFrom)) return false;
      if (dateTo && (!log.date || log.date > dateTo)) return false;
      return true;
    });

    logs = logs
      .filter((log) => includeDeleted || !log.deletedAt)
      .sort((a, b) => timestampMillis(b.createdAt) - timestampMillis(a.createdAt))
      .slice(0, requestedLimit);

    return res.status(200).json({
      success: true,
      logs,
    });
  } catch (error) {
    console.error("FOOD_LOG_LIST ERROR:", error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to load food logs",
    });
  }
});

router.post("/logs/add", async (req, res) => {
  try {
    if (!req.body.servingId && !req.body.serving_id) {
      const {
        userId,
        profileUserId,
        childProfileId,
        mealType,
        date,
        loggedAt,
        foodId,
        name,
        portion,
        calories,
        protein,
        carbohydrate,
        fat,
        sodium,
        potassium,
        phosphorus,
        source,
        needsManualReview,
        raw,
        userConfirmedAllergyWarning,
      } = req.body;

      if (!userId || !mealType || !name) {
        return res.status(400).json({
          success: false,
          error: "userId, mealType, and name are required",
        });
      }

      const loggedAtDate = parseLogDateTime(loggedAt || new Date().toISOString());
      const logDate = date || logDateKey(loggedAtDate);
      const now = admin.firestore.FieldValue.serverTimestamp();
      const fluidFields = fluidContributionFromBody(req.body);
      const finalNutrients = {
        calories: Number(calories) || 0,
        protein: Number(protein) || 0,
        carbohydrate: Number(carbohydrate) || 0,
        fat: Number(fat) || 0,
        sodium: Number(sodium) || 0,
        potassium: Number(potassium) || 0,
        phosphorus: resolvedPhosphorusValue(phosphorus, raw),
      };
      const phosphorusGuide = phosphorusGuideFromRaw(raw);
      const candidatePayload = cleanObject({
        childProfileId: childProfileId || profileUserId || userId,
        name,
        foodName: name,
        portion: portion || "1 serving",
        selectedServingDescription: portion || "1 serving",
        brandName: raw?.brand_name || raw?.brandName,
        foodType: raw?.food_type || raw?.foodType,
        raw,
      });
      const { childContext, allergyCheck } = await evaluateAllergyAlert({
        userId,
        childProfileId: childProfileId || profileUserId,
        payload: candidatePayload,
      });

      if (allergyCheck.allergyAlert && userConfirmedAllergyWarning !== true) {
        return res.status(200).json({
          success: false,
          requiresAllergyConfirmation: true,
          ...allergyCheck,
        });
      }

      const payload = addAllergyMetadataToPayload(cleanObject({
        userId,
        childProfileId: childProfileId || profileUserId || userId,
        mealType,
        date: logDate,
        loggedAt: admin.firestore.Timestamp.fromDate(loggedAtDate),
        foodId,
        foodName: name,
        name,
        portion: portion || "1 serving",
        selectedServingDescription: portion || "1 serving",
        selectedQuantity: 1,
        quantity: 1,
        waterMl:
          numberOrNull(fluidFields.totalFluidContributionMl) ??
          (String(name).trim().toLowerCase() === "water"
            ? extractWaterMlFromLog({
                name,
                portion: portion || "1 serving",
              })
            : 0),
        ...fluidFields,
        calories: finalNutrients.calories,
        protein: finalNutrients.protein,
        carbohydrate: finalNutrients.carbohydrate,
        fat: finalNutrients.fat,
        sodium: finalNutrients.sodium,
        potassium: finalNutrients.potassium,
        phosphorus: finalNutrients.phosphorus,
        finalNutrients,
        phosphorusGuide,
        source: source || "manual_entry",
        needsManualReview: needsManualReview === true,
        raw,
        version: 1,
        previousValues: [],
        createdAt: now,
        updatedAt: now,
      }), allergyCheck, userConfirmedAllergyWarning);
      const decisionSupport = phase2DecisionSupportForFoodLog({
        childContext,
        payload,
        body: req.body,
      });

      const docRef = await db.collection(FOOD_LOG_COLLECTION).add(payload);
      const hydrationLog = await createHydrationLogFromFood({
        userId,
        childProfileId: payload.childProfileId,
        foodLogId: docRef.id,
        fluidFields,
        loggedAtDate,
      });

      let dailySummaryStatus = "updated";
      try {
        const summary = await recomputeDailySummary(payload.childProfileId, logDate);
        await notifyLinkedCaregiverForNutritionLimits(
          payload.childProfileId,
          logDate,
          summary,
        );
        await recomputeGamification(payload.childProfileId, logDate);
      } catch (summaryError) {
        console.error("FOOD_LOG_SUMMARY ERROR:", summaryError.message);
        dailySummaryStatus = "queued_for_retry";
      }

      return res.status(200).json({
        success: true,
        foodLogId: docRef.id,
        mealLogId: docRef.id,
        dailySummaryStatus,
        allergyChecked: allergyCheck.allergyChecked,
        profileAllergies: allergyCheck.profileAllergies,
        allergyAlert: allergyCheck.allergyAlert,
        matchedAllergens: allergyCheck.matchedAllergens,
        hydrationLog,
        decisionSupport,
        log: {
          id: docRef.id,
          ...payload,
          loggedAt: loggedAtDate.toISOString(),
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        },
        message: "Food logged successfully",
      });
    }

    const {
      userId,
      profileUserId,
      childProfileId,
      mealType,
      date,
      loggedAt,
      foodId,
      servingId,
      serving_id,
      name,
      portion,
      calories,
      protein,
      carbohydrate,
      fat,
      sodium,
      potassium,
      phosphorus,
      quantity,
      source,
      needsManualReview,
      raw,
      userNotes,
      userConfirmedAllergyWarning,
    } = req.body;

    if (!userId || !mealType || !name) {
      return res.status(400).json({
        success: false,
        error: "userId, mealType, and name are required",
      });
    }

    const selectedServingId = servingId || serving_id;
    const loggedAtDate = parseLogDateTime(loggedAt || new Date().toISOString());
    const logDate = date || logDateKey(loggedAtDate);
    const selectedQuantity = Number(quantity) || 1;
    const fluidFields = fluidContributionFromBody(req.body);

    if (!Number.isFinite(selectedQuantity) || selectedQuantity <= 0 || selectedQuantity > 20) {
      return res.status(400).json({
        success: false,
        error: "quantity must be greater than 0 and no more than 20",
      });
    }

    const finalNutrients = {
      calories: Number(calories) || 0,
      protein: Number(protein) || 0,
      carbohydrate: Number(carbohydrate) || 0,
      fat: Number(fat) || 0,
      sodium: Number(sodium) || 0,
      potassium: Number(potassium) || 0,
      phosphorus: resolvedPhosphorusValue(phosphorus, raw),
    };
    const phosphorusGuide = phosphorusGuideFromRaw(raw);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const targetChildProfileId = childProfileId || profileUserId || userId;
    const candidatePayload = cleanObject({
      childProfileId: targetChildProfileId,
      name,
      foodName: name,
      brandName: raw?.brand_name || raw?.brandName,
      foodType: raw?.food_type || raw?.foodType,
      portion: portion || "1 serving",
      selectedServingDescription: portion || "1 serving",
      raw,
    });
    const { childContext, allergyCheck } = await evaluateAllergyAlert({
      userId,
      childProfileId: targetChildProfileId,
      payload: candidatePayload,
    });

    if (allergyCheck.allergyAlert && userConfirmedAllergyWarning !== true) {
      return res.status(200).json({
        success: false,
        requiresAllergyConfirmation: true,
        ...allergyCheck,
      });
    }

    const payload = addAllergyMetadataToPayload(cleanObject({
      userId,
      childProfileId: targetChildProfileId,
      mealType,
      date: logDate,
      loggedAt: admin.firestore.Timestamp.fromDate(loggedAtDate),
      foodId,
      foodName: name,
      name,
      brandName: raw?.brand_name || raw?.brandName,
      foodType: raw?.food_type || raw?.foodType,
      selectedServingId,
      selectedServingDescription: portion || "1 serving",
      selectedQuantity,
      quantity: selectedQuantity,
      portion: portion || "1 serving",
      waterMl:
        numberOrNull(fluidFields.totalFluidContributionMl) ??
        (String(name).trim().toLowerCase() === "water"
          ? extractWaterMlFromLog({
              name,
              portion: portion || "1 serving",
              waterMl: req.body.waterMl ?? req.body.water_ml,
            })
          : 0),
      ...fluidFields,
      calories: finalNutrients.calories,
      protein: finalNutrients.protein,
      carbohydrate: finalNutrients.carbohydrate,
      fat: finalNutrients.fat,
      sodium: finalNutrients.sodium,
      potassium: finalNutrients.potassium,
      phosphorus: finalNutrients.phosphorus,
      finalNutrients,
      phosphorusGuide,
      potassiumReliabilityNote:
        finalNutrients.potassium > 0 ? "Provider-estimated; use with caution." : undefined,
      safetyFlags: [],
      insights: [],
      source: source || "fatsecret",
      needsManualReview: needsManualReview === true,
      userNotes,
      raw,
      version: 1,
      previousValues: [],
      createdAt: now,
      updatedAt: now,
    }), allergyCheck, userConfirmedAllergyWarning);
    const decisionSupport = phase2DecisionSupportForFoodLog({
      childContext,
      payload,
      body: req.body,
    });

    const docRef = await db.collection(FOOD_LOG_COLLECTION).add(payload);
    const hydrationLog = await createHydrationLogFromFood({
      userId,
      childProfileId: payload.childProfileId,
      foodLogId: docRef.id,
      fluidFields,
      loggedAtDate,
    });

    let dailySummaryStatus = "updated";
    try {
      const summary = await recomputeDailySummary(payload.childProfileId, logDate);
      await notifyLinkedCaregiverForNutritionLimits(
        payload.childProfileId,
        logDate,
        summary,
      );
      await recomputeGamification(payload.childProfileId, logDate);
    } catch (summaryError) {
      console.error("FOOD_LOG_SUMMARY ERROR:", summaryError.message);
      dailySummaryStatus = "queued_for_retry";
    }

    return res.status(200).json({
      success: true,
      foodLogId: docRef.id,
      mealLogId: docRef.id,
      dailySummaryStatus,
      allergyChecked: allergyCheck.allergyChecked,
      profileAllergies: allergyCheck.profileAllergies,
      allergyAlert: allergyCheck.allergyAlert,
      matchedAllergens: allergyCheck.matchedAllergens,
      hydrationLog,
      decisionSupport,
      log: {
        id: docRef.id,
        ...payload,
        loggedAt: loggedAtDate.toISOString(),
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
      message: "Food logged successfully",
    });
  } catch (error) {
    console.error("FOOD_LOG_ADD ERROR:", error.message);
    return res.status(error.statusCode || 500).json({
      success: false,
      error: error.message || "Failed to save food log",
      details: error.data,
    });
  }
});

router.post("/logs/update", async (req, res) => {
  try {
    const {
      userId,
      profileUserId,
      childProfileId,
      foodLogId,
      mealType,
      date,
      name,
      portion,
      servingId,
      serving_id,
      quantity,
      calories,
      protein,
      carbohydrate,
      fat,
      sodium,
      potassium,
      phosphorus,
      raw,
    } = req.body;

    if (!userId || !foodLogId) {
      return res.status(400).json({
        success: false,
        error: "userId and foodLogId are required",
      });
    }

    const docRef = db.collection(FOOD_LOG_COLLECTION).doc(foodLogId);
    const doc = await docRef.get();

    if (!doc.exists) {
      return res.status(404).json({
        success: false,
        error: "Food log not found",
      });
    }

    const existing = doc.data() || {};
    const requestedProfileId = childProfileId || profileUserId;
    if (
      existing.userId !== userId &&
      (!requestedProfileId ||
        (existing.childProfileId !== requestedProfileId &&
          existing.userId !== requestedProfileId))
    ) {
      return res.status(403).json({
        success: false,
        error: "Food log does not belong to this user",
      });
    }

    const finalNutrients = {
      calories: Number(calories) || 0,
      protein: Number(protein) || 0,
      carbohydrate: Number(carbohydrate) || 0,
      fat: Number(fat) || 0,
      sodium: Number(sodium) || 0,
      potassium: Number(potassium) || 0,
      phosphorus: resolvedPhosphorusValue(phosphorus, raw || existing.raw),
    };
    const phosphorusGuide =
      phosphorusGuideFromRaw(raw) || existing.phosphorusGuide;
    const selectedQuantity = Number(quantity);
    const hasSelectedQuantity =
      Number.isFinite(selectedQuantity) && selectedQuantity > 0 && selectedQuantity <= 20;
    const selectedServingId = servingId || serving_id;
    const previousValues = Array.isArray(existing.previousValues)
      ? existing.previousValues.slice(-9)
      : [];
    previousValues.push({
      name: existing.name,
      portion: existing.portion,
      mealType: existing.mealType,
      date: existing.date,
      finalNutrients: existing.finalNutrients,
      updatedAt: serializeTimestamp(existing.updatedAt),
    });

    const payload = cleanObject({
      mealType: mealType || existing.mealType,
      date: date || existing.date,
      foodName: name || existing.name,
      name: name || existing.name,
      portion: portion || existing.portion,
      selectedServingDescription: portion || existing.selectedServingDescription,
      selectedServingId: selectedServingId || existing.selectedServingId,
      selectedQuantity: hasSelectedQuantity
        ? selectedQuantity
        : existing.selectedQuantity,
      quantity: hasSelectedQuantity ? selectedQuantity : existing.quantity,
      calories: finalNutrients.calories,
      protein: finalNutrients.protein,
      carbohydrate: finalNutrients.carbohydrate,
      fat: finalNutrients.fat,
      sodium: finalNutrients.sodium,
      potassium: finalNutrients.potassium,
      phosphorus: finalNutrients.phosphorus,
      finalNutrients,
      phosphorusGuide,
      raw: raw || existing.raw,
      previousValues,
      version: Number(existing.version || 1) + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await docRef.set(payload, { merge: true });

    const updatedDoc = await docRef.get();
    const updatedLog = serializeFoodLog(updatedDoc);

    let dailySummaryStatus = "updated";
    try {
      if (existing.childProfileId && existing.date) {
        const summary = await recomputeDailySummary(
          existing.childProfileId,
          existing.date,
        );
        await notifyLinkedCaregiverForNutritionLimits(
          existing.childProfileId,
          existing.date,
          summary,
        );
        await recomputeGamification(userId, existing.date);
      }
      if (
        updatedLog.childProfileId &&
        updatedLog.date &&
        (updatedLog.childProfileId !== existing.childProfileId ||
          updatedLog.date !== existing.date)
      ) {
        const summary = await recomputeDailySummary(
          updatedLog.childProfileId,
          updatedLog.date,
        );
        await notifyLinkedCaregiverForNutritionLimits(
          updatedLog.childProfileId,
          updatedLog.date,
          summary,
        );
        await recomputeGamification(userId, updatedLog.date);
      }
    } catch (summaryError) {
      console.error("FOOD_LOG_SUMMARY ERROR:", summaryError.message);
      dailySummaryStatus = "queued_for_retry";
    }

    return res.status(200).json({
      success: true,
      foodLogId,
      mealLogId: foodLogId,
      dailySummaryStatus,
      log: updatedLog,
      message: "Food log updated successfully",
    });
  } catch (error) {
    console.error("FOOD_LOG_UPDATE ERROR:", error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to update food log",
    });
  }
});

router.post("/logs/delete", async (req, res) => {
  try {
    const { userId, profileUserId, childProfileId, foodLogId } = req.body;

    if (!userId || !foodLogId) {
      return res.status(400).json({
        success: false,
        error: "userId and foodLogId are required",
      });
    }

    const docRef = db.collection(FOOD_LOG_COLLECTION).doc(foodLogId);
    const doc = await docRef.get();

    if (!doc.exists) {
      return res.status(404).json({
        success: false,
        error: "Food log not found",
      });
    }

    const existing = doc.data() || {};
    const requestedProfileId = childProfileId || profileUserId;
    if (
      existing.userId !== userId &&
      (!requestedProfileId ||
        (existing.childProfileId !== requestedProfileId &&
          existing.userId !== requestedProfileId))
    ) {
      return res.status(403).json({
        success: false,
        error: "Food log does not belong to this user",
      });
    }

    await docRef.set(
      {
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (existing.childProfileId && existing.date) {
      await recomputeDailySummary(existing.childProfileId, existing.date);
      await recomputeGamification(userId, existing.date);
    }

    return res.status(200).json({
      success: true,
      foodLogId,
      message: "Food log archived successfully",
    });
  } catch (error) {
    console.error("FOOD_LOG_DELETE ERROR:", error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to delete food log",
    });
  }
});

module.exports = router;
