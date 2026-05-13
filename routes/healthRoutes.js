const express = require("express");
const router = express.Router();
const { admin, db } = require("../firebase/admin");
const { generateProfileTargets } = require("../services/profileTargetGenerator");
const { generatePhase2DecisionSupport } = require("../services/phase2DecisionSupport");
const prescriptionOcrBridge = require("../services/prescriptionOcrBridgeService");
const { registerSummaryRoutes } = require("./health/registerSummaryRoutes");
const { registerRecordRoutes } = require("./health/registerRecordRoutes");
const { registerProfileRoutes } = require("./health/registerProfileRoutes");
const {
  encryptHealthProfile,
  decryptHealthProfile,
  encryptHealthDocument,
  decryptHealthDocument,
} = require("../utils/encryption");

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

router.post("/extract-prescription", async (req, res) => {
  console.log("Prescription OCR requested");

  try {
    const { imageBase64, image_base64, contentType, content_type } = req.body;
    const imagePayload = imageBase64 || image_base64;

    if (!imagePayload) {
      throw new Error("imageBase64 is required");
    }

    const result = await prescriptionOcrBridge.scanMedicationPrescription({
      image_base64: imagePayload,
      content_type: contentType || content_type || "image/jpeg",
    });

    return res.status(200).json({
      success: true,
      ...result,
    });
  } catch (error) {
    console.error("EXTRACT_PRESCRIPTION ERROR:", error.message);
    return res.status(error.statusCode || 400).json({
      success: false,
      error: error.message,
      details: error.data || null,
    });
  }
});

router.post("/medications/scan", async (req, res) => {
  console.log("Medication scan requested");

  try {
    const { imageBase64, image_base64, contentType, content_type } = req.body;
    const imagePayload = imageBase64 || image_base64;

    if (!imagePayload) {
      throw new Error("imageBase64 is required");
    }

    const result = await prescriptionOcrBridge.scanMedicationPrescription({
      image_base64: imagePayload,
      content_type: contentType || content_type || "image/jpeg",
    });

    return res.status(200).json({
      success: true,
      ...result,
    });
  } catch (error) {
    console.error("MEDICATION_SCAN ERROR:", error.message);
    return res.status(error.statusCode || 400).json({
      success: false,
      error: error.message,
      details: error.data || null,
    });
  }
});

