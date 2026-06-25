process.env.SKIP_FIREBASE_ADMIN_INIT = "true";
process.env.FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "local-test";
process.env.FIREBASE_CLIENT_EMAIL = process.env.FIREBASE_CLIENT_EMAIL || "test@test.local";
process.env.MEAL_PLAN_DEBUG_LOGS = "false";

const assert = require("assert");
const {
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
  mealTemplateAttemptLimit,
  enrichMealsWithFluidContributions,
  reservedNutrientBudget,
} = require("../services/mealPlanService");
const {
  generateMealPortions,
  buildMealTitle,
  buildIngredientList,
} = require("../services/portionControlService");
const {
  calculateProteinTarget,
  generatePediatricCkdNutrientLimits,
} = require("../services/profileTargetGenerator");

function food(name, nutrients = {}, servingDescription = "100 g") {
  const result = {
    foodId: name.toLowerCase().replace(/\s+/g, "-"),
    name,
    servingDescription,
    calories: 100,
    protein: 2,
    carbohydrate: 10,
    fat: 1,
    sodium: 10,
    potassium: 40,
    phosphorus: 20,
    calcium: 15,
    source: "fatsecret_test",
    ...nutrients,
  };
  result.servings = [{
    serving_id: `${result.foodId}-serving-1`,
    serving_description: result.servingDescription,
    nutrients: {
      calories: result.calories,
      protein: result.protein,
      carbohydrate: result.carbohydrate,
      fat: result.fat,
      sodium: result.sodium,
      potassium: result.potassium,
      phosphorus: result.phosphorus,
      calcium: result.calcium,
    },
  }];
  return result;
}

const foods = {
  chicken: food("Chicken", { calories: 165, protein: 20, carbohydrate: 0, fat: 4 }),
  rice: food("Rice", { calories: 130, protein: 2.5, carbohydrate: 28 }),
  cabbage: food("Cabbage", { calories: 25, protein: 1.3, carbohydrate: 6 }),
  apple: food("Apple", { calories: 52, protein: 0.3, carbohydrate: 14 }),
  grapes: food("Grapes", { calories: 69, protein: 0.7, carbohydrate: 18.1 }),
  egg: food("Egg", { calories: 143, protein: 12.6, carbohydrate: 0.7, fat: 9.5 }),
  tilapia: food("Tilapia", { calories: 128, protein: 26.2, carbohydrate: 0, fat: 2.7 }),
  "olive oil": food("Olive Oil", {
    calories: 119,
    protein: 0,
    carbohydrate: 0,
    fat: 13.5,
    sodium: 0,
    potassium: 0,
    phosphorus: 0,
    calcium: 0,
  }, "1 tbsp"),
};

function adapters(overrides = {}) {
  return {
    expandIngredient: async (ingredient) => [ingredient],
    searchFoods: async (query) => ({ foods: foods[query] ? [foods[query]] : [] }),
    resolveFood: async (candidate) => candidate,
    ...overrides,
  };
}

async function testProteinRules() {
  assert.deepStrictEqual(
    proteinPrescription({ weightKg: 50, dialysisStatus: "pre-dialysis", ckdType: "pre-dialysis" }),
    { gramsPerDay: 35, factor: 0.7, source: "manual_predialysis_fallback" },
  );
  assert.strictEqual(
    proteinPrescription({ weightKg: 50, dialysisStatus: "on dialysis" }).gramsPerDay,
    60,
  );
  assert.strictEqual(
    proteinPrescription({ weightKg: 50, dialysisStatus: "not on dialysis", ckdType: "kidney stone" }).gramsPerDay,
    40,
  );
  assert.strictEqual(
    proteinPrescription({ weightKg: 50, prescribedProtein: 42 }).gramsPerDay,
    42,
  );
}

async function testLegacyPortionMetadataUsesManualServings() {
  const result = generateMealPortions({
    weightKg: 50,
    calorieTarget: 1800,
    dialysisStatus: "not on dialysis",
    mealType: "Lunch",
    ingredientList: ["chicken", "rice", "cabbage", "apple", "olive oil"],
  });
  assert.strictEqual(result.mealProteinTarget, 11.7);
  assert.strictEqual(result.mealCaloriesTarget, null);
  assert.strictEqual(result.portions.find((item) => item.category === "protein").matchboxes, 1.5);
  assert.strictEqual(result.portions.find((item) => item.category === "carb").estimatedPortion, "1/2 cup rice");
  assert.strictEqual(result.portions.find((item) => item.category === "vegetable").estimatedPortion, "1 cup cooked vegetables");
  assert.strictEqual(result.portions.some((item) => "share" in item), false);

  const snack = generateMealPortions({
    weightKg: 50,
    dialysisStatus: "not on dialysis",
    mealType: "AM Snack",
    ingredientList: ["apple"],
  });
  assert.strictEqual(snack.mealProteinTarget, 0);
}

async function testDisplayRulesUseCategoriesNotExampleFoodNames() {
  const foods = [
    { name: "New starch", category: "carb" },
    { name: "New herb", category: "seasoning" },
    { name: "New produce", category: "vegetable" },
    { name: "New protein", category: "protein" },
    { name: "New oil", category: "fat" },
  ];

  assert.strictEqual(
    buildMealTitle({ foods }),
    "New Protein with New Starch and New Produce",
  );
  assert.deepStrictEqual(
    buildIngredientList({ foods }).map((item) => item.category),
    ["protein", "vegetable", "fat", "seasoning", "carb"],
  );
}

async function testProfileTargetsTakePrecedence() {
  const profile = buildNutritionProfile({
    childContext: {
      ckd_stage: "4",
      ckd_type: "pre-dialysis CKD",
      dialysis_status: "Not on dialysis",
      has_diabetes: "yes",
      fluid_restriction_status: "yes",
      targets: {
        protein_max: 42,
        calories: 1600,
        dailyFluidLimitMl: 900,
      },
    },
    labs: { potassium: 5.6, phosphorus: 4.1 },
    anthropometrics: { weight_kg: 50 },
  });
  assert.strictEqual(profile.proteinTarget, 42);
  assert.strictEqual(profile.proteinTargetSource, "clinician_target");
  assert.strictEqual(profile.calorieTarget, 1600);
  assert.strictEqual(profile.diabetesRisk, true);
  assert.strictEqual(profile.potassiumStatus, "High");
  assert.strictEqual(profile.dailyFluidLimitMl, 900);
}

