const SYSTEM_NOTES = [
  "Targets are based on age, sex, weight, CKD stage, and dialysis status.",
  "Growth and nutritional adequacy are prioritized.",
  "No automatic potassium, phosphorus, or sodium restriction is applied at this stage.",
  "Additional dietary adjustments will be based on future laboratory and clinical data.",
];

const ENERGY_TABLE = {
  "1": { male: [72, 120], female: [72, 120] },
  "2": { male: [81, 95], female: [79, 92] },
  "3": { male: [80, 82], female: [76, 77] },
  "4-6": { male: [67, 93], female: [64, 90] },
  "7-8": { male: [60, 77], female: [56, 75] },
  "9-10": { male: [55, 69], female: [49, 63] },
  "11-12": { male: [48, 63], female: [43, 57] },
  "13-14": { male: [44, 63], female: [39, 50] },
  "15-17": { male: [40, 55], female: [36, 46] },
};

const PROTEIN_TABLE = {
  "1": [0.9, 1.14],
  "2": [0.9, 1.05],
  "3": [0.9, 1.05],
  "4-6": [0.85, 0.95],
  "7-8": [0.9, 0.95],
  "9-10": [0.9, 0.95],
  "11-12": [0.9, 0.95],
  "13-14": [0.8, 0.9],
  "15-17": [0.8, 0.9],
};

function requireValue(profile, key, missing) {
  if (profile[key] === undefined || profile[key] === null || profile[key] === "") {
    missing.push(key);
  }
}

function normalizeSex(sex) {
  const value = String(sex || "").trim().toLowerCase();
  if (value.startsWith("m")) return "male";
  if (value.startsWith("f")) return "female";
  return value;
}

function normalizeActivity(activity) {
  const value = String(activity || "").trim().toLowerCase();
  if (value.startsWith("low")) return "low";
  if (value.startsWith("moderate")) return "moderate";
  if (value.startsWith("high")) return "high";
  return value;
}

function normalizeDialysisType(dialysisType) {
  const value = String(dialysisType || "").trim().toLowerCase();
  if (value === "hd" || value.includes("hemo")) return "HD";
  if (value === "pd" || value.includes("peritoneal")) return "PD";
  return "";
}

function normalizeFluidStatus(status) {
  const value = String(status || "").trim().toLowerCase();
  if (value === "yes") return "yes";
  if (value === "no") return "no";
  if (value === "not sure" || value === "unsure") return "not sure";
  return value;
}

function mapAgeGroup(ageYears) {
  if (ageYears === 1) return "1";
  if (ageYears === 2) return "2";
  if (ageYears === 3) return "3";
  if (ageYears >= 4 && ageYears <= 6) return "4-6";
  if (ageYears >= 7 && ageYears <= 8) return "7-8";
  if (ageYears >= 9 && ageYears <= 10) return "9-10";
  if (ageYears >= 11 && ageYears <= 12) return "11-12";
  if (ageYears >= 13 && ageYears <= 14) return "13-14";
  if (ageYears >= 15 && ageYears <= 17) return "15-17";
  throw new Error("age_years must be between 1 and 17");
}

function getFiberRange(ageYears, sex) {
  if (ageYears >= 1 && ageYears <= 3) return [14, 19];
  if (ageYears >= 4 && ageYears <= 8) return [18, 25];
  if (ageYears >= 9 && ageYears <= 13) return sex === "male" ? [24, 31] : [20, 26];
  if (ageYears >= 14 && ageYears <= 18) return sex === "male" ? [28, 38] : [22, 26];
  throw new Error("age_years must be between 1 and 18 for fiber targets");
}

function getCalciumRange(ageYears) {
  if (ageYears >= 1 && ageYears <= 3) return [450, 700];
  if (ageYears >= 4 && ageYears <= 10) return [700, 1000];
  if (ageYears >= 11 && ageYears <= 17) return [900, 1300];
  throw new Error("age_years must be between 1 and 17 for calcium targets");
}

function getPhosphateRange(ageYears) {
  if (ageYears >= 1 && ageYears <= 3) return [250, 500];
  if (ageYears >= 4 && ageYears <= 10) return [440, 800];
  if (ageYears >= 11 && ageYears <= 17) return [640, 1250];
  throw new Error("age_years must be between 1 and 17 for phosphate targets");
}

function midpoint(range) {
  return (range[0] + range[1]) / 2;
}

function toNumber(value) {
  if (typeof value === "number") return value;
  if (value === undefined || value === null || value === "") return null;
  const match = String(value).match(/-?\d+(\.\d+)?/);
  return match ? Number(match[0]) : null;
}