router.post("/medications/confirm", async (req, res) => {
  console.log("Medication confirm requested:", req.body);

  try {
    const {
      userId,
      uid,
      childProfileId,
      child_profile_id,
      medicineName,
      name,
      medicationName,
      medication_name,
      dosage,
      form,
      frequency,
      frequency_type,
      frequency_value,
      duration,
      instructions,
      rxcui,
      confirmedByUser,
      confirmed_by_user,
      rawOcrText,
      raw_ocr_text,
      start_time,
      scheduled_times,
      time,
      schedule,
      display_times,
      display_freq,
      status,
      source,
    } = req.body;

    const medicationUserId = userId || uid || childProfileId || child_profile_id;
    const medicationNameValue =
      medicineName || medicationName || medication_name || name;

    if (!medicationUserId || !medicationNameValue) {
      throw new Error("Missing required medication confirmation fields");
    }

    const medicationPayload = cleanObject({
      userId: medicationUserId,
      uid: medicationUserId,
      childProfileId: childProfileId || child_profile_id || medicationUserId,
      name: medicationNameValue,
      medicationName: medicationNameValue,
      medication_name: medicationNameValue,
      dosage,
      dose: dosage,
      form,
      frequency,
      frequency_type,
      frequency_value:
        frequency_value === undefined ? undefined : Number(frequency_value),
      duration,
      instructions,
      rxcui,
      confirmedByUser: confirmedByUser ?? confirmed_by_user ?? true,
      confirmed_by_user: confirmedByUser ?? confirmed_by_user ?? true,
      rawOcrText: rawOcrText || raw_ocr_text,
      raw_ocr_text: rawOcrText || raw_ocr_text,
      start_time,
      scheduled_times: scheduled_times || [],
      time: time || display_times,
      schedule: schedule || display_times,
      display_times,
      display_freq,
      status: status || "Pending",
      source: source || "ocr_rxnorm",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const docRef = await db
      .collection("medications")
      .add(encryptHealthDocument(medicationPayload));

    return res.status(200).json({
      success: true,
      medicationId: docRef.id,
      medication: {
        id: docRef.id,
        ...medicationPayload,
      },
    });
  } catch (error) {
    console.error("MEDICATION_CONFIRM ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.get("/medications", async (req, res) => {
  console.log("Medication list requested:", req.query);

  try {
    const userId =
      req.query.userId ||
      req.query.uid ||
      req.query.childProfileId ||
      req.query.child_profile_id;

    if (!userId) {
      throw new Error("Missing userId");
    }

    const medicationsByUserId = await getUserDocuments("medications", userId, 100);
    const medicationsByUid = await getDocumentsByField(
      "medications",
      "uid",
      userId,
      100,
    );
    const medications = sortByNewest(
      uniqueDocumentsById([...medicationsByUserId, ...medicationsByUid]),
    );

    return res.status(200).json({
      success: true,
      medications,
    });
  } catch (error) {
    console.error("MEDICATION_LIST ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.put("/medications/:medicationId", async (req, res) => {
  console.log("Medication REST update requested:", req.params, req.body);

  try {
    const medicationId = req.params.medicationId;
    const {
      userId,
      uid,
      childProfileId,
      child_profile_id,
      medicineName,
      medicationName,
      medication_name,
      name,
      dosage,
      form,
      frequency,
      frequency_type,
      frequency_value,
      duration,
      instructions,
      rxcui,
      confirmedByUser,
      confirmed_by_user,
      rawOcrText,
      raw_ocr_text,
      start_time,
      scheduled_times,
      time,
      schedule,
      display_times,
      display_freq,
      status,
      source,
    } = req.body;

    const medicationUserId =
      userId || uid || childProfileId || child_profile_id;
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

    const medicationNameValue =
      medicineName || medicationName || medication_name || name;
    const medicationPayload = cleanObject({
      userId: medicationUserId,
      uid: medicationUserId,
      childProfileId: childProfileId || child_profile_id,
      name: medicationNameValue,
      medicationName: medicationNameValue,
      medication_name: medicationNameValue,
      dosage,
      dose: dosage,
      form,
      frequency,
      frequency_type,
      frequency_value:
        frequency_value === undefined ? undefined : Number(frequency_value),
      duration,
      instructions,
      rxcui,
      confirmedByUser: confirmedByUser ?? confirmed_by_user,
      confirmed_by_user: confirmedByUser ?? confirmed_by_user,
      rawOcrText: rawOcrText || raw_ocr_text,
      raw_ocr_text: rawOcrText || raw_ocr_text,
      start_time,
      scheduled_times,
      time: time || display_times,
      schedule: schedule || display_times,
      display_times,
      display_freq,
      status,
      source,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await docRef.set(encryptHealthDocument(medicationPayload), { merge: true });

    return res.status(200).json({
      success: true,
      medicationId,
      message: "Medication updated successfully",
    });
  } catch (error) {
    console.error("MEDICATION_REST_UPDATE ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

/**
 * MARK MEDICATION AS TAKEN (per dose)
 *
 * For single-dose reminders (once a day): mark as taken for today.
 * For multiple times per day: mark as taken for the provided HH:mm dose time.
 *
 * This writes a per-day/per-time intake log so missed doses can still be identified.
 */
router.post("/medications/mark-taken", async (req, res) => {
  console.log("Mark medication taken requested:", req.body);

  try {
    const {
      ensureDoseRecordsForDate,
      markDoseTaken,
      todayDateKey,
      parseClockTime,
    } = require("../utils/medicationDoseRecords");
    const { userId, uid, profileUserId, childProfileId, medicationId, time } =
      req.body || {};

    const medicationUserId = profileUserId || childProfileId || userId || uid;
    if (!medicationUserId || !medicationId) {
      throw new Error("Missing userId and/or medicationId");
    }

    const medRef = db.collection("medications").doc(String(medicationId));
    const medDoc = await medRef.get();
    if (!medDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "Medication not found",
      });
    }

    const medication = decryptHealthDocument(medDoc.data() || {});
    const scheduledTimes = Array.isArray(medication.scheduled_times)
      ? medication.scheduled_times
      : [];
    const startTime = String(medication.start_time || "").trim();
    const candidateTimes =
      scheduledTimes.length > 0 ? scheduledTimes : startTime ? [startTime] : [];

    if (candidateTimes.length === 0) {
      throw new Error("Medication has no scheduled time(s) to mark as taken.");
    }

    const today = todayDateKey();

    // Ensure today's dose records exist. Never overwrites final statuses.
    await ensureDoseRecordsForDate({
      userId: medicationUserId,
      medicationId,
      medicationDoc: medDoc.data() || {},
      dateKey: today,
    });

    const doseTimesToMark =
      candidateTimes.length <= 1
        ? candidateTimes
        : time
          ? [time]
          : [];

    if (doseTimesToMark.length === 0) {
      throw new Error("Missing dose time (HH:mm) for multi-dose medication.");
    }

    const writes = doseTimesToMark.map(async (doseTime) => {
      const timeText = String(doseTime || "").trim();
      const parsed = parseClockTime(timeText);
      if (!parsed) {
        throw new Error("Invalid dose time format. Expected HH:mm.");
      }

      const doseUpdate = await markDoseTaken({
        userId: medicationUserId,
        medicationId,
        expectedDate: today,
        expectedTime: parsed.text,
      });

      // Backward compatibility: keep intake logs for existing dashboard logic.
      const docId = `${medicationUserId}_${medicationId}_${today}_${timeText}`;
      await db
        .collection("medicationIntakeLogs")
        .doc(docId)
        .set(
          {
            id: docId,
            userId: medicationUserId,
            medicationId,
            date: today,
            time: timeText,
            takenAt: admin.firestore.FieldValue.serverTimestamp(),
            source: "manual_mark_taken",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

      return doseUpdate;
    });

    const results = await Promise.all(writes);

    return res.status(200).json({
      success: true,
      message: "Medication marked as taken",
      medicationId,
      date: today,
      times: doseTimesToMark,
      doseRecords: results,
    });
  } catch (error) {
    console.error("MEDICATION_MARK_TAKEN ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.post("/medications/mark-untaken", async (req, res) => {
  console.log("Mark medication untaken requested:", req.body);

  try {
    const {
      ensureDoseRecordsForDate,
      undoDoseTaken,
      todayDateKey,
      parseClockTime,
    } = require("../utils/medicationDoseRecords");

    const { userId, uid, profileUserId, childProfileId, medicationId, time } =
      req.body || {};

    const medicationUserId = profileUserId || childProfileId || userId || uid;
    if (!medicationUserId || !medicationId) {
      throw new Error("Missing userId and/or medicationId");
    }

    const medRef = db.collection("medications").doc(String(medicationId));
    const medDoc = await medRef.get();
    if (!medDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "Medication not found",
      });
    }

    const medication = decryptHealthDocument(medDoc.data() || {});
    const scheduledTimes = Array.isArray(medication.scheduled_times)
      ? medication.scheduled_times
      : [];
    const startTime = String(medication.start_time || "").trim();
    const candidateTimes =
      scheduledTimes.length > 0 ? scheduledTimes : startTime ? [startTime] : [];

    if (candidateTimes.length === 0) {
      throw new Error("Medication has no scheduled time(s) to undo.");
    }

    const today = todayDateKey();

    // Ensure today's dose records exist (idempotent).
    await ensureDoseRecordsForDate({
      userId: medicationUserId,
      medicationId,
      medicationDoc: medDoc.data() || {},
      dateKey: today,
    });

    const doseTimesToUndo =
      candidateTimes.length <= 1
        ? candidateTimes
        : time
          ? [time]
          : [];

    if (doseTimesToUndo.length === 0) {
      throw new Error("Missing dose time (HH:mm) for multi-dose medication.");
    }

    const results = await Promise.all(
      doseTimesToUndo.map(async (doseTime) => {
        const timeText = String(doseTime || "").trim();
        const parsed = parseClockTime(timeText);
        if (!parsed) {
          throw new Error("Invalid dose time format. Expected HH:mm.");
        }

        const undoResult = await undoDoseTaken({
          userId: medicationUserId,
          medicationId,
          expectedDate: today,
          expectedTime: parsed.text,
        });

        if (undoResult.changed) {
          const intakeLogId = `${medicationUserId}_${medicationId}_${today}_${timeText}`;
          await db.collection("medicationIntakeLogs").doc(intakeLogId).delete();
        }

        return undoResult;
      }),
    );

    return res.status(200).json({
      success: true,
      message: "Medication dose undo processed",
      medicationId,
      date: today,
      times: doseTimesToUndo,
      doseRecords: results,
    });
  } catch (error) {
    console.error("MEDICATION_MARK_UNTAKEN ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.delete("/medications/:medicationId", async (req, res) => {
  console.log("Medication REST delete requested:", req.params, req.query);

  try {
    const medicationId = req.params.medicationId;
    const medicationUserId =
      req.query.userId ||
      req.query.uid ||
      req.query.childProfileId ||
      req.query.child_profile_id;

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

    return res.status(200).json({
      success: true,
      medicationId,
      message: "Medication deleted successfully",
    });
  } catch (error) {
    console.error("MEDICATION_REST_DELETE ERROR:", error.message);
    return res.status(400).json({
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
      profileUserId,
      childProfileId,
      medication_name,
      medicationName,
      name,
      dosage,
      form,
      instructions,
      frequency_type, // 'times_per_day' or 'interval'
      frequency_value, // e.g., 2 (for 2x day) or 8 (for every 8h)
      start_time,      // '08:00'
      scheduled_times, // ['08:00', '20:00']
      frequency,
      display_freq,
      duration,
      time,
      schedule,
      display_times,
      status,
      source
    } = req.body;

    const medicationNameValue = medication_name || medicationName || name;
    const medicationUserId = profileUserId || childProfileId || userId || uid;

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
      form,
      frequency_type,
      frequency_value: Number(frequency_value),
      frequency: frequency || display_freq,
      duration,
      rxcui: req.body.rxcui,
      confirmedByUser: req.body.confirmedByUser,
      confirmed_by_user: req.body.confirmed_by_user,
      rawOcrText: req.body.rawOcrText || req.body.raw_ocr_text,
      raw_ocr_text: req.body.rawOcrText || req.body.raw_ocr_text,
      start_time,
      scheduled_times: scheduled_times || [],
      time: time || display_times,
      schedule: schedule || display_times,
      status: status || "Pending",
      source: source || "manual_entry",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const docRef = await db
      .collection("medications")
      .add(encryptHealthDocument(medicationPayload));

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
      profileUserId,
      childProfileId,
      medicationId,
      medication_name,
      medicationName,
      name,
      dosage,
      form,
      instructions,
      frequency_type,
      frequency_value,
      start_time,
      scheduled_times,
      frequency,
      display_freq,
      duration,
      time,
      schedule,
      display_times,
      status,
    } = req.body;

    const medicationUserId = profileUserId || childProfileId || userId || uid;
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
      form,
      frequency_type,
      frequency_value:
        frequency_value === undefined ? undefined : Number(frequency_value),
      frequency: frequency || display_freq,
      duration,
      rxcui: req.body.rxcui,
      confirmedByUser: req.body.confirmedByUser,
      confirmed_by_user: req.body.confirmed_by_user,
      rawOcrText: req.body.rawOcrText || req.body.raw_ocr_text,
      raw_ocr_text: req.body.rawOcrText || req.body.raw_ocr_text,
      start_time,
      scheduled_times,
      time: time || display_times,
      schedule: schedule || display_times,
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await docRef.set(encryptHealthDocument(medicationPayload), { merge: true });

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
    const { userId, uid, profileUserId, childProfileId, medicationId } = req.body;
    const medicationUserId = profileUserId || childProfileId || userId || uid;

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
  return snapshot.exists
    ? decryptHealthDocument({ id: snapshot.id, ...snapshot.data() })
    : null;
}

async function getFirstUserDocument(collectionName, userId) {
  const snapshot = await db
    .collection(collectionName)
    .where("userId", "==", userId)
    .limit(1)
    .get();

  if (snapshot.empty) return null;

  const doc = snapshot.docs[0];
  return decryptHealthDocument({ id: doc.id, ...doc.data() });
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

  return snapshot.docs.map((doc) =>
    decryptHealthDocument({ id: doc.id, ...doc.data() }),
  );
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

function todayDateKey() {
  const manilaOffsetMs = 8 * 60 * 60 * 1000;
  return new Date(Date.now() + manilaOffsetMs).toISOString().slice(0, 10);
}

function numberOrZero(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function serializeIntakeLog(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    userId: data.userId,
    childProfileId: data.childProfileId,
    mealType: data.mealType,
    date: data.date,
    name: data.name ?? data.foodName ?? data.food_name ?? null,
    portion:
      data.portion ??
      data.selectedServingDescription ??
      data.selected_serving_description ??
      null,
    waterMl: numberOrZero(data.waterMl ?? data.water_ml),
    calories: numberOrZero(data.calories),
    protein: numberOrZero(data.protein),
    carbohydrate: numberOrZero(data.carbohydrate),
    fat: numberOrZero(data.fat),
    sodium: numberOrZero(data.sodium),
    potassium: numberOrZero(data.potassium),
    phosphorus: numberOrZero(data.phosphorus),
    loggedAt:
      typeof data.loggedAt?.toDate === "function"
        ? data.loggedAt.toDate().toISOString()
        : data.loggedAt ?? null,
    createdAt:
      typeof data.createdAt?.toDate === "function"
        ? data.createdAt.toDate().toISOString()
        : data.createdAt ?? null,
  };
}

function buildCandidateProfileIds(userId, user = {}) {
  return [...new Set(
    [
      userId,
      user.childProfileId,
      user.child_profile_id,
      user.childId,
      user.child_id,
      user.profileId,
      user.profile_id,
    ].filter(Boolean),
  )];
}

async function getFoodLogDocsForProfileDate(childProfileId, date) {
  const snapshots = await Promise.all([
    db
      .collection("foodLogs")
      .where("childProfileId", "==", childProfileId)
      .where("date", "==", date)
      .get(),
    db
      .collection("foodLogs")
      .where("userId", "==", childProfileId)
      .where("date", "==", date)
      .get(),
  ]);
  const docsById = new Map();
  snapshots.forEach((snapshot) => {
    snapshot.docs.forEach((doc) => docsById.set(doc.id, doc));
  });
  return [...docsById.values()];
}

async function getFoodLogDocsForProfileRange(childProfileId, startDate, endDate) {
  const snapshots = await Promise.all([
    db
      .collection("foodLogs")
      .where("childProfileId", "==", childProfileId)
      .where("date", ">=", startDate)
      .where("date", "<=", endDate)
      .get(),
    db
      .collection("foodLogs")
      .where("userId", "==", childProfileId)
      .where("date", ">=", startDate)
      .where("date", "<=", endDate)
      .get(),
  ]);
  const docsById = new Map();
  snapshots.forEach((snapshot) => {
    snapshot.docs.forEach((doc) => docsById.set(doc.id, doc));
  });
  return [...docsById.values()];
}

function extractWaterMlFromLog(data = {}) {
  const explicitWaterMl = Number(data.waterMl ?? data.water_ml ?? data.fluid_ml);
  if (Number.isFinite(explicitWaterMl) && explicitWaterMl > 0) {
    return explicitWaterMl;
  }

  const normalizedName = String(
    data.name ?? data.foodName ?? data.food_name ?? "",
  )
    .trim()
    .toLowerCase();

  // List of beverages that should be counted toward hydration
  const hydrationKeywords = [
    "water",
    "juice",
    "milk",
    "tea",
    "coffee",
    "smoothie",
    "drink",
    "beverage",
    "liquid",
    "coconut water",
    "sports drink",
    "electrolyte",
  ];

  const isHydrationItem = hydrationKeywords.some((keyword) =>
    normalizedName.includes(keyword),
  );

  if (!isHydrationItem) {
    return 0;
  }

  const portionText = String(
    data.portion ??
      data.selectedServingDescription ??
      data.selected_serving_description ??
      "",
  );
  
  // Try to extract ML from portion text (e.g., "250 mL", "250ml", "250 ml")
  const mlMatch = portionText.match(/(\d+(?:\.\d+)?)\s*m\s*l\b/i);
  if (mlMatch) {
    const parsedPortion = Number(mlMatch[1]);
    return Number.isFinite(parsedPortion) ? parsedPortion : 0;
  }

  // Try to extract from cup measurements (1 cup = 240 mL)
  const cupMatch = portionText.match(/(\d+(?:\.\d+)?)\s*(?:cup|c\b)/i);
  if (cupMatch) {
    const cups = Number(cupMatch[1]);
    return Number.isFinite(cups) ? Math.round(cups * 240) : 0;
  }

  // Try to extract from oz measurements (1 oz = 29.57 mL, approx 30 mL)
  const ozMatch = portionText.match(/(\d+(?:\.\d+)?)\s*(?:oz|fl\s*oz|fluid\s*oz)\b/i);
  if (ozMatch) {
    const oz = Number(ozMatch[1]);
    return Number.isFinite(oz) ? Math.round(oz * 30) : 0;
  }

  return 0;
}

async function getDailyIntakeData(userId, requestedDate, user = {}) {
  const date = requestedDate || todayDateKey();
  const candidateProfileIds = buildCandidateProfileIds(userId, user);

  for (const childProfileId of candidateProfileIds) {
    const summaryId = `${childProfileId}_${date}`;
    const summary = await getDocumentData("dailyIntakeSummaries", summaryId);
    if (summary) {
      const intakeDocs = await getFoodLogDocsForProfileDate(childProfileId, date);
      const foodLogs = intakeDocs
        .filter((doc) => !(doc.data() || {}).deletedAt)
        .map(serializeIntakeLog);
      const totals = {
        calories: 0,
        protein: 0,
        carbohydrate: 0,
        fat: 0,
        sodium: 0,
        potassium: 0,
        phosphorus: 0,
      };
      foodLogs.forEach((log) => {
        for (const nutrient of Object.keys(totals)) {
          totals[nutrient] += numberOrZero(log[nutrient]);
        }
      });
      let waterMl = numberOrZero(
        summary.waterMl ?? summary.water_ml ?? summary.fluid_ml,
      );
      if (waterMl <= 0) {
        foodLogs.forEach((log) => {
          waterMl += extractWaterMlFromLog(log);
        });
      }

      return {
        ...summary,
        childProfileId,
        date,
        waterMl,
        water_ml: waterMl,
        fluid_ml: waterMl,
        foodLogs,
        totals: foodLogs.length > 0 ? totals : summary.totals,
        mealCount: foodLogs.length > 0 ? foodLogs.length : summary.mealCount,
        source: "dailyIntakeSummaries",
      };
    }
  }

  const snapshots = await Promise.all(
    candidateProfileIds.map((childProfileId) =>
      getFoodLogDocsForProfileDate(childProfileId, date),
    ),
  );
  const dedupedDocs = new Map();
  snapshots.forEach((docs) => {
    docs.forEach((doc) => {
      dedupedDocs.set(doc.id, doc);
    });
  });

  const totals = {
    calories: 0,
    protein: 0,
    carbohydrate: 0,
    fat: 0,
    sodium: 0,
    potassium: 0,
    phosphorus: 0,
  };
  let mealCount = 0;
  let waterMl = 0;
  const foodLogs = [];

  dedupedDocs.forEach((doc) => {
    const data = doc.data() || {};
    if (data.deletedAt) return;
    mealCount += 1;
    waterMl += extractWaterMlFromLog(data);
    foodLogs.push(serializeIntakeLog(doc));
    const nutrients = data.finalNutrients || data.final_nutrients || data;
    for (const nutrient of Object.keys(totals)) {
      totals[nutrient] += numberOrZero(nutrients[nutrient]);
    }
  });

  return {
    childProfileId: candidateProfileIds[0] || userId,
    date,
    mealCount,
    waterMl,
    water_ml: waterMl,
    fluid_ml: waterMl,
    foodLogs,
    totals,
    source: "foodLogs",
  };
}

function addDays(dateString, days) {
  const date = new Date(`${dateString}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function dateRangeForAnalytics(range, today = todayDateKey()) {
  const normalized = String(range || "week").toLowerCase();
  if (normalized === "month") {
    return { periodType: "month", startDate: addDays(today, -29), endDate: today };
  }
  if (normalized === "3_months" || normalized === "3months" || normalized === "quarter") {
    return { periodType: "3_months", startDate: addDays(today, -89), endDate: today };
  }
  return { periodType: "week", startDate: addDays(today, -6), endDate: today };
}

function isDateWithinRange(date, startDate, endDate) {
  if (!date) return false;
  return date >= startDate && date <= endDate;
}

function monthLabelFromDate(dateString) {
  const parsed = new Date(`${dateString}T00:00:00.000Z`);
  return parsed.toLocaleString("en-US", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

function analyticsPeriodLabel(periodType, startDate, endDate) {
  if (periodType === "month") return monthLabelFromDate(endDate);
  return `${startDate} to ${endDate}`;
}

function analyticsSummaryDocumentId(childProfileId, periodType, startDate, endDate) {
  if (periodType === "month") {
    return `${childProfileId}_month_${endDate.slice(0, 7)}`;
  }
  if (periodType === "week") {
    return `${childProfileId}_week_${startDate}_${endDate}`;
  }
  return `${childProfileId}_${periodType}_${startDate}_${endDate}`;
}

async function getDailyIntakeSummariesForRange(userId, user, startDate, endDate) {
  const candidateProfileIds = buildCandidateProfileIds(userId, user);
  let selectedProfileId = candidateProfileIds[0] || userId;
  let summaries = [];

  // First try to get pre-computed daily summaries
  for (const childProfileId of candidateProfileIds) {
    const snapshot = await db
      .collection("dailyIntakeSummaries")
      .where("childProfileId", "==", childProfileId)
      .limit(400)
      .get();

    const candidateSummaries = snapshot.docs
      .map((doc) => ({ id: doc.id, ...doc.data() }))
      .filter((summary) => isDateWithinRange(summary.date, startDate, endDate))
      .sort((a, b) => String(a.date || "").localeCompare(String(b.date || "")));

    if (candidateSummaries.length > 0) {
      selectedProfileId = childProfileId;
      summaries = candidateSummaries;
      break;
    }
  }

  // If no pre-computed summaries found, build from food logs
  if (summaries.length === 0) {
    console.log(`No dailyIntakeSummaries found for range ${startDate}-${endDate}, building from food logs`);
    for (const childProfileId of candidateProfileIds) {
      const logDocs = await getFoodLogDocsForProfileRange(
        childProfileId,
        startDate,
        endDate,
      );

      const logsByDate = {};
      logDocs.forEach((doc) => {
        const data = doc.data();
        if (!data.deletedAt) {
          const date = data.date || "";
          if (!logsByDate[date]) {
            logsByDate[date] = [];
          }
          logsByDate[date].push(data);
        }
      });

      // Build summaries from food logs
      for (const date in logsByDate) {
        const logs = logsByDate[date];
        const summary = {
          childProfileId,
          date,
          mealCount: logs.length,
          waterMl: 0,
          water_ml: 0,
          fluid_ml: 0,
          totals: {
            calories: 0,
            protein: 0,
            carbohydrate: 0,
            fat: 0,
            sodium: 0,
            potassium: 0,
            phosphorus: 0,
          },
        };

        logs.forEach((log) => {
          const nutrients = log.finalNutrients || log;
          summary.totals.calories += numberOrZero(nutrients.calories);
          summary.totals.protein += numberOrZero(nutrients.protein);
          summary.totals.carbohydrate += numberOrZero(nutrients.carbohydrate);
          summary.totals.fat += numberOrZero(nutrients.fat);
          summary.totals.sodium += numberOrZero(nutrients.sodium);
          summary.totals.potassium += numberOrZero(nutrients.potassium);
          summary.totals.phosphorus += numberOrZero(nutrients.phosphorus);
          
          // Extract water from drink logs
          const waterMl = extractWaterMlFromLog(log);
          summary.waterMl += waterMl;
          summary.water_ml += waterMl;
          summary.fluid_ml += waterMl;
        });

        summaries.push(summary);
      }

      if (summaries.length > 0) {
        selectedProfileId = childProfileId;
        break;
      }
    }
  }

  return {
    childProfileId: selectedProfileId,
    summaries,
  };
}

function aggregateDailySummaries(dailySummaries, startDate, endDate) {
  const totals = {
    calories: 0,
    protein: 0,
    carbohydrate: 0,
    fat: 0,
    sodium: 0,
    potassium: 0,
    phosphorus: 0,
    waterMl: 0,
    mealCount: 0,
  };

  const summariesByDate = new Map(dailySummaries.map((summary) => [summary.date, summary]));
  const paddedDailySummaries = [];

  for (let date = startDate; date <= endDate; date = addDays(date, 1)) {
    const summary = summariesByDate.get(date);
    const dayTotals = summary?.totals || {};
    const waterMl = numberOrZero(summary?.waterMl ?? summary?.water_ml ?? summary?.fluid_ml);
    const mealCount = numberOrZero(summary?.mealCount ?? summary?.meal_count);

    const normalized = {
      date,
      waterMl,
      mealCount,
      totals: {
        calories: numberOrZero(dayTotals.calories),
        protein: numberOrZero(dayTotals.protein),
        carbohydrate: numberOrZero(dayTotals.carbohydrate),
        fat: numberOrZero(dayTotals.fat),
        sodium: numberOrZero(dayTotals.sodium),
        potassium: numberOrZero(dayTotals.potassium),
        phosphorus: numberOrZero(dayTotals.phosphorus),
      },
      hasData: Boolean(summary),
    };

    paddedDailySummaries.push(normalized);
    totals.calories += normalized.totals.calories;
    totals.protein += normalized.totals.protein;
    totals.carbohydrate += normalized.totals.carbohydrate;
    totals.fat += normalized.totals.fat;
    totals.sodium += normalized.totals.sodium;
    totals.potassium += normalized.totals.potassium;
    totals.phosphorus += normalized.totals.phosphorus;
    totals.waterMl += normalized.waterMl;
    totals.mealCount += normalized.mealCount;
  }

  const activeDays = paddedDailySummaries.filter((day) => day.hasData).length;
  const divisor = activeDays > 0 ? activeDays : paddedDailySummaries.length || 1;

  return {
    dailySummaries: paddedDailySummaries,
    totals,
    averages: {
      calories: totals.calories / divisor,
      protein: totals.protein / divisor,
      carbohydrate: totals.carbohydrate / divisor,
      fat: totals.fat / divisor,
      sodium: totals.sodium / divisor,
      potassium: totals.potassium / divisor,
      phosphorus: totals.phosphorus / divisor,
      waterMl: totals.waterMl / divisor,
      mealCount: totals.mealCount / divisor,
    },
    activeDays,
    totalDays: paddedDailySummaries.length,
  };
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
    .add(encryptHealthDocument(archivePayload));

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

  const user = { id: userDoc.id, ...decryptHealthProfile(userDoc.data() || {}) };
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
      .set(encryptHealthDocument(nutritionPayload), { merge: true });
  } else {
    const nutritionDoc = await db.collection("nutritionTargets").add({
      ...encryptHealthDocument(nutritionPayload),
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
      .set(encryptHealthDocument(phase2Payload), { merge: true });
  } else {
    const phase2Doc = await db.collection("phase2DecisionSupport").add({
      ...encryptHealthDocument(phase2Payload),
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

registerSummaryRoutes(router, {
  admin,
  db,
  getDocumentData,
  getFirstUserDocument,
  getUserDocuments,
  getDocumentsByField,
  getDocumentsByIds,
  uniqueDocumentsById,
  sortByNewest,
  getDailyIntakeData,
  dateRangeForAnalytics,
  todayDateKey,
  getDailyIntakeSummariesForRange,
  aggregateDailySummaries,
  analyticsSummaryDocumentId,
  analyticsPeriodLabel,
  decryptHealthProfile,
});

registerRecordRoutes(router, {
  admin,
  db,
  getDocumentData,
  getUserDocuments,
  getDocumentsByField,
  uniqueDocumentsById,
  sortByNewest,
  calculateBmi,
  archiveCurrentRecord,
  archiveAndDeleteExtraCurrentRecords,
  recalculateNutritionArtifacts,
  encryptHealthProfile,
  decryptHealthProfile,
  encryptHealthDocument,
  decryptHealthDocument,
});

registerProfileRoutes(router, {
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
  decryptHealthDocument,
});

/**
 * TEST ENDPOINT - Create a missed medication reminder manually
 * For testing and debugging the missed medication reminder system
 */
router.post("/test-missed-medication", async (req, res) => {
  console.log("TEST: Creating missed medication reminder...");
  
  try {
    if (process.env.ALLOW_TEST_ENDPOINTS !== "true") {
      return res.status(403).json({
        success: false,
        error: "Test endpoints are disabled.",
      });
    }

    const { userId, uid } = req.body;
    const medicationUserId = userId || uid;

    if (!medicationUserId) {
      return res.status(400).json({
        success: false,
        error: "userId or uid is required",
      });
    }

    // Create a missed medication notification
    const missedNotification = {
      userId: medicationUserId,
      type: "missed_medication_reminder",
      title: "Missed Medication Reminder",
      body: "You missed your medication reminder 1 hour ago. Please take your medication if possible.",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isMissed: true,
      priority: "high",
      color: "red",
      read: false,
    };

    // Store in notifications collection
    const notifRef = await db.collection("notifications").add(missedNotification);
    
    // Add to upcoming reminders
    await db.collection("upcomingReminders").add({
      ...missedNotification,
      scheduledTime: admin.firestore.FieldValue.serverTimestamp(),
      isMissed: true,
      dueTime: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("TEST: Created missed medication reminder for user:", medicationUserId);

    return res.status(200).json({
      success: true,
      message: "Test missed medication reminder created successfully",
      notificationId: notifRef.id,
    });
  } catch (error) {
    console.error("TEST_MISSED_MEDICATION ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

module.exports = router;