async function testClinicalRiskClassification() {
  const safe = buildNutritionProfile({
    childContext: { dialysis_status: "Not on dialysis", ckd_type: "CKD" },
    labs: { potassium: 5.0, glucose: 100, hba1c: 5.4 },
    anthropometrics: { weight_kg: 50 },
  });
  assert.strictEqual(safe.potassiumControlLevel, "Safe");
  assert.strictEqual(safe.potassiumStatus, "Normal");
  assert.strictEqual(safe.glycemicControlLevel, "Normal");

  const caution = buildNutritionProfile({
    childContext: { dialysis_status: "Not on dialysis", ckd_type: "CKD" },
    labs: { potassium: 5.5, glucose: 140, hba1c: 7.2 },
    anthropometrics: { weight_kg: 50 },
  });
  assert.strictEqual(caution.potassiumControlLevel, "Caution");
  assert.strictEqual(caution.carbohydratePortionScale, 0.75);
  assert.strictEqual(guideFoodPool("fruits", buildIngredientRules(caution, {})).includes("banana"), true);
  assert.strictEqual(buildFoodRestrictions(caution).prefer.includes("banana"), false);

  const mmolGlucose = buildNutritionProfile({
    childContext: { dialysis_status: "Not on dialysis", ckd_type: "CKD" },
    labs: { glucose: 10, glucose_unit: "mmol/L" },
    anthropometrics: { weight_kg: 50 },
  });
  assert.strictEqual(mmolGlucose.glucose, 180.2);
  assert.strictEqual(mmolGlucose.glycemicControlLevel, "High");

  const danger = buildNutritionProfile({
    childContext: { dialysis_status: "On dialysis", ckd_type: "CKD" },
    medicalProfile: { appetite: "Poor", oral_intake_percent: 60 },
    labs: { potassium: 6.1, glucose: 190, hba1c: 9.1 },
    anthropometrics: {
      weight_kg: 55,
      dry_weight_kg: 50,
      weight_change_1_month_percent: -6,
    },
  });
  assert.strictEqual(danger.potassiumControlLevel, "Danger");
  assert.strictEqual(danger.weightKg, 50);
  assert.strictEqual(danger.riskMalnutrition, true);
  assert.strictEqual(danger.snackFrequency, 1);
  assert.strictEqual(guideFoodPool("fruits", buildIngredientRules(danger, {})).includes("banana"), false);
}

async function testPediatricLabBasedNutrientLimits() {
  const limits = generatePediatricCkdNutrientLimits({
    age_years: 14,
    weight_kg: 30,
    potassium: 5.1,
    phosphorus: 4.6,
  });
  assert.deepStrictEqual(limits, {
    dailyPotassiumLimitMg: 1050,
    dailyPhosphateLimitMg: 640,
    dailyCalciumTargetMg: 1300,
    dailyCalciumUpperLimitMg: 2600,
  });

  const normalPotassium = buildNutritionProfile({
    childContext: { age: 8, dialysis_status: "Not on dialysis", ckd_type: "CKD" },
    labs: { potassium: 5.0, phosphorus: 4.4 },
    anthropometrics: { weight_kg: 20 },
  });
  const restrictions = buildFoodRestrictions(normalPotassium);
  assert.strictEqual(normalPotassium.potassiumStatus, "Normal");
  assert.strictEqual(restrictions.dailyPotassiumLimitMg, null);
  assert.strictEqual(restrictions.dailyPhosphorusLimitMg, 800);
  assert.strictEqual(restrictions.dailyCalciumTargetMg, 1000);
  assert.strictEqual(restrictions.dailyCalciumUpperLimitMg, 2000);
}

async function testDialysisNeverUsesLowProteinBranch() {
  assert.deepStrictEqual(
    calculateProteinTarget({ ckdStage: "5D", onDialysis: true }).range,
    [1.0, 1.2],
  );
  assert.deepStrictEqual(
    calculateProteinTarget({ ckdStage: "5D" }).range,
    [1.0, 1.2],
  );
  assert.deepStrictEqual(
    calculateProteinTarget({ ckdStage: "5", dialysisStatus: "Hemodialysis" }).range,
    [1.0, 1.2],
  );
  assert.deepStrictEqual(
    calculateProteinTarget({ ckdStage: "5", onDialysis: true, hasDiabetes: true }).range,
    [1.0, 1.2],
  );
  assert.deepStrictEqual(
    calculateProteinTarget({ ckdStage: "5", onDialysis: false }).range,
    [0.6, 0.8],
  );
}

