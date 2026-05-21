const PROFESSIONAL_REMINDER =
  "NutriKidney provides nutritional target estimation and foodlogging support guidance only. The application does not diagnose disease, prescribe treatment, adjust medications, or replace the care of a Registered Nutritionist-Dietitian, nephrologist, or physician.";

const SYSTEM_NOTES = [
  "Targets are estimated from CKD status, dialysis status, protein category, clinical status, and body weight.",
  "Laboratory values and clinical symptoms should guide nutrient restriction decisions.",
  PROFESSIONAL_REMINDER,
];

function normalizeText(value) {
  return String(value || "").trim().toLowerCase();
}

function toNumber(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (value === undefined || value === null || value === "") return null;
  const match = String(value).match(/-?\d+(\.\d+)?/);
  return match ? Number(match[0]) : null;
}

function isTruthy(value) {
  if (value === true) return true;
  const normalized = normalizeText(value);
  return ["true", "yes", "y", "1", "on dialysis"].includes(normalized);
}

function hasDiabetes(profile = {}) {
  return isTruthy(
    profile.hasDiabetes ??
      profile.has_diabetes ??
      profile.diabetes ??
      profile.hasDM ??
      profile.has_dm,
  );
}

function hasHighProteinRequirement(profile = {}) {
  return isTruthy(
    profile.hasHighProteinRequirement ??
      profile.has_high_protein_requirement ??
      profile.highProteinRequirement ??
      profile.high_protein_requirement,
  );
}

function normalizeCkdStage(value) {
  const stage = normalizeText(value)
    .replace(/^ckd\s*/, "")
    .replace(/^stage\s*/, "")
    .trim();

  if (stage === "5d" || stage === "5 d") return "5D";
  const match = stage.match(/[1-5]/);
  return match ? match[0] : "";
}

function hasCKDStage3to5(profile = {}) {
  const stage = normalizeCkdStage(profile.ckd_stage ?? profile.ckdStage);
  return ["3", "4", "5", "5D"].includes(stage);
}

function weightKg(profile = {}) {
  const dialysis = isTruthy(
    profile.isDialysis ?? profile.is_dialysis ?? profile.on_dialysis ?? profile.onDialysis,
  );
  const dryWeight = toNumber(profile.dry_weight_kg ?? profile.dryWeightKg ?? profile.dryWeight);
  const currentWeight = toNumber(profile.weight_kg ?? profile.weightKg ?? profile.weight);
  return dialysis && dryWeight ? dryWeight : currentWeight;
}

function gramsPerKgRangeToTarget(range, weight) {
  if (!weight) return null;
  return {
    min_g: Math.round(range[0] * weight * 10) / 10,
    max_g: Math.round(range[1] * weight * 10) / 10,
  };
}

function kcalPerKgRangeToTarget(range, weight) {
  if (!weight) return null;
  return {
    min_kcal: Math.round(range[0] * weight),
    max_kcal: Math.round(range[1] * weight),
  };
}

function calculateProteinTarget(patientData = {}) {
  const dialysis = isTruthy(
    patientData.isDialysis ??
      patientData.is_dialysis ??
      patientData.on_dialysis ??
      patientData.onDialysis,
  );
  const proteinCategory = normalizeText(
    patientData.proteinCategory ?? patientData.protein_category,
  );

  if (dialysis) return { label: "1.0-1.2 g/kg BW/day", range: [1.0, 1.2] };
  if (hasHighProteinRequirement(patientData)) {
    return { label: "1.2-1.5 g/kg BW/day", range: [1.2, 1.5] };
  }
  if (hasCKDStage3to5(patientData) && hasDiabetes(patientData)) {
    return { label: "0.6-0.8 g/kg BW/day", range: [0.6, 0.8] };
  }
  if (proteinCategory === "very low protein") {
    return { label: "0.28-0.43 g/kg BW/day", range: [0.28, 0.43] };
  }
  if (proteinCategory === "low protein") {
    return { label: "0.55-0.66 g/kg BW/day", range: [0.55, 0.66] };
  }
  return { label: "0.8-1.0 g/kg BW/day", range: [0.8, 1.0] };
}

function calculateCalorieTarget(patientData = {}) {
  const appetite = normalizeText(patientData.appetite ?? patientData.appetiteStatus);
  const bmiStatus = normalizeText(patientData.BMIStatus ?? patientData.bmi_status);
  const muacStatus = normalizeText(patientData.MUACStatus ?? patientData.muac_status);
  const dialysis = isTruthy(
    patientData.isDialysis ??
      patientData.is_dialysis ??
      patientData.on_dialysis ??
      patientData.onDialysis,
  );

  let note = "Use general CKD calorie support range";
  if (appetite === "poor" || appetite === "very poor") {
    note = "Use higher end of calorie range";
  } else if (bmiStatus === "low" || muacStatus === "low") {
    note = "Use higher end of calorie range";
  } else if (dialysis) {
    note = "Emphasize adequate nutritional intake";
  }

  return {
    label: "30-35 kcal/kg BW/day",
    range: [30, 35],
    note,
    display: `30-35 kcal/kg BW/day. ${note}.`,
  };
}

