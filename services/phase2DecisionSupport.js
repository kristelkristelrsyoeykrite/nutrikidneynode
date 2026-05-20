const {
  PROFESSIONAL_REMINDER,
  generateProfileTargets,
} = require("./profileTargetGenerator");

function normalizeText(value) {
  return String(value || "").trim().toLowerCase();
}

function titleStatus(value) {
  const normalized = normalizeText(value);
  if (!normalized) return "";
  if (normalized.includes("high")) return "High";
  if (normalized.includes("low")) return "Low";
  if (normalized.includes("normal") || normalized.includes("within")) return "Normal";
  return "";
}

function toNumber(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function isTruthy(value) {
  if (value === true) return true;
  const normalized = normalizeText(value);
  return ["true", "yes", "y", "1", "present"].includes(normalized);
}

function isDialysisStatus(value) {
  const normalized = normalizeText(value);
  return normalized === "on dialysis" || normalized === "dialysis" || normalized === "ckd 5d";
}

function uniqueMessages(messages) {
  const seen = new Set();
  const output = [];

  for (const message of messages) {
    const trimmed = String(message || "").trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    output.push(trimmed);
  }

  return output;
}

function classifySodium(value) {
  const sodium = toNumber(value);
  if (sodium === null) return "";
  if (sodium < 135) return "Low";
  if (sodium <= 145) return "Normal";
  return "High";
}

function classifyPotassium(value) {
  const potassium = toNumber(value);
  if (potassium === null) return "";
  if (potassium < 3.5) return "Low";
  if (potassium <= 5.0) return "Normal";
  return "High";
}

function statusFrom(labs = {}, statusKeys = [], valueKeys = [], classifier = null) {
  for (const key of statusKeys) {
    const status = titleStatus(labs[key]);
    if (status) return status;
  }

  if (!classifier) return "";
  for (const key of valueKeys) {
    const status = classifier(labs[key]);
    if (status) return status;
  }
  return "";
}

function normalizeLabData(labs = {}) {
  return {
    ...labs,
    albuminStatus: statusFrom(labs, ["albuminStatus", "albumin_status"]),
    BUNStatus: statusFrom(labs, ["BUNStatus", "bunStatus", "bun_status", "BUN_status"]),
    ureaStatus: statusFrom(labs, ["ureaStatus", "urea_status"]),
    hemoglobinStatus: statusFrom(labs, ["hemoglobinStatus", "hemoglobin_status", "hgb_status"]),
    sodiumStatus: statusFrom(
      labs,
      ["sodiumStatus", "sodium_status"],
      ["sodium"],
      classifySodium,
    ),
    potassiumStatus: statusFrom(
      labs,
      ["potassiumStatus", "potassium_status"],
      ["potassium"],
      classifyPotassium,
    ),
    phosphorusStatus: statusFrom(labs, [
      "phosphorusStatus",
      "phosphorus_status",
      "phosphateStatus",
      "phosphate_status",
    ]),
    calciumStatus: statusFrom(labs, ["calciumStatus", "calcium_status"]),
  };
}

function normalizePatientData(profile = {}) {
  return {
    ...profile,
    appetite: profile.appetite ?? profile.appetiteStatus ?? profile.appetite_status,
    hasHypertension:
      profile.hasHypertension ?? profile.has_hypertension ?? profile.hypertension,
    hasEdema: profile.hasEdema ?? profile.has_edema ?? profile.edema,
    isDialysis:
      profile.isDialysis ??
      profile.is_dialysis ??
      profile.on_dialysis ??
      profile.onDialysis ??
      isDialysisStatus(profile.dialysis_status),
    CKDStage: profile.CKDStage ?? profile.ckd_stage ?? profile.ckdStage,
    CKDType: profile.CKDType ?? profile.ckd_type ?? profile.ckdType,
  };
}

function checkNutritionAlerts(patientData = {}, labData = {}) {
  const patient = normalizePatientData(patientData);
  const labs = normalizeLabData(labData);
  const alerts = [];
  const appetite = normalizeText(patient.appetite);

  if (appetite === "poor" || appetite === "very poor") {
    alerts.push("Nutritional intake may require attention.");
  }

  if (labs.albuminStatus === "Low" && appetite === "poor") {
    alerts.push("Possible nutrition-risk concern based on low albumin and poor appetite.");
  }

  if (labs.BUNStatus === "High" || labs.ureaStatus === "High") {
    alerts.push("Protein intake may require monitoring.");
  }

  if (labs.hemoglobinStatus === "Low") {
    alerts.push("Hemoglobin-related nutrition review may be helpful.");
  }

  if (labs.sodiumStatus === "High") {
    alerts.push("High sodium intake may require attention.");
  }

  if (isTruthy(patient.hasHypertension)) {
    alerts.push("Sodium restriction may be beneficial.");
  }

  if (isTruthy(patient.hasEdema)) {
    alerts.push("Swelling may be associated with fluid retention.");
  }

  if (labs.potassiumStatus === "High") {
    alerts.push("Potassium intake may require monitoring.");
  }

  if (labs.phosphorusStatus === "High") {
    alerts.push("Phosphorus intake may require attention.");
  }

  if (labs.calciumStatus === "High") {
    alerts.push("Calcium intake may require monitoring.");
  }

  if (labs.calciumStatus === "Low") {
    alerts.push("Calcium intake may require attention.");
  }

  if (labs.phosphorusStatus === "High" && labs.calciumStatus !== "Normal") {
    alerts.push("Calcium and phosphorus balance may require monitoring.");
  }

  return uniqueMessages(alerts);
}

function foodLogsFrom(foodLogData) {
  if (Array.isArray(foodLogData)) return foodLogData;
  if (!foodLogData || typeof foodLogData !== "object") return [];
  if (Array.isArray(foodLogData.foodLogs)) return foodLogData.foodLogs;
  if (Array.isArray(foodLogData.food_logs)) return foodLogData.food_logs;
  if (Array.isArray(foodLogData.logs)) return foodLogData.logs;
  return [];
}

function foodFlag(foodItem = {}, keys = []) {
  return keys.some((key) => isTruthy(foodItem[key]));
}

function analyzeFoodLog(foodLogData = [], labData = {}, patientData = {}) {
  const labs = normalizeLabData(labData);
  const patient = normalizePatientData(patientData);
  const educationMessages = [];

  for (const foodItem of foodLogsFrom(foodLogData)) {
    const category = normalizeText(foodItem.category ?? foodItem.foodCategory ?? foodItem.food_category);

    if (category === "processed food" || category.includes("processed food")) {
      educationMessages.push("Fresh foods are preferred over processed foods.");
    }

    if (
      foodFlag(foodItem, ["containsSaltAdditive", "contains_salt_additive", "isHighSodium", "is_high_sodium"])
    ) {
      educationMessages.push("Processed foods are commonly high in salt and sodium additives.");
    }

    if (foodFlag(foodItem, ["containsPotassiumAdditive", "contains_potassium_additive"])) {
      educationMessages.push("Processed foods containing potassium additives should be avoided when possible.");
    }

    if (foodFlag(foodItem, ["containsPhosphateAdditive", "contains_phosphate_additive"])) {
      educationMessages.push("Processed foods containing phosphate additives should be avoided when possible.");
    }

    if (category === "dark-colored carbonated drink" || category === "dark colored carbonated drink") {
      educationMessages.push("Dark-colored carbonated drinks may contain phosphate additives.");
    }

    if (category === "processed meat") {
      educationMessages.push("Processed meats may contain phosphate additives and sodium additives.");
    }
  }

  if (labs.potassiumStatus === "Normal") {
    educationMessages.push("Fruits and vegetables should not be routinely omitted solely because of potassium content.");
  }

  if (labs.phosphorusStatus === "High") {
    educationMessages.push("Phosphate additives are highly absorbable.");
  }

  if (labs.potassiumStatus === "High") {
    educationMessages.push("Potassium restriction should be based on serum potassium levels.");
  }

  if (isTruthy(patient.isDialysis)) {
    educationMessages.push("Protein and nutrient losses may occur during dialysis.");
  }

  return uniqueMessages(educationMessages);
}

function estimatedTargetsFor(profile = {}) {
  try {
    return generateProfileTargets(profile);
  } catch (error) {
    return {
      target_error: error.message,
    };
  }
}

function displayRecommendation(recommendation, alerts, educationMessages, patientData = {}) {
  const summary = [
    "Nutrition Summary",
    `CKD Stage: ${patientData.CKDStage ?? patientData.ckd_stage ?? patientData.ckdStage ?? "Not specified"}`,
    `Dialysis Status: ${isTruthy(patientData.isDialysis) ? "On dialysis" : "Not on dialysis"}`,
    "",
    "Estimated Nutritional Targets",
    `- Protein: ${recommendation.protein_target ?? "Not available"}`,
    `- Calories: ${recommendation.calorie_target ?? "Not available"}`,
    `- Sodium: ${recommendation.sodium_target ?? "Not available"}`,
    `- Potassium: ${recommendation.potassium_target ?? "Not available"}`,
    `- Phosphorus: ${recommendation.phosphorus_target ?? "Not available"}`,
    `- Calcium: ${recommendation.calcium_target ?? "Not available"}`,
    "",
    "Nutrition Alerts",
    ...(alerts.length ? alerts.map((alert) => `- ${alert}`) : ["- No nutrition alerts generated."]),
    "",
    "Foodlogging Educational Guidance",
    ...(educationMessages.length
      ? educationMessages.map((message) => `- ${message}`)
      : ["- No foodlogging education messages generated."]),
    "",
    "Professional Reminder",
    PROFESSIONAL_REMINDER,
  ];

  return summary.join("\n");
}

function getMonitoringMode(ckdStage) {
  const stage = normalizeText(ckdStage);
  if (stage.includes("1") || stage.includes("2")) return { mode: "baseline" };
  if (stage.includes("3") || stage.includes("4")) return { mode: "enhanced" };
  return { mode: "intensive" };
}

function generatePhase2DecisionSupport(profile = {}, labs = {}, intake = null) {
  const patientData = normalizePatientData(profile);
  const labData = normalizeLabData(labs);
  const foodLogData = intake?.foodLogs ?? intake?.food_logs ?? intake?.logs ?? intake ?? [];
  const recommendation = estimatedTargetsFor(patientData);
  const alerts = checkNutritionAlerts(patientData, labData);
  const educationMessages = analyzeFoodLog(foodLogData, labData, patientData);
  const finalMessages = uniqueMessages([...alerts, ...educationMessages]);
  const monitoring = getMonitoringMode(patientData.CKDStage);

  return {
    monitoring_mode: monitoring.mode,
    nutrition_summary: {
      ckd_stage: patientData.CKDStage ?? null,
      dialysis_status: isTruthy(patientData.isDialysis) ? "On dialysis" : "Not on dialysis",
    },
    estimated_nutritional_targets: recommendation,
    nutrition_alerts: alerts,
    foodlogging_educational_guidance: educationMessages,
    professional_reminder: PROFESSIONAL_REMINDER,
    insights: finalMessages,
    recommendations: finalMessages,
    summary_text: displayRecommendation(recommendation, alerts, educationMessages, patientData),
  };
}

function isAdvancedCkdStage(value) {
  const stage = normalizeText(value);
  return stage.includes("5");
}

function evaluatePotassium({ labs = {} } = {}) {
  const status = normalizeLabData(labs).potassiumStatus;
  if (status === "High") return ["Potassium intake may require monitoring."];
  if (status === "Normal") return ["Fruits and vegetables should not be routinely omitted solely because of potassium content."];
  return [];
}

function evaluatePhosphorus({ labs = {} } = {}) {
  return normalizeLabData(labs).phosphorusStatus === "High"
    ? ["Phosphorus intake may require attention.", "Phosphate additives are highly absorbable."]
    : [];
}

function evaluateSodium({ labs = {}, profile = {} } = {}) {
  return checkNutritionAlerts(profile, labs).filter((message) =>
    message.toLowerCase().includes("sodium"),
  );
}

function evaluateFluid({ profile = {} } = {}) {
  return isTruthy(profile.hasEdema ?? profile.has_edema ?? profile.edema)
    ? ["Swelling may be associated with fluid retention."]
    : [];
}

function evaluateDietPattern() {
  return [];
}

function evaluateMealPattern() {
  return [];
}

function evaluateProcessedFood(profile = {}) {
  return normalizeText(profile.processed_food_intake ?? profile.processedFoodIntake) === "often"
    ? ["Fresh foods are preferred over processed foods."]
    : [];
}

module.exports = {
  generatePhase2DecisionSupport,
  checkNutritionAlerts,
  analyzeFoodLog,
  displayRecommendation,
  getMonitoringMode,
  evaluatePotassium,
  evaluatePhosphorus,
  evaluateSodium,
  evaluateFluid,
  evaluateDietPattern,
  evaluateMealPattern,
  evaluateProcessedFood,
  classifySodium,
  classifyPotassium,
  isAdvancedCkdStage,
};