async function testPediatricRowUsesProvisionalGrowthAwarePlanning() {
  const profile = buildNutritionProfile({
    childContext: {
      age: 14,
      sex: 2,
      race_ethnicity: 2,
      dmdeduc: null,
      indfmpir: 0.52,
      dialysis_status: "Not on dialysis",
      ckd_type: "unknown",
      has_diabetes: false,
      targets: {},
    },
    medicalProfile: { appetite: "Good" },
    anthropometrics: {
      weight_kg: 42.1,
      height_cm: 150.2,
      bmi: 18.7,
      waist_cm: 73.5,
    },
    labs: {
      eGFR_CKD_EPI: 140.22,
      creatinine: 0.54,
      bun: 10,
      uric_acid: 3.2,
      glucose: 86,
      glucose_unit: "mg/dL",
      serum_albumin: 4,
      total_protein: 7.2,
      phosphorus: 4.1,
      sodium: 142,
      potassium: 3.8,
      bicarbonate: 24,
      calcium: 9.5,
      urine_albumin: 6.97,
      urine_creatinine: 39,
      acr: 17.87,
      hba1c: 5.1,
      hemoglobin: 11.7,
      hematocrit: 34,
      wbc: 8.5,
      rbc: 4.25,
      platelets: 344,
      total_cholesterol: 133,
    },
  });

  assert.strictEqual(profile.pediatricMode, true);
  assert.strictEqual(profile.planMode, "growth-aware");
  assert.strictEqual(profile.bmiCategory, "Growth assessment not yet available");
  assert.strictEqual(profile.growthAssessmentComplete, false);
  assert.strictEqual(profile.calorieTarget, 1553);
  assert.strictEqual(profile.calorieTargetSource, "provisional_pediatric_eer");
  assert.strictEqual(profile.warnings.length, 0);
  assert.strictEqual(profile.growthInformation.length, 3);
  assert.strictEqual(profile.growthAssessmentStatus, "Not yet available");
  assert.strictEqual(profile.mealPlanningAvailable, true);
  assert.strictEqual(profile.proteinTargetMin, 33.7);
  assert.strictEqual(profile.proteinTarget, 35.8);
  assert.strictEqual(profile.proteinTargetMax, 37.9);
  assert.strictEqual(profile.potassiumControlLevel, "Safe");
  assert.strictEqual(profile.glycemicControlLevel, "Normal");
}

async function testPediatricRowCanGenerateMealPlan() {
  const profile = buildNutritionProfile({
    childContext: {
      age: 14,
      sex: 2,
      dialysis_status: "Not on dialysis",
      ckd_type: "unknown",
      has_diabetes: false,
      physical_activity_level: "unknown",
      targets: {},
    },
    medicalProfile: { appetite: "Good" },
    anthropometrics: { weight_kg: 42.1, height_cm: 150.2, bmi: 18.7 },
    labs: {
      eGFR_CKD_EPI: 140.22,
      glucose: 86,
      glucose_unit: "mg/dL",
      serum_albumin: 4,
      total_protein: 7.2,
      phosphorus: 4.1,
      sodium: 142,
      potassium: 3.8,
      hba1c: 5.1,
    },
  });
  const restrictions = buildFoodRestrictions(profile);
  const templates = [
    { mealType: "Breakfast", protein: "egg", carb: "rice", fruit: "apple" },
    { mealType: "AM Snack", fruit: "apple" },
    { mealType: "Lunch", protein: "chicken", carb: "rice", vegetable: "cabbage", fat: "olive oil" },
    { mealType: "PM Snack", fruit: "grapes" },
    { mealType: "Dinner", protein: "tilapia", carb: "rice", vegetable: "cabbage", fat: "olive oil" },
  ];
  const meals = [];
  for (const template of templates) {
    const meal = await resolvePortionedMealFromTemplates({
      templates: [template],
      nutritionProfile: profile,
      restrictions,
      nutrientBudgets: {
        sodium: restrictions.dailySodiumLimitMg,
        phosphorus: restrictions.dailyPhosphorusLimitMg,
      },
      existingMeals: meals,
      date: "2026-06-22",
      compute: (candidate, dailyTargets, nutritionProfile, mealRestrictions, options) =>
        computePortionedMeal(candidate, dailyTargets, nutritionProfile, mealRestrictions, {
          ...options,
          adapters: adapters(),
          maxVariants: 1,
        }),
    });
    assert.ok(meal, `${template.mealType} should resolve`);
    meals.push(meal);
  }
  const balanced = balanceDailyCalories(
    meals,
    profile.calorieTarget,
    8,
    profile,
    restrictions,
  );
  const safety = enforceDailySafetyLimits(
    balanced.meals,
    profile,
    restrictions,
  );
  if (process.env.PRINT_PEDIATRIC_PLAN === "true") {
    console.log("PEDIATRIC_PLAN_RESULT", JSON.stringify({
      profile: {
        calorieTarget: profile.calorieTarget,
        proteinTargetMin: profile.proteinTargetMin,
        proteinTarget: profile.proteinTarget,
        proteinTargetMax: profile.proteinTargetMax,
        growthAssessmentStatus: profile.growthAssessmentStatus,
        growthInformation: profile.growthInformation,
      },
      meals: safety.meals.map((meal) => ({
        mealType: meal.mealType,
        name: meal.name,
        calories: meal.calories,
        protein: meal.protein,
        carbohydrate: meal.carbohydrate,
        fat: meal.fat,
        sodium: meal.sodium,
        potassium: meal.potassium,
        phosphorus: meal.phosphorus,
        portions: (meal.componentBreakdown || []).map((component) => ({
          role: component.role || component.component,
          name: component.name || component.ingredient,
          portion: component.portion,
          servings: component.numberOfServings ?? component.servings,
        })),
      })),
      totals: safety.totals,
      validation: safety.validation,
    }, null, 2));
  }
  assert.strictEqual(safety.meals.length, 5);
  assert.strictEqual(safety.validation.allSafetyLimitsMet, true);
  assert.ok(safety.totals.calories > 0);
  assert.strictEqual(typeof safety.validation.caloriesWithinTarget, "boolean");
}

