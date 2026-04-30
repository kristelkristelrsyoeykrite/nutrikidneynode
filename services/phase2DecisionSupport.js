function normalizeText(value) {
  return String(value || "").trim().toLowerCase();
}

function isFrequentProcessedFood(value) {
  const normalized = normalizeText(value);
  return normalized === "often";
}

function toNumber(value) {
  if (typeof value === "number") return value;
  if (value === undefined || value === null || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function classifySodium(value) {
  const sodium = toNumber(value);

  if (sodium === null) return null;
  if (sodium < 135) return "low";
  if (sodium <= 145) return "normal";
  return "high";
}

function classifyPotassium(value) {
  const potassium = toNumber(value);

  if (potassium === null) return null;
  if (potassium < 3.5) return "low";
  if (potassium <= 5.0) return "normal";
  return "high";
}

function isAdvancedCkdStage(value) {
  const stage = normalizeText(value);
  return stage === "stage 5" || stage === "stage 5d";
}

function uniqueMessages(messages) {
  const seen = new Set();
  const output = [];

  for (const message of messages) {
    if (!message) continue;

    const trimmed = String(message).trim();
    if (!trimmed || seen.has(trimmed)) continue;

    seen.add(trimmed);
    output.push(trimmed);
  }

  return output;
}

function getMonitoringMode(ckdStage) {
  const stage = normalizeText(ckdStage);

  if (stage === "stage 1" || stage === "stage 2") {
    return {
      mode: "baseline",
      note: "Early-stage CKD. Continue growth-focused monitoring.",
    };
  }

  if (stage === "stage 3" || stage === "stage 4") {
    return {
      mode: "enhanced",
      note: "Moderate CKD. Closer monitoring of mineral balance and intake is recommended.",
    };
  }

  if (stage === "stage 5" || stage === "stage 5d") {
    return {
      mode: "intensive",
      note: "Advanced CKD. Nutritional and laboratory monitoring should be more frequent.",
    };
  }

  return {
    mode: "intensive",
    note: "Advanced CKD. Nutritional and laboratory monitoring should be more frequent.",
  };
}

function evaluatePotassium({ labs, profile }) {
  const output = [];
  const potassiumStatus = classifyPotassium(labs.potassium);

  if (potassiumStatus === null) {
    return output;
  }

  if (potassiumStatus === "low") {
    output.push("Potassium is below the normal range. Review intake and possible clinical causes.");
    return output;
  }

  if (potassiumStatus === "normal") {
    output.push("No potassium restriction is needed at this time.");
    return output;
  }

  output.push("Potassium is above the normal range. Reduce processed foods with potassium additives first.");
  output.push("Do not automatically remove all fruits and vegetables. Prefer lower-potassium substitutions if needed.");

  if (isFrequentProcessedFood(profile.processed_food_intake)) {
    output.push("Frequent processed food intake may contribute to excess potassium additives.");
  }

  return output;
}

function evaluatePhosphorus({ labs, profile }) {
  const output = [];
  const phosphorusStatus = normalizeText(labs.phosphorus_status);

  if (!phosphorusStatus) {
    return output;
  }

  if (phosphorusStatus === "normal") {
    output.push("No phosphate restriction is needed at this time.");
    return output;
  }

  if (phosphorusStatus === "high") {
    output.push("Phosphorus is elevated. Reduce processed foods with phosphate additives first.");
    output.push("Natural high-protein foods should not be reduced first unless the elevation persists.");

    if (isFrequentProcessedFood(profile.processed_food_intake)) {
      output.push("Frequent processed food intake may increase phosphate additive exposure.");
    }

    return output;
  }

  if (phosphorusStatus === "low") {
    output.push("Phosphorus is below the expected range. Dietary intake may need review.");
  }

  return output;
}

function evaluateSodium({ labs, profile }) {
  const output = [];
  const sodiumStatus =
    classifySodium(labs.sodium) || normalizeText(labs.sodium_status);
  const hypertensionStatus = normalizeText(profile.has_hypertension);
  const hasHypertension = hypertensionStatus === "yes";
  const frequentProcessedFood = isFrequentProcessedFood(profile.processed_food_intake);

  if (sodiumStatus === "high") {
    output.push("Reduce processed and high-salt foods. Prefer fresh home-prepared foods.");
  } else if (hasHypertension) {
    output.push("Limit high-salt and processed foods. Prefer fresh home-prepared foods.");
  } else {
    output.push("No sodium-focused dietary alert is needed at this time.");
  }

  if (frequentProcessedFood) {
    output.push("Frequent processed food intake may increase sodium burden.");
  }

  if ((sodiumStatus === "high" || hasHypertension) && isAdvancedCkdStage(profile.ckd_stage)) {
    output.push("Closer sodium and fluid monitoring is recommended in advanced CKD.");
  }

  return output;
}

function evaluateFluid({ profile, intake }) {
  const output = [];
  const fluidRestrictionStatus = normalizeText(profile.fluid_restriction_status);
  const fluidLimitMl = toNumber(profile.fluid_limit_ml);
  const loggedFluidMl = intake ? toNumber(intake.fluid_ml) : null;

  if (fluidRestrictionStatus === "no") {
    output.push("No fluid restriction has been indicated.");
    return output;
  }

  if (fluidRestrictionStatus === "not sure" || fluidRestrictionStatus === "not_sure") {
    output.push("Fluid restriction status is unclear.");
    return output;
  }

  if (fluidRestrictionStatus !== "yes" || fluidLimitMl === null) {
    return output;
  }

  output.push(`Fluid restriction is active. Daily fluid limit: ${fluidLimitMl} mL.`);

  if (loggedFluidMl === null) {
    return output;
  }

  if (loggedFluidMl >= 0.8 * fluidLimitMl && loggedFluidMl <= fluidLimitMl) {
    output.push("Approaching fluid limit.");
  }

  if (loggedFluidMl > fluidLimitMl) {
    output.push("Daily fluid limit exceeded.");
  }

  return output;
}

function evaluateDietPattern({ profile, labs }) {
  const output = [];
  const dietPattern = normalizeText(profile.diet_pattern);
  const potassiumStatus = classifyPotassium(labs.potassium);
  const phosphorusStatus = normalizeText(labs.phosphorus_status);

  if (!dietPattern) {
    return output;
  }

  if (dietPattern === "regular diet") {
    output.push("Reported diet pattern: Regular diet.");
  } else if (dietPattern === "renal diet") {
    output.push("Reported diet pattern: Renal diet. This will be used as context for current recommendations.");
  } else if (dietPattern === "high protein") {
    output.push("Reported diet pattern: High protein.");
  } else if (dietPattern === "low protein") {
    output.push("Reported diet pattern: Low protein. Low protein diets are not routinely recommended for children unless clinically indicated.");
  } else if (dietPattern === "low salt / low fat") {
    output.push("Reported diet pattern: Low salt / Low fat.");
  } else if (dietPattern === "low fat") {
    output.push("Reported diet pattern: Low fat.");
  } else if (dietPattern === "low salt") {
    output.push("Reported diet pattern: Low salt.");
  } else if (dietPattern === "low potassium") {
    if (potassiumStatus === "normal") {
      output.push("Reported diet pattern: Low potassium. This restriction may not currently be necessary based on laboratory values.");
    } else {
      output.push("Reported diet pattern: Low potassium.");
    }
  } else if (dietPattern === "low phosphorus") {
    if (phosphorusStatus === "normal") {
      output.push("Reported diet pattern: Low phosphorus. This restriction may not currently be necessary based on laboratory values.");
    } else {
      output.push("Reported diet pattern: Low phosphorus.");
    }
  } else if (dietPattern === "low purine") {
    output.push("Reported diet pattern: Low purine.");
  } else if (dietPattern === "vegetarian") {
    output.push("Reported diet pattern: Vegetarian. Ensure adequate protein quality and intake.");
  } else if (dietPattern === "vegan") {
    output.push("Reported diet pattern: Vegan. Ensure adequate protein quality and intake.");
  } else if (dietPattern === "other") {
    output.push("Reported diet pattern: Other.");
  }

  return output;
}

function evaluateMealPattern(profile) {
  const output = [];
  const mealPattern = normalizeText(profile.meal_pattern);

  if (mealPattern === "regular (3 meals)") {
    output.push("Meal pattern: Regular 3 meals.");
  }

  if (mealPattern === "3 meals + snacks") {
    output.push("Meal pattern: 3 meals with snacks. This may support adequate energy intake.");
  }

  if (mealPattern === "irregular") {
    output.push("Meal pattern: Irregular. Irregular meals may affect energy intake and growth.");
  }

  return output;
}

function evaluateProcessedFood(profile) {
  const output = [];
  const processedFoodIntake = normalizeText(profile.processed_food_intake);

  if (processedFoodIntake === "often") {
    output.push("Processed food intake: Often.");
  }

  if (processedFoodIntake === "sometimes") {
    output.push("Processed food intake: Sometimes.");
  }

  if (processedFoodIntake === "rarely") {
    output.push("Processed food intake: Rarely.");
  }

  return output;
}

function generatePhase2DecisionSupport(profile = {}, labs = {}, intake = null) {
  const normalizedProfile = {
    ...profile,
    processed_food_intake:
      profile.processed_food_intake ?? profile.processedFoodIntake,
    meal_pattern: profile.meal_pattern ?? profile.mealPattern,
    diet_pattern: profile.diet_pattern ?? profile.dietPattern,
    fluid_restriction_status:
      profile.fluid_restriction_status ?? profile.fluidRestrictionStatus,
    fluid_limit_ml: profile.fluid_limit_ml ?? profile.fluidLimitMl,
    has_hypertension: profile.has_hypertension ?? profile.hasHypertension,
  };

  const normalizedLabs = {
    ...labs,
    phosphorus_status: labs.phosphorus_status ?? labs.phosphorusStatus,
    sodium_status: labs.sodium_status ?? labs.sodiumStatus,
  };

  const monitoring = getMonitoringMode(normalizedProfile.ckd_stage);
  const messages = [monitoring.note];

  messages.push(
    ...evaluatePotassium({
      labs: normalizedLabs,
      profile: normalizedProfile,
    }),
  );
  messages.push(
    ...evaluatePhosphorus({
      labs: normalizedLabs,
      profile: normalizedProfile,
    }),
  );
  messages.push(
    ...evaluateSodium({
      labs: normalizedLabs,
      profile: normalizedProfile,
    }),
  );
  messages.push(...evaluateFluid({ profile: normalizedProfile, intake }));
  messages.push(...evaluateDietPattern({ profile: normalizedProfile, labs: normalizedLabs }));
  messages.push(...evaluateMealPattern(normalizedProfile));
  messages.push(...evaluateProcessedFood(normalizedProfile));

  const finalMessages = uniqueMessages(messages);

  return {
    monitoring_mode: monitoring.mode,
    insights: finalMessages,
    recommendations: finalMessages,
    summary_text: finalMessages.map((note) => `- ${note}`).join("\n"),
  };
}

module.exports = {
  generatePhase2DecisionSupport,
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
