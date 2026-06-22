/**
 * mealPlanService.js
 * 
 * CKD-compliant meal planning using ingredient expansion and breakdown.
 * 
 * ARCHITECTURE:
 * - Templates use INDIVIDUAL INGREDIENTS ONLY: { protein: "chicken", carb: "rice", vegetable: "cabbage" }
 * - NO recipe names, NO meal combinations, NO prepared dishes
 * - Each ingredient searched separately on FatSecret
 * - Nutrition is SUMMED from individual ingredients
 * 
 * EXAMPLE:
 * Template: { protein: "chicken", carb: "rice", vegetable: "cabbage", target: 420 }
 * 
 * Process:
 * 1. Expand "chicken" → FatSecret returns ["Chicken Breast", "Grilled Chicken", "Fried Chicken", ...]
 * 2. Pick random: "Grilled Chicken"
 * 3. Search FatSecret: "Grilled Chicken" → gets nutrition data
 * 
 * 4. Expand "rice" → ["White Rice", "Brown Rice", "Jasmine Rice", ...]
 * 5. Pick random: "White Rice"
 * 6. Search FatSecret: "White Rice" → gets nutrition data
 * 
 * 7. Expand "cabbage" → ["Cabbage", "Raw Cabbage", "Cooked Cabbage", ...]
 * 8. Pick random: "Cooked Cabbage"
 * 9. Search FatSecret: "Cooked Cabbage" → gets nutrition data
 * 
 * 10. TOTAL nutrition: Grilled Chicken + White Rice + Cooked Cabbage
 * 11. Result: "Grilled Chicken with White Rice with Cooked Cabbage"
 *     Calories: 450, Protein: 35g, Sodium: 280mg, Potassium: 420mg, Phosphorus: 280mg
 * 
 * BENEFITS:
 * ✓ FatSecret returns reliable nutrition for individual foods
 * ✓ No recipe search (user-generated, inconsistent)
 * ✓ Ingredient caching eliminates repeated API calls
 * ✓ Random variant selection ensures variety (never same meal twice)
 * ✓ Individual totals are accurate
 * ✓ CKD validation at ingredient level (each ingredient checked against restrictions)
 */

const {
  buildMealTitle,
  generateMealPortions,
} = require("./portionControlService");

const { db } = require("../firebase/admin");
const fatSecretBridge = require("./fatSecretBridgeService");
const ingredientExpansionService = require("./ingredientExpansionService");
const {
  decryptHealthDocument,
  decryptHealthProfile,
} = require("../utils/encryption");

const RECIPE_CACHE_COLLECTION = "recipes";
const RECIPE_SEARCH_CACHE_COLLECTION = "recipeSearchCache";
const RECIPE_CACHE_TTL_MS = 1000 * 60 * 60 * 24 * 14;
const MAX_CACHED_RECIPE_RESULTS = 50;
const FOOD_DETAIL_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const FOOD_DETAIL_FAILURE_CACHE_TTL_MS = 5 * 60 * 1000;
const foodDetailCache = new Map();
const SIMPLE_FAT_FOOD_NAMES = [
  "oil",
  "olive oil",
  "canola oil",
  "vegetable oil",
  "corn oil",
  "sunflower oil",
  "butter",
  "unsalted butter",
  "margarine",
  "mayonnaise",
  "light mayonnaise",
];

const MEAL_PLAN_DEBUG_LOGS = process.env.MEAL_PLAN_DEBUG_LOGS !== "false";

function mealPlanDebug(event, payload = {}) {
  if (!MEAL_PLAN_DEBUG_LOGS) return;
  const seen = new WeakSet();
  const json = JSON.stringify(payload, (key, value) => {
    if (key === "raw" || key === "raw_serving") return undefined;
    if (value instanceof Error) {
      return { name: value.name, message: value.message, stack: value.stack };
    }
    if (value && typeof value === "object") {
      if (seen.has(value)) return "[Circular]";
      seen.add(value);
    }
    return value;
  }, 2);
  console.log(`[MEAL_PLAN_DEBUG] ${event}\n${json}`);
}

function mealPlanFoodDiagnostic(food = {}) {
  return {
    foodId: food.foodId,
    name: food.name,
    servingId: food.servingId,
    servingDescription: food.servingDescription,
    calories: food.calories,
    protein: food.protein,
    carbohydrate: food.carbohydrate,
    fat: food.fat,
    sodium: food.sodium,
    potassium: food.potassium,
    phosphorus: food.phosphorus,
    missingNutrients: food.missingNutrients,
    estimatedNutrients: food.estimatedNutrients,
    nutrientSources: food.nutrientSources,
    needsManualReview: food.needsManualReview,
  };
}

function ingredientVariants() {
  return require("./ingredientVariantService");
}

const CKD_INGREDIENT_GUIDE = {
  // Food pools combine the existing choices with foods explicitly listed in
  // the Philippine CKD nutrition manual. Profile restrictions are applied
  // before any of these foods can become a meal component.
  proteins: [
    "beans",
    "cheese",
    "chicken",
    "chicken breast",
    "chicken tenderloin",
    "egg",
    "egg white",
    "fish",
    "lean beef",
    "lean beef lomo",
    "lean beef sirloin",
    "milkfish",
    "salmon",
    "seafood",
    "shrimp",
    "tilapia",
    "tofu",
    "tuna",
    "turkey",
  ],
  carbs: [
    "barley",
    "bread",
    "cassava",
    "cereals",
    "corn",
    "couscous",
    "crackers",
    "noodles",
    "oatmeal",
    "pandesal",
    "pasta",
    "potato",
    "rice",
    "root crops",
    "rolled oats",
    "unsweetened suman",
    "white bread",
    "whole wheat bread",
    "wild rice",
  ],
  vegetables: [
    "ampalaya",
    "asparagus",
    "bamboo shoots",
    "beets",
    "bell pepper",
    "broccoli",
    "cabbage",
    "carrot",
    "cauliflower",
    "celery",
    "corn",
    "chili pepper",
    "chinese cabbage",
    "cucumber",
    "eggplant",
    "green beans",
    "green peas",
    "lettuce",
    "mushroom",
    "okra",
    "onion",
    "pumpkin",
    "radish",
    "raw spinach",
    "spinach",
    "squash",
    "watercress",
    "zucchini",
  ],
  fruits: [
    "apple",
    "apricot",
    "avocado",
    "banana",
    "banana saba",
    "berries",
    "blueberries",
    "calamansi",
    "chico",
    "grapes",
    "mango",
    "melon",
    "orange",
    "pear",
    "peach",
    "pineapple",
    "plum",
    "raspberries",
    "star apple",
    "strawberries",
    "watermelon",
  ],
  fats: [
    "oil",
    "olive oil",
    "canola oil",
    "vegetable oil",
    "corn oil",
    "sunflower oil",
    "butter",
    "unsalted butter",
    "margarine",
    "mayonnaise",
    "light mayonnaise",
  ],
  snacks: [
    "banana saba",
    "unsweetened suman",
    "crackers",
    "noodles",
    "pasta",
  ],
  beverages: ["water", "coffee", "tea", "milk", "fresh juice"],
  // Low potassium - safe for all CKD stages
  lowPotassium: [
    "apple",
    "apricot",
    "asparagus",
    "bamboo shoots",
    "bell pepper",
    "berries",
    "blueberries",
    "broccoli",
    "cabbage",
    "carrot",
    "cauliflower",
    "celery",
    "corn",
    "chinese cabbage",
    "cucumber",
    "daikon radish",
    "eggplant",
    "garlic",
    "grapes",
    "green beans",
    "green peas",
    "kale",
    "lemon",
    "lettuce",
    "lime",
    "mushroom",
    "okra",
    "onion",
    "pear",
    "peach",
    "plum",
    "radish",
    "raspberries",
    "raw spinach",
    "rice",
    "brown rice",
    "white rice",
    "jasmine rice",
    "basmati rice",
    "strawberries",
    "squash",
    "watercress",
    "zucchini",
  ],
  // High potassium - RESTRICT in CKD
  highPotassium: [
    "baked potato",
    "bamboo shoots",
    "banana",
    "banana saba",
    "plantain",
    "bitter melon",
    "bok choy",
    "cantaloupe",
    "dragon fruit",
    "guava",
    "honeydew melon",
    "kiwi",
    "mango",
    "melon",
    "mandarin orange",
    "orange",
    "papaya",
    "potato chips",
    "prunes",
    "raisins",
    "spinach",
    "sweet corn",
    "sweet potato",
    "tangerine",
    "tomato",
    "watermelon",
    "yam",
  ],
  mediumPotassium: [
    "asparagus",
    "avocado",
    "beets",
    "celery",
    "chili pepper",
    "okra",
    "potato",
    "pumpkin",
    "tomato",
    "tomato paste",
    "tomato puree",
    "tomato sauce",
  ],
  // Lower phosphorus - preferred proteins
  lowerPhosphorus: [
    "chicken",
    "chicken breast",
    "chicken thigh",
    "chicken tenderloin",
    "cod",
    "crab",
    "egg white",
    "fish",
    "flounder",
    "haddock",
    "halibut",
    "lobster",
    "mahi mahi",
    "milkfish",
    "mussels",
    "oysters",
    "pollock",
    "scallops",
    "sea bass",
    "shrimp",
    "snappers",
    "tilapia",
    "tofu",
    "tuna",
    "turkey",
    "salmon",
  ],
  // High phosphorus - LIMIT or AVOID in CKD
  highPhosphorus: [
    "almonds",
    "black beans",
    "beans",
    "cashews",
    "cheddar cheese",
    "cheese",
    "chicken thigh",
    "chickpeas",
    "cottage cheese",
    "kidney beans",
    "lentils",
    "lima beans",
    "mozzarella cheese",
    "navy beans",
    "nuts",
    "parmesan cheese",
    "peanut butter",
    "peanuts",
    "pinto beans",
    "pistachios",
    "pork loin",
    "pork tenderloin",
    "soybeans",
    "swiss cheese",
    "walnuts",
  ],
  // High sodium - AVOID or MINIMIZE
  highSodium: [
    "anchovies",
    "canned foods",
    "processed cheese",
    "processed meats",
    "processed food",
    "sauces",
    "condiments",
    "sardines",
  ],
  // Base allowed - safe generic ingredients for meal building
  baseAllowed: [
    // Proteins (lower phosphorus)
    "chicken",
    "chicken breast",
    "chicken tenderloin",
    "cod",
    "egg",
    "egg white",
    "fish",
    "halibut",
    "lean beef",
    "milkfish",
    "salmon",
    "sea bass",
    "shrimp",
    "snappers",
    "tilapia",
    "tofu",
    "tuna",
    "turkey",
    // Grains & Starches
    "barley",
    "basmati rice",
    "bread",
    "cassava",
    "corn",
    "cereals",
    "crackers",
    "couscous",
    "jasmine rice",
    "noodles",
    "oatmeal",
    "pandesal",
    "pasta",
    "root crops",
    "rice",
    "rolled oats",
    "steel cut oats",
    "white bread",
    "whole wheat bread",
    "wild rice",
    "unsweetened suman",
    // Vegetables (low potassium)
    "asparagus",
    "ampalaya",
    "bamboo shoots",
    "bell pepper",
    "broccoli",
    "cabbage",
    "carrot",
    "cauliflower",
    "celery",
    "chili pepper",
    "chinese cabbage",
    "cucumber",
    "daikon radish",
    "eggplant",
    "garlic",
    "green beans",
    "green peas",
    "lettuce",
    "mushroom",
    "okra",
    "onion",
    "pumpkin",
    "radish",
    "watercress",
    "squash",
    "zucchini",
    // Fruits (low potassium)
    "apple",
    "apricot",
    "berries",
    "blueberries",
    "grapes",
    "lemon",
    "lime",
    "pear",
    "peach",
    "pineapple",
    "plum",
    "raspberries",
    "strawberries",
    "star apple",
    "chico",
    // Oils & Fats
    "butter",
    "canola oil",
    "corn oil",
    "margarine",
    "mayonnaise",
    "light mayonnaise",
    "olive oil",
    "sunflower oil",
    "vegetable oil",
    "oil",
    "unsalted butter",
    // Low-fat Dairy (limit portion)
    "low fat milk",
    "skim milk",
    "yogurt",
  ],
  kidneyStoneHighPurine: [
    "alcohol",
    "nuts",
    "red meat",
    "organ meat",
    "shellfish",
    "fish sauce",
    "small fish",
  ],
  kidneyStoneHighOxalate: [
    "spinach",
    "potato",
    "okra",
    "nuts",
    "cashew",
    "seeds",
    "grains",
    "legumes",
    "tea",
  ],
  kidneyStoneCitrusRecommended: ["calamansi", "lemon"],
};

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

function stableCacheKey(value) {
  return hashString(normalizeTextToken(value)).toString(36);
}

function seededPick(items, seed, offset = 0) {
  if (!Array.isArray(items) || items.length === 0) return null;
  return items[(seed + offset) % items.length];
}