async function testManualPortionsAndProteinSplit() {
  const profile = { calorieTarget: 1800, proteinTarget: 48 };
  const meal = await computePortionedMeal(
    {
      mealType: "Lunch",
      protein: "chicken",
      carb: "rice",
      vegetable: "cabbage",
      fruit: "apple",
      fat: "olive oil",
    },
    {},
    profile,
    { dailySodiumLimitMg: 2000 },
    { adapters: adapters(), nutrientBudgets: { sodium: 1000 }, maxIterations: 8 },
  );

  assert.ok(meal);
  assert.strictEqual(meal.satisfied, true);
  assert.strictEqual(meal.mealTargets.protein, 16);
  assert.ok(
    meal.components.find((item) => item.role === "protein").numberOfServings > 0,
  );
  assert.strictEqual(
    meal.components.find((item) => item.role === "carb").numberOfServings,
    0.5,
  );
  assert.strictEqual(
    meal.components.find((item) => item.role === "carb").portion,
    "50 g",
  );
  assert.strictEqual(
    meal.components.find((item) => item.role === "carb").portionControl.fatSecretServingMultiplier,
    0.5,
  );
  assert.ok(Math.abs(meal.totals.protein - 16) <= 1);
  assert.strictEqual(meal.components.every((item) => item.servingId), true);
  assert.strictEqual(meal.components.every((item) => item.servingDescription), true);
  assert.strictEqual(meal.components.every((item) => item.servingNutrients), true);

  const snack = await computePortionedMeal(
    { mealType: "AM Snack", fruit: "apple" },
    {},
    profile,
    { dailySodiumLimitMg: 2000 },
    { adapters: adapters(), nutrientBudgets: { sodium: 500 } },
  );
  assert.strictEqual(snack.mealTargets.protein, null);
  assert.strictEqual(snack.components.some((item) => item.role === "protein"), false);
}

async function testVariantRetryAndFailure() {
  let searches = 0;
  const grilledChicken = food("Grilled Chicken", {
    calories: 165,
    protein: 20,
    carbohydrate: 0,
    fat: 4,
  });
  const retryAdapters = adapters({
    expandIngredient: async (ingredient) => ingredient === "chicken" ? ["grilled chicken"] : [ingredient],
    searchFoods: async (query) => {
      searches += 1;
      if (query === "chicken") return { foods: [] };
      if (query === "grilled chicken") return { foods: [grilledChicken] };
      return { foods: foods[query] ? [foods[query]] : [] };
    },
  });
  const meal = await computePortionedMeal(
    { mealType: "Dinner", protein: "chicken", carb: "rice", vegetable: "cabbage" },
    { protein: 48, sodium: 2000 },
    null,
    {},
    { adapters: retryAdapters, maxVariants: 3 },
  );
  assert.ok(meal);
  assert.ok(searches >= 4);

  const unresolved = await computePortionedMeal(
    { mealType: "Dinner", protein: "unknown", carb: "rice" },
    { protein: 48, sodium: 2000 },
    null,
    {},
    { adapters: adapters(), maxVariants: 3 },
  );
  assert.strictEqual(unresolved, null);
}

async function testUsesOneFixedReferenceServing() {
  let detailCalls = 0;
  const meal = await computePortionedMeal(
    { mealType: "Lunch", protein: "chicken" },
    { protein: 48, sodium: 2000 },
    null,
    {},
    {
      adapters: adapters({
        resolveFood: async (candidate) => {
          detailCalls += 1;
          return candidate;
        },
      }),
    },
  );
  assert.ok(meal);
  assert.strictEqual(detailCalls, 0);
  assert.strictEqual(meal.components[0].numberOfServings, 0.8);
  assert.strictEqual(meal.components[0].servings, 0.8);
  assert.strictEqual(meal.components[0].nutrients.protein, 16);
  assert.strictEqual(meal.components[0].servingId, "chicken-serving-1");

  const incompleteFoods = Array.from({ length: 10 }, (_, index) => ({
    foodId: `bread-${index}`,
    name: "Bread",
    servingDescription: "1 slice",
    calories: null,
    protein: null,
    carbohydrate: null,
    sodium: null,
  }));
  detailCalls = 0;
  const unresolved = await computePortionedMeal(
    { mealType: "AM Snack", carb: "bread" },
    { sodium: 2000 },
    null,
    {},
    {
      adapters: {
        expandIngredient: async () => ["bread"],
        searchFoods: async () => ({ foods: incompleteFoods }),
        resolveFood: async (candidate) => {
          detailCalls += 1;
          return candidate;
        },
      },
    },
  );
  assert.strictEqual(unresolved, null);
  assert.strictEqual(detailCalls, 5);
}

async function testRiskBasedMissingNutrients() {
  const oilWithMissingMinerals = food("Olive Oil", {
    calories: 119,
    protein: 0,
    carbohydrate: 0,
    fat: null,
    sodium: null,
    potassium: null,
    phosphorus: null,
  });
  const oilMeal = await computePortionedMeal(
    { mealType: "AM Snack", fat: "olive oil" },
    { sodium: 2000, potassium: 3000, phosphorus: 1000 },
    null,
    {},
    {
      adapters: {
        expandIngredient: async (ingredient) => [ingredient],
        searchFoods: async () => ({ foods: [oilWithMissingMinerals] }),
        resolveFood: async (candidate) => candidate,
      },
    },
  );
  assert.ok(oilMeal);
  assert.strictEqual(oilMeal.satisfied, true);
  assert.strictEqual(oilMeal.components[0].nutrientSources.fat, "fat_from_calories_assumption");
  assert.strictEqual(oilMeal.components[0].nutrientSources.phosphorus, "fat_trace_assumption");
  assert.ok(oilMeal.components[0].estimatedNutrients.includes("phosphorus"));

  const chickenWithMissingPhosphorus = food("Chicken", { phosphorus: null });
  const riskyMeal = await computePortionedMeal(
    { mealType: "Lunch", protein: "chicken" },
    { protein: 48, sodium: 2000, phosphorus: 1000 },
    null,
    {},
    {
      adapters: {
        expandIngredient: async (ingredient) => [ingredient],
        searchFoods: async () => ({ foods: [chickenWithMissingPhosphorus] }),
        resolveFood: async (candidate) => candidate,
      },
    },
  );
  assert.strictEqual(riskyMeal, null);

  const firstIncompleteChicken = food("Chicken Breast", {
    protein: 20,
    phosphorus: null,
  });
  const secondIncompleteChicken = food("Cooked Chicken", {
    protein: 20,
    phosphorus: null,
  });
  let fallbackDetailCalls = 0;
  const fallbackMeal = await computePortionedMeal(
    { mealType: "Lunch", protein: "chicken" },
    { protein: 48, sodium: 2000, phosphorus: 1000 },
    null,
    {},
    {
      adapters: {
        expandIngredient: async (ingredient) => [ingredient],
        searchFoods: async () => ({
          foods: [firstIncompleteChicken, secondIncompleteChicken],
        }),
        resolveFood: async (candidate) => {
          fallbackDetailCalls += 1;
          return candidate.foodId === secondIncompleteChicken.foodId
            ? { ...candidate, phosphorus: 180 }
            : candidate;
        },
        resolveFirstServing: async (candidate) => candidate,
      },
    },
  );
  assert.ok(fallbackMeal);
  assert.strictEqual(fallbackDetailCalls, 2);
  assert.strictEqual(fallbackMeal.components[0].nutrients.phosphorus, 144);

  const incompleteServingChicken = food("Chicken Fillet", {
    protein: 20,
    phosphorus: 180,
  });
  const completeServingChicken = food("Cooked Chicken Breast", {
    protein: 20,
    phosphorus: 160,
  });
  let servingCandidateCalls = 0;
  const servingFallbackMeal = await computePortionedMeal(
    { mealType: "Lunch", protein: "chicken" },
    { protein: 48, sodium: 2000, phosphorus: 1000 },
    null,
    {},
    {
      adapters: {
        expandIngredient: async (ingredient) => [ingredient],
        searchFoods: async () => ({
          foods: [incompleteServingChicken, completeServingChicken],
        }),
        resolveFood: async (candidate) => candidate,
        resolveFirstServing: async (candidate) => {
          servingCandidateCalls += 1;
          return candidate.foodId === incompleteServingChicken.foodId
            ? { ...candidate, phosphorus: null }
            : candidate;
        },
      },
    },
  );
  assert.ok(servingFallbackMeal);
  assert.strictEqual(servingCandidateCalls, 2);
  assert.strictEqual(
    servingFallbackMeal.components[0].foodId,
    completeServingChicken.foodId,
  );
}

