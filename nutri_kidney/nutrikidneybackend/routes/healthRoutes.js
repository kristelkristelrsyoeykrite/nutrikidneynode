const express = require("express");
const router = express.Router();
const { admin, db } = require("../firebase/admin");
const { generateProfileTargets } = require("../services/profileTargetGenerator");
const { generatePhase2DecisionSupport } = require("../services/phase2DecisionSupport");

//////////////////// STEP 1 - Just collect data ////////////////////
router.post("/step1", async (req, res) => {
  console.log("Step 1 received:", req.body);
  
  try {
    res.json({
      success: true,
      message: "Step 1 data received (waiting for final submission)",
    });
  } catch (error) {
    console.error("Step 1 Error:", error.message);
    res.status(400).json({
      success: false,
      error: error.message
    });
  }
});

//////////////////// STEP 2 - Just collect data ////////////////////
router.post("/step2", async (req, res) => {
  console.log("Step 2 received:", req.body);
  
  try {
    res.json({
      success: true,
      message: "Step 2 data received (waiting for final submission)",
      data: req.body,
    });
  } catch (error) {
    console.error("Step 2 Error:", error.message);
    res.status(400).json({
      success: false,
      error: error.message
    });
  }
});


//////////////// STEP 3 - Just collect data ///////////////////////////
router.post("/step3", async (req, res) => {
  console.log("Step 3 received:", req.body);

  try {
    res.json({
      success: true,
      message: "Step 3 data received (waiting for final submission)",
      data: req.body
    });
  } catch (error) {
    console.error("Step 3 Error:", error.message);
    res.status(400).json({
      success: false,
      error: error.message
    });
  }
});

//////////////////// STEP 4 - Just collect data //////////////////////

router.post("/step4", async (req, res) => {
  console.log("Step 4 received:", req.body);

  try {
    res.json({
      success: true,
      message: "Step 4 data received (waiting for final submission)",
      data: req.body
    });
  } catch (error) {
    console.error("Step 4 Error:", error.message);
    res.status(400).json({
      success: false,
      error: error.message
    });
  }
});

