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
  guideFoodPool,
  guideFoodTemplates,
  portionTemplateCandidates,
  enrichMealsWithFluidContributions,
} = require("../services/mealPlanService");
const {
  generateMealPortions,
  buildMealTitle,
  buildIngredientList,
} = require("../services/portionControlService");

function food(name, nutrients = {}) {
  const result = {
    foodId: name.toLowerCase().replace(/\s+/g, "-"),
    name,
    servingDescription: "100 g",
    calories: 100,
    protein: 2,
    carbohydrate: 10,
    fat: 1,
    sodium: 10,
    potassium: 40,
    phosphorus: 20,
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
    },
  }];
  return result;
}

const foods = {
  chicken: food("Chicken", { calories: 165, protein: 20, carbohydrate: 0, fat: 4 }),
  rice: food("Rice", { calories: 130, protein: 2.5, carbohydrate: 28 }),
  cabbage: food("Cabbage", { calories: 25, protein: 1.3, carbohydrate: 6 }),
  apple: food("Apple", { calories: 52, protein: 0.3, carbohydrate: 14 }),
  "olive oil": food("Olive Oil", { calories: 119, protein: 0, carbohydrate: 0, fat: 13.5 }),
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
    labs: { potassium_status: "high", phosphorus_status: "normal" },
    anthropometrics: { weight_kg: 50 },
  });
  assert.strictEqual(profile.proteinTarget, 42);
  assert.strictEqual(profile.proteinTargetSource, "clinician_target");
  assert.strictEqual(profile.calorieTarget, 1600);
  assert.strictEqual(profile.diabetesRisk, true);
  assert.strictEqual(profile.potassiumStatus, "High");
  assert.strictEqual(profile.dailyFluidLimitMl, 900);
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
  assert.strictEqual(detailCalls, 1);
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
    { potassiumStatus: "High", phosphorusStatus: "Normal" },
    {},
  );
  assert.strictEqual(guideFoodPool("fruits", highPotassiumRules).includes("banana"), false);

  const highPhosphorusRules = buildIngredientRules(
    { potassiumStatus: "Normal", phosphorusStatus: "High" },
    {},
  );
  assert.strictEqual(guideFoodPool("proteins", highPhosphorusRules).includes("cheese"), false);
  assert.strictEqual(guideFoodPool("proteins", highPhosphorusRules).includes("beans"), false);
}

async function run() {
  await testProteinRules();
  await testLegacyPortionMetadataUsesManualServings();
  await testDisplayRulesUseCategoriesNotExampleFoodNames();
  await testProfileTargetsTakePrecedence();
  await testManualPortionsAndProteinSplit();
  await testVariantRetryAndFailure();
  await testUsesOneFixedReferenceServing();
  await testRiskBasedMissingNutrients();
  await testNonProteinUsesOneFirstServing();
  await testMealPlanUsesFoodLogWaterPreview();
  await testDailySafetyValidation();
  await testDailyCalorieBalancing();
  await testDailyBalancingPreservesSafetyLimits();
  await testTemplateReplacement();
  await testPhilippineGuideFoodListAndVariety();
  console.log("computePortionedMeal tests passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