async function testUsdaBackfillsMissingPhosphorus() {
  const originalFetch = global.fetch;
  const chickenMissingPhosphorus = food("Chicken", {
    protein: 20,
    phosphorus: null,
    missingNutrients: ["phosphorus"],
    needsManualReview: true,
  });
  chickenMissingPhosphorus.servings[0] = {
    ...chickenMissingPhosphorus.servings[0],
    nutrients: {
      ...chickenMissingPhosphorus.servings[0].nutrients,
      phosphorus: null,
    },
  };
  let usdaCalls = 0;
  global.fetch = async (url, options = {}) => {
    usdaCalls += 1;
    assert.ok(String(url).includes("/foods/search"));
    assert.strictEqual(options.method, "POST");
    const body = JSON.parse(options.body);
    assert.deepStrictEqual(body.nutrients, [305]);
    assert.deepStrictEqual(body.dataType, ["Foundation", "SR Legacy", "Survey (FNDDS)"]);
    return {
      ok: true,
      json: async () => ({
        foods: [{
          fdcId: 12345,
          description: "Chicken, cooked",
          dataType: "SR Legacy",
          foodNutrients: [{
            nutrientId: 305,
            nutrientName: "Phosphorus, P",
            value: 190,
          }],
        }],
      }),
    };
  };

  try {
    const meal = await computePortionedMeal(
      { mealType: "Lunch", protein: "chicken" },
      { protein: 48, sodium: 2000, phosphorus: 1000 },
      null,
      {},
      {
        adapters: {
          expandIngredient: async (ingredient) => [ingredient],
          searchFoods: async () => ({ foods: [chickenMissingPhosphorus] }),
        },
      },
    );
    assert.ok(meal);
    assert.ok(usdaCalls >= 1);
    assert.strictEqual(
      meal.components[0].nutrientSources.phosphorus,
      "usda_fooddata_central",
    );
    assert.ok(meal.components[0].nutrients.phosphorus > 0);
    assert.strictEqual(
      (meal.components[0].missingNutrients || []).includes("phosphorus"),
      false,
    );
    assert.notStrictEqual(meal.components[0].needsManualReview, true);
  } finally {
    global.fetch = originalFetch;
  }
}

async function testUsdaPhosphorusLookupFallsBackAfterBadRequest() {
  const originalFetch = global.fetch;
  const turkeyMissingPhosphorus = food("Turkey", {
    protein: 20,
    phosphorus: null,
    missingNutrients: ["phosphorus"],
    needsManualReview: true,
  });
  turkeyMissingPhosphorus.servings[0] = {
    ...turkeyMissingPhosphorus.servings[0],
    nutrients: {
      ...turkeyMissingPhosphorus.servings[0].nutrients,
      phosphorus: null,
    },
  };
  let usdaCalls = 0;
  global.fetch = async (url, options = {}) => {
    usdaCalls += 1;
    assert.ok(String(url).includes("/foods/search"));
    if (options.method === "POST") {
      return {
        ok: false,
        status: 400,
        text: async () => "Invalid search request",
      };
    }
    assert.ok(String(url).includes("nutrients=305"));
    return {
      ok: true,
      json: async () => ({
        foods: [{
          fdcId: 67890,
          description: "Turkey, cooked",
          dataType: "SR Legacy",
          foodNutrients: [{
            nutrientId: 305,
            nutrientName: "Phosphorus, P",
            value: 175,
          }],
        }],
      }),
    };
  };

  try {
    const meal = await computePortionedMeal(
      { mealType: "Lunch", protein: "turkey" },
      { protein: 48, sodium: 2000, phosphorus: 1000 },
      null,
      {},
      {
        adapters: {
          expandIngredient: async (ingredient) => [ingredient],
          searchFoods: async () => ({ foods: [turkeyMissingPhosphorus] }),
        },
      },
    );
    assert.ok(meal);
    assert.strictEqual(usdaCalls, 2);
    assert.strictEqual(
      meal.components[0].nutrientSources.phosphorus,
      "usda_fooddata_central",
    );
    assert.ok(meal.components[0].nutrients.phosphorus > 0);
    assert.strictEqual(
      (meal.components[0].missingNutrients || []).includes("phosphorus"),
      false,
    );
    assert.notStrictEqual(meal.components[0].needsManualReview, true);
  } finally {
    global.fetch = originalFetch;
  }
}

