process.env.SKIP_FIREBASE_ADMIN_INIT = "true";
process.env.FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "local-test";
process.env.FIREBASE_CLIENT_EMAIL = process.env.FIREBASE_CLIENT_EMAIL || "test@test.local";

const assert = require("assert");
const {
  computePortionedMeal,
  proteinPrescription,
  dailyConstraintStatus,
  balanceDailyCalories,
  resolvePortionedMealFromTemplates,
  buildNutritionProfile,
} = require("../services/mealPlanService");
const { generateMealPortions } = require("../services/portionControlService");

function food(name, nutrients = {}) {
  return {
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
  assert.match(meal.components.find((item) => item.role === "protein").portion, /^\d+ g \(2\.0 matchbox/);
  assert.ok(Math.abs(meal.totals.protein - 16) <= 1);
  assert.strictEqual(meal.components.find((item) => item.role === "carb").manualServing, "1/2 cup rice");
  assert.strictEqual(meal.components.find((item) => item.role === "vegetable").manualServing, "1 cup cooked");
  assert.strictEqual(meal.components.find((item) => item.role === "fruit").manualServing, "1 small fruit or 1/2 cup");
  assert.strictEqual(meal.components.find((item) => item.role === "fat").manualServing, "1 tsp");

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
  assert.ok(meal.components[0].servings > 0);

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
    fat: 13.5,
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
  assert.strictEqual(replacement.name, "Chicken Breast");
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

async function run() {
  await testProteinRules();
  await testLegacyPortionMetadataUsesManualServings();
  await testProfileTargetsTakePrecedence();
  await testManualPortionsAndProteinSplit();
  await testVariantRetryAndFailure();
  await testUsesOneFixedReferenceServing();
  await testRiskBasedMissingNutrients();
  await testDailySafetyValidation();
  await testDailyCalorieBalancing();
  await testTemplateReplacement();
  console.log("computePortionedMeal tests passed");
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
