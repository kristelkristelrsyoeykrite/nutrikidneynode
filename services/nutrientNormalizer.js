const CORE_NUTRIENTS = Object.freeze([
  "calories",
  "protein",
  "carbohydrate",
  "fat",
  "sodium",
  "potassium",
  "phosphorus",
]);

const NUTRIENT_ALIASES = Object.freeze({
  calories: ["calories", "calorie", "energy", "energy_kcal", "energyKcal"],
  protein: ["protein", "protein_g", "proteinG"],
  carbohydrate: [
    "carbohydrate",
    "carbohydrates",
    "carbs",
    "carb",
    "carbohydrate_g",
    "carbohydrateG",
  ],
  fat: ["fat", "total_fat", "totalFat", "fat_g", "fatG"],
  sodium: ["sodium", "sodium_mg", "sodiumMg"],
  potassium: ["potassium", "potassium_mg", "potassiumMg"],
  phosphorus: [
    "phosphorus",
    "phosphorous",
    "phosphorus_mg",
    "phosphorusMg",
  ],
});

function parseNutrientNumber(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (value === null || value === undefined || value === "") return null;
  if (typeof value === "object") {
    return parseNutrientNumber(
      value.value ?? value.amount ?? value.total ?? value.quantity,
    );
  }
  const match = String(value).replace(/,/g, "").match(/-?\d+(?:\.\d+)?/);
  if (!match) return null;
  const parsed = Number(match[0]);
  return Number.isFinite(parsed) ? parsed : null;
}

function nutrientValue(source, nutrient) {
  if (!source || typeof source !== "object" || Array.isArray(source)) return null;
  for (const alias of NUTRIENT_ALIASES[nutrient]) {
    const parsed = parseNutrientNumber(source[alias]);
    if (parsed !== null) return parsed;
  }
  return null;
}

function unwrapNutrientObject(source) {
  if (!source || typeof source !== "object" || Array.isArray(source)) return null;
  return source.firstNormalized || source.first_normalized || source.nutrients || source;
}

function servingLists(source) {
  if (!source || typeof source !== "object") return [];
  const possible = [
    source.servings,
    source.food?.servings,
    source.result?.servings,
    source.raw?.servings,
  ];
  const lists = [];
  for (const value of possible) {
    if (Array.isArray(value)) lists.push(value);
    else if (Array.isArray(value?.serving)) lists.push(value.serving);
    else if (value?.serving && typeof value.serving === "object") {
      lists.push([value.serving]);
    }
  }
  return lists;
}

function selectedServingCandidate(payload) {
  const servingId = String(
    payload.selectedServingId ?? payload.servingId ?? payload.serving_id ?? "",
  );
  const quantity = parseNutrientNumber(
    payload.selectedQuantity ?? payload.quantity,
  ) || 1;

  for (const source of [payload, payload.raw]) {
    for (const servings of servingLists(source)) {
      const selected = servings.find((serving) =>
        servingId && String(serving.serving_id ?? serving.servingId ?? "") === servingId,
      ) || (servings.length === 1 ? servings[0] : null);
      if (selected) {
        return { source: unwrapNutrientObject(selected), multiplier: quantity };
      }
    }
  }
  return null;
}

function componentCandidate(payload) {
  const lists = [
    payload.componentBreakdown,
    payload.component_breakdown,
    payload.components,
    payload.raw?.componentBreakdown,
    payload.raw?.component_breakdown,
    payload.raw?.components,
  ];
  const components = lists.find(Array.isArray);
  if (!components?.length) return null;

  const totals = Object.fromEntries(CORE_NUTRIENTS.map((key) => [key, 0]));
  let found = false;
  for (const component of components) {
    const normalized = normalizeNutrients(component, { includeComponents: false });
    if (!normalized.hasAnyValue) continue;
    found = true;
    for (const key of CORE_NUTRIENTS) totals[key] += normalized.nutrients[key];
  }
  return found ? totals : null;
}

function candidateSources(payload, includeComponents) {
  const raw = payload.raw && typeof payload.raw === "object" ? payload.raw : {};
  const candidates = [
    payload,
    payload.finalNutrients,
    payload.final_nutrients,
    payload.nutrientPreview,
    payload.nutrient_preview,
    payload.nutrients,
    raw.finalNutrients,
    raw.final_nutrients,
    raw.nutrientPreview,
    raw.nutrient_preview,
    raw.nutrients,
    raw.firstNormalized,
    raw.first_normalized,
  ].map(unwrapNutrientObject).filter(Boolean).map((source) => ({ source, multiplier: 1 }));

  const selectedServing = selectedServingCandidate(payload);
  if (selectedServing) candidates.push(selectedServing);
  if (includeComponents) {
    const components = componentCandidate(payload);
    if (components) candidates.push({ source: components, multiplier: 1 });
  }
  return candidates;
}

function normalizeNutrients(payload = {}, options = {}) {
  const includeComponents = options.includeComponents !== false;
  const values = Object.fromEntries(CORE_NUTRIENTS.map((key) => [key, []]));

  for (const candidate of candidateSources(payload, includeComponents)) {
    for (const nutrient of CORE_NUTRIENTS) {
      const value = nutrientValue(candidate.source, nutrient);
      if (value !== null) values[nutrient].push(value * candidate.multiplier);
    }
  }

  const nutrients = {};
  let hasAnyValue = false;
  for (const nutrient of CORE_NUTRIENTS) {
    const candidates = values[nutrient];
    hasAnyValue ||= candidates.length > 0;
    nutrients[nutrient] = candidates.find((value) => value !== 0) ?? candidates[0] ?? 0;
  }

  const hasNutrition = CORE_NUTRIENTS.some((key) => nutrients[key] !== 0);
  return { nutrients, hasAnyValue, hasNutrition, isAllZero: !hasNutrition };
}

function isWaterLog(payload = {}) {
  const name = String(payload.name ?? payload.foodName ?? payload.food_name ?? "")
    .trim()
    .toLowerCase();
  return name === "water" || /\b(drinking water|plain water)\b/.test(name);
}

module.exports = {
  CORE_NUTRIENTS,
  NUTRIENT_ALIASES,
  parseNutrientNumber,
  normalizeNutrients,
  isWaterLog,
};