async function testNormalPediatricPhosphorusTargetDoesNotRequirePhosphorusData() {
  const chickenMissingPhosphorus = food("Chicken", {
    protein: 20,
    phosphorus: null,
    missingNutrients: ["phosphorus"],
    needsManualReview: true,
  });
  chickenMissingPhosphorus.servings[0] = {
    ...chickenMissingPhosphorus.servings[0],
    nutrients: {
      ...chickenMissingPhosphorus.servings[0].nutrients,
      phosphorus: null,
    },
  };

  const meal = await computePortionedMeal(
    { mealType: "Lunch", protein: "chicken" },
    { protein: 48, sodium: 2000, phosphorus: 1250 },
    {
      calorieTarget: 1700,
      proteinTarget: 48,
      phosphorusStatus: "Normal",
      potassiumStatus: "Normal",
    },
    {
      dailySodiumLimitMg: 2000,
      dailyPhosphorusLimitMg: 1250,
    },
    {
      nutrientBudgets: {
        sodium: 600,
        phosphorus: 300,
      },
      adapters: {
        expandIngredient: async (ingredient) => [ingredient],
        searchFoods: async () => ({ foods: [chickenMissingPhosphorus] }),
        resolveFirstServing: async (candidate) => ({
          ...candidate,
          servingId: candidate.servings[0].serving_id,
          servingDescription: candidate.servings[0].serving_description,
          firstServing: candidate.servings[0],
        }),
      },
    },
  );

  assert.ok(meal);
  assert.strictEqual(meal.mealTargets.phosphorus, null);
  assert.ok(meal.components[0].nutrients.protein > 0);
}

async function testNonProteinUsesOneFirstServing() {
  const tablespoonOil = food("Olive Oil", {
    servingDescription: "1 tbsp",
    calories: 119,
    protein: 0,
    carbohydrate: 0,
    fat: 13.5,
    sodium: 0,
    potassium: 0,
    phosphorus: null,
  });
  tablespoonOil.servings.push({
    serving_id: "olive-oil-serving-2",
    serving_description: "100 g",
    nutrients: { calories: 900, fat: 100, sodium: 0 },
  });
  const meal = await computePortionedMeal(
    { mealType: "AM Snack", fat: "olive oil" },
    { sodium: 2000 },
    null,
    {},
    {
      adapters: {
        expandIngredient: async (ingredient) => [ingredient],
        searchFoods: async () => ({ foods: [tablespoonOil] }),
        resolveFood: async (candidate) => candidate,
      },
    },
  );
  assert.ok(meal);
  assert.strictEqual("grams" in meal.components[0], false);
  assert.strictEqual(meal.components[0].numberOfServings, 1);
  assert.strictEqual(meal.components[0].servings, 1);
  assert.strictEqual(meal.components[0].servingId, "olive-oil-serving-1");
  assert.strictEqual(meal.totals.calories, 119);
  assert.strictEqual(meal.totals.fat, 13.5);
}

async function testVegetableAndFruitGuidelineConversions() {
  const cabbage100g = food("Cabbage", {
    servingDescription: "100 g",
    calories: 25,
    protein: 1.3,
    carbohydrate: 6,
  });
  cabbage100g.servings[0] = {
    ...cabbage100g.servings[0],
    serving_description: "100 g",
    number_of_units: 100,
    measurement_description: "g",
    metric_serving_amount: 100,
    metric_serving_unit: "g",
  };
  cabbage100g.servings.push({
    serving_id: "cabbage-cup",
    serving_description: "1 cup cooked",
    number_of_units: 1,
    measurement_description: "cup",
    metric_serving_amount: 150,
    metric_serving_unit: "g",
    nutrients: {
      calories: 38,
      protein: 2,
      carbohydrate: 9,
      fat: 0,
      sodium: 15,
      potassium: 60,
      phosphorus: 30,
    },
  });
  const vegetableMeal = await computePortionedMeal(
    { mealType: "Lunch", vegetable: "cabbage" },
    { sodium: 2000 },
    null,
    {},
    {
      adapters: {
        expandIngredient: async (ingredient) => [ingredient],
        searchFoods: async () => ({ foods: [cabbage100g] }),
        resolveFood: async (candidate) => candidate,
      },
    },
  );
  assert.ok(vegetableMeal);
  assert.strictEqual(vegetableMeal.components[0].servingId, "cabbage-cup");
  assert.strictEqual(vegetableMeal.components[0].numberOfServings, 1);
  assert.strictEqual(vegetableMeal.components[0].portion, "1 cup (150 g)");

  const apple100g = food("Apple", {
    servingDescription: "100 g",
    calories: 52,
    protein: 0.3,
    carbohydrate: 14,
  });
  apple100g.servings[0] = {
    ...apple100g.servings[0],
    serving_description: "100 g",
    number_of_units: 100,
    measurement_description: "g",
    metric_serving_amount: 100,
    metric_serving_unit: "g",
  };
  const fruitMeal = await computePortionedMeal(
    { mealType: "AM Snack", fruit: "apple" },
    { sodium: 2000 },
    null,
    {},
    {
      adapters: {
        expandIngredient: async (ingredient) => [ingredient],
        searchFoods: async () => ({ foods: [apple100g] }),
        resolveFood: async (candidate) => candidate,
      },
    },
  );
  assert.ok(fruitMeal);
  assert.strictEqual(fruitMeal.components[0].numberOfServings, 0.75);
  assert.strictEqual(fruitMeal.components[0].portion, "75 g");
}

