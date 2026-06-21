const assert = require("assert");
const {
  normalizeNutrients,
  parseNutrientNumber,
  isWaterLog,
} = require("../services/nutrientNormalizer");

assert.strictEqual(parseNutrientNumber("1,250 mg"), 1250);
assert.strictEqual(parseNutrientNumber({ value: "12.5 g" }), 12.5);

const aliases = normalizeNutrients({
  nutrientPreview: {
    calories: "210 kcal",
    protein_g: "12 g",
    carbs: "31.5 g",
    sodium_mg: "440 mg",
    phosphorous: "90 mg",
  },
});
assert.deepStrictEqual(aliases.nutrients, {
  calories: 210,
  protein: 12,
  carbohydrate: 31.5,
  fat: 0,
  sodium: 440,
  potassium: 0,
  phosphorus: 90,
});

const selectedServing = normalizeNutrients({
  servingId: "serving-2",
  quantity: 1.5,
  calories: 0,
  protein: 0,
  raw: {
    servings: [
      { serving_id: "serving-1", nutrients: { calories: 100, protein: 2 } },
      { serving_id: "serving-2", nutrients: { calories: 180, protein: 8 } },
    ],
  },
});
assert.strictEqual(selectedServing.nutrients.calories, 270);
assert.strictEqual(selectedServing.nutrients.protein, 12);

const updatedValueWins = normalizeNutrients({
  calories: 240,
  finalNutrients: { calories: 120 },
});
assert.strictEqual(updatedValueWins.nutrients.calories, 240);

const components = normalizeNutrients({
  finalNutrients: { calories: 0, protein: 0 },
  raw: {
    componentBreakdown: [
      { nutrients: { calories: 100, protein: 8, carbs: 4 } },
      { nutrientPreview: { calories: 70, protein: 2, carbohydrate: 14 } },
    ],
  },
});
assert.strictEqual(components.nutrients.calories, 170);
assert.strictEqual(components.nutrients.protein, 10);
assert.strictEqual(components.nutrients.carbohydrate, 18);

assert.strictEqual(normalizeNutrients({ name: "Unknown", calories: 0 }).isAllZero, true);
assert.strictEqual(isWaterLog({ name: "Plain Water" }), true);

console.log("nutrientNormalizer tests passed");
