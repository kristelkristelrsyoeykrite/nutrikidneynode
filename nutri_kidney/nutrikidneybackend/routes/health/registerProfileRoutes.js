function registerProfileRoutes(router, deps) {
  const {
    admin,
    db,
    generateProfileTargets,
    generatePhase2DecisionSupport,
    cleanObject,
    getUserDocuments,
    getDocumentsByField,
    uniqueDocumentsById,
    sortByNewest,
    normalizeActivityLevel,
    archiveCurrentRecord,
    archiveAndDeleteExtraCurrentRecords,
    recalculateNutritionArtifacts,
  } = deps;

  function normalizeTextToken(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/&/g, " and ")
      .replace(/[^\w\s/.-]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function normalizeAllergiesInput(value) {
    const rawItems = Array.isArray(value)
      ? value
      : typeof value === "string"
        ? value.split(/[,;\n]+/)
        : [];
    const aliases = {
      milk: "milk",
      dairy: "milk",
      egg: "egg",
      eggs: "egg",
      peanut: "peanut",
      peanuts: "peanut",
      "tree nuts": "tree nuts",
      treenuts: "tree nuts",
      soy: "soy",
      soya: "soy",
      wheat: "wheat / gluten",
      gluten: "wheat / gluten",
      fish: "fish",
      shellfish: "shellfish",
      sesame: "sesame",
      "no known allergies": "no known allergies",
      "not sure": "not sure",
      other: "other",
    };

    const normalized = [];
    const seen = new Set();
    for (const item of rawItems) {
      const token = normalizeTextToken(item);
      if (!token) continue;
      const canonical = aliases[token] || token;
      if (canonical === "no known allergies") {
        return [];
      }
      if (!seen.has(canonical)) {
        seen.add(canonical);
        normalized.push(canonical);
      }
    }
    return normalized;
  }

  function sanitizeCaregiverSettings(value, existing = {}) {
    const source = value && typeof value === "object" ? value : {};
    const wantsCaregiverLink =
      source.wantsCaregiverLink ?? existing.wantsCaregiverLink ?? false;
    const caregiverLinked =
      source.caregiverLinked ?? existing.caregiverLinked ?? false;
    const caregiverId = source.caregiverId ?? existing.caregiverId ?? null;
    const consentConfirmed =
      source.consentConfirmed ?? existing.consentConfirmed ?? false;
    let linkStatus = source.linkStatus ?? existing.linkStatus ?? "none";

    if (caregiverLinked === true && caregiverId) {
      linkStatus = "linked";
    } else if (wantsCaregiverLink === true) {
      linkStatus = linkStatus === "linked" ? "linked" : "pending";
    } else {
      linkStatus = "none";
    }

    return {
      wantsCaregiverLink: wantsCaregiverLink === true,
      caregiverLinked: caregiverLinked === true && !!caregiverId,
      caregiverId: caregiverLinked === true && caregiverId ? caregiverId : null,
      consentConfirmed: caregiverLinked === true ? true : consentConfirmed === true,
      linkStatus,
    };
  }

  function buildEditPermissions(role, caregiverSettings, existing = {}) {
    if (role !== "adolescent") {
      return {
        canEditSensitive: true,
        requiresApproval: false,
      };
    }

    if (caregiverSettings?.caregiverLinked === true) {
      return {
        canEditSensitive: false,
        requiresApproval: true,
      };
    }

    return {
      canEditSensitive:
        existing.canEditSensitive === undefined ? true : existing.canEditSensitive === true,
      requiresApproval: existing.requiresApproval === true ? true : false,
    };
  }

  function isCaregiverRole(role) {
    const normalized = String(role || "").trim().toLowerCase();
    return normalized === "parent_caregiver" || normalized === "caregiver";
  }

  function applyUserProfileCoreFields(target, source = {}) {
    const ageValue = source.ageYears ?? source.age_years;
    const sexValue = source.sex ?? source.gender;
    const bmiValue = source.bmi;

    if (source.childFullName ?? source.name) {
      target.childFullName = source.childFullName ?? source.name;
    }
    if (source.dateOfBirth ?? source.dob) {
      target.dateOfBirth = source.dateOfBirth ?? source.dob;
    }
    if (ageValue !== undefined && ageValue !== null && ageValue !== "") {
      target.ageYears = Number(ageValue);
      target.age_years = Number(ageValue);
    }
    if (sexValue) {
      target.gender = sexValue;
      target.sex = sexValue;
    }
    if (bmiValue !== undefined && bmiValue !== null && bmiValue !== "") {
      target.bmi = Number(bmiValue);
    }
    if (source.preferredMeasurementSystem ?? source.preferredMeasurement) {
      target.preferredMeasurementSystem =
        source.preferredMeasurementSystem ?? source.preferredMeasurement;
    }
  }

  router.post("/update-profile", async (req, res) => {
    console.log("Update profile requested:", req.body);

    try {
      const {
        userId,
        uid,
        childFullName,
        ageYears,
        age_years,
        dateOfBirth,
        sex,
        gender,
        height_cm,
        height,
        weight_kg,
        weight,
        bmi,
        dryWeight,
        dry_weight_kg,
        ckdStage,
        ckd_stage,
        kidneyDiseaseType,
        dateOfDiagnosis,
        onDialysis,
        dialysisType,
        treatmentFrequency,
        dietPattern,
        diet_pattern,
        processedFoodIntake,
        processed_food_intake,
        mealPattern,
        meal_pattern,
        physicalActivityLevel,
        physical_activity_level,
        preferredMeasurementSystem,
        fluidRestrictionStatus,
        fluid_restriction_status,
        fluidLimitMl,
        fluid_limit_ml,
        hasHypertension,
        has_hypertension,
        allowDataExport,
        recalculateNutritionTargets,
        caregiverSettings,
        editPermissions,
      } = req.body;

      const actingUserId = userId || uid;
      const requestedProfileUserId =
        req.body.profileUserId || req.body.targetUserId || actingUserId;
      if (!actingUserId) throw new Error("Missing userId");

      const actingUserRef = db.collection("users").doc(actingUserId);
      const actingUserDoc = await actingUserRef.get();
      if (!actingUserDoc.exists) {
        return res.status(404).json({
          success: false,
          error: "Acting user profile not found",
        });
      }

      const actingUser = actingUserDoc.data() || {};
      const isLinkedCaregiverEditingChild =
        requestedProfileUserId !== actingUserId &&
        isCaregiverRole(actingUser.role) &&
        actingUser.linkedChildAccount === true &&
        actingUser.linkedChildUserId === requestedProfileUserId;

      if (requestedProfileUserId !== actingUserId && !isLinkedCaregiverEditingChild) {
        return res.status(403).json({
          success: false,
          error: "You are not allowed to update this profile",
        });
      }

      const profileUserId = requestedProfileUserId;
      const userRef = db.collection("users").doc(profileUserId);
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        return res.status(404).json({
          success: false,
          error: "User profile not found",
        });
      }

      const existingUser = userDoc.data() || {};
      const roleValue = existingUser.role || req.body.userRole || null;
      const ageValue = ageYears ?? age_years;
      const sexValue = sex ?? gender;
      const heightValue = height_cm ?? height;
      const weightValue = weight_kg ?? weight;
      const dryWeightValue = dryWeight ?? dry_weight_kg;
      const ckdStageValue = ckdStage ?? ckd_stage;
      const dietPatternValue = dietPattern ?? diet_pattern;
      const processedFoodValue = processedFoodIntake ?? processed_food_intake;
      const mealPatternValue = mealPattern ?? meal_pattern;
      const activityValue = normalizeActivityLevel(
        physicalActivityLevel ?? physical_activity_level,
      );
      const fluidStatusValue =
        fluidRestrictionStatus ?? fluid_restriction_status;
      const fluidLimitValue = fluidLimitMl ?? fluid_limit_ml;
      const hypertensionValue = hasHypertension ?? has_hypertension;
      const allergiesValue = normalizeAllergiesInput(req.body.allergies);
      const isLinkedAdolescent =
        roleValue === "adolescent" &&
        existingUser.caregiverSettings?.caregiverLinked === true;
      let caregiverSettingsValue = sanitizeCaregiverSettings(
        caregiverSettings,
        existingUser.caregiverSettings,
      );
      let editPermissionsValue = buildEditPermissions(
        roleValue,
        caregiverSettingsValue,
        editPermissions && typeof editPermissions === "object"
          ? editPermissions
          : existingUser.editPermissions || {},
      );
      const canManageLinkedAdolescent =
        isLinkedAdolescent && isLinkedCaregiverEditingChild;
      const allowAgeFieldUpdates = !isLinkedAdolescent || canManageLinkedAdolescent;

      if (isLinkedAdolescent && !canManageLinkedAdolescent) {
        caregiverSettingsValue = existingUser.caregiverSettings || caregiverSettingsValue;
        editPermissionsValue = existingUser.editPermissions || editPermissionsValue;
      }

      const userPayload = cleanObject({
        childFullName,
        ageYears:
          allowAgeFieldUpdates && ageValue !== undefined
            ? Number(ageValue)
            : undefined,
        age_years:
          allowAgeFieldUpdates && ageValue !== undefined
            ? Number(ageValue)
            : undefined,
        dateOfBirth,
        sex: sexValue,
        gender: sexValue,
        bmi: bmi === undefined ? undefined : Number(bmi),
        preferredMeasurementSystem,
        allowDataExport:
          allowDataExport === undefined ? undefined : allowDataExport === true,
        caregiverSettings: caregiverSettingsValue,
        editPermissions: editPermissionsValue,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await userRef.set(userPayload, { merge: true });

      let medicalProfileId = existingUser.medicalProfileId;
      const medicalProfilePayload = cleanObject({
        userId: profileUserId,
        kidneyDiseaseType,
        ckdStage: ckdStageValue,
        ckd_stage: ckdStageValue,
        dateOfDiagnosis,
        onDialysis,
        dialysisType,
        treatmentFrequency,
        dietPattern: dietPatternValue,
        diet_pattern: dietPatternValue,
        processedFoodIntake: processedFoodValue,
        processed_food_intake: processedFoodValue,
        mealPattern: mealPatternValue,
        meal_pattern: mealPatternValue,
        physicalActivityLevel: activityValue,
        physical_activity_level: activityValue,
        fluidRestrictionStatus: fluidStatusValue,
        fluid_restriction_status: fluidStatusValue,
        fluidLimitMl:
          fluidLimitValue === undefined ? undefined : Number(fluidLimitValue),
        fluid_limit_ml:
          fluidLimitValue === undefined ? undefined : Number(fluidLimitValue),
        hasHypertension: hypertensionValue,
        has_hypertension: hypertensionValue,
        allergies: allergiesValue,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (medicalProfileId) {
        await db
          .collection("medicalProfile")
          .doc(medicalProfileId)
          .set(medicalProfilePayload, { merge: true });
      } else {
        const medicalDoc = await db.collection("medicalProfile").add({
          ...medicalProfilePayload,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        medicalProfileId = medicalDoc.id;
        await userRef.set({ medicalProfileId }, { merge: true });
      }

      const anthropometricHistory = sortByNewest(
        uniqueDocumentsById([
          ...(await getUserDocuments("anthropometrics", profileUserId)),
          ...(await getDocumentsByField(
            "anthropometrics",
            "medicalProfileId",
            medicalProfileId,
          )),
        ]),
      );
      const currentAnthropometrics = anthropometricHistory[0] || null;
      const anthropometricPayload = cleanObject({
        userId: profileUserId,
        medicalProfileId,
        height: heightValue === undefined ? undefined : Number(heightValue),
        height_cm: heightValue === undefined ? undefined : Number(heightValue),
        weight: weightValue === undefined ? undefined : Number(weightValue),
        weight_kg: weightValue === undefined ? undefined : Number(weightValue),
        bmi: bmi === undefined ? undefined : Number(bmi),
        dryWeight:
          dryWeightValue === undefined ? undefined : Number(dryWeightValue),
        dry_weight_kg:
          dryWeightValue === undefined ? undefined : Number(dryWeightValue),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      let anthropometricId = currentAnthropometrics?.id || null;
      if (anthropometricId) {
        if (recalculateNutritionTargets === true) {
          await archiveCurrentRecord(
            currentAnthropometrics,
            "historicalAnthropometrics",
          );
          await archiveAndDeleteExtraCurrentRecords({
            records: anthropometricHistory,
            keepId: currentAnthropometrics.id,
            currentCollectionName: "anthropometrics",
            historicalCollectionName: "historicalAnthropometrics",
          });
        }
        await db
          .collection("anthropometrics")
          .doc(anthropometricId)
          .set(anthropometricPayload, { merge: true });
      } else if (Object.keys(anthropometricPayload).length > 3) {
        const anthropometricDoc = await db.collection("anthropometrics").add({
          ...anthropometricPayload,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        anthropometricId = anthropometricDoc.id;
      }

      const recalculation =
        recalculateNutritionTargets === true
          ? await recalculateNutritionArtifacts(profileUserId)
          : null;

      return res.status(200).json({
        success: true,
        message: "Profile updated successfully",
        medicalProfileId,
        anthropometricId,
        recalculation,
      });
    } catch (error) {
      console.error("UPDATE_PROFILE ERROR:", error.message);
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }
  });

  router.post("/submit-all", async (req, res) => {
    console.log("Final submission received - saving to database");

    const { userId, step1, step2, step3, step4, userRole } = req.body;

    try {
      const ageYears = step1?.age_years ?? step1?.ageYears;
      const sex = step1?.sex ?? step1?.gender;
      const heightCm = step1?.height_cm ?? step1?.height;
      const weightKg = step1?.weight_kg ?? step1?.weight;
      const bmi = step1?.bmi;
      const fluidRestrictionStatus =
        step3?.fluid_restriction_status ?? step3?.fluidRestrictionStatus;
      const fluidLimitMl = step3?.fluid_limit_ml ?? step3?.fluidLimitMl;
      const physicalActivityLevel =
        step3?.physical_activity_level ?? step3?.physicalActivityLevel;
      const hasHypertension =
        step3?.has_hypertension ?? step3?.hasHypertension;
      const dietPattern = step3?.diet_pattern ?? step3?.dietPattern;
      const processedFoodIntake =
        step3?.processed_food_intake ?? step3?.processedFoodIntake;
      const mealPattern = step3?.meal_pattern ?? step3?.mealPattern;
      const allergies = normalizeAllergiesInput(step2?.allergies);
      const caregiverSettings = sanitizeCaregiverSettings(
        step1?.caregiverSettings,
        {},
      );

      const existingUserDoc = await db.collection("users").doc(userId).get();
      const existingUser =
        existingUserDoc.exists ? existingUserDoc.data() || {} : {};
      if (existingUser.baselineNutritionTargetId) {
        const existingTargetDoc = await db
          .collection("nutritionTargets")
          .doc(existingUser.baselineNutritionTargetId)
          .get();
        const existingTargets = existingTargetDoc.exists
          ? existingTargetDoc.data()
          : null;
        let existingPhase2DecisionSupport = null;
        if (existingUser.phase2DecisionSupportId) {
          const existingPhase2Doc = await db
            .collection("phase2DecisionSupport")
            .doc(existingUser.phase2DecisionSupportId)
            .get();
          existingPhase2DecisionSupport = existingPhase2Doc.exists
            ? existingPhase2Doc.data()
            : null;
        }

        return res.status(200).json({
          success: true,
          message:
            "Profile already completed. Existing nutrition targets returned.",
          userId,
          medicalProfileId: existingUser.medicalProfileId,
          nutritionTargetId: existingUser.baselineNutritionTargetId,
          baselineTargets: existingTargets,
          phase2DecisionSupportId: existingUser.phase2DecisionSupportId,
          phase2DecisionSupport: existingPhase2DecisionSupport,
        });
      }

      const userPayload = {
        uid: userId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (!existingUser.createdAt) {
        userPayload.createdAt = admin.firestore.FieldValue.serverTimestamp();
      }

      applyUserProfileCoreFields(userPayload, {
        name: step1?.name,
        dob: step1?.dob,
        ageYears,
        sex,
        bmi,
        preferredMeasurement: step3?.preferredMeasurement,
      });
      if (userRole) userPayload.role = userRole;
      if (userRole === "adolescent") {
        userPayload.caregiverSettings = caregiverSettings;
        userPayload.editPermissions = buildEditPermissions(
          userRole,
          caregiverSettings,
          step1?.editPermissions || {},
        );
      }
      if (
        (userRole === "parent_caregiver" || userRole === "caregiver") &&
        existingUser.childAgeGroup === "5-13"
      ) {
        userPayload.childProfileCreated = true;
      }

      await db.collection("users").doc(userId).set(userPayload, { merge: true });

      const medicalProfilePayload = {
        userId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (step1?.kidneyType) {
        medicalProfilePayload.kidneyDiseaseType = step1.kidneyType;
      }
      if (step1?.ckdStage) medicalProfilePayload.ckdStage = step1.ckdStage;
      if (step1?.diagnosisDate) {
        medicalProfilePayload.dateOfDiagnosis = step1.diagnosisDate;
      }
      if (step2?.isOnDialysis !== undefined) {
        medicalProfilePayload.onDialysis = step2.isOnDialysis;
      }
      if (step2?.dialysisType) {
        medicalProfilePayload.dialysisType = step2.dialysisType;
      }
      if (step2?.treatmentFrequency) {
        medicalProfilePayload.treatmentFrequency = step2.treatmentFrequency;
      }
      if (step3?.fluidRestriction) {
        medicalProfilePayload.fluidRestriction = step3.fluidRestriction;
      }
      if (fluidRestrictionStatus) {
        medicalProfilePayload.fluidRestrictionStatus = fluidRestrictionStatus;
        medicalProfilePayload.fluid_restriction_status = fluidRestrictionStatus;
      }
      if (fluidLimitMl) {
        medicalProfilePayload.fluidLimitMl = Number(fluidLimitMl);
        medicalProfilePayload.fluid_limit_ml = Number(fluidLimitMl);
      }
      if (physicalActivityLevel) {
        medicalProfilePayload.physicalActivityLevel = physicalActivityLevel;
        medicalProfilePayload.physical_activity_level = physicalActivityLevel;
      }
      if (dietPattern) {
        medicalProfilePayload.dietPattern = dietPattern;
        medicalProfilePayload.diet_pattern = dietPattern;
      }
      if (processedFoodIntake) {
        medicalProfilePayload.processedFoodIntake = processedFoodIntake;
        medicalProfilePayload.processed_food_intake = processedFoodIntake;
      }
      if (mealPattern) {
        medicalProfilePayload.mealPattern = mealPattern;
        medicalProfilePayload.meal_pattern = mealPattern;
      }
      if (hasHypertension) {
        medicalProfilePayload.hasHypertension = hasHypertension;
        medicalProfilePayload.has_hypertension = hasHypertension;
      }
      medicalProfilePayload.allergies = allergies;
      if (Array.isArray(step2?.medications)) {
        medicalProfilePayload.medications = step2.medications;
      }
      if (step2?.medicationsSummary) {
        medicalProfilePayload.medicationsSummary = step2.medicationsSummary;
      }

      const medicalProfileDoc = await db
        .collection("medicalProfile")
        .add(medicalProfilePayload);

      const medicalProfileId = medicalProfileDoc.id;
      console.log("Medical Profile created:", medicalProfileId);

      const medicationIds = [];
      if (Array.isArray(step2?.medications) && step2.medications.length > 0) {
        for (const medication of step2.medications) {
          if (medication.medicationId) {
            await db
              .collection("medications")
              .doc(medication.medicationId)
              .set(
                cleanObject({
                  medicalProfileId,
                  source: medication.source || "profile_setup",
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                }),
                { merge: true },
              );
            medicationIds.push(medication.medicationId);
            continue;
          }

          const medicationName =
            medication.medication_name ||
            medication.medicationName ||
            medication.name;

          if (!medicationName) continue;

          const medicationPayload = cleanObject({
            userId,
            medicalProfileId,
            name: medicationName,
            medicationName,
            medication_name: medicationName,
            dosage: medication.dosage,
            dose: medication.dosage,
            frequency_type: medication.frequency_type,
            frequency_value: medication.frequency_value,
            frequency: medication.frequency || medication.display_freq,
            start_time: medication.start_time,
            scheduled_times: medication.scheduled_times,
            time: medication.time || medication.display_times,
            schedule: medication.schedule || medication.display_times,
            instructions: medication.instructions,
            status: medication.status || "Pending",
            source: "profile_setup",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          const medicationDoc = await db
            .collection("medications")
            .add(medicationPayload);
          medicationIds.push(medicationDoc.id);
        }
      }

      const anthropometricPayload = {
        userId,
        medicalProfileId,
        date: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (heightCm) {
        anthropometricPayload.height = heightCm;
        anthropometricPayload.height_cm = Number(heightCm);
      }
      if (weightKg) {
        anthropometricPayload.weight = weightKg;
        anthropometricPayload.weight_kg = Number(weightKg);
      }
      if (step1?.dryWeight) anthropometricPayload.dryWeight = step1.dryWeight;
      if (bmi) anthropometricPayload.bmi = Number(bmi);
      if (step1?.muac) anthropometricPayload.MUAC = step1.muac;

      const anthropometricDoc = await db
        .collection("anthropometrics")
        .add(anthropometricPayload);

      console.log("Anthropometric data created:", anthropometricDoc.id);

      const labResultPayload = {
        userId,
        medicalProfileId,
        testName: "Blood Test",
        date: step4?.resultDate ?? null,
        creatinine: parseFloat(step4?.creatinine) || null,
        potassium: parseFloat(step4?.potassium) || null,
        phosphorus: parseFloat(step4?.phosphorus) || null,
        phosphorus_status:
          step4?.phosphorus_status ?? step4?.phosphorusStatus ?? null,
        sodium: parseFloat(step4?.sodium) || null,
        sodium_status: step4?.sodium_status ?? step4?.sodiumStatus ?? null,
        calcium: parseFloat(step4?.calcium) || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      const labResultDoc = await db.collection("labResults").add(labResultPayload);

      console.log("Lab Result created:", labResultDoc.id);

      const baselineTargets = generateProfileTargets({
        child_name: step1?.name,
        age_years: ageYears,
        sex,
        height_cm: heightCm,
        weight_kg: weightKg,
        bmi,
        ckd_stage: step1?.ckdStage,
        on_dialysis: step2?.isOnDialysis === true,
        dialysis_type: step2?.dialysisType,
        dry_weight_kg: step1?.dryWeight,
        physical_activity_level: physicalActivityLevel,
        fluid_restriction_status: fluidRestrictionStatus,
        fluid_limit_ml: fluidLimitMl,
      });

      const nutritionTargetDoc = await db.collection("nutritionTargets").add({
        userId,
        medicalProfileId,
        source: "profile_baseline",
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...baselineTargets,
      });

      console.log("Baseline nutrition targets created:", nutritionTargetDoc.id);

      const phase2DecisionSupport = generatePhase2DecisionSupport(
        {
          age_years: ageYears,
          sex,
          weight_kg: weightKg,
          bmi,
          ckd_stage: step1?.ckdStage,
          dialysis_status:
            step2?.isOnDialysis === true ? "on dialysis" : "not on dialysis",
          dialysis_type: step2?.dialysisType,
          physical_activity_level: physicalActivityLevel,
          diet_pattern: dietPattern,
          meal_pattern: mealPattern,
          processed_food_intake: processedFoodIntake,
          has_hypertension: hasHypertension,
          fluid_restriction_status: fluidRestrictionStatus,
          fluid_limit_ml: fluidLimitMl,
        },
        {
          potassium: step4?.potassium,
          phosphorus: step4?.phosphorus,
          phosphorus_status:
            step4?.phosphorus_status ?? step4?.phosphorusStatus,
          sodium: step4?.sodium,
          sodium_status: step4?.sodium_status ?? step4?.sodiumStatus,
          calcium: step4?.calcium,
          creatinine: step4?.creatinine,
          result_date: step4?.resultDate,
        },
      );

      const phase2DecisionSupportDoc = await db
        .collection("phase2DecisionSupport")
        .add({
          userId,
          medicalProfileId,
          labResultId: labResultDoc.id,
          source: "phase2_decision_support",
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...phase2DecisionSupport,
        });

      console.log(
        "Phase 2 decision support created:",
        phase2DecisionSupportDoc.id,
      );

      await db.collection("users").doc(userId).update({
        medicalProfileId,
        baselineNutritionTargetId: nutritionTargetDoc.id,
        phase2DecisionSupportId: phase2DecisionSupportDoc.id,
        labResultId: labResultDoc.id,
        medicationIds,
      });

      console.log("FINAL SUBMIT: All collections created for user:", userId);

      res.status(200).json({
        success: true,
        message: "All data saved successfully to database",
        userId,
        medicalProfileId,
        nutritionTargetId: nutritionTargetDoc.id,
        medicationIds,
        baselineTargets,
        phase2DecisionSupportId: phase2DecisionSupportDoc.id,
        phase2DecisionSupport,
      });
    } catch (error) {
      console.error("FINAL SUBMIT ERROR:", error.message);
      res.status(400).json({
        success: false,
        error: error.message,
      });
    }
  });
}

module.exports = { registerProfileRoutes };
