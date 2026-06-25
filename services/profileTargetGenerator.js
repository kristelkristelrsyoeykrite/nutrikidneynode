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

function isDialysisProfile(profile = {}) {
  if (normalizeCkdStage(profile.ckd_stage ?? profile.ckdStage) === "5D") {
    return true;
  }
  if (
    isTruthy(
      profile.isDialysis ??
        profile.is_dialysis ??
        profile.on_dialysis ??
        profile.onDialysis,
    )
  ) {
    return true;
  }
  const status = normalizeText(
    profile.dialysis_status ?? profile.dialysisStatus ?? profile.dialysisType,
  );
  return status.includes("dialysis") &&
    !status.includes("not on") &&
    !status.includes("no dialysis") &&
    !status.includes("pre-dialysis") &&
    !status.includes("pre dialysis");
}

function hasCKDStage3to5(profile = {}) {
  const stage = normalizeCkdStage(profile.ckd_stage ?? profile.ckdStage);
  return !isDialysisProfile(profile) && ["3", "4", "5"].includes(stage);
}

function weightKg(profile = {}) {
  const dialysis = isDialysisProfile(profile);
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
  if (!weight || !Array.isArray(range)) return null;
  return {
    min_kcal: Math.round(range[0] * weight),
    max_kcal: Math.round(range[1] * weight),
  };
}

function calculateProteinTarget(patientData = {}) {
  const dialysis = isDialysisProfile(patientData);
  const proteinCategory = normalizeText(
    patientData.proteinCategory ?? patientData.protein_category,
  );

  if (dialysis) return { label: "1.0-1.2 g/kg BW/day", range: [1.0, 1.2] };
  const age = toNumber(patientData.age_years ?? patientData.ageYears ?? patientData.age);
  if (age !== null && age >= 13 && age <= 14) {
    return { label: "0.8-0.9 g/kg BW/day", range: [0.8, 0.9] };
  }
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
  if (hasCKDStage3to5(patientData)) {
    return { label: "0.6-0.8 g/kg BW/day", range: [0.6, 0.8] };
  }
  return { label: "0.8-1.0 g/kg BW/day", range: [0.8, 1.0] };
}

