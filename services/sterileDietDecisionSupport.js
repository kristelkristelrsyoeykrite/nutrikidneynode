const PROFESSIONAL_REMINDER =
  "Follow sterile diet and food safety instructions provided by the healthcare team.";

function normalizeText(value) {
  return String(value || "").trim().toLowerCase();
}

function isTruthy(value) {
  if (value === true) return true;
  const normalized = normalizeText(value);
  return ["true", "yes", "y", "1"].includes(normalized);
}

function toNumber(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
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

function sterileDietWeeksFrom(patientData = {}) {
  return toNumber(
    patientData.sterileDietWeeks ??
      patientData.sterile_diet_weeks ??
      patientData.weeksPostTransplant ??
      patientData.weeks_post_transplant ??
      patientData.postTransplantWeeks ??
      patientData.post_transplant_weeks,
  );
}

function checkSterileDiet(patientData = {}) {
  return isTruthy(
    patientData.requiresSterileDiet ?? patientData.requires_sterile_diet,
  );
}

function calculateSterileProtein(patientData = {}) {
  const sterileDietWeeks = sterileDietWeeksFrom(patientData);
  if (sterileDietWeeks !== null && sterileDietWeeks <= 8) {
    return "1.2-1.5 g/kg BW";
  }

  return "1.0 g/kg BW";
}

function calculateSterileCalories() {
  return "30-35 kcal/kg BW";
}

function calculateSterileCalcium() {
  return "1000-1500 mg";
}

function generateSterileDietEducation() {
  return [
    "Adequate protein intake is important for wound healing.",
    "Protein intake may help minimize protein wasting.",
    "Adequate calorie intake helps meet post-surgery energy demands.",
    "Energy intake allows protein to be used for anabolism.",
    "Calcium intake may help minimize further bone demineralization associated with drug therapy.",
    "Calcium intake may help correct calcium-phosphorus imbalance.",
  ];
}

function generateSterileDietAlerts(patientData = {}) {
  const alerts = [];
  const sterileDietWeeks = sterileDietWeeksFrom(patientData);

  if (sterileDietWeeks !== null && sterileDietWeeks <= 8) {
    alerts.push("Higher protein intake may be needed during the first 6-8 weeks.");
  }

  if (isTruthy(patientData.isPostSurgery ?? patientData.is_post_surgery)) {
    alerts.push(
      "Adequate calorie intake is important for post-surgery energy demands.",
    );
  }

  if (
    isTruthy(
      patientData.hasCalciumPhosphorusImbalance ??
        patientData.has_calcium_phosphorus_imbalance,
    )
  ) {
    alerts.push("Calcium-phosphorus balance may require monitoring.");
  }

  return uniqueMessages(alerts);
}

function calculateSterileDietTargets(patientData = {}) {
  return {
    protein_target: calculateSterileProtein(patientData),
    calorie_target: calculateSterileCalories(patientData),
    calcium_target: calculateSterileCalcium(patientData),
  };
}

function displaySterileDietRecommendation(
  targets = {},
  educationMessages = [],
  alerts = [],
) {
  return [
    "Sterile Diet Nutrition Targets",
    `- Protein: ${targets.protein_target ?? "Not available"}`,
    `- Calories: ${targets.calorie_target ?? "Not available"}`,
    `- Calcium: ${targets.calcium_target ?? "Not available"}`,
    "",
    "Sterile Diet Guidance",
    ...(educationMessages.length
      ? educationMessages.map((message) => `- ${message}`)
      : ["- No sterile diet guidance generated."]),
    "",
    "Sterile Diet Alerts",
    ...(alerts.length
      ? alerts.map((alert) => `- ${alert}`)
      : ["- No sterile diet alerts generated."]),
    "",
    "Professional Reminder",
    PROFESSIONAL_REMINDER,
  ].join("\n");
}

function generateSterileDietDecisionSupport(patientData = {}) {
  const sterileDietMode = checkSterileDiet(patientData);

  if (!sterileDietMode) {
    return {
      sterileDietMode,
      sterileTargets: null,
      sterileAlerts: [],
      sterileEducation: [],
      professionalReminder: PROFESSIONAL_REMINDER,
      summaryText: "",
    };
  }

  const sterileTargets = calculateSterileDietTargets(patientData);
  const sterileEducation = generateSterileDietEducation(patientData);
  const sterileAlerts = generateSterileDietAlerts(patientData);

  return {
    sterileDietMode,
    sterileTargets,
    sterileAlerts,
    sterileEducation,
    professionalReminder: PROFESSIONAL_REMINDER,
    summaryText: displaySterileDietRecommendation(
      sterileTargets,
      sterileEducation,
      sterileAlerts,
    ),
  };
}

module.exports = {
  PROFESSIONAL_REMINDER,
  checkSterileDiet,
  calculateSterileProtein,
  calculateSterileCalories,
  calculateSterileCalcium,
  calculateSterileDietTargets,
  generateSterileDietEducation,
  generateSterileDietAlerts,
  displaySterileDietRecommendation,
  generateSterileDietDecisionSupport,
};