function numberOrNull(value) {
  if (value === null || value === undefined || value === "") return null;
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

function isDialysisStatus(value) {
  const normalized = normalizeTextToken(value);
  if (
    !normalized ||
    normalized.includes("not on dialysis") ||
    normalized.includes("no dialysis") ||
    normalized.includes("pre-dialysis") ||
    normalized.includes("pre dialysis")
  ) return false;
  return normalized.includes("dialysis") || normalized === "rrt" || normalized === "5d";
}

function isAffirmative(value) {
  if (value === true || value === 1) return true;
  return ["yes", "true", "1", "enabled", "positive"].includes(normalizeTextToken(value));
}

function normalizedLabStatus(value, numericValue, highThreshold) {
  const normalized = normalizeTextToken(value);
  if (["high", "danger", "caution", "elevated"].some((item) => normalized.includes(item))) {
    return "High";
  }
  if (normalized.includes("low")) return "Low";
  if (["normal", "safe", "within range"].some((item) => normalized.includes(item))) {
    return "Normal";
  }
  return labStatus(numericValue, highThreshold);
}

function potassiumControlLevel(value, numericValue) {
  const potassium = numberOrNull(numericValue);
  if (potassium !== null) {
    if (potassium > 6.0) return "Danger";
    if (potassium >= 5.1) return "Caution";
    return "Safe";
  }
  const normalized = normalizeTextToken(value);
  if (normalized.includes("danger")) return "Danger";
  if (["caution", "high", "elevated"].some((item) => normalized.includes(item))) {
    return "Caution";
  }
  if (["safe", "normal", "within range"].some((item) => normalized.includes(item))) {
    return "Safe";
  }
  return "Unknown";
}

function glycemicControlLevel({ glucose, hba1c, hasDiabetes }) {
  if ((hba1c !== null && hba1c >= 9) || (glucose !== null && glucose >= 180)) {
    return "High";
  }
  if (
    isAffirmative(hasDiabetes) ||
    (hba1c !== null && hba1c >= 6.5) ||
    (glucose !== null && glucose > 126)
  ) {
    return "Elevated";
  }
  return "Normal";
}

function glucoseInMgDl(value, unit) {
  const glucose = numberOrNull(value);
  if (glucose === null) return null;
  const normalizedUnit = normalizeTextToken(unit);
  return normalizedUnit.includes("mmol")
    ? Number((glucose * 18.0182).toFixed(1))
    : glucose;
}

function proteinPrescription({
  weightKg,
  dialysisStatus,
  ckdType,
  prescribedProtein,
  ageYears,
}) {
  const prescribed = numberOrNull(prescribedProtein);
  if (prescribed !== null && prescribed > 0) {
    return { gramsPerDay: prescribed, factor: null, source: "clinician_target" };
  }

  const weight = numberOrNull(weightKg);
  if (weight === null || weight <= 0) {
    return { gramsPerDay: null, factor: null, source: "missing_weight" };
  }

  const dialysis = isDialysisStatus(dialysisStatus);
  const age = numberOrNull(ageYears);
  if (!dialysis && age !== null && age >= 13 && age <= 14) {
    return {
      gramsPerDay: Number((weight * 0.85).toFixed(1)),
      minGramsPerDay: Number((weight * 0.8).toFixed(1)),
      maxGramsPerDay: Number((weight * 0.9).toFixed(1)),
      factor: 0.85,
      factorRange: [0.8, 0.9],
      source: "pediatric_sdi_age_13_14",
    };
  }
  const type = normalizeTextToken(ckdType);
  const status = normalizeTextToken(dialysisStatus);
  const preDialysis =
    type.includes("pre") ||
    status.includes("pre-dialysis") ||
    status.includes("pre dialysis") ||
    (!dialysis && type.includes("ckd") && !type.includes("stone"));
  const factor = dialysis ? 1.2 : preDialysis ? 0.7 : 0.8;
  return {
    gramsPerDay: Number((weight * factor).toFixed(1)),
    factor,
    source: dialysis
      ? "manual_dialysis_formula"
      : preDialysis
        ? "manual_predialysis_fallback"
        : "conservative_application_fallback",
  };
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
    age: numberOrNull(
      profileOwner?.ageYears ??
        profileOwner?.age_years ??
        profileOwner?.age ??
        medicalProfile?.age,
    ),
    sex: profileOwner?.sex ?? profileOwner?.gender ?? medicalProfile?.sex ?? null,
    ckd_stage:
      medicalProfile?.ckdStage ||
      medicalProfile?.ckd_stage ||
      medicalProfile?.stage ||
      targets?.ckd_stage ||
      "unknown",
    dialysis_status:
      medicalProfile?.dialysisStatus ||
      medicalProfile?.dialysis_status ||
      targets?.dialysis_status ||
      (medicalProfile?.onDialysis === true ? "on_dialysis" : "unknown"),
    ckd_type:
      medicalProfile?.ckdType ||
      medicalProfile?.ckd_type ||
      medicalProfile?.kidneyDiseaseType ||
      medicalProfile?.kidney_disease_type ||
      "unknown",
    has_diabetes:
      medicalProfile?.hasDiabetes ??
      medicalProfile?.has_diabetes ??
      medicalProfile?.diabetes ??
      false,
    diet_pattern:
      medicalProfile?.dietPattern ||
      medicalProfile?.diet_pattern ||
      "unknown",
    physical_activity_level:
      medicalProfile?.physicalActivityLevel ||
      medicalProfile?.physical_activity_level ||
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
          targets.maxSodiumMg ??
          targets.sodium_target_mg,
      ),
      potassium: numberOrNull(
        targets.potassium ??
          targets.potassiumLimitMg ??
          targets.potassium_limit_mg ??
          targets.maxPotassiumMg ??
          targets.potassium_target_mg,
      ),
      phosphorus: numberOrNull(
        targets.phosphorus ??
          targets.phosphorusLimitMg ??
          targets.phosphorus_limit_mg ??
          targets.phosphorus_target_mg ??
          targets.phosphate_target_mg,
      ),
      protein_min: numberOrNull(
        targets.proteinMin ??
          targets.protein_min ??
          targets.minProteinG ??
          targets.protein_target_min_g,
      ),
      protein_max: numberOrNull(
        targets.proteinMax ??
          targets.protein_max ??
          targets.maxProteinG ??
          targets.protein_target_g,
      ),
      calories: numberOrNull(
        targets.calories ??
          targets.calories_max ??
          targets.calorieTarget ??
          targets.energy_target_kcal,
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

function pediatricBmiCategory(percentile, sds) {
  const parsedPercentile = numberOrNull(percentile);
  if (parsedPercentile !== null) {
    if (parsedPercentile < 5) return "Below healthy range for age";
    if (parsedPercentile < 85) return "Healthy range for age";
    if (parsedPercentile < 95) return "Elevated BMI-for-age";
    return "High BMI-for-age";
  }
  const parsedSds = numberOrNull(sds);
  if (parsedSds !== null) {
    if (parsedSds < -2) return "Below healthy range for age";
    if (parsedSds < 1) return "Healthy range for age";
    if (parsedSds < 2) return "Elevated BMI-for-age";
    return "High BMI-for-age";
  }
  return "Growth assessment not yet available";
}

function provisionalPediatricEnergyTarget({ ageYears, sex, weightKg, heightCm, activityLevel }) {
  const age = numberOrNull(ageYears);
  const weight = numberOrNull(weightKg);
  const height = numberOrNull(heightCm);
  if (age === null || weight === null || height === null || height <= 0) return null;
  const normalizedSex = normalizeTextToken(sex);
  const female = sex === 2 || normalizedSex === "2" || normalizedSex === "female";
  const male = sex === 1 || normalizedSex === "1" || normalizedSex === "male";
  if (!female && !male) return null;
  const activity = normalizeTextToken(activityLevel);
  const pa = female
    ? activity.includes("very") ? 1.56 : activity.includes("moderate") || activity.includes("active") ? 1.31 : activity.includes("light") ? 1.16 : 1
    : activity.includes("very") ? 1.42 : activity.includes("moderate") || activity.includes("active") ? 1.26 : activity.includes("light") ? 1.13 : 1;
  const heightMeters = height / 100;
  const estimate = female
    ? 135.3 - 30.8 * age + pa * (10 * weight + 934 * heightMeters) + 25
    : 88.5 - 61.9 * age + pa * (26.7 * weight + 903 * heightMeters) + 25;
  return Math.max(1, Math.round(estimate));
}

function containsAny(text, words = []) {
  const normalized = normalizeTextToken(text);
  return words.some((word) => {
    const escaped = String(word).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`(^|[^a-z])${escaped}(?=[^a-z]|$)`, "i").test(normalized);
  });
}

function addUnique(set, items = []) {
  items.forEach((item) => {
    const normalized = normalizeTextToken(item);
    if (normalized) set.add(normalized);
  });
}

function ingredientTokensFromText(value) {
  const text = normalizeTextToken(value);
  if (!text) return [];
  const knownIngredients = new Set([
    ...CKD_INGREDIENT_GUIDE.proteins,
    ...CKD_INGREDIENT_GUIDE.carbs,
    ...CKD_INGREDIENT_GUIDE.vegetables,
    ...CKD_INGREDIENT_GUIDE.fruits,
    ...CKD_INGREDIENT_GUIDE.fats,
    ...CKD_INGREDIENT_GUIDE.snacks,
    ...CKD_INGREDIENT_GUIDE.beverages,
    ...CKD_INGREDIENT_GUIDE.lowPotassium,
    ...CKD_INGREDIENT_GUIDE.mediumPotassium,
    ...CKD_INGREDIENT_GUIDE.highPotassium,
    ...CKD_INGREDIENT_GUIDE.lowerPhosphorus,
    ...CKD_INGREDIENT_GUIDE.highPhosphorus,
    ...CKD_INGREDIENT_GUIDE.highSodium,
    ...CKD_INGREDIENT_GUIDE.baseAllowed,
    "garlic",
    "ginger",
    "lemon",
    "pasta",
    "rice",
    "toast",
    "oatmeal",
  ]);
  return [...knownIngredients].filter((ingredient) => containsAny(text, [ingredient]));
}

function buildIngredientRules(profile = {}, childContext = {}) {
  const allowed = new Set(CKD_INGREDIENT_GUIDE.baseAllowed.map(normalizeTextToken));
  const blocked = new Set(CKD_INGREDIENT_GUIDE.highSodium.map(normalizeTextToken));

  addUnique(allowed, CKD_INGREDIENT_GUIDE.lowPotassium);
  addUnique(allowed, CKD_INGREDIENT_GUIDE.lowerPhosphorus);
  for (const category of ["proteins", "carbs", "vegetables", "fruits", "fats", "snacks"]) {
    addUnique(allowed, CKD_INGREDIENT_GUIDE[category]);
  }

  if (profile.potassiumControlLevel === "Danger") {
    addUnique(blocked, CKD_INGREDIENT_GUIDE.highPotassium);
  }
  if (["Caution", "Danger"].includes(profile.potassiumControlLevel)) {
    addUnique(blocked, ["potassium additive", "potassium chloride"]);
  }
  if (profile.phosphorusStatus === "High") {
    addUnique(blocked, CKD_INGREDIENT_GUIDE.highPhosphorus);
  }
  if (profile.diabetesRisk) {
    addUnique(blocked, ["cake", "candy", "dessert", "soda", "sweetened"]);
  }
  addUnique(blocked, childContext.allergies || []);

  blocked.forEach((ingredient) => allowed.delete(ingredient));

  return {
    allowedIngredients: [...allowed].sort(),
    blockedIngredients: [...blocked].sort(),
  };
}

function ingredientStatus(ingredient, rules = {}) {
  const normalized = normalizeTextToken(ingredient);
  if (!normalized) return "unknown";
  if (containsAny(normalized, rules.blockedIngredients || [])) return "blocked";
  if (containsAny(normalized, rules.allowedIngredients || [])) return "allowed";
  return "unknown";
}

function extractRecipeIngredients(recipe = {}) {
  const rawIngredients = recipe.ingredients || recipe.ingredient_list || recipe.ingredientList;
  const values = [];
  if (Array.isArray(rawIngredients)) {
    rawIngredients.forEach((item) => {
      if (typeof item === "string") values.push(item);
      else if (item && typeof item === "object") {
        values.push(item.ingredient || item.food_name || item.name || item.description || "");
      }
    });
  } else if (typeof rawIngredients === "string") {
    values.push(...rawIngredients.split(/[,;\n]+/));
  }

  values.push(recipe.name, recipe.title, recipe.description);
  const ingredients = new Set();
  values.forEach((value) => {
    ingredientTokensFromText(value).forEach((ingredient) => ingredients.add(ingredient));
  });
  return [...ingredients];
}

function validateRecipeCandidate(recipe = {}, rules = {}, restrictions = {}) {
  const ingredients = extractRecipeIngredients(recipe);
  const blocked = ingredients.filter((ingredient) => ingredientStatus(ingredient, rules) === "blocked");
  const allowed = ingredients.filter((ingredient) => ingredientStatus(ingredient, rules) === "allowed");
  const unknown = ingredients.filter((ingredient) => ingredientStatus(ingredient, rules) === "unknown");
  const text = [
    recipe.name,
    recipe.description,
    Array.isArray(recipe.ingredients) ? recipe.ingredients.join(" ") : "",
  ].join(" ");
  const blockedByRestriction = (restrictions.avoid || []).filter((item) =>
    containsAny(text, [item]),
  );
  const isAllowed = blocked.length === 0 && blockedByRestriction.length === 0;

  return {
    isAllowed,
    allowedIngredients: allowed,
    blockedIngredients: [...new Set([...blocked, ...blockedByRestriction.map(normalizeTextToken)])],
    unknownIngredients: unknown,
    reason: isAllowed
      ? "Recipe ingredients passed CKD ingredient validation."
      : "Recipe contains blocked or limited ingredients.",
  };
}

function normalizeCachedRecipe(recipe = {}, query = "") {
  const ingredients = extractRecipeIngredients(recipe);
  return cleanObject({
    recipeId: recipe.recipeId || recipe.recipe_id || recipe.food_id || recipe.id,
    name: 
      recipe.name || 
      recipe.recipe_name || 
      recipe.food_name ||  // Python service uses food_name
      recipe.title,
    description: recipe.description || recipe.recipe_description,
    servingSize: 
      recipe.servingSize || 
      recipe.serving_size || 
      recipe.serving_description ||  // Python service uses serving_description
      "1 serving",
    servings: recipe.servings,
    imageUrl: recipe.imageUrl || recipe.recipe_image || recipe.image_url,
    ingredients,
    calories: numberOrNull(recipe.calories),
    protein: numberOrNull(recipe.protein),
    carbohydrate: numberOrNull(recipe.carbohydrate ?? recipe.carbohydrates),
    fat: numberOrNull(recipe.fat),
    sodium: numberOrNull(recipe.sodium),
    potassium: numberOrNull(recipe.potassium),
    phosphorus: numberOrNull(recipe.phosphorus),
    source: recipe.source || "fatsecret_recipe",
    sourceQuery: query,
    cachedAt: new Date().toISOString(),
  });
}

function cacheIsFresh(value) {
  const cachedAt = timestampMillis(value?.cachedAt || value?.updatedAt);
  return cachedAt > 0 && Date.now() - cachedAt < RECIPE_CACHE_TTL_MS;
}

/**
 * Extract base ingredient from a search query
 * "chicken rice low sodium recipe" → "chicken"
 * "fish stew recipe" → "fish"
 */
function extractBaseSearchTerm(query) {
  if (!query || typeof query !== "string") return null;
  
  // Remove common query modifiers
  const cleaned = query
    .toLowerCase()
    .replace(/\b(recipe|healthy|low sodium|low potassium|low phosphorus|diabetic|high protein)\b/g, "")
    .trim();
  
  // Get first meaningful word (usually the main ingredient)
  const words = cleaned.split(/\s+/).filter(w => w.length > 2);
  return words.length > 0 ? words[0] : null;
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
  const currentWeightKg = numberOrNull(
    firstPresent(anthropometrics, ["weight_kg", "weightKg", "weight"]) ||
      firstPresent(medicalProfile, ["weight_kg", "weightKg", "weight"]),
  );
  const bmi = numberOrNull(
    firstPresent(anthropometrics, ["bmi", "BMI"]) ||
      firstPresent(medicalProfile, ["bmi", "BMI"]),
  );
  const heightCm = numberOrNull(
    firstPresent(anthropometrics, ["height_cm", "heightCm", "height"]) ||
      firstPresent(medicalProfile, ["height_cm", "heightCm", "height"]),
  );
  const dialysisStatus = childContext.dialysis_status || "unknown";
  const ageYears = numberOrNull(
    childContext.age ?? firstPresent(medicalProfile, ["ageYears", "age_years", "age"]),
  );
  const pediatricMode = ageYears !== null && ageYears < 18;
  const bmiForAgePercentile = numberOrNull(
    firstPresent(anthropometrics, ["bmiForAgePercentile", "bmi_for_age_percentile"]),
  );
  const bmiForAgeSds = numberOrNull(
    firstPresent(anthropometrics, ["bmiForAgeSds", "bmi_for_age_sds", "bmiForAgeZScore"]),
  );
  const growthTrend = firstPresent(anthropometrics, ["growthTrend", "growth_trend"]);
  const growthAssessmentAvailable =
    bmiForAgePercentile !== null || bmiForAgeSds !== null || Boolean(growthTrend);
  const prescribedCalories = numberOrNull(childContext.targets?.calories);
  const provisionalPediatricCalories = pediatricMode
    ? provisionalPediatricEnergyTarget({
        ageYears,
        sex: childContext.sex,
        weightKg: currentWeightKg,
        heightCm,
        activityLevel: childContext.physical_activity_level,
      })
    : null;
  const dryWeightKg = numberOrNull(
    firstPresent(anthropometrics, ["dry_weight_kg", "dryWeightKg", "dryWeight"]),
  );
  const weightKg = isDialysisStatus(dialysisStatus) && dryWeightKg !== null
    ? dryWeightKg
    : currentWeightKg;
  const protein = proteinPrescription({
    weightKg,
    currentWeightKg,
    dryWeightKg,
    dialysisStatus,
    ckdType: childContext.ckd_type,
    prescribedProtein: childContext.targets?.protein_max,
    ageYears,
  });
  const glucoseUnit = firstPresent(labs, ["glucose_unit", "glucoseUnit"]) || "mg/dL";
  const glucose = glucoseInMgDl(
    firstPresent(labs, ["glucose", "fastingGlucose"]),
    glucoseUnit,
  );
  const hba1c = numberOrNull(firstPresent(labs, ["HbA1c", "hba1c", "hemoglobinA1c"]));
  const serumAlbumin = numberOrNull(
    firstPresent(labs, ["serum_albumin", "serumAlbumin", "albumin"]),
  );
  const totalProtein = numberOrNull(
    firstPresent(labs, ["total_protein", "totalProtein"]),
  );
  const potassiumValue = numberOrNull(firstPresent(labs, ["potassium", "K"]));
  const potassiumLevel = potassiumControlLevel(
    firstPresent(labs, ["potassium_status", "potassiumStatus"]),
    potassiumValue,
  );
  const glycemicLevel = glycemicControlLevel({
    glucose,
    hba1c,
    hasDiabetes: childContext.has_diabetes,
  });
  const appetite = normalizeTextToken(
    firstPresent(medicalProfile, ["appetite", "appetiteStatus", "appetite_status"]),
  );
  const oralIntakePercent = numberOrNull(
    firstPresent(medicalProfile, ["oralIntakePercent", "oral_intake_percent"]),
  );
  const weightChangeOneMonthPercent = numberOrNull(
    firstPresent(anthropometrics, ["weightChangeOneMonthPercent", "weight_change_1_month_percent"]),
  );
  const weightChangeSixMonthsPercent = numberOrNull(
    firstPresent(anthropometrics, ["weightChangeSixMonthsPercent", "weight_change_6_months_percent"]),
  );
  const poorAppetite = ["poor", "very poor"].includes(appetite);
  const weightLossRisk =
    (weightChangeOneMonthPercent !== null && weightChangeOneMonthPercent <= -5) ||
    (weightChangeSixMonthsPercent !== null && weightChangeSixMonthsPercent <= -10);
  const riskMalnutrition =
    (serumAlbumin !== null && serumAlbumin < 3.5) ||
    (totalProtein !== null && totalProtein < 6.0) ||
    poorAppetite ||
    (oralIntakePercent !== null && oralIntakePercent < 75) ||
    weightLossRisk;

  return {
    stage,
    egfr,
    serumPotassium: potassiumValue,
    potassiumControlLevel: potassiumLevel,
    potassiumStatus:
      potassiumLevel === "Safe"
        ? "Normal"
        : potassiumLevel === "Unknown"
          ? "Unknown"
          : "High",
    phosphorusStatus: normalizedLabStatus(
      firstPresent(labs, ["phosphorus_status", "phosphorusStatus"]),
      firstPresent(labs, ["phosphorus", "phosphate"]),
      4.5,
    ),
    sodiumStatus: normalizedLabStatus(
      firstPresent(labs, ["sodium_status", "sodiumStatus"]),
      firstPresent(labs, ["sodium", "Na"]),
      145,
    ),
    glucose,
    glucoseUnit: "mg/dL",
    hba1c,
    glycemicControlLevel: glycemicLevel,
    carbohydratePortionScale:
      glycemicLevel === "High" ? 0.5 : glycemicLevel === "Elevated" ? 0.75 : 1,
    fruitPortionScale:
      glycemicLevel === "High" ? 0.5 : glycemicLevel === "Elevated" ? 0.75 : 1,
    snackFrequency: glycemicLevel === "High" ? 1 : 2,
    diabetesRisk: glycemicLevel !== "Normal",
    ageYears,
    sex: childContext.sex || null,
    pediatricMode,
    planMode: pediatricMode ? "growth-aware" : "adult",
    requireGrowthAssessment: false,
    bmiForAgePercentile,
    bmiForAgeSds,
    growthTrend,
    growthAssessmentComplete: !pediatricMode || growthAssessmentAvailable,
    growthAssessmentStatus: pediatricMode && !growthAssessmentAvailable
      ? "Not yet available"
      : "Available",
    growthAssessmentSource: "historical_anthropometrics",
    growthInformation: pediatricMode && !growthAssessmentAvailable
      ? [
          "Growth assessment is not yet available.",
          "Additional height and weight measurements are needed to evaluate growth trends.",
          "Meal planning remains available using the current profile and laboratory results.",
        ]
      : [],
    warnings: [],
    mealPlanningAvailable: true,
    bmiCategory: pediatricMode
      ? pediatricBmiCategory(bmiForAgePercentile, bmiForAgeSds)
      : bmiCategory(bmi),
    proteinTarget: protein.gramsPerDay,
    proteinTargetMin: protein.minGramsPerDay || protein.gramsPerDay,
    proteinTargetMax: protein.maxGramsPerDay || protein.gramsPerDay,
    proteinFactor: protein.factor,
    proteinTargetSource: protein.source,
    calorieTarget: prescribedCalories || provisionalPediatricCalories || (pediatricMode ? null : 1800),
    calorieTargetSource: prescribedCalories
      ? "profile_or_clinician_target"
      : provisionalPediatricCalories
        ? "provisional_pediatric_eer"
        : pediatricMode
          ? "pediatric_estimate_unavailable"
          : "adult_application_fallback",
    poorAppetite,
    oralIntakePercent,
    weightChangeOneMonthPercent,
    weightChangeSixMonthsPercent,
    weightLossRisk,
    riskMalnutrition,
    weightKg,
    currentWeightKg,
    heightCm,
    bmi,
    ckdType: childContext.ckd_type,
    dialysisStatus,
    diabetes: isAffirmative(childContext.has_diabetes),
    fluidRestrictionStatus: childContext.fluid_restriction_status,
    dailyFluidLimitMl: childContext.targets?.dailyFluidLimitMl || null,
  };
}

function buildFoodRestrictions(profile) {
  const avoid = new Set(["soy sauce", "fish sauce", "bagoong", "processed", "fast food"]);
  const prefer = new Set(["apple", "grapes", "cabbage", "cauliflower", "lettuce", "radish"]);

  if (profile.potassiumControlLevel === "Danger") {
    ["banana", "avocado", "orange", "melon", "potato", "sweet potato", "spinach", "tomato paste"].forEach((item) => avoid.add(item));
  }
  if (["Caution", "Danger"].includes(profile.potassiumControlLevel)) {
    ["apple", "berries", "grapes", "cabbage", "cauliflower"].forEach((item) => prefer.add(item));
  }
  if (profile.phosphorusStatus === "High") {
    ["nuts", "beans", "cola", "cheese", "organ meat"].forEach((item) => avoid.add(item));
  }
  if (profile.diabetesRisk) {
    ["dessert", "sweetened", "candy", "cake", "soda"].forEach((item) => avoid.add(item));
  }
  if (normalizeTextToken(profile.ckdType).includes("stone")) {
    CKD_INGREDIENT_GUIDE.kidneyStoneHighPurine.forEach((item) => avoid.add(item));
    CKD_INGREDIENT_GUIDE.kidneyStoneHighOxalate.forEach((item) => avoid.add(item));
    CKD_INGREDIENT_GUIDE.kidneyStoneCitrusRecommended.forEach((item) => prefer.add(item));
  }

  return {
    dailySodiumLimitMg: profile.sodiumLimitMg || 2000,
    dailyPotassiumLimitMg:
      ["Caution", "Danger"].includes(profile.potassiumControlLevel)
        ? profile.potassiumLimitMg || 3000
        : null,
    dailyPhosphorusLimitMg: profile.phosphorusLimitMg || 1000,
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

function ingredientsFromLog(log = {}) {
  const raw = log.raw && typeof log.raw === "object" ? log.raw : {};
  const values = [
    log.name,
    log.foodName,
    log.portion,
    raw.food_name,
    raw.foodName,
    raw.description,
    raw.ingredients,
    raw.ingredient_list,
    raw.ingredientList,
    ...(Array.isArray(raw.componentFoods)
      ? raw.componentFoods.map((food) => food?.component || food?.name || "")
      : []),
    ...(Array.isArray(raw.recognizedFoods)
      ? raw.recognizedFoods.map((food) => food?.name || food?.food_name || "")
      : []),
  ];
  const ingredients = new Set();
  values.filter(Boolean).forEach((value) => {
    ingredientTokensFromText(value).forEach((ingredient) => ingredients.add(ingredient));
  });
  return [...ingredients];
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
  const byIngredient = new Map();
  const relationCounts = new Map();
  const sodiumLimit = numberOrNull(restrictions.dailySodiumLimitMg) || 2000;
  const potassiumLimit = numberOrNull(restrictions.dailyPotassiumLimitMg);
  const phosphorusLimit = numberOrNull(restrictions.dailyPhosphorusLimitMg);

  for (const log of logs) {
    const name = String(log.name || log.foodName || "").trim();
    if (!name) continue;
    const key = normalizeTextToken(name);
    const nutrients = nutrientsFromLog(log);
    const logIngredients = ingredientsFromLog(log);
    logIngredients.forEach((ingredient) => {
      const existing = byIngredient.get(ingredient) || { ingredient, count: 0 };
      existing.count += 1;
      byIngredient.set(ingredient, existing);
    });
    for (let i = 0; i < logIngredients.length; i += 1) {
      for (let j = i + 1; j < logIngredients.length; j += 1) {
        const pair = [logIngredients[i], logIngredients[j]].sort();
        const relationKey = pair.join("::");
        relationCounts.set(relationKey, (relationCounts.get(relationKey) || 0) + 1);
      }
    }
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
    ingredientCounts: [...byIngredient.values()].sort((a, b) => b.count - a.count),
    ingredientRelations: [...relationCounts.entries()]
      .map(([key, count]) => {
        const [ingredientA, ingredientB] = key.split("::");
        return { ingredientA, ingredientB, count };
      })
      .sort((a, b) => b.count - a.count)
      .slice(0, 30),
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
  if (profile.riskMalnutrition) tags.push("nutrition support");
  return tags;
}

function perMealTargets(profile, restrictions, mealType) {
  const isSnack = mealType.includes("Snack");
  const proteinTarget = profile.proteinTarget && !isSnack
    ? Number((profile.proteinTarget / 3).toFixed(1))
    : null;
  return {
    calories: null,
    sodium: restrictions.dailySodiumLimitMg || 2000,
    potassium:
      profile.potassiumStatus === "High" ? restrictions.dailyPotassiumLimitMg || null : null,
    phosphorus:
      profile.phosphorusStatus === "High" ? restrictions.dailyPhosphorusLimitMg || null : null,
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
  if (targets.sodium && sodium > targets.sodium) {
    score -= Math.min(35, Math.ceil((sodium - targets.sodium) / 40));
  }
  if (targets.potassium && potassium > targets.potassium) score -= 24;
  if (targets.phosphorus && phosphorus > targets.phosphorus) score -= 24;
  if (profile.potassiumStatus === "High" && potassium > 500) score -= 20;
  if (profile.phosphorusStatus === "High" && phosphorus > 250) score -= 20;
  if (profile.diabetesRisk && containsAny(foodText, ["sweet", "sugar", "syrup", "dessert"])) score -= 20;
  if (targets.protein && protein > targets.protein * 1.4) score -= 10;
  if (knownNutrients >= 4) score += 10;
  if (knownNutrients <= 2) score -= 12;
  if (containsAny(foodText, restrictions.prefer)) score += 10;
  if (mealType.includes("Snack") && calories > 300) score -= 12;
  if (!mealType.includes("Snack") && calories < 120) score -= 8;
  if (targets.calories && Math.abs(calories - targets.calories) <= targets.calories * 0.3) {
    score += 8;
  }

  return score;
}

function historyWeightedIngredients(history = {}, ingredientRules = {}) {
  const blocked = ingredientRules.blockedIngredients || [];
  const fromHistory = (history.ingredientCounts || [])
    .filter((item) => !containsAny(item.ingredient, blocked))
    .map((item) => item.ingredient);
  const allowed = (ingredientRules.allowedIngredients || []).filter(
    (ingredient) => !containsAny(ingredient, blocked),
  );
  return [...new Set([...fromHistory, ...allowed])].slice(0, 18);
}

function relatedIngredientFor(baseIngredient, history = {}, ingredientRules = {}, fallbackOffset = 0) {
  const blocked = ingredientRules.blockedIngredients || [];
  const relation = (history.ingredientRelations || []).find((item) => {
    if (item.ingredientA !== baseIngredient && item.ingredientB !== baseIngredient) return false;
    const other =
      item.ingredientA === baseIngredient ? item.ingredientB : item.ingredientA;
    return !containsAny(other, blocked);
  });
  if (relation) {
    return relation.ingredientA === baseIngredient
      ? relation.ingredientB
      : relation.ingredientA;
  }
  const allowed = historyWeightedIngredients(history, ingredientRules).filter(
    (ingredient) => ingredient !== baseIngredient,
  );
  return allowed[fallbackOffset % Math.max(allowed.length, 1)] || null;
}

function recipeDrivenTemplates(mealType, history = {}, ingredientRules = {}) {
  const ingredients = historyWeightedIngredients(history, ingredientRules);
  const templates = [];
  ingredients.slice(0, 6).forEach((ingredient, index) => {
    const related = relatedIngredientFor(ingredient, history, ingredientRules, index);
    const components = related ? [ingredient, related] : [ingredient];
    const title = components
      .map((component) => component.replace(/\b\w/g, (char) => char.toUpperCase()))
      .join(" ");
    templates.push({
      name:
        mealType.includes("Snack") && components.length === 1
          ? `${title} Snack`
          : `${title} Recipe`,
      components,
      target: mealType.includes("Snack") ? 160 : 400,
      source: "constraint_recipe_template",
    });
  });
  return templates;
}

function guideFoodPool(category, ingredientRules = {}) {
  const blocked = ingredientRules.blockedIngredients || [];
  return [...new Set(CKD_INGREDIENT_GUIDE[category] || [])]
    .filter((ingredient) => !containsAny(ingredient, blocked));
}

function guideFoodTemplates(mealType, ingredientRules = {}) {
  const proteins = guideFoodPool("proteins", ingredientRules);
  const carbs = guideFoodPool("carbs", ingredientRules);
  const vegetables = guideFoodPool("vegetables", ingredientRules);
  const fruits = guideFoodPool("fruits", ingredientRules);
  const snacks = guideFoodPool("snacks", ingredientRules);
  const templates = [];

  if (mealType.includes("Snack")) {
    const snackCount = Math.max(fruits.length, vegetables.length, snacks.length);
    for (let index = 0; index < snackCount; index += 1) {
      if (index % 3 === 0 && fruits.length) {
        templates.push({ fruit: fruits[index % fruits.length] });
      } else if (index % 3 === 1 && snacks.length) {
        const snack = snacks[index % snacks.length];
        templates.push(CKD_INGREDIENT_GUIDE.fruits.includes(snack)
          ? { fruit: snack }
          : { carb: snack });
      } else if (vegetables.length) {
        templates.push({ vegetable: vegetables[index % vegetables.length] });
      }
    }
  } else if (proteins.length && carbs.length && vegetables.length) {
    const count = Math.max(proteins.length, carbs.length, vegetables.length, fruits.length);
    for (let index = 0; index < count; index += 1) {
      templates.push({
        protein: proteins[index % proteins.length],
        carb: carbs[(index * 3 + 1) % carbs.length],
        vegetable: vegetables[(index * 5 + 2) % vegetables.length],
        ...(mealType === "Breakfast" && fruits.length
          ? { fruit: fruits[(index * 7 + 3) % fruits.length] }
          : {}),
      });
    }
  }

  return templates.map((template) => ({
    ...template,
    target: mealType.includes("Snack") ? 150 : mealType === "Breakfast" ? 300 : 420,
    mealType,
    source: "psn_ckd_food_list_template",
  }));
}

function mealTemplateBank(profile, history = {}, ingredientRules = {}) {
  const bank = {
    Breakfast: [
      { protein: "egg", carb: "bread", fruit: "apple", target: 280, mealType: "Breakfast" },
      { protein: "chicken", carb: "rice", fruit: "berries", target: 300, mealType: "Breakfast" },
      { protein: "tofu", carb: "oatmeal", fruit: "pear", target: 290, mealType: "Breakfast" },
      { protein: "egg", carb: "pandesal", fruit: "grapes", target: 270, mealType: "Breakfast" },
      { protein: "fish", carb: "rice", fruit: "strawberries", target: 300, mealType: "Breakfast" },
      { protein: "turkey", carb: "noodles", fruit: "apple", target: 310, mealType: "Breakfast" },
      { protein: "egg", carb: "toast", fruit: "peach", target: 260, mealType: "Breakfast" },
      { protein: "tofu", carb: "bread", fruit: "berries", target: 280, mealType: "Breakfast" },
    ],
    "AM Snack": [
      { fruit: "apple", target: 150, mealType: "AM Snack" },
      { fruit: "grapes", target: 150, mealType: "AM Snack" },
      { fruit: "pear", target: 140, mealType: "AM Snack" },
      { fruit: "strawberries", target: 120, mealType: "AM Snack" },
      { fruit: "peach", target: 140, mealType: "AM Snack" },
      { vegetable: "cucumber", carb: "bread", target: 150, mealType: "AM Snack" },
      { vegetable: "carrot", carb: "crackers", target: 140, mealType: "AM Snack" },
      { vegetable: "bell pepper", target: 120, mealType: "AM Snack" },
    ],
    Lunch: [
      { protein: "chicken", carb: "rice", vegetable: "cabbage", target: 420, mealType: "Lunch" },
      { protein: "fish", carb: "pasta", vegetable: "asparagus", target: 420, mealType: "Lunch" },
      { protein: "turkey", carb: "barley", vegetable: "cauliflower", target: 420, mealType: "Lunch" },
      { protein: "beef", carb: "noodles", vegetable: "broccoli", target: 430, mealType: "Lunch" },
      { protein: "tilapia", carb: "corn", vegetable: "bell pepper", target: 410, mealType: "Lunch" },
      { protein: "tofu", carb: "rice", vegetable: "mushrooms", target: 410, mealType: "Lunch" },
      { protein: "seafood", carb: "noodles", vegetable: "cucumber", target: 420, mealType: "Lunch" },
      { protein: "chicken", carb: "couscous", vegetable: "eggplant", target: 410, mealType: "Lunch" },
      { protein: "fish", carb: "bread", vegetable: "tomato", target: 400, mealType: "Lunch" },
      { protein: "turkey", carb: "rice", vegetable: "chinese cabbage", target: 420, mealType: "Lunch" },
      { protein: "beef", carb: "pasta", vegetable: "bell pepper", target: 430, mealType: "Lunch" },
      { protein: "tilapia", carb: "barley", vegetable: "onion", target: 410, mealType: "Lunch" },
      { protein: "tofu", carb: "noodles", vegetable: "carrot", target: 410, mealType: "Lunch" },
      { protein: "seafood", carb: "couscous", vegetable: "okra", target: 410, mealType: "Lunch" },
    ],
    "PM Snack": [
      { fruit: "grapes", carb: "bread", target: 160, mealType: "PM Snack" },
      { fruit: "apple", carb: "crackers", target: 150, mealType: "PM Snack" },
      { vegetable: "cucumber", target: 100, mealType: "PM Snack" },
      { fruit: "berries", target: 120, mealType: "PM Snack" },
      { fruit: "pear", carb: "crackers", target: 150, mealType: "PM Snack" },
      { vegetable: "carrot", target: 130, mealType: "PM Snack" },
      { vegetable: "bell pepper", target: 120, mealType: "PM Snack" },
      { vegetable: "radish", target: 110, mealType: "PM Snack" },
      { fruit: "strawberries", carb: "bread", target: 150, mealType: "PM Snack" },
      { fruit: "peach", target: 140, mealType: "PM Snack" },
    ],
    Dinner: [
      { protein: "fish", carb: "rice", vegetable: "cauliflower", target: 420, mealType: "Dinner" },
      { protein: "chicken", carb: "pasta", vegetable: "cabbage", target: 430, mealType: "Dinner" },
      { protein: "turkey", carb: "couscous", vegetable: "broccoli", target: 420, mealType: "Dinner" },
      { protein: "beef", carb: "rice", vegetable: "mushrooms", target: 430, mealType: "Dinner" },
      { protein: "tilapia", carb: "barley", vegetable: "asparagus", target: 410, mealType: "Dinner" },
      { protein: "tofu", carb: "noodles", vegetable: "chinese cabbage", target: 410, mealType: "Dinner" },
      { protein: "seafood", carb: "rice", vegetable: "bell pepper", target: 420, mealType: "Dinner" },
      { protein: "chicken", carb: "corn", vegetable: "carrot", target: 410, mealType: "Dinner" },
      { protein: "beef", carb: "pasta", vegetable: "cucumber", target: 430, mealType: "Dinner" },
      { protein: "fish", carb: "couscous", vegetable: "okra", target: 400, mealType: "Dinner" },
      { protein: "turkey", carb: "noodles", vegetable: "mushrooms", target: 420, mealType: "Dinner" },
      { protein: "tilapia", carb: "rice", vegetable: "eggplant", target: 410, mealType: "Dinner" },
      { protein: "tofu", carb: "bread", vegetable: "lettuce", target: 380, mealType: "Dinner" },
      { protein: "beef", carb: "couscous", vegetable: "bamboo shoots", target: 420, mealType: "Dinner" },
      { protein: "chicken", carb: "pandesal", vegetable: "green peas", target: 400, mealType: "Dinner" },
      { protein: "seafood", carb: "rice", vegetable: "watercress", target: 410, mealType: "Dinner" },
    ],
  };

  Object.keys(bank).forEach((mealType) => {
    bank[mealType].push(...guideFoodTemplates(mealType, ingredientRules));
  });

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
    foods.slice(0, 3).forEach((food) => {
      bank[targetMealType].push({
        protein: food.name,
        target: Math.round(food.average?.calories || 250),
        portion: food.portion,
        source: "recent_food_log_template",
        mealType: targetMealType,
      });
    });
  });

  return bank;
}

function safeMealTemplates(mealType, profile, restrictions, history, ingredientRules) {
  const templates = mealTemplateBank(profile, history, ingredientRules)[mealType] || [];
  const safe = templates.filter((template) => {
    const text = [
      template.name,
      template.protein,
      template.carb,
      template.grain,
      template.vegetable,
      ...(template.components || []),
    ]
      .filter(Boolean)
      .join(" ");
    return (
      !containsAny(text, restrictions.avoid) &&
      !containsAny(text, ingredientRules?.blockedIngredients || [])
    );
  });
  return safe.length ? safe : templates;
}

function plannedMealFor(mealType, profile, restrictions, seed, mealIndex, history, ingredientRules) {
  const templates = safeMealTemplates(
    mealType,
    profile,
    restrictions,
    history,
    ingredientRules,
  );
  const selected = seededPick(templates, seed, mealIndex * 7) || templates[0];
  return {
    mealType,
    ...selected,
    source: "ckd_guide_rule_template",
  };
}

function portionTemplateCandidates(
  mealType,
  profile,
  restrictions,
  seed,
  mealIndex,
  history,
  ingredientRules,
  limit = 5,
) {
  const templates = safeMealTemplates(
    mealType,
    profile,
    restrictions,
    history,
    ingredientRules,
  );
  if (!templates.length) return [];
  const start = Math.abs(seed + mealIndex * 7) % templates.length;
  const fruitChoices = guideFoodPool("fruits", ingredientRules).length
    ? guideFoodPool("fruits", ingredientRules)
    : ["apple"];
  const vegetableChoices = guideFoodPool("vegetables", ingredientRules).length
    ? guideFoodPool("vegetables", ingredientRules)
    : ["cabbage"];
  const fatChoices = guideFoodPool("fats", ingredientRules).length
    ? guideFoodPool("fats", ingredientRules)
    : ["oil"];

  return Array.from({ length: Math.min(limit, templates.length) }, (_, offset) => {
    const template = templates[(start + offset) % templates.length];
    if (mealType.includes("Snack")) {
      return { mealType, ...template, source: template.source || "ckd_guide_rule_template" };
    }
    return {
      mealType,
      ...template,
      vegetable:
        template.vegetable || vegetableChoices[(start + offset) % vegetableChoices.length],
      fruit: template.fruit || fruitChoices[(start + offset) % fruitChoices.length],
      fat: template.fat || fatChoices[(start + offset) % fatChoices.length],
      source: template.source || "ckd_guide_rule_template",
    };
  });
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
  const queryKey = stableCacheKey(`${query}:${page}:${calorieTarget || "any"}`);
  const cacheRef = db.collection(RECIPE_SEARCH_CACHE_COLLECTION).doc(queryKey);
  try {
    const cacheSnap = await cacheRef.get();
    if (cacheSnap.exists) {
      const cached = cacheSnap.data() || {};
      if (cacheIsFresh(cached) && Array.isArray(cached.recipes)) {
        return {
          query,
          page,
          totalResults: cached.totalResults || cached.recipes.length,
          recipes: cached.recipes,
          source: "recipe_cache",
        };
      }
    }
  } catch (cacheError) {
    console.error("MEAL_PLAN_RECIPE_CACHE_READ_ERROR:", {
      query,
      error: cacheError.message,
    });
  }

  try {
    const result = await fatSecretBridge.searchRecipes(
      query,
      page,
      calorieTarget ? Math.round(calorieTarget * 1.1) : null,
    );
    const recipes = (result.recipes || [])
      .slice(0, MAX_CACHED_RECIPE_RESULTS)
      .map((recipe) => normalizeCachedRecipe(recipe, query));

    // Learn ingredient variants from recipe titles
    // Extract base ingredient from query (e.g., "chicken" from "chicken rice low sodium recipe")
    const baseIngredient = extractBaseSearchTerm(query);
    if (baseIngredient && recipes.length > 0) {
      ingredientVariants().learnVariantsFromRecipes(baseIngredient, recipes)
        .catch(err => console.error("VARIANT_LEARNING_FAILED:", err.message));
    }

    try {
      await cacheRef.set(
        {
          queryKey,
          query,
          page,
          calorieTarget: calorieTarget || null,
          recipes,
          recipeIds: recipes.map((recipe) => recipe.recipeId).filter(Boolean),
          totalResults: result.totalResults || recipes.length,
          source: "fatsecret",
          cachedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      await Promise.all(
        recipes
          .filter((recipe) => recipe.recipeId)
          .map((recipe) =>
            db
              .collection(RECIPE_CACHE_COLLECTION)
              .doc(String(recipe.recipeId))
              .set(recipe, { merge: true }),
          ),
      );
    } catch (cacheError) {
      console.error("MEAL_PLAN_RECIPE_CACHE_WRITE_ERROR:", {
        query,
        error: cacheError.message,
      });
    }

    return {
      ...result,
      recipes,
      source: "fatsecret",
    };
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

/**
 * Enhanced recipe search using learned ingredient variants
 * 
 * Instead of just searching "fish recipe",
 * searches: ["fish recipe", "tilapia recipe", "bangus recipe", "salmon recipe"]
 * and combines + deduplicates results
 */
async function searchMealPlanRecipesWithVariants(
  query,
  mealType,
  calorieTarget = null,
  page = 0
) {
  try {
    // Get base ingredient from query
    const baseIngredient = extractBaseSearchTerm(query);
    
    // Get learned variants
    const variantData = await ingredientVariants().getVariantsForIngredient(baseIngredient);
    const expandedIngredients = [baseIngredient, ...variantData.variants];
    
    if (expandedIngredients.length === 1) {
      // No variants learned yet, use standard search
      return await searchMealPlanRecipes(query, mealType, calorieTarget, page);
    }

    // Generate search queries for each variant
    const queries = expandedIngredients.map(ingredient => {
      // Preserve the original query structure but replace ingredient
      const remainder = query.toLowerCase()
        .replace(new RegExp(`\\b${baseIngredient}\\b`, "i"), "")
        .trim();
      return remainder ? `${ingredient} ${remainder}` : `${ingredient} recipe`;
    });

    // Search with all variant queries
    const allResults = [];
    const seenRecipeIds = new Set();
    let totalResults = 0;

    for (const variantQuery of queries) {
      try {
        const result = await searchMealPlanRecipes(
          variantQuery,
          mealType,
          calorieTarget,
          0
        );
        
        if (result.recipes) {
          // Deduplicate by recipeId
          result.recipes.forEach(recipe => {
            const recipeId = recipe.recipeId || recipe.foodId || recipe.id;
            if (recipeId && !seenRecipeIds.has(recipeId)) {
              seenRecipeIds.add(recipeId);
              allResults.push({
                ...recipe,
                searchVariant: variantQuery, // Track which variant found this
              });
            }
          });
          totalResults += result.totalResults || 0;
        }
      } catch (err) {
        console.error("VARIANT_SEARCH_FAILED:", {
          query: variantQuery,
          error: err.message,
        });
      }
    }

    return {
      query,
      baseIngredient,
      variantsUsed: expandedIngredients,
      variantCount: expandedIngredients.length,
      recipes: allResults,
      totalResults,
      source: "variant_search",
    };
  } catch (error) {
    console.error("VARIANT_SEARCH_ERROR:", {
      query,
      error: error.message,
    });
    // Fallback to standard search
    return await searchMealPlanRecipes(query, mealType, calorieTarget, page);
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
    const enriched = {
      ...item,
      ...(details.recipe || {}),
      ingredients: extractRecipeIngredients(details.recipe || item),
      raw: {
        ...(item.raw || {}),
        recipeDetails: details.raw || details.recipe,
      },
    };
    try {
      await db
        .collection(RECIPE_CACHE_COLLECTION)
        .doc(String(item.recipeId))
        .set(normalizeCachedRecipe(enriched, item.queryUsed || item.sourceQuery || ""), {
          merge: true,
        });
    } catch (cacheError) {
      console.error("MEAL_PLAN_RECIPE_DETAIL_CACHE_ERROR:", {
        recipeId: item.recipeId,
        error: cacheError.message,
      });
    }
    return enriched;
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
  if (usefulNutrition(food) && food.needsManualReview !== true) return food;
  const cacheKey = String(food.foodId);
  const cached = foodDetailCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.promise;

  const promise = (async () => {
    try {
      const details = await fatSecretBridge.getFoodDetails(food.foodId);
      const detailedFood = details.food || {};
      const merged = {
        ...food,
        ...detailedFood,
        calories: detailedFood.calories ?? food.calories ?? null,
        protein: detailedFood.protein ?? food.protein ?? null,
        carbohydrate: detailedFood.carbohydrate ?? food.carbohydrate ?? null,
        fat: detailedFood.fat ?? food.fat ?? null,
        sodium: detailedFood.sodium ?? food.sodium ?? null,
        potassium: detailedFood.potassium ?? food.potassium ?? null,
        phosphorus: detailedFood.phosphorus ?? food.phosphorus ?? null,
        raw: {
          ...(food.raw || {}),
          foodDetails: details.raw || details.food,
        },
      };
      const entry = foodDetailCache.get(cacheKey);
      const remainsIncomplete =
        detailedFood.needsManualReview === true ||
        (Array.isArray(detailedFood.missingNutrients) && detailedFood.missingNutrients.length > 0);
      if (entry) {
        entry.expiresAt = Date.now() + (
          remainsIncomplete
            ? FOOD_DETAIL_FAILURE_CACHE_TTL_MS
            : FOOD_DETAIL_CACHE_TTL_MS
        );
      }
      return merged;
    } catch (error) {
      console.error("MEAL_PLAN_FOOD_DETAILS_ERROR:", {
        foodId: food.foodId,
        error: error.message,
      });
      const entry = foodDetailCache.get(cacheKey);
      if (entry) entry.expiresAt = Date.now() + FOOD_DETAIL_FAILURE_CACHE_TTL_MS;
      return food;
    }
  })();

  foodDetailCache.set(cacheKey, {
    expiresAt: Date.now() + FOOD_DETAIL_FAILURE_CACHE_TTL_MS,
    promise,
  });
  return promise;
}

function embeddedServingOptions(food = {}) {
  const candidates = [
    food.servings,
    food.raw?.servings,
    food.raw?.food?.servings,
    food.raw?.foodDetails?.servings,
    food.raw?.foodDetails?.food?.servings,
  ];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) return candidate;
    if (Array.isArray(candidate?.serving)) return candidate.serving;
    if (candidate?.serving && typeof candidate.serving === "object") {
      return [candidate.serving];
    }
  }
  return [];
}

function preferredGuidelineServing(servings, role) {
  if (!Array.isArray(servings) || servings.length === 0) return null;
  const servingText = (serving) => String(
    serving.measurement_description ||
      serving.measurementDescription ||
      serving.serving_description ||
      serving.servingDescription ||
      "",
  ).toLowerCase();
  if (role === "vegetable") {
    return servings.find((serving) => /\bcups?\b/.test(servingText(serving))) ||
      servings[0];
  }
  if (role === "fruit") {
    return servings.find((serving) => /\bsmall\b/.test(servingText(serving))) ||
      servings.find((serving) => /\bcups?\b/.test(servingText(serving))) ||
      servings[0];
  }
  return servings[0];
}

function foodFromFirstServing(food, details = {}, role = null) {
  const servings = embeddedServingOptions({
    ...food,
    servings: details.servings || details.food?.servings || food.servings,
  });
  const firstServing = preferredGuidelineServing(servings, role);
  if (!firstServing) return null;
  const nutrients = firstServing.nutrients || firstServing;
  const servingId = firstServing.serving_id || firstServing.servingId;
  if (!servingId) return null;

  return {
    ...food,
    servingId: String(servingId),
    servingDescription:
      firstServing.serving_description ||
      firstServing.servingDescription ||
      firstServing.display_text ||
      firstServing.displayText ||
      "1 serving",
    calories: numberOrNull(nutrients.calories),
    protein: numberOrNull(nutrients.protein),
    carbohydrate: numberOrNull(
      nutrients.carbohydrate ?? nutrients.carbohydrates ?? nutrients.carbs,
    ),
    fat: numberOrNull(nutrients.fat),
    sodium: numberOrNull(nutrients.sodium),
    potassium: numberOrNull(nutrients.potassium),
    phosphorus: numberOrNull(nutrients.phosphorus ?? nutrients.phosphorous),
    firstServing,
  };
}

async function resolveMealPlanFirstServing(food, role = null) {
  const embedded = foodFromFirstServing(food, {}, role);
  if (embedded) {
    mealPlanDebug("FIRST_SERVING_FROM_EMBEDDED_DATA", {
      food: mealPlanFoodDiagnostic(food),
      selected: mealPlanFoodDiagnostic(embedded),
      firstServing: embedded.firstServing,
    });
    return embedded;
  }
  if (!food?.foodId) return null;
  try {
    const details = await fatSecretBridge.mealLoggingFoodDetails(food.foodId);
    const resolved = foodFromFirstServing(food, details, role);
    mealPlanDebug("FIRST_SERVING_FROM_FATSECRET", {
      food: mealPlanFoodDiagnostic(food),
      servingCount: Array.isArray(details.servings) ? details.servings.length : 0,
      servingOptions: (details.servings || []).map((serving) => ({
        servingId: serving.serving_id || serving.servingId,
        servingDescription:
          serving.serving_description || serving.servingDescription,
        displayText: serving.display_text || serving.displayText,
        metricServingAmount:
          serving.metric_serving_amount || serving.metricServingAmount,
        metricServingUnit:
          serving.metric_serving_unit || serving.metricServingUnit,
        nutrients: serving.nutrients || serving,
      })),
      selected: resolved ? mealPlanFoodDiagnostic(resolved) : null,
    });
    return resolved;
  } catch (error) {
    console.error("MEAL_PLAN_FIRST_SERVING_ERROR:", {
      foodId: food.foodId,
      error: error.message,
    });
    return null;
  }
}

const COOKED_VEGETABLE_CUP_GRAMS = 150;
const FRUIT_HALF_CUP_GRAMS = 75;

function referenceServingMetadata(food = {}) {
  const serving = food.firstServing || {};
  const existing = food.servingMetadata || {};
  return {
    numberOfUnits: numberOrNull(
      existing.numberOfUnits ?? serving.number_of_units ?? serving.numberOfUnits,
    ) || 1,
    measurementDescription: String(
      existing.measurementDescription ??
        serving.measurement_description ??
        serving.measurementDescription ??
        "",
    ).trim(),
    metricServingAmount: numberOrNull(
      existing.metricServingAmount ??
        serving.metric_serving_amount ??
        serving.metricServingAmount,
    ),
    metricServingUnit: String(
      existing.metricServingUnit ??
        serving.metric_serving_unit ??
        serving.metricServingUnit ??
        "",
    ).trim(),
  };
}

function guidelineServingMultiplier(role, food, mealType, fallback) {
  const metadata = referenceServingMetadata(food);
  const measurement = metadata.measurementDescription.toLowerCase();
  const metricUnit = metadata.metricServingUnit.toLowerCase();
  const isCup = /\bcups?\b/.test(measurement);

  if (role === "vegetable") {
    const targetCups = String(mealType).toLowerCase().includes("snack") ? 0.5 : 1;
    if (isCup) return targetCups / metadata.numberOfUnits;
    if (metadata.metricServingAmount && ["g", "gram", "grams"].includes(metricUnit)) {
      const targetGrams = COOKED_VEGETABLE_CUP_GRAMS * targetCups;
      return targetGrams / metadata.metricServingAmount;
    }
  }

  if (role === "fruit") {
    if (isCup) return 0.5 / metadata.numberOfUnits;
    const isWholeFruitUnit = measurement &&
      !/\b(g|gram|grams|kg|ml|oz|ounce|serving)\b/.test(measurement);
    if (isWholeFruitUnit) return 1 / metadata.numberOfUnits;
    if (metadata.metricServingAmount && ["g", "gram", "grams"].includes(metricUnit)) {
      return FRUIT_HALF_CUP_GRAMS / metadata.metricServingAmount;
    }
  }

  return fallback;
}

function calculatedServingText(food, servings) {
  const metadata = referenceServingMetadata(food);
  const description = food.servingDescription || food.servingSize || "1 serving";
  const quantity = Number(servings);
  const parts = [];

  const parsedMeasurement = metadata.measurementDescription.match(
    /^\s*(\d+(?:\.\d+)?)\s+(.+)$/,
  );
  const measurementAmount = parsedMeasurement
    ? Number(parsedMeasurement[1])
    : metadata.numberOfUnits;
  const measurementUnit = parsedMeasurement
    ? parsedMeasurement[2].trim()
    : metadata.measurementDescription;
  const measurementIsMetric = /^(g|gram|grams|kg|ml|milliliters?)$/i.test(
    measurementUnit,
  );
  if (measurementUnit && !measurementIsMetric) {
    const amount = measurementAmount * quantity;
    parts.push(`${Number(amount.toFixed(2))} ${measurementUnit}`);
  }
  if (metadata.metricServingAmount && metadata.metricServingUnit) {
    const metricAmount = metadata.metricServingAmount * quantity;
    parts.push(`${Number(metricAmount.toFixed(1))} ${metadata.metricServingUnit}`);
  }
  if (!parts.length) {
    const metricDescription = String(description).match(
      /^\s*(\d+(?:\.\d+)?)\s*(g|gram|grams|kg|ml|milliliters?)\s*$/i,
    );
    if (metricDescription) {
      const amount = Number(metricDescription[1]) * quantity;
      return `${Number(amount.toFixed(2))} ${metricDescription[2]}`;
    }
  }
  if (parts.length) return parts.join(" (") + (parts.length > 1 ? ")" : "");
  return `${Number(quantity.toFixed(6))} × ${description}`;
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

function bestValidatedRecipeCandidate(
  candidates,
  mealType,
  nutritionProfile,
  restrictions,
  ingredientRules,
) {
  return candidates
    .map((item) => {
      const recipeValidation = validateRecipeCandidate(
        item,
        ingredientRules,
        restrictions,
      );
      return {
        ...item,
        recipeValidation,
        score:
          scoreMealCandidate(item, mealType, nutritionProfile, restrictions) +
          (recipeValidation.isAllowed ? 15 : -80) +
          recipeValidation.allowedIngredients.length * 4 -
          recipeValidation.unknownIngredients.length,
      };
    })
    .filter((item) => usefulNutrition(item) && item.recipeValidation.isAllowed && item.score >= 45)
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
  return componentFoods.map((food) => {
    const nutrients = roundNutrients(food);
    console.log("COMPONENT_NUTRIENTS:", {
      component: food.component || food.name,
      calories: food.calories,
      protein: food.protein,
      phosphorus: food.phosphorus,
      roundedCalories: nutrients.calories,
      roundedProtein: nutrients.protein,
      roundedPhosphorus: nutrients.phosphorus
    });
    
    return {
      component: food.component || food.name,
      matchedName: food.name,
      foodId: food.foodId,
      portion: food.servingDescription || food.servingSize || "1 serving",
      nutrients,
      source: food.source || "fatsecret",
      needsManualReview: food.needsManualReview === true,
      suggestions: food.suggestions || [],
    };
  });
}

function componentFoodText(food = {}) {
  return [
    food.name,
    food.description,
    food.servingDescription,
    food.servingSize,
    food.brandName,
  ].join(" ");
}

function firstIngredientPresentFood(candidates = [], component = "") {
  const withIngredient = candidates.filter((food) =>
    containsAny(componentFoodText(food), [component]),
  );
  return withIngredient.find(usefulNutrition) || withIngredient[0] || candidates[0] || null;
}

function componentSuggestions(candidates = [], selected = {}, component = "") {
  const selectedKey = normalizeTextToken(selected.foodId || selected.name);
  return candidates
    .filter((food) => containsAny(componentFoodText(food), [component]))
    .filter((food) => normalizeTextToken(food.foodId || food.name) !== selectedKey)
    .slice(0, 4)
    .map((food) => ({
      foodId: food.foodId,
      name: food.name,
      portion: food.servingDescription || food.servingSize || "1 serving",
      nutrients: roundNutrients(food),
      source: food.source || "fatsecret",
      needsManualReview: food.needsManualReview === true,
    }));
}

async function resolveWholeMealNutrition(plannedMeal, nutritionProfile, restrictions, seed, ingredientRules) {
  // GUARD: Skip if meal name and components are both undefined
  // This prevents "undefined recipe" search queries
  if (!plannedMeal?.name && (!plannedMeal?.components || plannedMeal.components.length === 0)) {
    console.warn("SKIP_WHOLE_MEAL_SEARCH: No meal name or components provided");
    return null;
  }

  const guideTags = buildGuideTags(nutritionProfile).join(" ");
  const queries = [
    ...(plannedMeal.name ? [`${plannedMeal.name} recipe`] : []),
    ...(plannedMeal.components?.length > 0 ? [`${plannedMeal.components.join(" ")} recipe`] : []),
    ...(plannedMeal.name && guideTags ? [`${plannedMeal.name} ${guideTags} recipe`] : []),
  ].filter(Boolean);

  // GUARD: If no valid queries can be built, skip
  if (queries.length === 0) {
    console.warn("SKIP_WHOLE_MEAL_SEARCH: No valid search queries built");
    return null;
  }

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
  const recipeCandidate = bestValidatedRecipeCandidate(
    enriched.filter((candidate) => candidate.recipeId),
    plannedMeal.mealType,
    nutritionProfile,
    restrictions,
    ingredientRules,
  );
  if (recipeCandidate) return recipeCandidate;

  return bestScoredCandidate(
    enriched.filter((candidate) => !candidate.recipeId),
    plannedMeal.mealType,
    nutritionProfile,
    restrictions,
  );
}

/**
 * Try to find a single FatSecret food whose per-serving protein
 * closely matches the meal protein target. This is the "search-first"
 * fast-path: prefer whole-serving suggestions when available.
 */
async function findSingleServingProteinMatch(plannedMeal, nutritionProfile, restrictions, ingredientRules, tolerancePercent = 0.15) {
  try {
    const targets = perMealTargets(nutritionProfile, restrictions, plannedMeal.mealType || "Lunch");
    const mealProtein = numberOrNull(targets.protein) || null;
    if (!mealProtein) return null;

    // Determine a focused search term (prefer explicit protein ingredient)
    const queryBase = (plannedMeal.protein && String(plannedMeal.protein).trim()) ||
      extractBaseSearchTerm(plannedMeal.name) || plannedMeal.name || (plannedMeal.components && plannedMeal.components[0]);
    if (!queryBase) return null;

    const searchResult = await searchMealPlanFoods(queryBase, plannedMeal.mealType || "Lunch", 0);
    const foods = (searchResult.foods || []).slice(0, 20);
    if (!foods.length) return null;

    const detailed = await Promise.all(foods.map(resolveFoodDetails));

    for (const candidate of detailed) {
      if (!usefulNutrition(candidate)) continue;
      const candidateProtein = numberOrNull(candidate.protein);
      if (!candidateProtein || candidateProtein <= 0) continue;
      const ratio = Math.abs(candidateProtein - mealProtein) / Math.max(1, mealProtein);
      if (ratio > tolerancePercent) continue;

      // Quick CKD restriction checks (per-meal targets)
      if (targets.sodium && numberOrNull(candidate.sodium) > targets.sodium) continue;
      if (targets.potassium && numberOrNull(candidate.potassium) > targets.potassium) continue;
      if (targets.phosphorus && numberOrNull(candidate.phosphorus) > targets.phosphorus) continue;

      const score = scoreMealCandidate(candidate, plannedMeal.mealType || "Lunch", nutritionProfile, restrictions);
      if (score < 40) continue;

      // Build a meal object consistent with other resolvers
      const meal = {
        foodId: candidate.foodId || candidate.recipeId,
        name: candidate.name || candidate.title || queryBase,
        portion: candidate.servingDescription || candidate.servingSize || "1 serving",
        servingDescription: candidate.servingDescription || candidate.servingSize || "1 serving",
        calories: numberOrNull(candidate.calories),
        protein: numberOrNull(candidate.protein),
        carbohydrate: numberOrNull(candidate.carbohydrate),
        fat: numberOrNull(candidate.fat),
        sodium: numberOrNull(candidate.sodium),
        potassium: numberOrNull(candidate.potassium),
        phosphorus: numberOrNull(candidate.phosphorus),
        componentBreakdown: componentBreakdownFromFoods([candidate]),
        nutrientPreview: roundNutrients(candidate),
        score,
        source: "fatsecret_single_serving_match",
        reason: `Single serving matched protein target within ${Math.round(tolerancePercent * 100)}% tolerance.`,
        raw: { candidateQuery: queryBase, candidate },
      };

      return meal;
    }
    return null;
  } catch (err) {
    console.error("SINGLE_SERVING_MATCH_ERROR:", { plannedMeal: plannedMeal?.name, error: err.message });
    return null;
  }
}

/**
 * Resolve a meal using ingredient expansion (PREFERRED METHOD)
 * 
 * Template structure:
 * { protein: "chicken", carb: "white rice", vegetable: "cabbage", target: 420 }
 * 
 * Process:
 * 1. Expand each ingredient to specific FatSecret variants
 * 2. Randomly pick one variant from each ingredient
 * 3. Search FatSecret for each specific variant
 * 4. Combine nutrition values
 * 5. Return complete meal with real food names
 */
async function resolveIngredientBasedMeal(
  mealTemplate,
  nutritionProfile,
  restrictions,
  ingredientRules,
) {
  if (!mealTemplate) return null;

  console.log("RESOLVE_INGREDIENT_MEAL_START:", { 
    protein: mealTemplate.protein,
    carb: mealTemplate.carb,
    vegetable: mealTemplate.vegetable,
    mealType: mealTemplate.mealType
  });

  const ingredients = {
    protein: mealTemplate.protein,
    carb: mealTemplate.carb || mealTemplate.grain,
    vegetable: mealTemplate.vegetable || mealTemplate.vegetables,
    ...Object.keys(mealTemplate)
      .filter((k) => !["name", "target", "mealType", "source", "components"].includes(k))
      .reduce((acc, k) => {
        if (typeof mealTemplate[k] === "string" && mealTemplate[k].length > 2) {
          acc[k] = mealTemplate[k];
        }
        return acc;
      }, {}),
  };

  const selectedFoods = {};
  const foodDetails = [];

  // Expand each ingredient and pick a random variant
  for (const [role, ingredient] of Object.entries(ingredients)) {
    if (!ingredient) continue;

    try {
      // Get random variant from cache/FatSecret
      const variant = await ingredientExpansionService.pickRandomVariant(ingredient);
      if (!variant) {
        console.warn("INGREDIENT_NO_VARIANT:", { ingredient, role });
        continue;
      }
      selectedFoods[role] = variant;
      console.log("INGREDIENT_VARIANT_SELECTED:", { role, ingredient, variant });

      // Search FatSecret for this specific variant
      const result = await searchMealPlanFoods(variant, mealTemplate.mealType, 0);
      if (!result || !result.foods || result.foods.length === 0) {
        console.warn("FATSECRET_NO_FOODS_FOUND:", { variant, role });
        continue;
      }
      
      const food = result.foods[0];
      console.log("FATSECRET_FOOD_FOUND:", { role, variant, foodId: food.foodId, foodName: food.food_name });
      
      const detailed = await resolveFoodDetails(food);
      if (!detailed) {
        console.warn("FOOD_DETAILS_FAILED:", { role, variant, foodId: food.foodId });
        continue;
      }
      
      console.log("FOOD_DETAILS_RESOLVED:", { 
        role, 
        variant, 
        calories: detailed.calories,
        protein: detailed.protein,
        carbs: detailed.carbohydrate,
        sodium: detailed.sodium
      });
      
      foodDetails.push({
        ...detailed,
        role,
        baseIngredient: ingredient,
        selectedVariant: variant,
      });
    } catch (error) {
      console.error("INGREDIENT_EXPANSION_ERROR:", { ingredient, role, error: error.message, stack: error.stack });
    }
  }

  if (foodDetails.length === 0) {
    console.warn("INGREDIENT_MEAL_NO_FOODS:", { mealType: mealTemplate.mealType, ingredients });
    return null;
  }

  // Validate ingredients against CKD rules
  const validation = {
    blocked: [],
    allowed: [],
    unknown: [],
  };

  foodDetails.forEach((food) => {
    const status = ingredientStatus(food.selectedVariant, ingredientRules);
    if (status === "blocked") validation.blocked.push(food.selectedVariant);
    else if (status === "allowed") validation.allowed.push(food.selectedVariant);
    else validation.unknown.push(food.selectedVariant);
  });

  // Reject if any blocked ingredients
  if (validation.blocked.length > 0) {
    console.warn("INGREDIENT_MEAL_BLOCKED:", { mealType: mealTemplate.mealType, blocked: validation.blocked });
    return null;
  }

  // Combine nutrition from all foods
  const totals = nutrientTotals(foodDetails);
  
  // Warn if all nutrients are 0 (indicates data quality issue)
  const allNutrientsZero = totals.calories === 0 && totals.protein === 0 && 
                          totals.sodium === 0 && totals.potassium === 0 && 
                          totals.phosphorus === 0;
  
  if (allNutrientsZero) {
    console.warn("INGREDIENT_MEAL_ZERO_NUTRIENTS:", {
      mealType: mealTemplate.mealType,
      components: foodDetails.length,
      foodDetails: foodDetails.map(f => ({
        ingredient: f.baseIngredient,
        variant: f.selectedVariant,
        calories: f.calories,
        protein: f.protein,
        sourceType: f.source,
        hasUsefulNutrition: usefulNutrition(f)
      }))
    });
  }
  
  console.log("INGREDIENT_MEAL_TOTALS:", { 
    mealType: mealTemplate.mealType,
    components: foodDetails.length,
    calories: totals.calories,
    protein: totals.protein,
    sodium: totals.sodium,
    potassium: totals.potassium,
    phosphorus: totals.phosphorus,
    allNutrientsMissing: allNutrientsZero
  });

  // Build meal name from actual selected variants
  const mealName = buildMealTitle({
    foods: Object.entries(ingredients).map(([category, name]) => ({ category, name })),
  });

  const result = {
    foodId: foodDetails.map((f) => f.foodId).filter(Boolean).join(","),
    name: mealName,
    portion: "1 serving",
    servingDescription: "1 serving",
    ...totals,
    componentBreakdown: foodDetails.map((food) => ({
      component: food.role,
      matchedName: food.selectedVariant,
      sourceName: food.selectedVariant,
      displayName: food.baseIngredient,
      foodId: food.foodId,
      baseIngredient: food.baseIngredient,
      portion: food.servingDescription || food.servingSize || "1 serving",
      nutrients: roundNutrients(food),
      source: food.source || "fatsecret",
    })),
    nutrientPreview: roundNutrients(totals),
    score: scoreMealCandidate(
      { ...totals, name: mealName },
      mealTemplate.mealType,
      nutritionProfile,
      restrictions,
    ),
    source: "fatsecret_ingredient_expansion_meal",
    reason:
      "Meal generated from ingredient expansion with FatSecret variants; ensures diversity without recipe search complexity.",
    raw: {
      template: mealTemplate,
      selectedFoods,
      validation,
    },
  };

  console.log("INGREDIENT_MEAL_COMPLETE:", { 
    mealType: mealTemplate.mealType,
    name: result.name,
    score: result.score
  });

  return result;
}

/**
 * Compute a portioned meal from a simple template following the user's 10-step flow.
 * - Calculates per-meal nutrient targets (from daily targets or profile)
 * - Picks FatSecret variants for each ingredient
 * - Computes decimal FatSecret serving quantities from nutrient targets
 * - Recalculates totals and adjusts portions / substitutes to satisfy CKD constraints
 */
async function computePortionedMeal(
  mealTemplate = {},
  dailyTargets = {},
  nutritionProfile = null,
  restrictions = {},
  options = {},
) {
  const maxIterations = Number(options.maxIterations || 8);
  const maxVariants = Number(options.maxVariants || 3);
  const mealType = mealTemplate.mealType || "Lunch";
  const isSnack = mealType.includes("Snack");
  const adapters = {
    expandIngredient:
      options.adapters?.expandIngredient || ingredientExpansionService.expandIngredient,
    searchFoods: options.adapters?.searchFoods || searchMealPlanFoods,
    resolveFood: options.adapters?.resolveFood || resolveFoodDetails,
    resolveFirstServing:
      options.adapters?.resolveFirstServing || resolveMealPlanFirstServing,
  };

  // Protein is split only across the three main meals. Electrolyte caps are
  // supplied as a shrinking daily budget by generateMealPlan.
  let mealTargets = {};
  if (nutritionProfile && nutritionProfile.calorieTarget) {
    mealTargets = perMealTargets(nutritionProfile, restrictions, mealType);
  } else {
    const daily = {
      calories: Number(dailyTargets.calories || 1800),
      protein: Number(dailyTargets.protein || 60),
      sodium: Number(dailyTargets.sodium || 2000),
      potassium: Number(dailyTargets.potassium || 0),
      phosphorus: Number(dailyTargets.phosphorus || 0),
    };
    mealTargets = {
      calories: null,
      protein: isSnack ? null : Number((daily.protein / 3).toFixed(1)),
      sodium: daily.sodium || null,
      potassium: daily.potassium || null,
      phosphorus: daily.phosphorus || null,
    };
  }
  for (const nutrient of ["sodium", "potassium", "phosphorus"]) {
    const budget = numberOrNull(options.nutrientBudgets?.[nutrient]);
    if (budget !== null) mealTargets[nutrient] = Math.max(0, Math.round(budget));
  }

  const plate = { vegetables: 0.5, protein: 0.25, carbs: 0.25 };
  const components = {
    protein: mealTemplate.protein || mealTemplate.proteins || null,
    carb: mealTemplate.carb || mealTemplate.carbohydrate || mealTemplate.grain || null,
    vegetable: mealTemplate.vegetable || mealTemplate.vegetables || null,
    fruit: mealTemplate.fruit || null,
    fat: mealTemplate.fat || null,
  };
  const portionControlPlan = generateMealPortions({
    weightKg: nutritionProfile?.weightKg || nutritionProfile?.weight_kg,
    calorieTarget: nutritionProfile?.calorieTarget || dailyTargets.calories,
    ckdStage: nutritionProfile?.ckdStage || nutritionProfile?.ckd_stage,
    dialysisStatus:
      nutritionProfile?.dialysisStatus ||
      nutritionProfile?.dialysis_status ||
      nutritionProfile?.ckdType ||
      nutritionProfile?.ckd_type,
    prescribedProtein: nutritionProfile?.proteinTarget || dailyTargets.protein,
    mealType,
    ingredientList: Object.entries(components)
      .filter(([, ingredient]) => ingredient)
      .map(([role, ingredient]) => ({
        name: ingredient,
        category: role,
      })),
    restrictions,
  });
  const portionRulesByRole = new Map(
    (portionControlPlan.portions || []).map((portion) => [
      portion.category,
      portion,
    ]),
  );
  mealPlanDebug("COMPUTE_START", {
    mealType,
    template: mealTemplate,
    components,
    mealTargets,
    portionControl: portionControlPlan,
    nutrientBudgets: options.nutrientBudgets || {},
    restrictions: {
      avoid: restrictions.avoid || [],
      dailySodiumLimitMg: restrictions.dailySodiumLimitMg,
      dailyPotassiumLimitMg: restrictions.dailyPotassiumLimitMg,
      dailyPhosphorusLimitMg: restrictions.dailyPhosphorusLimitMg,
    },
    maxIterations,
    maxVariants,
  });

  function initialServingPortion(role, food, portionRule) {
    const description = food.servingDescription || food.servingSize || "";
    let servings = numberOrNull(portionRule?.fatSecretServingMultiplier);
    if (servings === null || servings <= 0) servings = 1;

    if (role === "protein") {
      const proteinPerServing = numberOrNull(food.protein) || 0;
      const portionProteinTarget = numberOrNull(portionRule?.targetProtein);
      const targetProtein =
        portionProteinTarget !== null && portionProteinTarget > 0
          ? portionProteinTarget
          : mealTargets.protein;
      if (!targetProtein || proteinPerServing <= 0) return null;
      servings = targetProtein / proteinPerServing;
    } else {
      servings = guidelineServingMultiplier(role, food, mealType, servings);
      if (role === "carb") {
        servings *= numberOrNull(nutritionProfile?.carbohydratePortionScale) || 1;
      } else if (role === "fruit") {
        servings *= numberOrNull(nutritionProfile?.fruitPortionScale) || 1;
      }
    }

    const roundedServings = Number(servings.toFixed(6));
    return {
      text: calculatedServingText(food, roundedServings),
      servings: roundedServings,
      manualServing: description || "1 serving",
      portionControl: portionRule || null,
    };
  }

  function requiredNutritionIssues(role, food) {
    const issues = [];
    function nutrientProvided(nutrient) {
      const value = numberOrNull(food?.[nutrient]);
      if (value === null) return false;
      if (value !== 0 || !food.raw) return true;
      const rawValues = [
        food.raw?.[nutrient],
        food.raw?.food?.[nutrient],
        food.raw?.foodDetails?.[nutrient],
        food.raw?.foodDetails?.food?.[nutrient],
      ];
      return rawValues.some((rawValue) => rawValue !== undefined && rawValue !== null && rawValue !== "");
    }

    if (!food) return ["food_missing"];
    if ((numberOrNull(food.calories) || 0) <= 0) issues.push("calories_missing_or_zero");
    if (role === "protein" && (numberOrNull(food.protein) || 0) <= 0) {
      issues.push("protein_missing_or_zero");
    }
    if (role === "carb" && (numberOrNull(food.carbohydrate) || 0) <= 0) {
      issues.push("carbohydrate_missing_or_zero");
    }
    if (role === "fat" && (numberOrNull(food.fat) || 0) <= 0) {
      issues.push("fat_missing_or_zero");
    }
    if (!nutrientProvided("sodium")) issues.push("sodium_missing");
    if (mealTargets.potassium && !nutrientProvided("potassium")) {
      issues.push("potassium_required_but_missing");
    }
    if (mealTargets.phosphorus && !nutrientProvided("phosphorus")) {
      issues.push("phosphorus_required_but_missing");
    }
    return issues;
  }

  function requiredNutritionPresent(role, food) {
    return requiredNutritionIssues(role, food).length === 0;
  }

  function applyRiskBasedNutrientFallbacks(role, ingredient, food) {
    if (!food) return food;
    const name = normalizeTextToken(food.name || ingredient);
    const traceCategory = SIMPLE_FAT_FOOD_NAMES.some((item) => name.includes(item));
    const fatRoleTracePortion =
      role === "fat" &&
      (traceCategory || /\b(oil|butter|margarine)\b/.test(name));
    if (!fatRoleTracePortion) return food;

    const resolved = {
      ...food,
      estimatedNutrients: [...(food.estimatedNutrients || [])],
      nutrientSources: { ...(food.nutrientSources || {}) },
      nutrientEstimateNotes: { ...(food.nutrientEstimateNotes || {}) },
    };
    const calories = numberOrNull(resolved.calories);
    const fat = numberOrNull(resolved.fat);
    if (fat === null && calories !== null && calories > 0) {
      resolved.fat = Number((calories / 9).toFixed(1));
      if (!resolved.estimatedNutrients.includes("fat")) {
        resolved.estimatedNutrients.push("fat");
      }
      resolved.nutrientSources.fat = "fat_from_calories_assumption";
      resolved.nutrientEstimateNotes.fat =
        "Estimated from calories for a simple fat/oil reference serving.";
    } else if ((calories === null || calories <= 0) && fat !== null && fat > 0) {
      resolved.calories = Math.round(fat * 9);
      if (!resolved.estimatedNutrients.includes("calories")) {
        resolved.estimatedNutrients.push("calories");
      }
      resolved.nutrientSources.calories = "calories_from_fat_assumption";
      resolved.nutrientEstimateNotes.calories =
        "Estimated from fat grams for a simple fat/oil reference serving.";
    }
    for (const nutrient of [
      "protein",
      "carbohydrate",
      "sodium",
      "potassium",
      "phosphorus",
    ]) {
      if (numberOrNull(resolved[nutrient]) !== null) continue;
      resolved[nutrient] = 0;
      if (!resolved.estimatedNutrients.includes(nutrient)) {
        resolved.estimatedNutrients.push(nutrient);
      }
      resolved.nutrientSources[nutrient] = "fat_trace_assumption";
      resolved.nutrientEstimateNotes[nutrient] =
        "Estimated as trace for the selected FatSecret serving.";
    }
    resolved.isEstimated = resolved.estimatedNutrients.length > 0;
    return resolved;
  }

  const picked = [];
  for (const [role, ingredient] of Object.entries(components)) {
    if (!ingredient) continue;
    try {
      let variants = [ingredient];
      let selected = null;
      let detailLookupUsed = false;
      for (let variantIndex = 0; variantIndex < variants.length && !selected; variantIndex += 1) {
        const variant = variants[variantIndex];
        const result = await adapters.searchFoods(variant, mealType, 0);
        const searchedCandidates = (result.foods || []).slice(0, 10);
        const candidates = searchedCandidates.filter((candidate) => {
          const text = componentFoodText(candidate);
          return containsAny(text, [ingredient, variant]) &&
            !containsAny(text, restrictions.avoid || []);
        }).map((candidate) => applyRiskBasedNutrientFallbacks(role, ingredient, candidate));
        mealPlanDebug("CANDIDATE_SEARCH", {
          mealType,
          role,
          ingredient,
          variant,
          resultCount: result.foods?.length || 0,
          candidates: searchedCandidates.map((candidate) => ({
            ...mealPlanFoodDiagnostic(candidate),
            textMatched: containsAny(componentFoodText(candidate), [ingredient, variant]),
            restrictionMatched: containsAny(
              componentFoodText(candidate),
              restrictions.avoid || [],
            ),
            requiredNutritionIssues: requiredNutritionIssues(
              role,
              applyRiskBasedNutrientFallbacks(role, ingredient, candidate),
            ),
          })),
        });

        const fixedServing = candidates.find((candidate) =>
          requiredNutritionPresent(role, candidate),
        );
        if (fixedServing) {
          mealPlanDebug("CANDIDATE_ACCEPTED_FROM_SEARCH", {
            role,
            ingredient,
            variant,
            food: mealPlanFoodDiagnostic(fixedServing),
          });
          selected = { role, ingredient, variant, food: fixedServing };
          break;
        }

        if (!detailLookupUsed && candidates[0]) {
          detailLookupUsed = true;
          const detailed = applyRiskBasedNutrientFallbacks(
            role,
            ingredient,
            await adapters.resolveFood(candidates[0]),
          );
          if (requiredNutritionPresent(role, detailed)) {
            mealPlanDebug("CANDIDATE_ACCEPTED_AFTER_DETAIL_LOOKUP", {
              role,
              ingredient,
              variant,
              food: mealPlanFoodDiagnostic(detailed),
            });
            selected = { role, ingredient, variant, food: detailed };
          } else {
            mealPlanDebug("CANDIDATE_DETAIL_REJECTED", {
              role,
              ingredient,
              variant,
              food: mealPlanFoodDiagnostic(detailed),
              issues: requiredNutritionIssues(role, detailed),
            });
          }
        }

        if (!selected && variants.length === 1 && maxVariants > 1) {
          const expanded = await adapters.expandIngredient(ingredient);
          variants = [...new Set([ingredient, ...(Array.isArray(expanded) ? expanded : [])])]
            .slice(0, maxVariants);
        }
      }
      if (!selected) {
        mealPlanDebug("COMPONENT_UNRESOLVED", { mealType, role, ingredient, variants });
        return null;
      }
      const servingFood = await adapters.resolveFirstServing(selected.food, role);
      if (!servingFood) {
        console.warn("MEAL_PLAN_FIRST_SERVING_MISSING:", {
          ingredient,
          foodId: selected.food?.foodId,
        });
        return null;
      }
      selected.food = applyRiskBasedNutrientFallbacks(
        role,
        ingredient,
        servingFood,
      );
      const firstServingIssues = requiredNutritionIssues(role, selected.food);
      if (firstServingIssues.length) {
        mealPlanDebug("FIRST_SERVING_REJECTED", {
          mealType,
          role,
          ingredient,
          food: mealPlanFoodDiagnostic(selected.food),
          issues: firstServingIssues,
        });
        return null;
      }
      mealPlanDebug("COMPONENT_RESOLVED", {
        mealType,
        role,
        ingredient,
        variant: selected.variant,
        food: mealPlanFoodDiagnostic(selected.food),
      });
      picked.push(selected);
    } catch (err) {
      console.error("COMPUTE_PORTIONED_MEAL_FETCH_ERROR:", { role, ingredient, error: err.message });
      return null;
    }
  }

  if (picked.length === 0) return null;

  function scaleNutrients(food, scale) {
    return {
      calories: Math.round((numberOrNull(food.calories) || 0) * scale),
      protein: Number(((numberOrNull(food.protein) || 0) * scale).toFixed(1)),
      carbohydrate: Number(((numberOrNull(food.carbohydrate) || 0) * scale).toFixed(1)),
      fat: Number(((numberOrNull(food.fat) || 0) * scale).toFixed(1)),
      sodium: Math.round((numberOrNull(food.sodium) || 0) * scale),
      potassium: Math.round((numberOrNull(food.potassium) || 0) * scale),
      phosphorus: Math.round((numberOrNull(food.phosphorus) || 0) * scale),
    };
  }

  const componentsPortions = picked.map((entry) => {
    const portion = initialServingPortion(
      entry.role,
      entry.food,
      portionRulesByRole.get(entry.role),
    );
    if (!portion) return null;
    const nutrients = scaleNutrients(entry.food, portion.servings);

    return {
      role: entry.role,
      ingredient: entry.ingredient,
      variant: entry.variant,
      food: entry.food || null,
      portion,
      nutrients,
    };
  });
  if (componentsPortions.some((part) => !part)) {
    mealPlanDebug("PORTION_INITIALIZATION_FAILED", {
      mealType,
      picked: picked.map((entry) => ({
        role: entry.role,
        ingredient: entry.ingredient,
        food: mealPlanFoodDiagnostic(entry.food),
      })),
    });
    return null;
  }
  mealPlanDebug("INITIAL_PORTIONS", {
    mealType,
    portions: componentsPortions.map((part) => ({
      role: part.role,
      ingredient: part.ingredient,
      foodId: part.food?.foodId,
      servingId: part.food?.servingId,
      servingDescription: part.food?.servingDescription,
      numberOfServings: part.portion.servings,
      nutrients: part.nutrients,
    })),
  });

  // STEP 6: Recalculate totals
  function totalsFromParts(parts) {
    return parts.reduce((sum, part) => ({
      calories: sum.calories + (numberOrNull(part.nutrients.calories) || 0),
      protein: sum.protein + (numberOrNull(part.nutrients.protein) || 0),
      carbs: sum.carbs + (numberOrNull(part.nutrients.carbohydrate) || 0),
      fat: sum.fat + (numberOrNull(part.nutrients.fat) || 0),
      sodium: sum.sodium + (numberOrNull(part.nutrients.sodium) || 0),
      potassium: sum.potassium + (numberOrNull(part.nutrients.potassium) || 0),
      phosphorus: sum.phosphorus + (numberOrNull(part.nutrients.phosphorus) || 0),
    }), { calories: 0, protein: 0, carbs: 0, fat: 0, sodium: 0, potassium: 0, phosphorus: 0 });
  }

  let parts = componentsPortions;
  let totals = totalsFromParts(parts);

  function checkConstraints(totals, targets) {
    const proteinOk = !targets.protein || Math.abs(totals.protein - Number(targets.protein)) <= Math.max(1, Number(targets.protein) * 0.1);
    const caloriesOk = true;
    const sodiumOk = !targets.sodium || totals.sodium <= Number(targets.sodium);
    const potassiumOk = !targets.potassium || (Number.isFinite(Number(targets.potassium)) ? totals.potassium <= Number(targets.potassium) : true);
    const phosphorusOk = !targets.phosphorus || totals.phosphorus <= Number(targets.phosphorus);
    return { proteinOk, caloriesOk, sodiumOk, potassiumOk, phosphorusOk, allOk: proteinOk && caloriesOk && sodiumOk && potassiumOk && phosphorusOk };
  }

  let iter = 0;

  while (iter < maxIterations) {
    const status = checkConstraints(totals, mealTargets);
    mealPlanDebug("CONSTRAINT_ITERATION", {
      mealType,
      iteration: iter,
      totals,
      targets: mealTargets,
      status,
      portions: parts.map((part) => ({
        role: part.role,
        ingredient: part.ingredient,
        numberOfServings: part.portion.servings,
        nutrients: part.nutrients,
      })),
    });
    if (status.allOk) break;

    // Protein adjustments
    if (!status.proteinOk) {
      const proteinPart = parts.find((p) => p.role === "protein");
      if (proteinPart?.portion) {
        const currentProtein = totals.protein || 0;
        const wanted = mealTargets.protein || 0;
        if (currentProtein > 0 && wanted >= 0) {
          const ratio = wanted / currentProtein;
          proteinPart.portion.servings = Number(
            (proteinPart.portion.servings * ratio).toFixed(6),
          );
          proteinPart.portion.text = calculatedServingText(
            proteinPart.food || {},
            proteinPart.portion.servings,
          );
          const scale = proteinPart.portion.servings;
          proteinPart.nutrients = scaleNutrients(proteinPart.food || {}, scale);
        }
      }
    }

    totals = totalsFromParts(parts);
    const currentStatus = checkConstraints(totals, mealTargets);
    const failingNutrient = !currentStatus.sodiumOk
      ? "sodium"
      : !currentStatus.potassiumOk
        ? "potassium"
        : !currentStatus.phosphorusOk
          ? "phosphorus"
          : null;
    if (failingNutrient) {
      const culprit = [...parts]
        .filter((part) => part.role !== "protein")
        .sort((a, b) => (b.nutrients[failingNutrient] || 0) - (a.nutrients[failingNutrient] || 0))[0];
      if (!culprit || culprit.portion.servings <= 0.5) break;
      culprit.portion.servings = Math.max(0.5, culprit.portion.servings * 0.85);
      culprit.portion.servings = Number(culprit.portion.servings.toFixed(6));
      culprit.portion.text = calculatedServingText(
        culprit.food || {},
        culprit.portion.servings,
      );
      culprit.nutrients = scaleNutrients(culprit.food || {}, culprit.portion.servings);
    }

    // Recompute totals at end of iteration
    totals = totalsFromParts(parts);
    iter += 1;
  }

  totals = totalsFromParts(parts);
  mealPlanDebug("COMPUTE_COMPLETE", {
    mealType,
    totals,
    targets: mealTargets,
    validation: checkConstraints(totals, mealTargets),
    iterations: iter,
    components: parts.map((part) => ({
      role: part.role,
      ingredient: part.ingredient,
      variant: part.variant,
      food: mealPlanFoodDiagnostic(part.food),
      numberOfServings: part.portion.servings,
      nutrients: part.nutrients,
    })),
  });

  // STEP 10: Return structured meal
  const meal = {
    mealType,
    template: mealTemplate,
    plate,
    components: parts.map((p) => ({
      role: p.role,
      ingredient: p.ingredient,
      variant: p.variant,
      name: p.food?.name || String(p.variant || p.ingredient || ""),
      sourceName: p.food?.name || String(p.variant || ""),
      displayName: String(p.ingredient || p.variant || p.food?.name || ""),
      genericName: String(p.ingredient || ""),
      foodId: p.food?.foodId || null,
      servingId: p.food?.servingId || null,
      servingDescription: p.food?.servingDescription || "1 serving",
      servingMetadata: referenceServingMetadata(p.food || {}),
      portion: p.portion.text,
      numberOfServings: p.portion.servings,
      servings: p.portion.servings,
      servingNutrients: {
        calories: numberOrNull(p.food?.calories) || 0,
        protein: numberOrNull(p.food?.protein) || 0,
        carbohydrate: numberOrNull(p.food?.carbohydrate) || 0,
        fat: numberOrNull(p.food?.fat) || 0,
        sodium: numberOrNull(p.food?.sodium) || 0,
        potassium: numberOrNull(p.food?.potassium) || 0,
        phosphorus: numberOrNull(p.food?.phosphorus) || 0,
      },
      manualServing: p.portion.manualServing,
      portionControl: p.portion.portionControl,
      nutrients: p.nutrients,
      source: p.food?.source || "fatsecret",
      isEstimated: p.food?.isEstimated === true,
      estimatedNutrients: p.food?.estimatedNutrients || [],
      nutrientSources: p.food?.nutrientSources || {},
      nutrientEstimateNotes: p.food?.nutrientEstimateNotes || {},
      phosphorusReference: p.food?.phosphorusReference || null,
    })),
    totals: roundNutrients({
      calories: totals.calories,
      protein: totals.protein,
      carbohydrate: totals.carbs,
      fat: totals.fat,
      sodium: totals.sodium,
      potassium: totals.potassium,
      phosphorus: totals.phosphorus,
    }),
    iterations: iter,
    satisfied: checkConstraints(totals, mealTargets).allOk,
    mealTargets,
    dailyProteinTarget:
      nutritionProfile?.proteinTarget || numberOrNull(dailyTargets.protein) || null,
    validation: checkConstraints(totals, mealTargets),
  };

  return meal;
}

async function resolveComponentNutrition(plannedMeal, nutritionProfile, restrictions) {
  const componentFoods = [];
  for (const component of plannedMeal.components || []) {
    const result = await searchMealPlanFoods(component, plannedMeal.mealType, 0);
    const detailed = await Promise.all(
      (result.foods || []).slice(0, 8).map(resolveFoodDetails),
    );
    const selected = firstIngredientPresentFood(detailed, component);
    
    console.log("RESOLVE_COMPONENT:", {
      component,
      foundTotal: result.foods?.length || 0,
      selectedName: selected?.name,
      selectedHasNutrition: selected ? usefulNutrition(selected) : false,
      selectedCalories: selected?.calories,
      selectedProtein: selected?.protein
    });
    
    if (selected) componentFoods.push({ ...selected, component });
    if (selected) {
      componentFoods[componentFoods.length - 1].suggestions = componentSuggestions(
        detailed,
        selected,
        component,
      );
    }
  }
  if (!componentFoods.length) return null;
  const totals = nutrientTotals(componentFoods);
  const componentBreakdown = componentBreakdownFromFoods(componentFoods);
  
  // Build meal name from actual FatSecret food names for uniqueness
  const mealNameFromFoods = buildMealTitle({
    foods: componentFoods.map((food) => ({
      ...food,
      category: food.role || food.category || food.component,
    })),
  });
  
  return {
    foodId: componentFoods.map((food) => food.foodId).filter(Boolean).join(","),
    name: mealNameFromFoods || plannedMeal.name,
    portion: "1 planned serving",
    servingDescription: "1 planned serving",
    ...totals,
    componentBreakdown,
    nutrientPreview: roundNutrients(totals),
    score: scoreMealCandidate(
      { ...totals, name: mealNameFromFoods || plannedMeal.name },
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

async function resolvePlannedMeal(plannedMeal, nutritionProfile, restrictions, seed, ingredientRules) {
  // FAST PATH: try to find a single FatSecret serving that already matches
  // the meal protein target (search-first). Falls back to ingredient-based
  // or component resolution if no good single-serving match is found.
  try {
    const singleMatch = await findSingleServingProteinMatch(plannedMeal, nutritionProfile, restrictions, ingredientRules);
    if (singleMatch) return singleMatch;
  } catch (err) {
    console.warn("SINGLE_MATCH_FAILED", { name: plannedMeal?.name, error: err?.message });
  }

  // PREFERRED: Use ingredient expansion if template has protein/carb/vegetable fields
  const hasIngredientFields = plannedMeal.protein || plannedMeal.carb || plannedMeal.grain || plannedMeal.vegetable;
  
  if (hasIngredientFields) {
    const ingredientBased = await resolveIngredientBasedMeal(
      plannedMeal,
      nutritionProfile,
      restrictions,
      ingredientRules,
    );
    if (ingredientBased && ingredientBased.score >= 45) {
      return ingredientBased;
    }
  }

  // FALLBACK: Use old component-based resolution if needed
  const components = await resolveComponentNutrition(
    plannedMeal,
    nutritionProfile,
    restrictions,
  );
  if (components) return components;

  // Last resort: whole meal nutrition search (not recommended)
  const wholeMeal = await resolveWholeMealNutrition(
    plannedMeal,
    nutritionProfile,
    restrictions,
    seed,
    ingredientRules,
  );
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
      "Meal idea selected by CKD guide rules. No matching FatSecret recipe or component nutrition was found yet, so it remains in the plan as a guide for manual review.",
    raw: {
      plannedMeal,
    },
  };
}

function mealFromPortionResult(portioned, date) {
  const nutrients = roundNutrients(portioned.totals);
  const name = buildMealTitle({
    foods: portioned.components.map((component) => ({
      category: component.role,
      displayName: component.displayName || component.ingredient,
      sourceName: component.sourceName || component.name,
    })),
  });
  return {
    date,
    mealType: portioned.mealType,
    foodId: portioned.components.map((component) => component.foodId).filter(Boolean).join(",") || null,
    name,
    portion: "Calculated portions",
    quantity: 1,
    ...nutrients,
    nutrientPreview: nutrients,
    componentBreakdown: portioned.components.map((component) => ({
      component: component.role,
      matchedName: component.name,
      sourceName: component.sourceName || component.name,
      displayName: component.displayName || component.ingredient,
      genericName: component.genericName || component.ingredient,
      foodId: component.foodId || null,
      servingId: component.servingId || null,
      servingDescription: component.servingDescription || "1 serving",
      servingLabel: component.servingDescription || "1 serving",
      servingMetadata: component.servingMetadata || {},
      numberOfServings: component.numberOfServings,
      servingNutrients: component.servingNutrients,
      baseIngredient: component.ingredient,
      portion: component.portion,
      displayAmount: component.portion,
      servings: component.servings,
      manualServing: component.manualServing,
      portionControl: component.portionControl,
      nutrients: roundNutrients(component.nutrients),
      source: component.source,
      isEstimated: component.isEstimated,
      estimatedNutrients: component.estimatedNutrients,
      nutrientSources: component.nutrientSources,
      nutrientEstimateNotes: component.nutrientEstimateNotes,
      phosphorusReference: component.phosphorusReference,
    })),
    recipeValidation: { isAllowed: portioned.satisfied },
    ingredients: portioned.components.map((component) => component.ingredient),
    matchConfidence: "profile_portioned",
    score: portioned.satisfied ? 100 : 0,
    selectionReason:
      "Portions calculated from the CKD nutrition manual, medical profile, and FatSecret nutrients.",
    source: "fatsecret_profile_portioned_meal",
    needsManualReview: false,
    portionControl: {
      satisfied: portioned.satisfied,
      iterations: portioned.iterations,
      targets: portioned.mealTargets,
      validation: portioned.validation,
      plate: portioned.plate,
      dailyProteinTarget: portioned.dailyProteinTarget,
    },
    raw: { template: portioned.template },
  };
}

function mealSignature(meal) {
  return (meal.componentBreakdown || [])
    .map((component) => normalizeTextToken(component.baseIngredient || component.matchedName))
    .filter(Boolean)
    .sort()
    .join("|");
}

async function resolvePortionedMealFromTemplates({
  templates,
  nutritionProfile,
  restrictions,
  nutrientBudgets,
  existingMeals = [],
  date,
  compute = computePortionedMeal,
}) {
  for (const [templateIndex, template] of templates.entries()) {
    mealPlanDebug("TEMPLATE_ATTEMPT", {
      date,
      templateIndex,
      templateCount: templates.length,
      template,
      nutrientBudgets,
      existingMealSignatures: existingMeals.map(mealSignature),
    });
    const portioned = await compute(
      template,
      {},
      nutritionProfile,
      restrictions,
      { maxIterations: 8, maxVariants: 3, nutrientBudgets },
    );
    if (!portioned) {
      mealPlanDebug("TEMPLATE_REJECTED_UNRESOLVED", {
        date,
        templateIndex,
        template,
      });
      continue;
    }
    if (!portioned.satisfied) {
      mealPlanDebug("TEMPLATE_REJECTED_CONSTRAINTS", {
        date,
        templateIndex,
        template,
        totals: portioned.totals,
        targets: portioned.mealTargets,
        validation: portioned.validation,
        components: portioned.components,
      });
      continue;
    }
    const candidate = mealFromPortionResult(portioned, date);
    const signature = mealSignature(candidate);
    if (!signature) {
      mealPlanDebug("TEMPLATE_REJECTED_EMPTY_SIGNATURE", {
        date,
        templateIndex,
        candidate,
      });
      continue;
    }
    if (existingMeals.some((meal) => mealSignature(meal) === signature)) {
      mealPlanDebug("TEMPLATE_REJECTED_DUPLICATE", {
        date,
        templateIndex,
        signature,
        candidate,
      });
      continue;
    }
    mealPlanDebug("TEMPLATE_ACCEPTED", {
      date,
      templateIndex,
      signature,
      candidate,
    });
    return candidate;
  }
  mealPlanDebug("ALL_TEMPLATES_REJECTED", {
    date,
    templateCount: templates.length,
    templates,
    nutrientBudgets,
  });
  return null;
}

function dailyConstraintStatus(totals, nutritionProfile, restrictions) {
  const calorieTarget = numberOrNull(nutritionProfile.calorieTarget);
  const proteinTarget = numberOrNull(nutritionProfile.proteinTarget);
  const sodiumLimit = numberOrNull(restrictions.dailySodiumLimitMg);
  const potassiumLimit = numberOrNull(restrictions.dailyPotassiumLimitMg);
  const phosphorusLimit = numberOrNull(restrictions.dailyPhosphorusLimitMg);
  const caloriesWithinTarget = !calorieTarget ||
    Math.abs(totals.calories - calorieTarget) <= Math.max(100, calorieTarget * 0.2);
  const proteinWithinTarget = !proteinTarget ||
    totals.protein <= proteinTarget + Math.max(2, proteinTarget * 0.1);
  const sodiumWithinLimit = !sodiumLimit || totals.sodium <= sodiumLimit;
  const potassiumWithinLimit = !potassiumLimit || totals.potassium <= potassiumLimit;
  const phosphorusWithinLimit = !phosphorusLimit || totals.phosphorus <= phosphorusLimit;
  return {
    caloriesWithinTarget,
    proteinWithinTarget,
    sodiumWithinLimit,
    potassiumWithinLimit,
    phosphorusWithinLimit,
    allSafetyLimitsMet:
      proteinWithinTarget && sodiumWithinLimit && potassiumWithinLimit && phosphorusWithinLimit,
    allTargetsMet:
      caloriesWithinTarget &&
      proteinWithinTarget &&
      sodiumWithinLimit &&
      potassiumWithinLimit &&
      phosphorusWithinLimit,
  };
}

function refreshMealNutrients(meals, adjustmentFlag) {
  for (const meal of meals) {
    const mealTotals = roundNutrients(
      nutrientTotals((meal.componentBreakdown || []).map((component) => component.nutrients || {})),
    );
    Object.assign(meal, mealTotals, { nutrientPreview: mealTotals });
    if (meal.portionControl && adjustmentFlag) {
      meal.portionControl[adjustmentFlag] = true;
    }
  }
}

function scaleComponentNutrients(component, ratio) {
  const oldServings = numberOrNull(
    component.numberOfServings ?? component.servings,
  ) || 1;
  component.numberOfServings = Number((oldServings * ratio).toFixed(6));
  component.servings = component.numberOfServings;
  component.portion = calculatedServingText(component, component.numberOfServings);
  component.displayAmount = component.portion;
  const scaled = {};
  for (const nutrient of [
    "calories",
    "protein",
    "carbohydrate",
    "fat",
    "sodium",
    "potassium",
    "phosphorus",
  ]) {
    scaled[nutrient] = (numberOrNull(component.nutrients?.[nutrient]) || 0) * ratio;
  }
  component.nutrients = roundNutrients(scaled);
}

function dailySafetyUpperLimits(nutritionProfile = {}, restrictions = {}) {
  const proteinTarget = numberOrNull(nutritionProfile.proteinTarget);
  return {
    protein: proteinTarget
      ? proteinTarget + Math.max(2, proteinTarget * 0.1)
      : null,
    sodium: numberOrNull(restrictions.dailySodiumLimitMg),
    potassium: numberOrNull(restrictions.dailyPotassiumLimitMg),
    phosphorus: numberOrNull(restrictions.dailyPhosphorusLimitMg),
  };
}

function balanceDailyCalories(
  meals,
  calorieTarget,
  maxIterations = 8,
  nutritionProfile = {},
  restrictions = {},
) {
  const target = numberOrNull(calorieTarget);
  if (!target || target <= 0) return { meals, iterations: 0 };
  let iterations = 0;

  while (iterations < maxIterations) {
    const totals = nutrientTotals(meals);
    if (Math.abs(totals.calories - target) <= Math.max(100, target * 0.2)) break;
    const increasingCalories = totals.calories < target;
    const adjustable = meals.flatMap((meal) =>
      (meal.componentBreakdown || [])
        .filter((component) =>
          component.component === "fat" ||
          (component.component === "carb" && !(increasingCalories && nutritionProfile.diabetesRisk)),
        )
        .map((component) => ({ meal, component })),
    );
    const adjustableCalories = adjustable.reduce(
      (sum, item) => sum + (numberOrNull(item.component.nutrients?.calories) || 0),
      0,
    );
    if (adjustableCalories <= 0) break;
    const fixedCalories = totals.calories - adjustableCalories;
    const desiredAdjustableCalories = Math.max(0, target - fixedCalories);
    let ratio = Math.min(1.35, Math.max(0.75, desiredAdjustableCalories / adjustableCalories));
    if (ratio > 1) {
      const safetyLimits = dailySafetyUpperLimits(nutritionProfile, restrictions);
      for (const [nutrient, limit] of Object.entries(safetyLimits)) {
        if (limit === null) continue;
        const adjustableNutrient = adjustable.reduce(
          (sum, item) => sum + (numberOrNull(item.component.nutrients?.[nutrient]) || 0),
          0,
        );
        if (adjustableNutrient <= 0) continue;
        const fixedNutrient = totals[nutrient] - adjustableNutrient;
        const safeRatio = (limit - fixedNutrient) / adjustableNutrient;
        ratio = Math.min(ratio, Math.max(1, safeRatio));
      }
    }
    if (Math.abs(ratio - 1) < 0.01) break;

    for (const { component } of adjustable) {
      scaleComponentNutrients(component, ratio);
    }

    refreshMealNutrients(meals, "calorieBalanced");
    iterations += 1;
  }
  return { meals, iterations };
}

function enforceDailySafetyLimits(
  meals,
  nutritionProfile = {},
  restrictions = {},
  maxIterations = 24,
) {
  const limits = dailySafetyUpperLimits(nutritionProfile, restrictions);
  let iterations = 0;

  while (iterations < maxIterations) {
    const totals = nutrientTotals(meals);
    const failingNutrient = Object.entries(limits)
      .find(([nutrient, limit]) => limit !== null && totals[nutrient] > limit)?.[0];
    if (!failingNutrient) break;

    const limit = limits[failingNutrient];
    const excess = totals[failingNutrient] - limit;
    const candidates = meals
      .flatMap((meal) => (meal.componentBreakdown || []).map((component) => ({ meal, component })))
      .filter(({ component }) => (numberOrNull(component.nutrients?.[failingNutrient]) || 0) > 0)
      .sort((left, right) => {
        const leftProtein = left.component.component === "protein" ? 1 : 0;
        const rightProtein = right.component.component === "protein" ? 1 : 0;
        if (leftProtein !== rightProtein) return leftProtein - rightProtein;
        return (right.component.nutrients[failingNutrient] || 0) -
          (left.component.nutrients[failingNutrient] || 0);
      });
    const culprit = candidates[0]?.component;
    if (!culprit) break;

    const contribution = numberOrNull(culprit.nutrients?.[failingNutrient]) || 0;
    const minimumRatio = 0.5;
    const neededRatio = Math.max(0, (contribution - excess - 0.5) / contribution);
    const ratio = Math.max(minimumRatio, Math.min(0.95, neededRatio));
    if (ratio >= 0.999) break;
    scaleComponentNutrients(culprit, ratio);
    refreshMealNutrients(meals, "safetyAdjusted");
    iterations += 1;
  }

  const totals = roundNutrients(nutrientTotals(meals));
  return {
    meals,
    totals,
    validation: dailyConstraintStatus(totals, nutritionProfile, restrictions),
    iterations,
  };
}

async function enrichMealsWithFluidContributions({
  meals,
  userId,
  childProfileId,
  childContext,
  date,
  previewFood = fatSecretBridge.mealLoggingPreview,
}) {
  let dailyWaterMl = 0;
  for (const meal of meals) {
    let mealWaterMl = 0;
    for (const component of meal.componentBreakdown || []) {
      const foodId = component.foodId;
      const servingId = component.servingId;
      const quantity = numberOrNull(
        component.numberOfServings ?? component.servings,
      );
      if (!foodId || !servingId || quantity === null || quantity <= 0) continue;

      try {
        const previewContext = {
          ...childContext,
          targets: {
            ...(childContext?.targets || {}),
            currentDailyFluidConsumedMl: dailyWaterMl,
          },
        };
        const preview = await previewFood({
          user_id: String(userId),
          child_profile_id: String(childProfileId),
          food_id: String(foodId),
          serving_id: String(servingId),
          quantity,
          meal_type: meal.mealType || "Meal",
          logged_at: `${date}T12:00:00+08:00`,
          child_context: previewContext,
        });
        const fluidContribution =
          preview.fluid_contribution || preview.fluidContribution || {};
        const waterMl = numberOrNull(
          fluidContribution.total_fluid_contribution_ml ??
            fluidContribution.totalFluidContributionMl ??
            fluidContribution.water_content_ml ??
            fluidContribution.waterContentMl,
        ) || 0;
        component.fluidContribution = fluidContribution;
        component.waterMl = waterMl;
        mealWaterMl += waterMl;
        dailyWaterMl += waterMl;
      } catch (error) {
        console.warn("MEAL_PLAN_WATER_PREVIEW_UNAVAILABLE:", {
          foodId,
          servingId,
          error: error.message,
        });
      }
    }
    meal.waterMl = Number(mealWaterMl.toFixed(2));
  }
  return Number(dailyWaterMl.toFixed(2));
}

async function generateMealPlan(body = {}) {
  const userId = body.userId || body.uid;
  const requestedProfileId = body.childProfileId || body.profileUserId || userId;
  const planDate = dateKeyFromBody(body);
  const requestedDays = Number(body.days || body.planDays || body.durationDays || 7);
  const planDays = Math.min(7, Math.max(1, Number.isFinite(requestedDays) ? requestedDays : 7));
  const generationSeed = body.seed ?? `${Date.now()}:${Math.random()}`;
  const seed = hashString(`${requestedProfileId}:${planDate}:${generationSeed}`);
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
  const missingPediatricInputs = [
    ["age", nutritionProfile.ageYears],
    ["sex", nutritionProfile.sex],
    ["weight", nutritionProfile.currentWeightKg],
    ["height", nutritionProfile.heightCm],
  ].filter(([, value]) => value === null || value === undefined || value === "");
  if (missingPediatricInputs.length) {
    const error = new Error(
      `Missing required pediatric profile fields: ${missingPediatricInputs.map(([name]) => name).join(", ")}.`,
    );
    error.statusCode = 422;
    error.code = "pediatric_profile_incomplete";
    throw error;
  }
  nutritionProfile.sodiumLimitMg = numberOrNull(childContext.targets?.sodium);
  nutritionProfile.potassiumLimitMg =
    nutritionProfile.potassiumStatus === "High"
      ? numberOrNull(childContext.targets?.potassium)
      : null;
  nutritionProfile.phosphorusLimitMg =
    nutritionProfile.phosphorusStatus === "High"
      ? numberOrNull(childContext.targets?.phosphorus)
      : null;
  const ingredientRules = buildIngredientRules(nutritionProfile, childContext);
  const history = analyzeFoodHistory(
    await getRecentFoodLogs(userId, requestedProfileId),
    buildFoodRestrictions(nutritionProfile),
  );
  const restrictions = personalizeRestrictions(
    buildFoodRestrictions(nutritionProfile),
    history,
  );
  const mealTypes = nutritionProfile.snackFrequency === 1
    ? ["Breakfast", "AM Snack", "Lunch", "Dinner"]
    : ["Breakfast", "AM Snack", "Lunch", "PM Snack", "Dinner"];
  mealPlanDebug("GENERATION_START", {
    planDate,
    planDays,
    nutritionProfile,
    restrictions,
    ingredientRules,
    mealTypes,
  });

  const days = [];
  for (let dayIndex = 0; dayIndex < planDays; dayIndex += 1) {
    const currentDate = addDays(planDate, dayIndex);
    const daySeed = seed + dayIndex * 97;
    const meals = [];
    for (const [mealIndex, mealType] of mealTypes.entries()) {
      const totalsSoFar = nutrientTotals(meals);
      const nutrientBudgets = {};
      for (const [nutrient, dailyLimit] of [
        ["sodium", restrictions.dailySodiumLimitMg],
        ["potassium", restrictions.dailyPotassiumLimitMg],
        ["phosphorus", restrictions.dailyPhosphorusLimitMg],
      ]) {
        const limit = numberOrNull(dailyLimit);
        if (limit !== null) {
          nutrientBudgets[nutrient] = Math.max(0, limit - totalsSoFar[nutrient]);
        }
      }

      const templates = portionTemplateCandidates(
        mealType,
        nutritionProfile,
        restrictions,
        daySeed,
        mealIndex + dayIndex,
        history,
        ingredientRules,
        5,
      );
      mealPlanDebug("MEAL_RESOLUTION_START", {
        date: currentDate,
        dayIndex,
        mealIndex,
        mealType,
        totalsSoFar,
        nutrientBudgets,
        templates,
      });
      const mealObject = await resolvePortionedMealFromTemplates({
        templates,
        nutritionProfile,
        restrictions,
        nutrientBudgets,
        existingMeals: meals,
        date: currentDate,
      });

      if (!mealObject) {
        mealPlanDebug("MEAL_RESOLUTION_FAILED", {
          date: currentDate,
          dayIndex,
          mealIndex,
          mealType,
          totalsSoFar,
          nutrientBudgets,
          templates,
        });
        const error = new Error(
          `Unable to resolve a complete, profile-safe ${mealType.toLowerCase()} after trying replacement meals.`,
        );
        error.statusCode = 503;
        error.code = "meal_plan_resolution_failed";
        throw error;
      }
      meals.push(mealObject);
    }

    const calorieBalance = balanceDailyCalories(
      meals,
      nutritionProfile.calorieTarget,
      8,
      nutritionProfile,
      restrictions,
    );
    const safetyBalance = enforceDailySafetyLimits(
      calorieBalance.meals,
      nutritionProfile,
      restrictions,
    );
    const dayTotals = safetyBalance.totals;
    const dayValidation = safetyBalance.validation;
    dayValidation.calorieBalanceIterations = calorieBalance.iterations;
    dayValidation.safetyBalanceIterations = safetyBalance.iterations;
    if (!dayValidation.allSafetyLimitsMet) {
      const failedDailyLimits = Object.entries({
        protein: dayValidation.proteinWithinTarget,
        sodium: dayValidation.sodiumWithinLimit,
        potassium: dayValidation.potassiumWithinLimit,
        phosphorus: dayValidation.phosphorusWithinLimit,
      })
        .filter(([, passed]) => passed === false)
        .map(([nutrient]) => nutrient);
      const error = new Error(
        `Unable to generate a complete meal plan within the daily CKD safety limits for ${currentDate}: ${failedDailyLimits.join(", ") || "unknown limit"}.`,
      );
      error.statusCode = 503;
      error.code = "meal_plan_daily_limits_failed";
      error.validation = dayValidation;
      error.totals = dayTotals;
      error.failedDailyLimits = failedDailyLimits;
      throw error;
    }
    mealPlanDebug("DAY_BALANCE_COMPLETE", {
      date: currentDate,
      calorieBalanceIterations: calorieBalance.iterations,
      safetyBalanceIterations: safetyBalance.iterations,
      totals: dayTotals,
      validation: dayValidation,
      meals,
    });
    const dayWaterMl = await enrichMealsWithFluidContributions({
      meals,
      userId,
      childProfileId: requestedProfileId,
      childContext,
      date: currentDate,
    });
    dayTotals.waterMl = dayWaterMl;
    days.push({
      date: currentDate,
      meals,
      totals: dayTotals,
      validation: dayValidation,
    });
  }

  const meals = days[0]?.meals || [];
  const totals = days[0]?.totals || roundNutrients({});
  const weeklyTotals = roundNutrients(
    nutrientTotals(days.flatMap((day) => day.meals || [])),
  );
  weeklyTotals.waterMl = Number(
    days.reduce((sum, day) => sum + (numberOrNull(day.totals?.waterMl) || 0), 0)
      .toFixed(2),
  );

  return {
    planDate,
    planDays,
    nutritionProfile,
    restrictions,
    ingredientRules,
    historyRecommendations: {
      logCount: history.logCount,
      prefer: history.prefer,
      avoid: history.avoid,
      ingredientCounts: history.ingredientCounts,
      ingredientRelations: history.ingredientRelations,
      messages: history.messages,
    },
    mealStructure: mealTypes,
    days,
    meals,
    totals,
    weeklyTotals,
    validation: {
      ...dailyConstraintStatus(totals, nutritionProfile, restrictions),
      generatedFrom: [
        "profile",
        "latest_labs",
        "nutrition_targets",
        "guide_rule_meal_templates",
        "allowed_ingredient_rules",
        "manual_portion_rules",
        "fatsecret_component_resolution",
        "profile_driven_portion_adjustment",
        "automatic_meal_replacement",
        "previous_food_logs",
        "personalized_history_recommendations",
        "ckd_guide_rules",
        "seven_day_seeded_selection",
      ],
    },
    displayMessage:
      "Every meal is portioned from CKD manual rules, verified with FatSecret nutrients, and checked against the medical profile. Unresolved meals are replaced before the plan is returned.",
  };
}

/**
 * Get replacement suggestions for a recipe
 * 
 * User clicks "Grilled Tilapia" → returns similar recipes like:
 * - Fish Stew (90% similar)
 * - Baked Salmon (85% similar)
 * - Fish Soup (80% similar)
 */
async function getRecipeReplacements(selectedRecipe, nutritionProfile, restrictions) {
  try {
    if (!selectedRecipe || !selectedRecipe.name) {
      return {
        success: false,
        error: "No recipe selected",
        suggestions: [],
      };
    }

    // Extract primary ingredient from selected recipe
    const primaryIngredient = ingredientVariants().extractPrimaryFoodName(selectedRecipe.name);
    
    if (!primaryIngredient) {
      return {
        success: false,
        error: "Could not extract ingredient from recipe",
        suggestions: [],
      };
    }

    // Get variants of the primary ingredient
    const variantData = await ingredientVariants().getVariantsForIngredient(primaryIngredient);
    const searchIngredients = [primaryIngredient, ...variantData.variants];

    // Search for recipes with all variants
    const allRecipes = [];
    const seenRecipeIds = new Set();

    for (const ingredient of searchIngredients) {
      try {
        const results = await searchMealPlanRecipes(`${ingredient} recipe`, selectedRecipe.mealType || "Lunch");
        
        if (results.recipes) {
          results.recipes.forEach(recipe => {
            const recipeId = recipe.recipeId || recipe.foodId || recipe.id;
            if (recipeId && !seenRecipeIds.has(recipeId)) {
              seenRecipeIds.add(recipeId);
              allRecipes.push(recipe);
            }
          });
        }
      } catch (err) {
        console.error("REPLACEMENT_SEARCH_ERROR:", { ingredient, error: err.message });
      }
    }

    // Find similar recipes using the variant service
    const similarRecipes = await ingredientVariants().findSimilarRecipes(
      selectedRecipe,
      allRecipes,
      6 // Return top 6 suggestions
    );

    // Score replacements based on medical safety
    const scoredReplacements = similarRecipes
      .map(recipe => ({
        ...recipe,
        medicalScore: scoreMealCandidate(recipe, selectedRecipe.mealType || "Lunch"),
      }))
      .filter(recipe => recipe.medicalScore >= 45) // Must pass safety threshold
      .sort((a, b) => {
        // Primary: Medical score
        if (b.medicalScore !== a.medicalScore) {
          return b.medicalScore - a.medicalScore;
        }
        // Secondary: Similarity to original
        return (b.similarityScore || 0) - (a.similarityScore || 0);
      })
      .slice(0, 5);

    return {
      success: true,
      originalRecipe: {
        name: selectedRecipe.name,
        primaryIngredient,
      },
      suggestions: scoredReplacements,
      variantsExplored: searchIngredients,
      discoveredCount: similarRecipes.length,
    };
  } catch (error) {
    console.error("GET_RECIPE_REPLACEMENTS_ERROR:", {
      recipe: selectedRecipe?.name,
      error: error.message,
    });
    return {
      success: false,
      error: error.message,
      suggestions: [],
    };
  }
}

/**
 * Prewarm the ingredient expansion cache with all common meal ingredients
 * Call this on app startup to populate cache and avoid first-request delays
 */
async function prewarmMealPlanCache() {
  const allIngredients = [...new Set([
    // Common proteins
    "chicken", "fish", "turkey", "beef", "tilapia", "egg", "tofu", "shrimp", "seafood",
    // Common carbs
    "rice", "pasta", "bread", "noodles", "corn", "oatmeal", "barley", "couscous",
    // Common vegetables
    "cabbage", "carrot", "cauliflower", "broccoli", "asparagus", "green beans", "cucumber", "lettuce", "bell pepper", "onion",
    // Common fruits
    "apple", "pear", "berries", "grapes", "peach", "strawberries",
    ...CKD_INGREDIENT_GUIDE.proteins,
    ...CKD_INGREDIENT_GUIDE.carbs,
    ...CKD_INGREDIENT_GUIDE.vegetables,
    ...CKD_INGREDIENT_GUIDE.fruits,
    ...CKD_INGREDIENT_GUIDE.fats,
    ...CKD_INGREDIENT_GUIDE.snacks,
  ])];

  try {
    const results = await ingredientExpansionService.prewarmCache(allIngredients);
    console.log("MEAL_PLAN_CACHE_PREWARMED:", {
      ingredientsCount: results.length,
      totalVariants: results.reduce((sum, r) => sum + r.count, 0),
    });
    return results;
  } catch (error) {
    console.error("PREWARM_CACHE_ERROR:", { error: error.message });
    return [];
  }
}

module.exports = {
  generateMealPlan,
  getRecipeReplacements,
  searchMealPlanRecipesWithVariants,
  prewarmMealPlanCache,
  computePortionedMeal,
  proteinPrescription,
  dailyConstraintStatus,
  balanceDailyCalories,
  enforceDailySafetyLimits,
  resolvePortionedMealFromTemplates,
  buildNutritionProfile,
  buildIngredientRules,
  buildFoodRestrictions,
  guideFoodPool,
  guideFoodTemplates,
  portionTemplateCandidates,
  enrichMealsWithFluidContributions,
};