function calculateSodiumTarget(patientData = {}) {
  const ckdType = normalizeText(
    patientData.CKDType ??
      patientData.ckd_type ??
      patientData.ckdType ??
      patientData.kidneyDiseaseType ??
      patientData.kidney_disease_type ??
      patientData.kidneyType,
  );
  const stage = normalizeCkdStage(patientData.CKDStage ?? patientData.ckd_stage ?? patientData.ckdStage);

  if (ckdType === "ckd dkd" || ckdType === "dkd") return { label: "<3000 mg/day", limit_mg: 3000 };
  if (stage === "5D") return { label: "<2300 mg/day", limit_mg: 2300 };
  return { label: "<2000 mg/day", limit_mg: 2000 };
}

function calculatePotassiumTarget() {
  return { label: "<3000 mg/day", limit_mg: 3000 };
}

function calculatePhosphorusTarget() {
  return { label: "800-1000 mg/day", min_mg: 800, max_mg: 1000 };
}

function calculateCalciumTarget() {
  return { label: "<2000 mg/day", limit_mg: 2000 };
}

function generateProfileTargets(profile = {}) {
  const weight = weightKg(profile);
  if (!weight || weight <= 0) {
    throw new Error("weight_kg or dry_weight_kg must be a positive number");
  }

  const protein = calculateProteinTarget(profile);
  const calories = calculateCalorieTarget(profile);
  const sodium = calculateSodiumTarget(profile);
  const potassium = calculatePotassiumTarget(profile);
  const phosphorus = calculatePhosphorusTarget(profile);
  const calcium = calculateCalciumTarget(profile);
  const proteinDaily = gramsPerKgRangeToTarget(protein.range, weight);
  const calorieDaily = kcalPerKgRangeToTarget(calories.range, weight);

  return {
    child_name: profile.child_name,
    age_years: toNumber(profile.age_years ?? profile.ageYears),
    sex: profile.sex,
    ckd_stage: profile.ckd_stage ?? profile.ckdStage,
    dialysis_status:
      isTruthy(profile.on_dialysis ?? profile.onDialysis ?? profile.isDialysis)
        ? "On dialysis"
        : "Not on dialysis",
    bmi: toNumber(profile.bmi),
    body_weight_kg: weight,
    protein_target: protein.label,
    protein_target_g_per_kg: protein.label,
    protein_target_min_g: proteinDaily.min_g,
    protein_target_g: proteinDaily.max_g,
    calorie_target: calories.display,
    calorie_target_kcal_per_kg: calories.label,
    calorie_target_note: calories.note,
    energy_target_min_kcal: calorieDaily.min_kcal,
    energy_target_kcal: calorieDaily.max_kcal,
    sodium_target: sodium.label,
    sodium_target_mg: sodium.limit_mg,
    potassium_target: potassium.label,
    potassium_target_mg: potassium.limit_mg,
    phosphorus_target: phosphorus.label,
    phosphorus_target_min_mg: phosphorus.min_mg,
    phosphorus_target_mg: phosphorus.max_mg,
    phosphate_target_mg: phosphorus.max_mg,
    calcium_target: calcium.label,
    calcium_target_mg: calcium.limit_mg,
    professional_reminder: PROFESSIONAL_REMINDER,
    system_notes: SYSTEM_NOTES,
    summary_text: [
      "Nutrition Summary",
      `CKD Stage: ${profile.ckd_stage ?? profile.ckdStage ?? "Not specified"}`,
      `Dialysis Status: ${
        isTruthy(profile.on_dialysis ?? profile.onDialysis ?? profile.isDialysis)
          ? "On dialysis"
          : "Not on dialysis"
      }`,
      "",
      "Estimated Nutritional Targets",
      `- Protein: ${protein.label}`,
      `- Calories: ${calories.display}`,
      `- Sodium: ${sodium.label}`,
      `- Potassium: ${potassium.label}`,
      `- Phosphorus: ${phosphorus.label}`,
      `- Calcium: ${calcium.label}`,
      "",
      "Professional Reminder",
      PROFESSIONAL_REMINDER,
    ].join("\n"),
  };
}

module.exports = {
  PROFESSIONAL_REMINDER,
  generateProfileTargets,
  calculateProteinTarget,
  calculateCalorieTarget,
  calculateSodiumTarget,
  calculatePotassiumTarget,
  calculatePhosphorusTarget,
  calculateCalciumTarget,
};