async function testMealPlanUsesFoodLogWaterPreview() {
  const meals = [{
    mealType: "AM Snack",
    componentBreakdown: [{
      foodId: "strawberries",
      servingId: "strawberries-serving-1",
      numberOfServings: 0.6,
    }],
  }];
  let previewPayload = null;
  const waterMl = await enrichMealsWithFluidContributions({
    meals,
    userId: "user-1",
    childProfileId: "child-1",
    childContext: { targets: { dailyFluidLimitMl: 1000 } },
    date: "2026-06-21",
    previewFood: async (payload) => {
      previewPayload = payload;
      return {
        fluid_contribution: {
          water_data_available: true,
          total_fluid_contribution_ml: 42.5,
        },
      };
    },
  });
  assert.strictEqual(previewPayload.food_id, "strawberries");
  assert.strictEqual(previewPayload.serving_id, "strawberries-serving-1");
  assert.strictEqual(previewPayload.quantity, 0.6);
  assert.strictEqual(waterMl, 42.5);
  assert.strictEqual(meals[0].waterMl, 42.5);
  assert.strictEqual(meals[0].componentBreakdown[0].waterMl, 42.5);
}

async function testDailySafetyValidation() {
  const status = dailyConstraintStatus(
    { calories: 1700, protein: 48, sodium: 1900, potassium: 2900, phosphorus: 900 },
    { calorieTarget: 1800, proteinTarget: 48 },
    { dailySodiumLimitMg: 2000, dailyPotassiumLimitMg: 3000, dailyPhosphorusLimitMg: 1000 },
  );
  assert.strictEqual(status.allSafetyLimitsMet, true);
  assert.strictEqual(status.caloriesWithinTarget, true);
  assert.strictEqual(
    dailyConstraintStatus(
      { calories: 1700, protein: 48, sodium: 2100, potassium: 2900, phosphorus: 900 },
      { calorieTarget: 1800, proteinTarget: 48 },
      { dailySodiumLimitMg: 2000 },
    ).allSafetyLimitsMet,
    false,
  );
}

async function testDailyCalorieBalancing() {
  const meals = [{
    calories: 300,
    protein: 10,
    carbohydrate: 30,
    fat: 5,
    sodium: 100,
    potassium: 100,
    phosphorus: 50,
    componentBreakdown: [
      {
        component: "protein",
        portion: "100 g",
        grams: 100,
        servings: 1,
        nutrients: {
          calories: 200,
          protein: 8,
          carbohydrate: 8,
          fat: 4,
          sodium: 95,
          potassium: 80,
          phosphorus: 40,
        },
      },
      {
        component: "carb",
        portion: "50 g",
        grams: 50,
        servings: 0.5,
        nutrients: {
          calories: 100,
          protein: 2,
          carbohydrate: 22,
          fat: 1,
          sodium: 5,
          potassium: 20,
          phosphorus: 10,
        },
      },
    ],
    portionControl: {},
  }];
  const result = balanceDailyCalories(meals, 500, 8);
  assert.ok(result.iterations > 0);
  assert.ok(meals[0].calories > 100);
  assert.notStrictEqual(meals[0].componentBreakdown[1].portion, "50 g");
}

async function testDailyBalancingPreservesSafetyLimits() {
  const meals = [{
    calories: 300,
    protein: 10,
    carbohydrate: 30,
    fat: 5,
    sodium: 100,
    potassium: 100,
    phosphorus: 50,
    componentBreakdown: [
      {
        component: "protein",
        portion: "100 g",
        grams: 100,
        manualGrams: 100,
        servings: 1,
        nutrients: { calories: 200, protein: 8, sodium: 95 },
      },
      {
        component: "carb",
        portion: "50 g",
        grams: 50,
        manualGrams: 50,
        servings: 0.5,
        nutrients: { calories: 100, protein: 2, carbohydrate: 22, sodium: 5 },
      },
    ],
    portionControl: {},
  }];
  balanceDailyCalories(meals, 600, 8, { proteinTarget: 10 }, { dailySodiumLimitMg: 2000 });
  assert.ok(meals[0].protein <= 12);

  meals[0].componentBreakdown[1].nutrients.sodium = 2500;
  meals[0].sodium = 2595;
  const repaired = enforceDailySafetyLimits(
    meals,
    { proteinTarget: 10 },
    { dailySodiumLimitMg: 2000 },
  );
  assert.strictEqual(repaired.validation.allSafetyLimitsMet, true);
  assert.ok(repaired.iterations > 0);
}

async function testTemplateReplacement() {
  const templates = [
    { mealType: "Lunch", protein: "missing" },
    { mealType: "Lunch", protein: "chicken" },
  ];
  const attempted = [];
  const replacement = await resolvePortionedMealFromTemplates({
    templates,
    nutritionProfile: { proteinTarget: 48 },
    restrictions: {},
    nutrientBudgets: {},
    date: "2026-06-20",
    compute: async (template) => {
      attempted.push(template.protein);
      if (template.protein === "missing") return null;
      return {
        mealType: "Lunch",
        template,
        plate: { vegetables: 0.5, protein: 0.25, carbs: 0.25 },
        components: [{
          role: "protein",
          ingredient: "chicken",
          name: "Chicken Breast",
          portion: "70 g",
          grams: 70,
          servings: 0.7,
          nutrients: foods.chicken,
          source: "fatsecret_test",
        }],
        totals: foods.chicken,
        iterations: 0,
        satisfied: true,
        mealTargets: { protein: 16 },
        validation: { allOk: true },
        dailyProteinTarget: 48,
      };
    },
  });
  assert.deepStrictEqual(attempted, ["missing", "chicken"]);
  assert.strictEqual(replacement.name, "Chicken");
  assert.notStrictEqual(replacement.name, "Food");
  assert.strictEqual(replacement.matchConfidence, "profile_portioned");

  const unresolved = await resolvePortionedMealFromTemplates({
    templates,
    nutritionProfile: {},
    restrictions: {},
    nutrientBudgets: {},
    date: "2026-06-20",
    compute: async () => null,
  });
  assert.strictEqual(unresolved, null);
}

