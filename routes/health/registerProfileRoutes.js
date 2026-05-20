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
    encryptHealthProfile,
    decryptHealthProfile,
    encryptHealthDocument,
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

  function isAdolescentAccountRole(role) {
    return String(role || "").trim().toLowerCase() === "adolescent";
  }

  function isDirectManagedChildEntry(child = {}) {
    if (child?.type === "direct") return true;
    if (
      child?.relationship === "adolescent" ||
      child?.type === "linked" ||
      child?.type === "adolescent"
    ) {
      return false;
    }
    const childAgeGroup = String(child?.childAgeGroup || "");
    if (
      childAgeGroup === "5-12" ||
      childAgeGroup === "5-13" ||
      childAgeGroup === "13-18-direct"
    ) {
      return true;
    }
    const age = Number(child?.age ?? child?.ageYears);
    if (Number.isFinite(age)) return age < 13;
    return true;
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
    console.log("Update profile requested:", {
      userId: req.body.userId || req.body.uid || null,
      profileUserId: req.body.profileUserId || req.body.targetUserId || null,
      hasSensitiveFields: Boolean(
        req.body.childFullName ||
          req.body.dateOfBirth ||
          req.body.allergies,
      ),
    });

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
        isPostTransplant,
        is_post_transplant,
        requiresSterileDiet,
        requires_sterile_diet,
        sterileDietWeeks,
        sterile_diet_weeks,
        isPostSurgery,
        is_post_surgery,
        hasCalciumPhosphorusImbalance,
        has_calcium_phosphorus_imbalance,
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
      const linkedChildren = Array.isArray(actingUser.linkedChildren)
        ? actingUser.linkedChildren
        : [];
      const isManagedLinkedChild = linkedChildren.some((child) => {
        const childId = child?.userId || child?.uid || child?.id;
        return String(childId || "") === String(requestedProfileUserId);
      });
      const isLinkedCaregiverEditingChild =
        requestedProfileUserId !== actingUserId &&
        isCaregiverRole(actingUser.role) &&
        actingUser.linkedChildAccount === true &&
        (actingUser.linkedChildUserId === requestedProfileUserId ||
          isManagedLinkedChild);

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

      const existingUser = decryptHealthProfile(userDoc.data() || {});
      const roleValue = existingUser.role || null;
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
      const postTransplantValue = isPostTransplant ?? is_post_transplant;
      const sterileDietInput = requiresSterileDiet ?? requires_sterile_diet;
      const sterileDietWeeksValue = sterileDietWeeks ?? sterile_diet_weeks;
      const postSurgeryValue = isPostSurgery ?? is_post_surgery;
      const calciumPhosphorusImbalanceValue =
        hasCalciumPhosphorusImbalance ?? has_calcium_phosphorus_imbalance;
      const sterileDietValue =
        sterileDietInput !== undefined && sterileDietInput !== null
          ? sterileDietInput
          : postTransplantValue === true ||
            String(postTransplantValue || "").trim().toLowerCase() === "yes";
      const allergiesValue = normalizeAllergiesInput(req.body.allergies);
      const isLinkedAdolescent =
        isAdolescentAccountRole(roleValue) &&
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
      if (existingUser.role) {
        userPayload.role = existingUser.role;
      }
      if (existingUser.userRole) {
        userPayload.userRole = existingUser.userRole;
      }
      if (existingUser.securitySettings !== undefined) {
        userPayload.securitySettings = existingUser.securitySettings;
      }
      if (existingUser.mfaEnabled !== undefined) {
        userPayload.mfaEnabled = existingUser.mfaEnabled;
      }
      if (existingUser.mfaMethod !== undefined) {
        userPayload.mfaMethod = existingUser.mfaMethod;
      }

      await userRef.set(encryptHealthProfile(userPayload), { merge: true });

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
        isPostTransplant: postTransplantValue,
        is_post_transplant: postTransplantValue,
        requiresSterileDiet: sterileDietValue,
        requires_sterile_diet: sterileDietValue,
        sterileDietWeeks: sterileDietWeeksValue,
        sterile_diet_weeks: sterileDietWeeksValue,
        isPostSurgery: postSurgeryValue,
        is_post_surgery: postSurgeryValue,
        hasCalciumPhosphorusImbalance: calciumPhosphorusImbalanceValue,
        has_calcium_phosphorus_imbalance: calciumPhosphorusImbalanceValue,
        allergies: allergiesValue,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (medicalProfileId) {
        await db
          .collection("medicalProfile")
          .doc(medicalProfileId)
          .set(encryptHealthDocument(medicalProfilePayload), { merge: true });
      } else {
        const medicalDoc = await db.collection("medicalProfile").add({
          ...encryptHealthDocument(medicalProfilePayload),
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
      const actingUserDoc = await db.collection("users").doc(userId).get();
      const actingUser = actingUserDoc.exists
        ? decryptHealthProfile(actingUserDoc.data() || {})
        : {};
      const linkedChildren = Array.isArray(actingUser.linkedChildren)
        ? actingUser.linkedChildren
        : [];
      const stagedChildAgeGroupRaw =
        req.body.caregiverChildAgeGroup || actingUser.pendingChildAgeGroup;
      const stagedChildAgeGroup =
        stagedChildAgeGroupRaw === "5-13" ? "5-13" : "5-12";
      const shouldCreateCaregiverChild =
        !req.body.childProfileId &&
        !req.body.profileUserId &&
        isCaregiverRole(actingUser.role) &&
        Boolean(stagedChildAgeGroupRaw);
      let requestedProfileUserId =
        req.body.childProfileId || req.body.profileUserId || userId;

      if (shouldCreateCaregiverChild) {
        if (linkedChildren.length >= 3) {
          return res.status(400).json({
            success: false,
            error: "This caregiver account can manage up to 3 child profiles",
          });
        }
        requestedProfileUserId = db.collection("users").doc().id;
      }

      const isCaregiverChildSetup =
        shouldCreateCaregiverChild ||
        (requestedProfileUserId !== userId &&
          isCaregiverRole(actingUser.role) &&
          linkedChildren.some((child) => {
            const childId = child?.userId || child?.uid || child?.id;
            return String(childId || "") === String(requestedProfileUserId);
          }));

      if (requestedProfileUserId !== userId && !isCaregiverChildSetup) {
        return res.status(403).json({
          success: false,
          error: "You are not allowed to create this child profile",
        });
      }

      const profileUserId = requestedProfileUserId;
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
      const hasEdema = step3?.has_edema ?? step3?.hasEdema ?? step2?.has_edema ?? step2?.hasEdema;
      const isPostTransplant =
        step1?.is_post_transplant ??
        step1?.isPostTransplant ??
        step1?.post_transplant ??
        step1?.postTransplant;
      const requiresSterileDietInput =
        step1?.requires_sterile_diet ?? step1?.requiresSterileDiet;
      const requiresSterileDiet =
        requiresSterileDietInput !== undefined && requiresSterileDietInput !== null
          ? requiresSterileDietInput
          : isPostTransplant === true ||
            String(isPostTransplant || "").trim().toLowerCase() === "yes";
      const sterileDietWeeks =
        step1?.sterile_diet_weeks ??
        step1?.sterileDietWeeks ??
        step1?.weeks_post_transplant ??
        step1?.weeksPostTransplant;
      const isPostSurgery =
        step1?.is_post_surgery ?? step1?.isPostSurgery ?? requiresSterileDiet;
      const hasCalciumPhosphorusImbalance =
        step1?.has_calcium_phosphorus_imbalance ??
        step1?.hasCalciumPhosphorusImbalance;
      const appetite = step3?.appetite ?? step3?.appetiteStatus ?? step2?.appetite;
      const bmiStatus = step1?.bmi_status ?? step1?.bmiStatus;
      const muacStatus = step1?.muac_status ?? step1?.muacStatus;
      const ckdType = step1?.ckd_type ?? step1?.ckdType;
      const proteinCategory = step3?.protein_category ?? step3?.proteinCategory;
      const hasDiabetes = step1?.has_diabetes ?? step1?.hasDiabetes ?? step2?.has_diabetes ?? step2?.hasDiabetes;
      const hasHighProteinRequirement =
        step3?.has_high_protein_requirement ?? step3?.hasHighProteinRequirement;
      const dietPattern = step3?.diet_pattern ?? step3?.dietPattern;
      const processedFoodIntake =
        step3?.processed_food_intake ?? step3?.processedFoodIntake;
      const mealPattern = step3?.meal_pattern ?? step3?.mealPattern;
      const allergies = normalizeAllergiesInput(step2?.allergies);
      const setupMedications = Array.isArray(step4?.medications)
        ? step4.medications
        : Array.isArray(step2?.medications)
          ? step2.medications
          : [];
      const setupMedicationsSummary =
        step4?.medicationsSummary ?? step2?.medicationsSummary;
      const caregiverSettings = sanitizeCaregiverSettings(
        step1?.caregiverSettings,
        {},
      );

      const existingUserDoc = await db.collection("users").doc(profileUserId).get();
      const existingUser =
        existingUserDoc.exists
          ? decryptHealthProfile(existingUserDoc.data() || {})
          : {};
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
          userId: profileUserId,
          ...(isCaregiverChildSetup ? { caregiverUserId: userId } : {}),
          medicalProfileId: existingUser.medicalProfileId,
          nutritionTargetId: existingUser.baselineNutritionTargetId,
          baselineTargets: existingTargets,
          phase2DecisionSupportId: existingUser.phase2DecisionSupportId,
          phase2DecisionSupport: existingPhase2DecisionSupport,
        });
      }

      const userPayload = {
        uid: profileUserId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      const caregiverUserId = isCaregiverChildSetup
        ? userId
        : existingUser.caregiverUserId;
      if (caregiverUserId) {
        userPayload.caregiverUserId = caregiverUserId;
      }
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
      if (isCaregiverChildSetup) {
        const childAgeGroup =
          stagedChildAgeGroup || existingUser.childAgeGroup || "5-12";
        userPayload.role = "managed_child";
        userPayload.childAgeGroup = childAgeGroup;
        userPayload.profileComplete = true;
      } else if (userRole) {
        userPayload.role = userRole;
      }
      if (!isCaregiverChildSetup && userRole === "adolescent") {
        userPayload.caregiverSettings = caregiverSettings;
        userPayload.editPermissions = buildEditPermissions(
          userRole,
          caregiverSettings,
          step1?.editPermissions || {},
        );
      }
      await db
        .collection("users")
        .doc(profileUserId)
        .set(encryptHealthProfile(userPayload), { merge: true });

      const medicalProfilePayload = {
        userId: profileUserId,
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
      if (hasEdema) {
        medicalProfilePayload.hasEdema = hasEdema;
        medicalProfilePayload.has_edema = hasEdema;
      }
      if (isPostTransplant) {
        medicalProfilePayload.isPostTransplant = isPostTransplant;
        medicalProfilePayload.is_post_transplant = isPostTransplant;
      }
      medicalProfilePayload.requiresSterileDiet = requiresSterileDiet;
      medicalProfilePayload.requires_sterile_diet = requiresSterileDiet;
      if (sterileDietWeeks !== undefined && sterileDietWeeks !== null) {
        medicalProfilePayload.sterileDietWeeks = Number(sterileDietWeeks);
        medicalProfilePayload.sterile_diet_weeks = Number(sterileDietWeeks);
      }
      medicalProfilePayload.isPostSurgery = isPostSurgery;
      medicalProfilePayload.is_post_surgery = isPostSurgery;
      if (hasCalciumPhosphorusImbalance !== undefined) {
        medicalProfilePayload.hasCalciumPhosphorusImbalance =
          hasCalciumPhosphorusImbalance;
        medicalProfilePayload.has_calcium_phosphorus_imbalance =
          hasCalciumPhosphorusImbalance;
      }
      if (appetite) {
        medicalProfilePayload.appetite = appetite;
      }
      if (ckdType) {
        medicalProfilePayload.ckdType = ckdType;
        medicalProfilePayload.ckd_type = ckdType;
      }
      if (proteinCategory) {
        medicalProfilePayload.proteinCategory = proteinCategory;
        medicalProfilePayload.protein_category = proteinCategory;
      }
      if (hasDiabetes) {
        medicalProfilePayload.hasDiabetes = hasDiabetes;
        medicalProfilePayload.has_diabetes = hasDiabetes;
      }
      if (hasHighProteinRequirement) {
        medicalProfilePayload.hasHighProteinRequirement = hasHighProteinRequirement;
        medicalProfilePayload.has_high_protein_requirement = hasHighProteinRequirement;
      }
      medicalProfilePayload.allergies = allergies;
      if (setupMedications.length > 0) {
        medicalProfilePayload.medications = setupMedications;
      }
      if (setupMedicationsSummary) {
        medicalProfilePayload.medicationsSummary = setupMedicationsSummary;
      }

      const medicalProfileDoc = await db
        .collection("medicalProfile")
        .add(encryptHealthDocument(medicalProfilePayload));

      const medicalProfileId = medicalProfileDoc.id;
      console.log("Medical Profile created:", medicalProfileId);

      const medicationIds = [];
      if (setupMedications.length > 0) {
        for (const medication of setupMedications) {
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
            userId: profileUserId,
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
            .add(encryptHealthDocument(medicationPayload));
          medicationIds.push(medicationDoc.id);
        }
      }

      const anthropometricPayload = {
        userId: profileUserId,
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

      const hasLabResultData = Boolean(
        step4?.resultDate ||
          step4?.creatinine ||
          step4?.potassium ||
          step4?.phosphorus ||
          step4?.phosphorus_status ||
          step4?.phosphorusStatus ||
          step4?.sodium ||
          step4?.sodium_status ||
          step4?.sodiumStatus ||
          step4?.calcium,
      );
      let labResultDoc = null;
      if (hasLabResultData) {
        const labResultPayload = {
          userId: profileUserId,
          medicalProfileId,
          testName: "Blood Test",
          date: step4?.resultDate ?? null,
          albumin: parseFloat(step4?.albumin) || null,
          albumin_status:
            step4?.albumin_status ?? step4?.albuminStatus ?? null,
          BUN: parseFloat(step4?.BUN ?? step4?.bun) || null,
          BUN_status:
            step4?.BUN_status ?? step4?.bun_status ?? step4?.bunStatus ?? null,
          urea: parseFloat(step4?.urea) || null,
          urea_status: step4?.urea_status ?? step4?.ureaStatus ?? null,
          hemoglobin: parseFloat(step4?.hemoglobin) || null,
          hemoglobin_status:
            step4?.hemoglobin_status ?? step4?.hemoglobinStatus ?? null,
          creatinine: parseFloat(step4?.creatinine) || null,
          potassium: parseFloat(step4?.potassium) || null,
          potassium_status:
            step4?.potassium_status ?? step4?.potassiumStatus ?? null,
          phosphorus: parseFloat(step4?.phosphorus) || null,
          phosphorus_status:
            step4?.phosphorus_status ?? step4?.phosphorusStatus ?? null,
          sodium: parseFloat(step4?.sodium) || null,
          sodium_status: step4?.sodium_status ?? step4?.sodiumStatus ?? null,
          calcium: parseFloat(step4?.calcium) || null,
          calcium_status: step4?.calcium_status ?? step4?.calciumStatus ?? null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        labResultDoc = await db
          .collection("labResults")
          .add(encryptHealthDocument(labResultPayload));
        console.log("Lab Result created:", labResultDoc.id);
      }

      const baselineTargets = generateProfileTargets({
        child_name: step1?.name,
        age_years: ageYears,
        sex,
        height_cm: heightCm,
        weight_kg: weightKg,
        bmi,
        ckd_stage: step1?.ckdStage,
        ckd_type: ckdType,
        protein_category: proteinCategory,
        has_diabetes: hasDiabetes,
        has_high_protein_requirement: hasHighProteinRequirement,
        appetite,
        bmi_status: bmiStatus,
        muac_status: muacStatus,
        on_dialysis: step2?.isOnDialysis === true,
        dialysis_type: step2?.dialysisType,
        dry_weight_kg: step1?.dryWeight,
        physical_activity_level: physicalActivityLevel,
        fluid_restriction_status: fluidRestrictionStatus,
        fluid_limit_ml: fluidLimitMl,
        is_post_transplant: isPostTransplant,
        requires_sterile_diet: requiresSterileDiet,
        sterile_diet_weeks: sterileDietWeeks,
        is_post_surgery: isPostSurgery,
        has_calcium_phosphorus_imbalance: hasCalciumPhosphorusImbalance,
      });

      const nutritionTargetDoc = await db.collection("nutritionTargets").add({
        userId: profileUserId,
        medicalProfileId,
        source: "profile_baseline",
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...encryptHealthDocument(baselineTargets),
      });

      console.log("Baseline nutrition targets created:", nutritionTargetDoc.id);

      const phase2DecisionSupport = generatePhase2DecisionSupport(
        {
          age_years: ageYears,
          sex,
          weight_kg: weightKg,
          bmi,
          ckd_stage: step1?.ckdStage,
          ckd_type: ckdType,
          protein_category: proteinCategory,
          has_diabetes: hasDiabetes,
          has_high_protein_requirement: hasHighProteinRequirement,
          appetite,
          bmi_status: bmiStatus,
          muac_status: muacStatus,
          dialysis_status:
            step2?.isOnDialysis === true ? "on dialysis" : "not on dialysis",
          dialysis_type: step2?.dialysisType,
          physical_activity_level: physicalActivityLevel,
          diet_pattern: dietPattern,
          meal_pattern: mealPattern,
          processed_food_intake: processedFoodIntake,
          has_hypertension: hasHypertension,
          has_edema: hasEdema,
          is_post_transplant: isPostTransplant,
          requires_sterile_diet: requiresSterileDiet,
          sterile_diet_weeks: sterileDietWeeks,
          is_post_surgery: isPostSurgery,
          has_calcium_phosphorus_imbalance: hasCalciumPhosphorusImbalance,
          fluid_restriction_status: fluidRestrictionStatus,
          fluid_limit_ml: fluidLimitMl,
        },
        {
          albumin: step4?.albumin,
          albumin_status: step4?.albumin_status ?? step4?.albuminStatus,
          BUN: step4?.BUN ?? step4?.bun,
          BUN_status: step4?.BUN_status ?? step4?.bun_status ?? step4?.bunStatus,
          urea: step4?.urea,
          urea_status: step4?.urea_status ?? step4?.ureaStatus,
          hemoglobin: step4?.hemoglobin,
          hemoglobin_status: step4?.hemoglobin_status ?? step4?.hemoglobinStatus,
          potassium: step4?.potassium,
          potassium_status: step4?.potassium_status ?? step4?.potassiumStatus,
          phosphorus: step4?.phosphorus,
          phosphorus_status:
            step4?.phosphorus_status ?? step4?.phosphorusStatus,
          sodium: step4?.sodium,
          sodium_status: step4?.sodium_status ?? step4?.sodiumStatus,
          calcium: step4?.calcium,
          calcium_status: step4?.calcium_status ?? step4?.calciumStatus,
          creatinine: step4?.creatinine,
          result_date: step4?.resultDate,
        },
      );

      const phase2DecisionSupportDoc = await db
        .collection("phase2DecisionSupport")
        .add({
          ...encryptHealthDocument({
            userId: profileUserId,
            medicalProfileId,
            labResultId: labResultDoc?.id || null,
            source: "phase2_decision_support",
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ...phase2DecisionSupport,
          }),
        });

      console.log(
        "Phase 2 decision support created:",
        phase2DecisionSupportDoc.id,
      );

      await db.collection("users").doc(profileUserId).update({
        medicalProfileId,
        baselineNutritionTargetId: nutritionTargetDoc.id,
        phase2DecisionSupportId: phase2DecisionSupportDoc.id,
        labResultId: labResultDoc?.id || null,
        medicationIds,
      });

      if (isCaregiverChildSetup) {
        const childEntry = {
          id: profileUserId,
          userId: profileUserId,
          type: "direct",
          childAgeGroup:
            stagedChildAgeGroup || existingUser.childAgeGroup || "5-12",
          ckdStage: step1?.ckdStage || null,
          age: ageYears ?? null,
          profileComplete: true,
        };
        const hasExistingEntry = linkedChildren.some((child) => {
          const childId = child?.userId || child?.uid || child?.id;
          return String(childId || "") === String(profileUserId);
        });
        const nextLinkedChildren = hasExistingEntry
          ? linkedChildren.map((child) => {
              const childId = child?.userId || child?.uid || child?.id;
              if (String(childId || "") !== String(profileUserId)) return child;
              return { ...child, ...childEntry };
            })
          : [...linkedChildren, childEntry];
        const linkedAccountChild = nextLinkedChildren.find(
          (child) => !isDirectManagedChildEntry(child),
        );

        await db.collection("users").doc(userId).set(
          {
            childProfileCreated: true,
            activeDirectChildProfileId: profileUserId,
            pendingChildAgeGroup: admin.firestore.FieldValue.delete(),
            linkedChildAccount: Boolean(linkedAccountChild),
            linkedChildUserId:
              linkedAccountChild?.userId ||
              linkedAccountChild?.uid ||
              linkedAccountChild?.id ||
              null,
            linkedChildren: nextLinkedChildren,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      console.log("FINAL SUBMIT: All collections created for user:", profileUserId);

      res.status(200).json({
        success: true,
        message: "All data saved successfully to database",
        userId: profileUserId,
        ...(isCaregiverChildSetup
          ? { caregiverUserId: userId, childProfileId: profileUserId }
          : {}),
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