function validateProfile(profile) {
  const missing = [];
  [
    "age_years",
    "sex",
    "weight_kg",
    "bmi",
    "ckd_stage",
    "on_dialysis",
    "physical_activity_level",
    "fluid_restriction_status",
  ].forEach((key) => requireValue(profile, key, missing));

  if (profile.on_dialysis === true) {
    requireValue(profile, "dialysis_type", missing);
  }
  if (normalizeFluidStatus(profile.fluid_restriction_status) === "yes") {
    requireValue(profile, "fluid_limit_ml", missing);
  }
  if (missing.length > 0) {
    throw new Error(`Missing required profile fields: ${missing.join(", ")}`);
  }
}

function generateProfileTargets(profile) {
  validateProfile(profile);

  const ageYears = Number(profile.age_years);
  const sex = normalizeSex(profile.sex);
  const ageGroup = mapAgeGroup(ageYears);
  const effectiveWeight =
    profile.on_dialysis === true && profile.dry_weight_kg
      ? toNumber(profile.dry_weight_kg)
      : toNumber(profile.weight_kg);

  if (!Number.isFinite(effectiveWeight) || effectiveWeight <= 0) {
    throw new Error("weight_kg or dry_weight_kg must be a positive number");
  }
  if (!["male", "female"].includes(sex)) {
    throw new Error("sex must be male or female");
  }

  const energyRange = ENERGY_TABLE[ageGroup][sex];
  const proteinRange = PROTEIN_TABLE[ageGroup];
  const fiberRange = getFiberRange(ageYears, sex);
  const calciumRange = getCalciumRange(ageYears);
  const phosphateRange = getPhosphateRange(ageYears);

  let energyTarget = midpoint(energyRange) * effectiveWeight;
  const activity = normalizeActivity(profile.physical_activity_level);
  if (activity === "low") energyTarget *= 0.95;
  if (activity === "high") energyTarget *= 1.05;

  let proteinTarget = proteinRange[1] * effectiveWeight;
  const dialysisType = normalizeDialysisType(profile.dialysis_type);
  if (profile.on_dialysis === true && dialysisType === "HD") {
    proteinTarget += 0.1 * effectiveWeight;
  }
  if (profile.on_dialysis === true && dialysisType === "PD") {
    proteinTarget += 0.225 * effectiveWeight;
  }

  const fluidStatus = normalizeFluidStatus(profile.fluid_restriction_status);
  let fluidNote = "Fluid restriction status is unclear. No fluid alert threshold will be applied until a limit is entered.";
  if (fluidStatus === "yes") {
    fluidNote = `Fluid intake is restricted. Daily fluid limit: ${profile.fluid_limit_ml} mL/day.`;
  }
  if (fluidStatus === "no") {
    fluidNote = "No fluid restriction has been indicated.";
  }

  return {
    child_name: profile.child_name,
    age_years: ageYears,
    sex: profile.sex,
    ckd_stage: profile.ckd_stage,
    dialysis_status: profile.on_dialysis === true ? dialysisType : "Not on dialysis",
    bmi: toNumber(profile.bmi),
    energy_target_kcal: Math.round(energyTarget),
    protein_target_g: Math.round(proteinTarget * 10) / 10,
    fiber_target_g: Math.round(midpoint(fiberRange)),
    calcium_target_mg: Math.round(midpoint(calciumRange)),
    phosphate_target_mg: Math.round(midpoint(phosphateRange)),
    fluid_note: fluidNote,
    system_notes: SYSTEM_NOTES,
    summary_text: [
      "Nutrition Profile Summary",
      "",
      `Child: ${profile.child_name}`,
      `Age: ${ageYears} years`,
      `Sex: ${profile.sex}`,
      `CKD Stage: ${profile.ckd_stage}`,
      `Dialysis Status: ${profile.on_dialysis === true ? dialysisType : "Not on dialysis"}`,
      `BMI: ${profile.bmi} kg/m2`,
      "",
      "Baseline Nutrition Targets",
      `- Estimated energy target: ${Math.round(energyTarget)} kcal/day`,
      `- Estimated protein target: ${Math.round(proteinTarget * 10) / 10} g/day`,
      `- Estimated fiber target: ${Math.round(midpoint(fiberRange))} g/day`,
      `- Estimated calcium target: ${Math.round(midpoint(calciumRange))} mg/day`,
      `- Estimated phosphate target: ${Math.round(midpoint(phosphateRange))} mg/day`,
      "",
      "Fluid Note",
      `- ${fluidNote}`,
      "",
      "System Note",
      ...SYSTEM_NOTES.map((note) => `- ${note}`),
    ].join("\n"),
  };
}

module.exports = { generateProfileTargets };