function testRemainingMealBudgetReservation() {
  const mealTypes = ["Breakfast", "AM Snack", "Lunch", "PM Snack", "Dinner"];
  const breakfastBudget = reservedNutrientBudget({
    dailyLimit: 2000,
    consumed: 0,
    mealType: "Breakfast",
    remainingMealTypes: mealTypes,
  });
  assert.strictEqual(breakfastBudget, 541);

  const dinnerBudget = reservedNutrientBudget({
    dailyLimit: 2000,
    consumed: 1200,
    mealType: "Dinner",
    remainingMealTypes: ["Dinner"],
  });
  assert.strictEqual(dinnerBudget, 800);

  const snackBudget = reservedNutrientBudget({
    dailyLimit: 1000,
    consumed: 0,
    mealType: "AM Snack",
    remainingMealTypes: ["AM Snack", "Lunch", "PM Snack", "Dinner"],
  });
  assert.strictEqual(snackBudget, 130);
  assert.strictEqual(
    reservedNutrientBudget({
      dailyLimit: null,
      mealType: "Dinner",
      remainingMealTypes: ["Dinner"],
    }),
    null,
  );
}

function testMealTemplateAttemptLimitBroadensBreakfastRecovery() {
  assert.strictEqual(mealTemplateAttemptLimit("Breakfast", 21), 16);
  assert.strictEqual(mealTemplateAttemptLimit("AM Snack", 21), 10);
  assert.strictEqual(mealTemplateAttemptLimit("Lunch", 21), 14);
  assert.strictEqual(mealTemplateAttemptLimit("Breakfast", 4), 4);
}

async function testPhilippineGuideFoodListAndVariety() {
  const rules = buildIngredientRules(
    { potassiumStatus: "Normal", phosphorusStatus: "Normal" },
    {},
  );
  assert.ok(guideFoodPool("carbs", rules).includes("unsweetened suman"));
  assert.ok(guideFoodPool("proteins", rules).includes("lean beef lomo"));
  assert.ok(guideFoodPool("proteins", rules).includes("cheese"));
  assert.ok(guideFoodPool("vegetables", rules).includes("ampalaya"));
  assert.ok(guideFoodPool("fruits", rules).includes("star apple"));
  assert.ok(guideFoodPool("fruits", rules).includes("calamansi"));
  assert.ok(guideFoodPool("fats", rules).includes("light mayonnaise"));

  const guideTemplates = guideFoodTemplates("Lunch", rules);
  assert.ok(guideTemplates.length > 10);
  assert.ok(guideTemplates.every((template) => template.source === "psn_ckd_food_list_template"));

  const selectedFats = new Set();
  for (let seed = 0; seed < 40; seed += 1) {
    const candidates = portionTemplateCandidates(
      "Lunch",
      {},
      { avoid: [] },
      seed,
      seed,
      {},
      rules,
      5,
    );
    candidates.forEach((candidate) => selectedFats.add(candidate.fat));
  }
  assert.ok(selectedFats.size > 3);

  const highPotassiumRules = buildIngredientRules(
    { potassiumStatus: "High", potassiumControlLevel: "Danger", phosphorusStatus: "Normal" },
    {},
  );
  assert.strictEqual(guideFoodPool("fruits", highPotassiumRules).includes("banana"), false);

  const highPhosphorusRules = buildIngredientRules(
    { potassiumStatus: "Normal", phosphorusStatus: "High" },
    {},
  );
  assert.strictEqual(guideFoodPool("proteins", highPhosphorusRules).includes("cheese"), false);
  assert.strictEqual(guideFoodPool("proteins", highPhosphorusRules).includes("beans"), false);
  assert.strictEqual(guideFoodPool("proteins", highPhosphorusRules).includes("lean beef"), false);
  assert.strictEqual(guideFoodPool("proteins", highPhosphorusRules).includes("egg"), true);
  assert.strictEqual(guideFoodPool("proteins", highPhosphorusRules).includes("salmon"), false);
  assert.strictEqual(guideFoodPool("fruits", highPhosphorusRules).includes("berries"), false);
  assert.strictEqual(guideFoodPool("fruits", highPhosphorusRules).includes("apple"), true);
  assert.strictEqual(guideFoodPool("carbs", highPhosphorusRules).includes("white rice"), true);
  assert.strictEqual(guideFoodPool("fats", highPhosphorusRules).includes("oil"), true);
  assert.ok(
    guideFoodTemplates("Breakfast", highPhosphorusRules).every((template) =>
      highPhosphorusRules.allowedProteinIngredients.includes(template.protein),
    ),
  );
}

async function run() {
  await testProteinRules();
  await testLegacyPortionMetadataUsesManualServings();
  await testDisplayRulesUseCategoriesNotExampleFoodNames();
  await testProfileTargetsTakePrecedence();
  await testClinicalRiskClassification();
  await testPediatricLabBasedNutrientLimits();
  await testDialysisNeverUsesLowProteinBranch();
  await testPediatricRowUsesProvisionalGrowthAwarePlanning();
  await testPediatricRowCanGenerateMealPlan();
  await testManualPortionsAndProteinSplit();
  await testVariantRetryAndFailure();
  await testUsesOneFixedReferenceServing();
  await testRiskBasedMissingNutrients();
  await testUsdaBackfillsMissingPhosphorus();
  await testUsdaPhosphorusLookupFallsBackAfterBadRequest();
  await testNormalPediatricPhosphorusTargetDoesNotRequirePhosphorusData();
  await testNonProteinUsesOneFirstServing();
  await testVegetableAndFruitGuidelineConversions();
  await testMealPlanUsesFoodLogWaterPreview();
  await testDailySafetyValidation();
  await testDailyCalorieBalancing();
  await testDailyBalancingPreservesSafetyLimits();
  await testTemplateReplacement();
  testRemainingMealBudgetReservation();
  testMealTemplateAttemptLimitBroadensBreakfastRecovery();
  await testPhilippineGuideFoodListAndVariety();
  console.log("computePortionedMeal tests passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