router.post("/phase2-decision-support", async (req, res) => {
  console.log("Phase 2 decision support received:", req.body);

  try {
    const profile = req.body.profile || {
      ckd_stage: req.body.ckd_stage,
      processed_food_intake: req.body.processed_food_intake,
      meal_pattern: req.body.meal_pattern,
      diet_pattern: req.body.diet_pattern,
      fluid_restriction_status: req.body.fluid_restriction_status,
      fluid_limit_ml: req.body.fluid_limit_ml,
      has_hypertension: req.body.has_hypertension,
    };
    const labs = req.body.labs || {
      potassium: req.body.potassium,
      phosphorus: req.body.phosphorus,
      phosphorus_status: req.body.phosphorus_status,
      sodium: req.body.sodium,
      sodium_status: req.body.sodium_status,
      calcium: req.body.calcium,
      creatinine: req.body.creatinine,
      result_date: req.body.result_date,
    };
    const intake = req.body.intake || null;
    const decisionSupport = generatePhase2DecisionSupport(profile, labs, intake);

    res.status(200).json({
      success: true,
      decisionSupport,
    });
  } catch (error) {
    console.error("PHASE2_DECISION_SUPPORT ERROR:", error.message);
    res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

/**
 * SAVE MEDICATION
 * Stores alarm-like medication schedules.
 */
router.post("/save-medication", async (req, res) => {
  console.log("Save medication requested:", req.body);

  try {
    const {
      userId,
      uid,
      medication_name,
      medicationName,
      name,
      dosage,
      instructions,
      frequency_type, // 'times_per_day' or 'interval'
      frequency_value, // e.g., 2 (for 2x day) or 8 (for every 8h)
      start_time,      // '08:00'
      scheduled_times, // ['08:00', '20:00']
      frequency,
      display_freq,
      time,
      schedule,
      display_times,
      status,
      source
    } = req.body;

    const medicationNameValue = medication_name || medicationName || name;
    const medicationUserId = userId || uid;

    if (!medicationUserId || !medicationNameValue || !frequency_type || !start_time) {
      throw new Error("Missing required medication fields");
    }

    const medicationPayload = cleanObject({
      userId: medicationUserId,
      uid: medicationUserId,
      name: medicationNameValue,
      medicationName: medicationNameValue,
      medication_name: medicationNameValue,
      dosage,
      dose: dosage,
      instructions,
      frequency_type,
      frequency_value: Number(frequency_value),
      frequency: frequency || display_freq,
      start_time,
      scheduled_times: scheduled_times || [],
      time: time || display_times,
      schedule: schedule || display_times,
      status: status || "Pending",
      source: source || "manual_entry",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const docRef = await db.collection("medications").add(medicationPayload);

    res.status(200).json({
      success: true,
      medicationId: docRef.id,
      message: "Medication schedule saved successfully",
    });
  } catch (error) {
    console.error("SAVE_MEDICATION ERROR:", error.message);
    res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.post("/update-medication", async (req, res) => {
  console.log("Update medication requested:", req.body);

  try {
    const {
      userId,
      uid,
      medicationId,
      medication_name,
      medicationName,
      name,
      dosage,
      instructions,
      frequency_type,
      frequency_value,
      start_time,
      scheduled_times,
      frequency,
      display_freq,
      time,
      schedule,
      display_times,
      status,
    } = req.body;

    const medicationUserId = userId || uid;
    const medicationNameValue = medication_name || medicationName || name;

    if (!medicationUserId || !medicationId) {
      throw new Error("Missing required medication update fields");
    }

    const docRef = db.collection("medications").doc(medicationId);
    const doc = await docRef.get();

    if (!doc.exists) {
      return res.status(404).json({
        success: false,
        error: "Medication not found",
      });
    }

    const existing = doc.data() || {};
    if (existing.userId && existing.userId !== medicationUserId) {
      return res.status(403).json({
        success: false,
        error: "Medication does not belong to this user",
      });
    }

    const medicationPayload = cleanObject({
      userId: medicationUserId,
      uid: medicationUserId,
      name: medicationNameValue,
      medicationName: medicationNameValue,
      medication_name: medicationNameValue,
      dosage,
      dose: dosage,
      instructions,
      frequency_type,
      frequency_value:
        frequency_value === undefined ? undefined : Number(frequency_value),
      frequency: frequency || display_freq,
      start_time,
      scheduled_times,
      time: time || display_times,
      schedule: schedule || display_times,
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await docRef.set(medicationPayload, { merge: true });

    res.status(200).json({
      success: true,
      medicationId,
      message: "Medication updated successfully",
    });
  } catch (error) {
    console.error("UPDATE_MEDICATION ERROR:", error.message);
    res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.post("/delete-medication", async (req, res) => {
  console.log("Delete medication requested:", req.body);

  try {
    const { userId, uid, medicationId } = req.body;
    const medicationUserId = userId || uid;

    if (!medicationUserId || !medicationId) {
      throw new Error("Missing required medication delete fields");
    }

    const docRef = db.collection("medications").doc(medicationId);
    const doc = await docRef.get();

    if (!doc.exists) {
      return res.status(404).json({
        success: false,
        error: "Medication not found",
      });
    }

    const existing = doc.data() || {};
    if (existing.userId && existing.userId !== medicationUserId) {
      return res.status(403).json({
        success: false,
        error: "Medication does not belong to this user",
      });
    }

    await docRef.delete();

    res.status(200).json({
      success: true,
      medicationId,
      message: "Medication deleted successfully",
    });
  } catch (error) {
    console.error("DELETE_MEDICATION ERROR:", error.message);
    res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

////////////// FINAL SUBMIT - Saves All Data to Firestore //////////////

// Helper function to clean undefined values from objects
function cleanObject(obj) {
  const cleaned = {};
  for (const key in obj) {
    if (obj[key] !== undefined && obj[key] !== null && obj[key] !== "") {
      cleaned[key] = obj[key];
    }
  }
  return cleaned;
}

async function getDocumentData(collectionName, id) {
  if (!id) return null;

  const snapshot = await db.collection(collectionName).doc(id).get();
  return snapshot.exists ? { id: snapshot.id, ...snapshot.data() } : null;
}

async function getFirstUserDocument(collectionName, userId) {
  const snapshot = await db
    .collection(collectionName)
    .where("userId", "==", userId)
    .limit(1)
    .get();

  if (snapshot.empty) return null;

  const doc = snapshot.docs[0];
  return { id: doc.id, ...doc.data() };
}

async function getUserDocuments(collectionName, userId, limit = 20) {
  return getDocumentsByField(collectionName, "userId", userId, limit);
}

async function getDocumentsByField(collectionName, fieldName, value, limit = 20) {
  if (!value) return [];

  const snapshot = await db
    .collection(collectionName)
    .where(fieldName, "==", value)
    .limit(limit)
    .get();

  return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

async function getDocumentsByIds(collectionName, ids = []) {
  if (!Array.isArray(ids) || ids.length === 0) return [];

  const uniqueIds = [...new Set(ids.filter(Boolean))];
  const docs = await Promise.all(
    uniqueIds.map((id) => getDocumentData(collectionName, id)),
  );

  return docs.filter(Boolean);
}

function uniqueDocumentsById(records) {
  const seen = new Set();
  return records.filter((record) => {
    if (!record?.id || seen.has(record.id)) return false;
    seen.add(record.id);
    return true;
  });
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value._seconds === "number") return value._seconds * 1000;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function sortByNewest(records) {
  return [...records].sort((a, b) => {
    const aTime = Math.max(
      timestampMillis(a.createdAt),
      timestampMillis(a.date),
      timestampMillis(a.resultDate),
    );
    const bTime = Math.max(
      timestampMillis(b.createdAt),
      timestampMillis(b.date),
      timestampMillis(b.resultDate),
    );
    return bTime - aTime;
  });
}

function normalizeActivityLevel(value) {
  const text = String(value || "").toLowerCase();
  if (text.includes("low")) return "low";
  if (text.includes("moderate")) return "moderate";
  if (text.includes("high")) return "high";
  return value;
}

function calculateBmi(weightKg, heightCm) {
  const weight = Number(weightKg);
  const height = Number(heightCm);
  if (!Number.isFinite(weight) || !Number.isFinite(height) || height <= 0) {
    return null;
  }

  const heightMeters = height > 3 ? height / 100 : height;
  if (heightMeters <= 0) return null;
  return Number((weight / (heightMeters * heightMeters)).toFixed(1));
}

function withoutDocumentId(record) {
  if (!record) return {};
  const { id, ...data } = record;
  return data;
}

async function archiveCurrentRecord(record, historicalCollectionName) {
  if (!record?.id) return null;

  const archivePayload = {
    ...withoutDocumentId(record),
    archivedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const archiveRef = await db
    .collection(historicalCollectionName)
    .add(archivePayload);

  return archiveRef.id;
}

async function archiveAndDeleteExtraCurrentRecords({
  records,
  keepId,
  currentCollectionName,
  historicalCollectionName,
}) {
  const extraRecords = uniqueDocumentsById(records).filter(
    (record) => record.id && record.id !== keepId,
  );

  for (const record of extraRecords) {
    await archiveCurrentRecord(record, historicalCollectionName);
    await db.collection(currentCollectionName).doc(record.id).delete();
  }
}

async function recalculateNutritionArtifacts(userId) {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    throw new Error("User profile not found for nutrition recalculation");
  }

  const user = { id: userDoc.id, ...userDoc.data() };
  const medicalProfile = await getDocumentData(
    "medicalProfile",
    user.medicalProfileId,
  );
  const anthropometricRecords = sortByNewest(
    uniqueDocumentsById([
      ...(await getUserDocuments("anthropometrics", userId)),
      ...(await getDocumentsByField(
        "anthropometrics",
        "medicalProfileId",
        user.medicalProfileId,
      )),
    ]),
  );
  const anthropometrics = anthropometricRecords[0] || {};
  const labResults =
    (await getDocumentData("labResults", user.labResultId)) ||
    (await getFirstUserDocument("labResults", userId)) ||
    {};

  const profile = {
    child_name: user.childFullName || user.child_name || user.name,
    age_years: user.ageYears ?? user.age_years,
    sex: user.sex ?? user.gender,
    height_cm: anthropometrics.height_cm ?? anthropometrics.height,
    weight_kg: anthropometrics.weight_kg ?? anthropometrics.weight,
    bmi: anthropometrics.bmi ?? user.bmi,
    ckd_stage: medicalProfile?.ckdStage ?? medicalProfile?.ckd_stage,
    on_dialysis: medicalProfile?.onDialysis === true,
    dialysis_type: medicalProfile?.dialysisType,
    dry_weight_kg:
      anthropometrics.dry_weight_kg ?? anthropometrics.dryWeight,
    physical_activity_level:
      medicalProfile?.physical_activity_level ??
      medicalProfile?.physicalActivityLevel,
    fluid_restriction_status:
      medicalProfile?.fluid_restriction_status ??
      medicalProfile?.fluidRestrictionStatus,
    fluid_limit_ml:
      medicalProfile?.fluid_limit_ml ?? medicalProfile?.fluidLimitMl,
  };

  const baselineTargets = generateProfileTargets(profile);
  const nutritionPayload = {
    userId,
    medicalProfileId: user.medicalProfileId || null,
    source: "profile_baseline",
    regeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...baselineTargets,
  };

  let nutritionTargetId = user.baselineNutritionTargetId;
  if (nutritionTargetId) {
    await db
      .collection("nutritionTargets")
      .doc(nutritionTargetId)
      .set(nutritionPayload, { merge: true });
  } else {
    const nutritionDoc = await db.collection("nutritionTargets").add({
      ...nutritionPayload,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    nutritionTargetId = nutritionDoc.id;
  }

  const phase2DecisionSupport = generatePhase2DecisionSupport(
    {
      age_years: profile.age_years,
      sex: profile.sex,
      weight_kg: profile.weight_kg,
      bmi: profile.bmi,
      ckd_stage: profile.ckd_stage,
      dialysis_status: profile.on_dialysis ? "on dialysis" : "not on dialysis",
      dialysis_type: profile.dialysis_type,
      physical_activity_level: profile.physical_activity_level,
      diet_pattern: medicalProfile?.diet_pattern ?? medicalProfile?.dietPattern,
      meal_pattern: medicalProfile?.meal_pattern ?? medicalProfile?.mealPattern,
      processed_food_intake:
        medicalProfile?.processed_food_intake ??
        medicalProfile?.processedFoodIntake,
      has_hypertension:
        medicalProfile?.has_hypertension ?? medicalProfile?.hasHypertension,
      fluid_restriction_status: profile.fluid_restriction_status,
      fluid_limit_ml: profile.fluid_limit_ml,
    },
    {
      potassium: labResults.potassium,
      phosphorus: labResults.phosphorus,
      phosphorus_status: labResults.phosphorus_status,
      sodium: labResults.sodium,
      sodium_status: labResults.sodium_status,
      calcium: labResults.calcium,
      creatinine: labResults.creatinine,
      result_date: labResults.date ?? labResults.resultDate,
    },
  );

  let phase2DecisionSupportId = user.phase2DecisionSupportId;
  const phase2Payload = {
    userId,
    medicalProfileId: user.medicalProfileId || null,
    labResultId: labResults.id || user.labResultId || null,
    source: "phase2_decision_support",
    regeneratedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...phase2DecisionSupport,
  };

  if (phase2DecisionSupportId) {
    await db
      .collection("phase2DecisionSupport")
      .doc(phase2DecisionSupportId)
      .set(phase2Payload, { merge: true });
  } else {
    const phase2Doc = await db.collection("phase2DecisionSupport").add({
      ...phase2Payload,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    phase2DecisionSupportId = phase2Doc.id;
  }

  await db.collection("users").doc(userId).set(
    {
      baselineNutritionTargetId: nutritionTargetId,
      phase2DecisionSupportId,
      bmi: baselineTargets.bmi,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    nutritionTargetId,
    baselineTargets,
    phase2DecisionSupportId,
    phase2DecisionSupport,
  };
}

router.post("/dashboard-summary", async (req, res) => {
  console.log("Dashboard summary requested:", req.body);

  try {
    const { userId } = req.body;

    if (!userId) {
      throw new Error("Missing userId");
    }

    const userDoc = await db.collection("users").doc(userId).get();

    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const user = { id: userDoc.id, ...userDoc.data() };
    const nutritionTargets = await getDocumentData(
      "nutritionTargets",
      user.baselineNutritionTargetId,
    );
    const medicalProfile = await getDocumentData(
      "medicalProfile",
      user.medicalProfileId,
    );
    const phase2DecisionSupport = await getDocumentData(
      "phase2DecisionSupport",
      user.phase2DecisionSupportId,
    );
    const labResults =
      (await getDocumentData("labResults", user.labResultId)) ||
      (await getFirstUserDocument("labResults", userId));
    const anthropometricHistoryByUser = await getUserDocuments(
      "anthropometrics",
      userId,
    );
    const anthropometricHistoryByProfile = await getDocumentsByField(
      "anthropometrics",
      "medicalProfileId",
      user.medicalProfileId,
    );
    const anthropometricHistory = sortByNewest([
      ...anthropometricHistoryByUser,
      ...anthropometricHistoryByProfile,
    ]);
    const anthropometrics = anthropometricHistory[0] || null;
    const medicationUserIds = [
      userId,
      user.uid,
      user.firebaseUid,
      user.authUid,
    ].filter(Boolean);
    const medicationsByUserId = (
      await Promise.all(
        medicationUserIds.map((id) => getUserDocuments("medications", id)),
      )
    ).flat();
    const medicationsByUid = (
      await Promise.all(
        medicationUserIds.map((id) =>
          getDocumentsByField("medications", "uid", id),
        ),
      )
    ).flat();
    const medicationsByIds = await getDocumentsByIds(
      "medications",
      user.medicationIds,
    );
    const medications = sortByNewest(
      uniqueDocumentsById([
        ...medicationsByUserId,
        ...medicationsByUid,
        ...medicationsByIds,
      ]),
    );

    return res.status(200).json({
      success: true,
      user,
      nutritionTargets,
      medicalProfile,
      phase2DecisionSupport,
      labResults,
      anthropometrics,
      intakeData: null,
      medicationData: medications.length > 0 ? { count: medications.length } : null,
      medications,
    });
  } catch (error) {
    console.error("DASHBOARD_SUMMARY ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.post("/health-summary", async (req, res) => {
  console.log("Health summary requested:", req.body);

  try {
    const { userId } = req.body;

    if (!userId) {
      throw new Error("Missing userId");
    }

    const userDoc = await db.collection("users").doc(userId).get();

    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const user = { id: userDoc.id, ...userDoc.data() };
    const medicalProfile = await getDocumentData(
      "medicalProfile",
      user.medicalProfileId,
    );
    const phase2DecisionSupport = await getDocumentData(
      "phase2DecisionSupport",
      user.phase2DecisionSupportId,
    );
    const nutritionTargets = await getDocumentData(
      "nutritionTargets",
      user.baselineNutritionTargetId,
    );
    const currentLabResultsHistory = await getUserDocuments(
      "labResults",
      userId,
    );
    const historicalLabResultsHistory = await getUserDocuments(
      "historicalLabResults",
      userId,
    );
    const labResultsHistory = sortByNewest(
      uniqueDocumentsById([
        ...currentLabResultsHistory,
        ...historicalLabResultsHistory,
      ]),
    );
    const latestLabResult =
      (await getDocumentData("labResults", user.labResultId)) ||
      labResultsHistory[0] ||
      null;
    const anthropometricHistoryByUser = await getUserDocuments(
      "anthropometrics",
      userId,
    );
    const anthropometricHistoryByProfile = await getDocumentsByField(
      "anthropometrics",
      "medicalProfileId",
      user.medicalProfileId,
    );
    const historicalAnthropometricHistoryByUser = await getUserDocuments(
      "historicalAnthropometrics",
      userId,
    );
    const historicalAnthropometricHistoryByProfile = await getDocumentsByField(
      "historicalAnthropometrics",
      "medicalProfileId",
      user.medicalProfileId,
    );
    const anthropometricHistory = sortByNewest([
      ...anthropometricHistoryByUser,
      ...anthropometricHistoryByProfile,
      ...historicalAnthropometricHistoryByUser,
      ...historicalAnthropometricHistoryByProfile,
    ]);
    const currentAnthropometrics = sortByNewest([
      ...anthropometricHistoryByUser,
      ...anthropometricHistoryByProfile,
    ]);
    const anthropometrics = currentAnthropometrics[0] || null;
    const medications = await getUserDocuments("medications", userId);

    return res.status(200).json({
      success: true,
      user,
      medicalProfile,
      phase2DecisionSupport,
      nutritionTargets,
      anthropometrics,
      anthropometricHistory,
      latestLabResult,
      labResultsHistory,
      medications,
    });
  } catch (error) {
    console.error("HEALTH_SUMMARY ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.post("/save-measurement", async (req, res) => {
  console.log("Save measurement requested:", req.body);

  try {
    const {
      userId,
      metricType,
      value,
      date,
      recalculateNutritionTargets,
    } = req.body;

    if (!userId) throw new Error("Missing userId");
    if (!metricType) throw new Error("Missing metricType");
    if (value === undefined || value === null || value === "") {
      throw new Error("Missing measurement value");
    }

    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const user = userDoc.data() || {};
    const anthropometricRecords = sortByNewest(
      uniqueDocumentsById([
      ...(await getUserDocuments("anthropometrics", userId)),
      ...(await getDocumentsByField(
        "anthropometrics",
        "medicalProfileId",
        user.medicalProfileId,
      )),
      ]),
    );
    const currentAnthropometrics = anthropometricRecords[0] || null;
    const metric = String(metricType).trim().toLowerCase();
    const payload = {
      userId,
      medicalProfileId: user.medicalProfileId || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const numericValue = Number(value);
    const storedValue = Number.isFinite(numericValue) ? numericValue : value;

    if (date) {
      payload.date = date;
    }

    if (metric === "weight") {
      payload.weight_kg = storedValue;
      payload.weight = storedValue;
    } else if (metric === "height") {
      payload.height_cm = storedValue;
      payload.height = storedValue;
    } else if (metric === "bmi") {
      payload.bmi = storedValue;
    } else if (metric === "blood pressure") {
      payload.bloodPressure = value;
      payload.blood_pressure = value;

      const match = String(value).match(/(\d+)\s*\/\s*(\d+)/);
      if (match) {
        payload.systolic = Number(match[1]);
        payload.diastolic = Number(match[2]);
      }
    } else if (metric === "heart rate") {
      payload.heartRate = storedValue;
      payload.heart_rate = storedValue;
    } else {
      throw new Error("Unsupported anthropometric measurement type");
    }

    if (metric === "weight" || metric === "height") {
      const latestWeight =
        metric === "weight"
          ? storedValue
          : currentAnthropometrics?.weight_kg ?? currentAnthropometrics?.weight;
      const latestHeight =
        metric === "height"
          ? storedValue
          : currentAnthropometrics?.height_cm ?? currentAnthropometrics?.height;
      const computedBmi = calculateBmi(latestWeight, latestHeight);
      if (computedBmi !== null) {
        payload.bmi = computedBmi;
      }
    }

    let docRef;
    if (currentAnthropometrics?.id) {
      await archiveCurrentRecord(
        currentAnthropometrics,
        "historicalAnthropometrics",
      );
      await archiveAndDeleteExtraCurrentRecords({
        records: anthropometricRecords,
        keepId: currentAnthropometrics.id,
        currentCollectionName: "anthropometrics",
        historicalCollectionName: "historicalAnthropometrics",
      });
      docRef = db.collection("anthropometrics").doc(currentAnthropometrics.id);
      await docRef.set(payload, { merge: true });
    } else {
      payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
      docRef = await db.collection("anthropometrics").add(payload);
    }

    if (payload.bmi !== undefined) {
      await db.collection("users").doc(userId).set(
        {
          bmi: payload.bmi,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    const recalculation = recalculateNutritionTargets === true
      ? await recalculateNutritionArtifacts(userId)
      : null;

    return res.status(200).json({
      success: true,
      anthropometricId: docRef.id,
      measurement: payload,
      recalculation,
    });
  } catch (error) {
    console.error("SAVE_MEASUREMENT ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.post("/save-lab-result", async (req, res) => {
  console.log("Save lab result requested:", req.body);

  try {
    const { userId, uid, labResultId, metricType, value, resultDate } = req.body;
    const labUserId = userId || uid;

    if (!labUserId) throw new Error("Missing userId");
    if (!metricType) throw new Error("Missing lab metric type");
    if (value === undefined || value === null || value === "") {
      throw new Error("Missing lab result value");
    }
    if (!resultDate || !String(resultDate).trim()) {
      throw new Error("Lab result date is required");
    }

    const userDoc = await db.collection("users").doc(labUserId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const user = userDoc.data() || {};
    const linkedLabResult = await getDocumentData("labResults", user.labResultId);
    const requestedLabResult = labResultId
      ? await getDocumentData("labResults", labResultId)
      : null;
    const labRecords = sortByNewest(
      uniqueDocumentsById([
        ...(linkedLabResult ? [linkedLabResult] : []),
        ...(requestedLabResult ? [requestedLabResult] : []),
        ...(await getUserDocuments("labResults", labUserId)),
        ...(await getDocumentsByField(
          "labResults",
          "medicalProfileId",
          user.medicalProfileId,
        )),
      ]),
    );
    const currentLabResult =
      requestedLabResult || linkedLabResult || labRecords[0] || null;

    if (labResultId && !requestedLabResult) {
      return res.status(404).json({
        success: false,
        error: "Lab result not found",
      });
    }

    if (
      currentLabResult?.userId &&
      currentLabResult.userId !== labUserId
    ) {
      return res.status(403).json({
        success: false,
        error: "Lab result does not belong to this user",
      });
    }

    const metric = String(metricType).trim().toLowerCase();
    const numericValue = Number(value);
    const storedValue = Number.isFinite(numericValue) ? numericValue : value;
    const labResultPayload = {
      userId: labUserId,
      medicalProfileId: user.medicalProfileId || null,
      testName: "Blood Test",
      date: String(resultDate).trim(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (!labResultId) {
      labResultPayload.creatinine = null;
      labResultPayload.potassium = null;
      labResultPayload.phosphorus = null;
      labResultPayload.phosphorus_status = null;
      labResultPayload.sodium = null;
      labResultPayload.sodium_status = null;
      labResultPayload.calcium = null;
    }

    if (metric === "creatinine") {
      labResultPayload.creatinine = storedValue;
    } else if (metric === "potassium") {
      labResultPayload.potassium = storedValue;
    } else if (metric === "phosphorus") {
      labResultPayload.phosphorus = storedValue;
    } else if (metric === "sodium") {
      labResultPayload.sodium = storedValue;
    } else if (metric === "calcium") {
      labResultPayload.calcium = storedValue;
    } else if (metric === "egfr") {
      labResultPayload.egfr = storedValue;
      labResultPayload.eGFR = storedValue;
    } else {
      throw new Error("Unsupported lab result type");
    }

    let docRef;
    if (currentLabResult?.id) {
      await archiveCurrentRecord(currentLabResult, "historicalLabResults");
      await archiveAndDeleteExtraCurrentRecords({
        records: labRecords,
        keepId: currentLabResult.id,
        currentCollectionName: "labResults",
        historicalCollectionName: "historicalLabResults",
      });
      docRef = db.collection("labResults").doc(currentLabResult.id);
      if (labResultId) {
        await docRef.set(labResultPayload, { merge: true });
      } else {
        labResultPayload.createdAt = admin.firestore.FieldValue.serverTimestamp();
        await docRef.set(labResultPayload);
      }
    } else {
      labResultPayload.createdAt = admin.firestore.FieldValue.serverTimestamp();
      docRef = await db.collection("labResults").add(labResultPayload);
    }

    await db.collection("users").doc(labUserId).set(
      {
        labResultId: docRef.id,
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      labResultId: docRef.id,
      labResult: labResultPayload,
    });
  } catch (error) {
    console.error("SAVE_LAB_RESULT ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

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
      recalculateNutritionTargets,
    } = req.body;

    const profileUserId = userId || uid;
    if (!profileUserId) throw new Error("Missing userId");

    const userRef = db.collection("users").doc(profileUserId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const existingUser = userDoc.data() || {};
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

    const userPayload = cleanObject({
      childFullName,
      ageYears: ageValue === undefined ? undefined : Number(ageValue),
      age_years: ageValue === undefined ? undefined : Number(ageValue),
      dateOfBirth,
      sex: sexValue,
      gender: sexValue,
      bmi: bmi === undefined ? undefined : Number(bmi),
      preferredMeasurementSystem,
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
      height:
        heightValue === undefined ? undefined : Number(heightValue),
      height_cm:
        heightValue === undefined ? undefined : Number(heightValue),
      weight:
        weightValue === undefined ? undefined : Number(weightValue),
      weight_kg:
        weightValue === undefined ? undefined : Number(weightValue),
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

    const recalculation = recalculateNutritionTargets === true
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

    const existingUserDoc = await db.collection("users").doc(userId).get();
    const existingUser = existingUserDoc.exists ? existingUserDoc.data() || {} : {};
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
        message: "Profile already completed. Existing nutrition targets returned.",
        userId: userId,
        medicalProfileId: existingUser.medicalProfileId,
        nutritionTargetId: existingUser.baselineNutritionTargetId,
        baselineTargets: existingTargets,
        phase2DecisionSupportId: existingUser.phase2DecisionSupportId,
        phase2DecisionSupport: existingPhase2DecisionSupport,
      });
    }

    // 1. Save User data - build payload with only defined values
    const userPayload = {
      uid: userId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Only add fields if they have values
    if (step1?.name) userPayload.childFullName = step1.name;
    if (step1?.dob) userPayload.dateOfBirth = step1.dob;
    if (ageYears) {
      userPayload.ageYears = Number(ageYears);
      userPayload.age_years = Number(ageYears);
    }
    if (sex) {
      userPayload.gender = sex;
      userPayload.sex = sex;
    }
    if (bmi) userPayload.bmi = Number(bmi);
    if (step3?.preferredMeasurement) userPayload.preferredMeasurementSystem = step3.preferredMeasurement;
    if (userRole) userPayload.role = userRole;

    await db.collection("users").doc(userId).set(userPayload, { merge: true });

    // 2. Create MedicalProfile and get its ID - build payload with only defined values
    const medicalProfilePayload = {
      userId: userId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (step1?.kidneyType) medicalProfilePayload.kidneyDiseaseType = step1.kidneyType;
    if (step1?.ckdStage) medicalProfilePayload.ckdStage = step1.ckdStage;
    if (step1?.diagnosisDate) medicalProfilePayload.dateOfDiagnosis = step1.diagnosisDate;
    if (step2?.isOnDialysis !== undefined) medicalProfilePayload.onDialysis = step2.isOnDialysis;
    if (step2?.dialysisType) medicalProfilePayload.dialysisType = step2.dialysisType;
    if (step2?.treatmentFrequency) medicalProfilePayload.treatmentFrequency = step2.treatmentFrequency;
    if (step3?.fluidRestriction) medicalProfilePayload.fluidRestriction = step3.fluidRestriction;
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
    if (step2?.allergies) medicalProfilePayload.allergies = step2.allergies;
    if (Array.isArray(step2?.medications)) {
      medicalProfilePayload.medications = step2.medications;
    }
    if (step2?.medicationsSummary) {
      medicalProfilePayload.medicationsSummary = step2.medicationsSummary;
    }

    const medicalProfileDoc = await db.collection("medicalProfile").add(medicalProfilePayload);
    
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

    // 3. Create AnthropometricData - build payload with only defined values
    const anthropometricPayload = {
      userId: userId,
      medicalProfileId: medicalProfileId,
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

    const anthropometricDoc = await db.collection("anthropometrics").add(anthropometricPayload);
    
    console.log("Anthropometric data created:", anthropometricDoc.id);

    // 4. Create LabResults
    // Build lab result payload safely (avoid undefined values)
    const labResultPayload = {
      userId: userId,
      medicalProfileId: medicalProfileId,
      testName: "Blood Test",
      date: step4?.resultDate ?? null,
      creatinine: parseFloat(step4?.creatinine) || null,
      potassium: parseFloat(step4?.potassium) || null,
      phosphorus: parseFloat(step4?.phosphorus) || null,
      phosphorus_status: step4?.phosphorus_status ?? step4?.phosphorusStatus ?? null,
      sodium: parseFloat(step4?.sodium) || null,
      sodium_status: step4?.sodium_status ?? step4?.sodiumStatus ?? null,
      calcium: parseFloat(step4?.calcium) || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const labResultDoc = await db.collection("labResults").add(labResultPayload);
    
    console.log("Lab Result created:", labResultDoc.id);

    // 5. Create baseline nutrition targets from profile data only.
    // Lab values are intentionally not used for restrictions at this stage.
    const baselineTargets = generateProfileTargets({
      child_name: step1?.name,
      age_years: ageYears,
      sex: sex,
      height_cm: heightCm,
      weight_kg: weightKg,
      bmi: bmi,
      ckd_stage: step1?.ckdStage,
      on_dialysis: step2?.isOnDialysis === true,
      dialysis_type: step2?.dialysisType,
      dry_weight_kg: step1?.dryWeight,
      physical_activity_level: physicalActivityLevel,
      fluid_restriction_status: fluidRestrictionStatus,
      fluid_limit_ml: fluidLimitMl,
    });

    const nutritionTargetDoc = await db.collection("nutritionTargets").add({
      userId: userId,
      medicalProfileId: medicalProfileId,
      source: "profile_baseline",
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...baselineTargets,
    });

    console.log("Baseline nutrition targets created:", nutritionTargetDoc.id);

    // 6. Create Phase 2 decision support from profile + lab interpretation.
    const phase2DecisionSupport = generatePhase2DecisionSupport(
      {
        age_years: ageYears,
        sex: sex,
        weight_kg: weightKg,
        bmi: bmi,
        ckd_stage: step1?.ckdStage,
        dialysis_status: step2?.isOnDialysis === true ? "on dialysis" : "not on dialysis",
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
        phosphorus_status: step4?.phosphorus_status ?? step4?.phosphorusStatus,
        sodium: step4?.sodium,
        sodium_status: step4?.sodium_status ?? step4?.sodiumStatus,
        calcium: step4?.calcium,
        creatinine: step4?.creatinine,
        result_date: step4?.resultDate,
      },
    );

    const phase2DecisionSupportDoc = await db.collection("phase2DecisionSupport").add({
      userId: userId,
      medicalProfileId: medicalProfileId,
      labResultId: labResultDoc.id,
      source: "phase2_decision_support",
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...phase2DecisionSupport,
    });

    console.log("Phase 2 decision support created:", phase2DecisionSupportDoc.id);

    // 7. Update user document with references
    await db.collection("users").doc(userId).update({
      medicalProfileId: medicalProfileId,
      baselineNutritionTargetId: nutritionTargetDoc.id,
      phase2DecisionSupportId: phase2DecisionSupportDoc.id,
      labResultId: labResultDoc.id,
      medicationIds,
    });

    console.log("FINAL SUBMIT: All collections created for user:", userId);

    res.status(200).json({
      success: true,
      message: "All data saved successfully to database",
      userId: userId,
      medicalProfileId: medicalProfileId,
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
      error: error.message
    });
  }
});

module.exports = router;