function calculateCalorieTarget(patientData = {}) {
  const age = toNumber(patientData.age_years ?? patientData.ageYears ?? patientData.age);
  if (age !== null && age < 18) {
    return {
      label: "Pediatric target required",
      range: null,
      note: "Use a growth-aware pediatric or clinician-provided energy target",
      display: "Pediatric calorie target required before meal planning.",
    };
  }
  const appetite = normalizeText(patientData.appetite ?? patientData.appetiteStatus);
  const bmiStatus = normalizeText(patientData.BMIStatus ?? patientData.bmi_status);
  const muacStatus = normalizeText(patientData.MUACStatus ?? patientData.muac_status);
  const dialysis = isDialysisProfile(patientData);

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

function calculateSodiumTarget() {
  return { label: "<2000 mg/day", limit_mg: 2000 };
}

function ageBandForSdi(ageYears) {
  const age = toNumber(ageYears);
  if (age === null) return null;
  if (age >= 1 && age <= 3) return "1-3";
  if (age >= 4 && age <= 10) return "4-10";
  if (age >= 11 && age <= 17) return "11-17";
  return null;
}

const PHOSPHATE_SDI_MG = {
  "1-3": { lower: 250, upper: 500 },
  "4-10": { lower: 440, upper: 800 },
  "11-17": { lower: 640, upper: 1250 },
};

const CALCIUM_SDI_MG = {
  "1-3": { target: 700, upper: 1400 },
  "4-10": { target: 1000, upper: 2000 },
  "11-17": { target: 1300, upper: 2600 },
};

const SERUM_PHOSPHATE_UPPER_MG_DL = {
  "1-3": 6.5,
  "4-10": 5.8,
  "11-17": 4.5,
};

function phosphateReferenceUpper(profile = {}, ageBand) {
  return toNumber(
    profile.phosphorusReferenceHigh ??
      profile.phosphorus_reference_high ??
      profile.phosphateReferenceHigh ??
      profile.phosphate_reference_high ??
      profile.serumPhosphateReferenceHigh ??
      profile.serum_phosphate_reference_high,
  ) ?? SERUM_PHOSPHATE_UPPER_MG_DL[ageBand] ?? null;
}

function phosphateValueMgDl(profile = {}) {
  const value = toNumber(
    profile.phosphorus ??
      profile.phosphate ??
      profile.serumPhosphorus ??
      profile.serum_phosphorus ??
      profile.serumPhosphate ??
      profile.serum_phosphate,
  );
  if (value === null) return null;

  const unit = normalizeText(
    profile.phosphorus_unit ??
      profile.phosphate_unit ??
      profile.serum_phosphate_unit ??
      profile.serumPhosphorusUnit,
  );
  if (unit.includes("mmol")) return value * 3.097;
  return value;
}

function generatePediatricCkdNutrientLimits(profile = {}) {
  const age = toNumber(profile.age_years ?? profile.ageYears ?? profile.age);
  const weight = weightKg(profile);
  const ageBand = ageBandForSdi(age);
  const potassium = toNumber(
    profile.potassium ?? profile.serumPotassium ?? profile.serum_potassium ?? profile.K,
  );
  const potassiumUnit = normalizeText(
    profile.potassium_unit ?? profile.serum_potassium_unit,
  );
  const potassiumMmolL =
    potassium !== null && potassiumUnit.includes("mg/dl")
      ? potassium / 3.91
      : potassium;
  const phosphate = phosphateValueMgDl(profile);
  const phosphateUpper = phosphateReferenceUpper(profile, ageBand);
  const phosphateRestricted =
    phosphate !== null && phosphateUpper !== null && phosphate > phosphateUpper;
  const phosphateSdi = PHOSPHATE_SDI_MG[ageBand] || null;
  const calciumSdi = CALCIUM_SDI_MG[ageBand] || null;
  const potassiumRestricted =
    potassiumMmolL !== null && potassiumMmolL > 5.0 && weight && weight > 0;

  return {
    dailyPotassiumLimitMg: potassiumRestricted
      ? Math.round(weight * (age !== null && age < 1 ? 80 : 35))
      : null,
    dailyPhosphateLimitMg: phosphateSdi
      ? (phosphateRestricted ? phosphateSdi.lower : phosphateSdi.upper)
      : null,
    dailyCalciumTargetMg: calciumSdi ? calciumSdi.target : null,
    dailyCalciumUpperLimitMg: calciumSdi ? calciumSdi.upper : null,
  };
}

function calculatePotassiumTarget(profile = {}) {
  const pediatricLimits = generatePediatricCkdNutrientLimits(profile);
  if ((toNumber(profile.age_years ?? profile.ageYears ?? profile.age) ?? 18) < 18) {
    return {
      label: pediatricLimits.dailyPotassiumLimitMg
        ? `<${pediatricLimits.dailyPotassiumLimitMg} mg/day`
        : "No potassium restriction from current serum potassium",
      limit_mg: pediatricLimits.dailyPotassiumLimitMg,
    };
  }
  return { label: "<3000 mg/day", limit_mg: 3000 };
}

function calculatePhosphorusTarget(profile = {}) {
  const pediatricLimits = generatePediatricCkdNutrientLimits(profile);
  if ((toNumber(profile.age_years ?? profile.ageYears ?? profile.age) ?? 18) < 18) {
    return {
      label: pediatricLimits.dailyPhosphateLimitMg !== null
        ? `${pediatricLimits.dailyPhosphateLimitMg} mg/day`
        : "Pediatric phosphorus target unavailable",
      min_mg: pediatricLimits.dailyPhosphateLimitMg,
      max_mg: pediatricLimits.dailyPhosphateLimitMg,
    };
  }
  return { label: "800-1000 mg/day", min_mg: 800, max_mg: 1000 };
}

function calculateCalciumTarget(profile = {}) {
  const pediatricLimits = generatePediatricCkdNutrientLimits(profile);
  if ((toNumber(profile.age_years ?? profile.ageYears ?? profile.age) ?? 18) < 18) {
    return {
      label: pediatricLimits.dailyCalciumTargetMg !== null
        ? `${pediatricLimits.dailyCalciumTargetMg} mg/day`
        : "Pediatric calcium target unavailable",
      target_mg: pediatricLimits.dailyCalciumTargetMg,
      limit_mg: pediatricLimits.dailyCalciumUpperLimitMg,
    };
  }
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
  const pediatricNutrientLimits = generatePediatricCkdNutrientLimits(profile);
  const proteinDaily = gramsPerKgRangeToTarget(protein.range, weight);
  const calorieDaily = kcalPerKgRangeToTarget(calories.range, weight);

  return {
    child_name: profile.child_name,
    age_years: toNumber(profile.age_years ?? profile.ageYears),
    sex: profile.sex,
    ckd_stage: profile.ckd_stage ?? profile.ckdStage,
    dialysis_status:
      isDialysisProfile(profile)
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
    energy_target_min_kcal: calorieDaily?.min_kcal ?? null,
    energy_target_kcal: calorieDaily?.max_kcal ?? null,
    pediatric_mode:
      (toNumber(profile.age_years ?? profile.ageYears ?? profile.age) ?? 18) < 18,
    requires_growth_assessment: false,
    growth_assessment_source: "historical_anthropometrics",
    sodium_target: sodium.label,
    sodium_target_mg: sodium.limit_mg,
    potassium_target: potassium.label,
    potassium_target_mg: potassium.limit_mg,
    dailyPotassiumLimitMg: pediatricNutrientLimits.dailyPotassiumLimitMg,
    phosphorus_target: phosphorus.label,
    phosphorus_target_min_mg: phosphorus.min_mg,
    phosphorus_target_mg: phosphorus.max_mg,
    phosphate_target_mg: phosphorus.max_mg,
    dailyPhosphateLimitMg: pediatricNutrientLimits.dailyPhosphateLimitMg,
    calcium_target: calcium.label,
    calcium_target_mg: calcium.target_mg ?? calcium.limit_mg,
    calcium_upper_limit_mg: calcium.limit_mg,
    dailyCalciumTargetMg: pediatricNutrientLimits.dailyCalciumTargetMg,
    dailyCalciumUpperLimitMg: pediatricNutrientLimits.dailyCalciumUpperLimitMg,
    professional_reminder: PROFESSIONAL_REMINDER,
    system_notes: SYSTEM_NOTES,
    summary_text: [
      "Nutrition Summary",
      `CKD Stage: ${profile.ckd_stage ?? profile.ckdStage ?? "Not specified"}`,
      `Dialysis Status: ${
        isDialysisProfile(profile)
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
  generatePediatricCkdNutrientLimits,
};
