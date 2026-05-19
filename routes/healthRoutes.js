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
const {
  consumeAiUsage,
  getAiUsageStatus,
} = require("../utils/aiUsageLimiter");
const {
  markActiveWindowTaken,
  markWindowTaken,
  undoActiveWindowTaken,
} = require("../utils/medicationDoseRecords");

function requestMeta(req, extra = {}) {
  const body = req.body && typeof req.body === "object" ? req.body : {};
  return {
    uid: body.uid || body.userId || body.profileUserId || body.childProfileId,
    keys: Object.keys(body).length,
    ...extra,
  };
}

function medicationTargetId({
  userId,
  uid,
  profileUserId,
  childProfileId,
  child_profile_id,
} = {}) {
  return profileUserId || childProfileId || child_profile_id || userId || uid;
}

function medicationOwnerIds(medication = {}) {
  return [
    medication.userId,
    medication.uid,
    medication.profileUserId,
    medication.childProfileId,
    medication.child_profile_id,
  ]
    .map((value) => String(value || "").trim())
    .filter(Boolean);
}

function medicationDoseLogOwnerId(medication = {}, fallbackUserId) {
  return medicationOwnerIds(medication)[0] || String(fallbackUserId || "").trim();
}

function normalizeClockTime(value) {
  const text = String(value || "").trim();
  const match = text.match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return "";
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) return "";
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return "";
  return `${hour.toString().padStart(2, "0")}:${minute.toString().padStart(2, "0")}`;
}

function canAccessMedication(medication = {}, targetProfileId, requesterUserId) {
  const owners = medicationOwnerIds(medication);
  if (owners.length === 0) return true;
  const target = String(targetProfileId || "").trim();
  const requester = String(requesterUserId || "").trim();
  return owners.some((owner) => owner === target || owner === requester);
}

function linkedChildIdsFromCaregiver(profile = {}) {
  const ids = new Set();
  for (const value of [
    profile.activeDirectChildProfileId,
    profile.linkedChildUserId,
    profile.childProfileId,
  ]) {
    const id = String(value || "").trim();
    if (id) ids.add(id);
  }

  if (Array.isArray(profile.linkedChildren)) {
    for (const child of profile.linkedChildren) {
      for (const value of [child?.userId, child?.uid, child?.id]) {
        const id = String(value || "").trim();
        if (id) ids.add(id);
      }
    }
  }

  return ids;
}

async function canAccessProfile(requesterUserId, targetProfileUserId) {
  const requester = String(requesterUserId || "").trim();
  const target = String(targetProfileUserId || "").trim();
  if (!requester || !target) return false;
  if (requester === target) return true;

  const requesterDoc = await db.collection("users").doc(requester).get();
  if (requesterDoc.exists) {
    const requesterProfile = decryptHealthProfile(requesterDoc.data() || {});
    if (linkedChildIdsFromCaregiver(requesterProfile).has(target)) {
      return true;
    }
  }

  const targetDoc = await db.collection("users").doc(target).get();
  if (targetDoc.exists) {
    const targetProfile = decryptHealthProfile(targetDoc.data() || {});
    const caregiverIds = [
      targetProfile.caregiverUserId,
      targetProfile.caregiverId,
      targetProfile.caregiverSettings?.caregiverId,
    ].map((value) => String(value || "").trim());
    if (caregiverIds.includes(requester)) {
      return true;
    }
  }

  return false;
}

async function deleteQuerySnapshot(snapshot) {
  if (snapshot.empty) return 0;
  let deleted = 0;
  for (let index = 0; index < snapshot.docs.length; index += 400) {
    const batch = db.batch();
    for (const doc of snapshot.docs.slice(index, index + 400)) {
      batch.delete(doc.ref);
      deleted += 1;
    }
    await batch.commit();
  }
  return deleted;
}

async function resolveMissedMedicationArtifacts({
  medicationId,
  profileUserId,
  date,
  scheduledTimes = [],
  window,
}) {
  if (!medicationId || !profileUserId || !date) return;

  const timeSet = new Set(
    [
      ...scheduledTimes,
      window?.expectedTime,
    ].map((time) => normalizeClockTime(time)).filter(Boolean),
  );

  const matchesDose = (data = {}) => {
    const sameUser = String(data.userId || "") === String(profileUserId);
    const sameMedication = String(data.medicationId || "") === String(medicationId);
    const sameDay = !data.day || String(data.day) === String(date);
    const scheduledTime = normalizeClockTime(data.scheduledTime || data.time);
    const sameTime = timeSet.size === 0 || timeSet.has(scheduledTime);
    return sameUser && sameMedication && sameDay && sameTime;
  };

  for (const collectionName of ["notifications", "upcomingReminders"]) {
    const snapshot = await db
      .collection(collectionName)
      .where("medicationId", "==", String(medicationId))
      .limit(100)
      .get();

    const batch = db.batch();
    let pendingWrites = 0;
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      if (!matchesDose(data)) continue;

      if (collectionName === "notifications") {
        batch.set(
          doc.ref,
          {
            read: true,
            isMissed: false,
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
            resolvedBy: "manual_mark_taken",
          },
          { merge: true },
        );
      } else {
        batch.delete(doc.ref);
      }
      pendingWrites += 1;
    }

    if (pendingWrites > 0) {
      await batch.commit();
    }
  }
}

async function cleanupMedicationReminderArtifacts({
  medicationId,
  profileUserId,
  scheduledTimes = [],
}) {
  if (!medicationId) return;

  const collectionsWithMedicationId = ["notifications", "upcomingReminders"];
  for (const collectionName of collectionsWithMedicationId) {
    const snapshot = await db
      .collection(collectionName)
      .where("medicationId", "==", medicationId)
      .get();
    await deleteQuerySnapshot(snapshot);
  }

  const today = todayDateKey();
  for (const time of scheduledTimes) {
    const timeText = normalizeClockTime(time);
    if (!timeText) continue;
    await db
      .collection("medicationIntakeLogs")
      .doc(`${profileUserId}_${medicationId}_${today}_${timeText}`)
      .delete()
      .catch(() => {});
    await db
      .collection("reminderState")
      .doc(`${profileUserId}_missed_medication_${medicationId}_${today}_${timeText}`)
      .delete()
      .catch(() => {});
  }
}

//////////////////// STEP 1 - Just collect data ////////////////////
router.post("/step1", async (req, res) => {
  console.log("Step 1 received:", requestMeta(req));
  
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
  console.log("Step 2 received:", requestMeta(req));
  
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
  console.log("Step 3 received:", requestMeta(req));

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
  console.log("Step 4 received:", requestMeta(req));

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
  console.log("Phase 2 decision support received:", requestMeta(req, {
    hasLabs: Boolean(req.body.labs || req.body.potassium || req.body.creatinine),
    hasIntake: Boolean(req.body.intake),
  }));

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

  let aiUsage = null;
  try {
    const { imageBase64, image_base64, contentType, content_type, userId, uid } = req.body;
    const imagePayload = imageBase64 || image_base64;

    if (!imagePayload) {
      throw new Error("imageBase64 is required");
    }

    aiUsage = await consumeAiUsage({
      db,
      admin,
      uid: userId || uid,
      feature: "medication_ocr",
    });

    const result = await prescriptionOcrBridge.scanMedicationPrescription({
      image_base64: imagePayload,
      content_type: contentType || content_type || "image/jpeg",
    });

    return res.status(200).json({
      success: true,
      ...result,
      aiUsage,
    });
  } catch (error) {
    console.error("EXTRACT_PRESCRIPTION ERROR:", error.message);
    return res.status(error.statusCode || 400).json({
      success: false,
      error: error.message,
      aiUsage: error.aiUsage || aiUsage,
      details: error.data || null,
    });
  }
});

router.post("/medications/scan", async (req, res) => {
  console.log("Medication scan requested");

  let aiUsage = null;
  try {
    const { imageBase64, image_base64, contentType, content_type, userId, uid } = req.body;
    const imagePayload = imageBase64 || image_base64;

    if (!imagePayload) {
      throw new Error("imageBase64 is required");
    }

    aiUsage = await consumeAiUsage({
      db,
      admin,
      uid: userId || uid,
      feature: "medication_ocr",
    });

    const result = await prescriptionOcrBridge.scanMedicationPrescription({
      image_base64: imagePayload,
      content_type: contentType || content_type || "image/jpeg",
    });

    return res.status(200).json({
      success: true,
      ...result,
      aiUsage,
    });
  } catch (error) {
    console.error("MEDICATION_SCAN ERROR:", error.message);
    return res.status(error.statusCode || 400).json({
      success: false,
      error: error.message,
      aiUsage: error.aiUsage || aiUsage,
      details: error.data || null,
    });
  }
});

router.post("/ai-usage/status", async (req, res) => {
  try {
    const { userId, uid, feature } = req.body;
    const aiUsage = await getAiUsageStatus({
      db,
      uid: userId || uid,
      feature: feature || "medication_ocr",
    });

    return res.status(200).json({
      success: true,
      aiUsage,
    });
  } catch (error) {
    return res.status(error.statusCode || 400).json({
      success: false,
      error: error.message,
    });
  }
});

router.post("/medications/confirm", async (req, res) => {
  console.log("Medication confirm requested:", requestMeta(req, {
    hasRawOcrText: Boolean(req.body.rawOcrText || req.body.raw_ocr_text),
  }));

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

    const medicationUserId = medicationTargetId({
      userId,
      uid,
      childProfileId,
      child_profile_id,
    });
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
  console.log("Medication REST update requested:", {
    medicationId: req.params.medicationId,
    ...requestMeta(req, {
      hasRawOcrText: Boolean(req.body.rawOcrText || req.body.raw_ocr_text),
    }),
  });

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

    const medicationUserId = medicationTargetId({
      userId,
      uid,
      childProfileId,
      child_profile_id,
    });
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

    const existing = decryptHealthDocument(doc.data() || {});
    if (!canAccessMedication(existing, medicationUserId, userId || uid)) {
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
  console.log("Mark medication taken requested:", requestMeta(req, {
    medicationId: req.body.medicationId,
  }));

  try {
    const { userId, uid, profileUserId, childProfileId, medicationId, time } =
      req.body || {};

    const medicationUserId = medicationTargetId({
      userId,
      uid,
      profileUserId,
      childProfileId,
    });
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
    if (!canAccessMedication(medication, medicationUserId, userId || uid)) {
      return res.status(403).json({
        success: false,
        error: "Medication does not belong to this profile",
      });
    }
    const logUserId = medicationDoseLogOwnerId(medication, medicationUserId);
    const result = time
      ? await markWindowTaken({
          userId: logUserId,
          medicationId,
          medicationDoc: medication,
          expectedTime: time,
        })
      : await markActiveWindowTaken({
          userId: logUserId,
          medicationId,
          medicationDoc: medication,
        });

    if (!result.late) {
      await resolveMissedMedicationArtifacts({
        medicationId,
        profileUserId: logUserId,
        date: result.window.expectedDate,
        scheduledTimes: [result.window.expectedTime],
        window: result.window,
      });
    }

    return res.status(200).json({
      success: true,
      message: result.late
        ? "Medication window already missed; late intake recorded"
        : "Medication marked as taken",
      medicationId,
      date: result.window.expectedDate,
      times: [result.window.expectedTime],
      doseWindow: {
        expectedDate: result.window.expectedDate,
        expectedTime: result.window.expectedTime,
        startAt: result.window.startAt.toISOString(),
        endAt: result.window.endAt.toISOString(),
        status: result.status,
      },
      late: result.late,
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
  console.log("Mark medication untaken requested:", requestMeta(req, {
    medicationId: req.body.medicationId,
  }));

  try {
    const { userId, uid, profileUserId, childProfileId, medicationId } =
      req.body || {};

    const medicationUserId = medicationTargetId({
      userId,
      uid,
      profileUserId,
      childProfileId,
    });
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
    if (!canAccessMedication(medication, medicationUserId, userId || uid)) {
      return res.status(403).json({
        success: false,
        error: "Medication does not belong to this profile",
      });
    }
    const logUserId = medicationDoseLogOwnerId(medication, medicationUserId);
    const result = await undoActiveWindowTaken({
      userId: logUserId,
      medicationId,
      medicationDoc: medication,
    });

    return res.status(200).json({
      success: true,
      message: "Medication marked as untaken",
      medicationId,
      date: result.window.expectedDate,
      times: [result.window.expectedTime],
      doseWindow: {
        expectedDate: result.window.expectedDate,
        expectedTime: result.window.expectedTime,
        startAt: result.window.startAt.toISOString(),
        endAt: result.window.endAt.toISOString(),
        status: result.status,
      },
    });
  } catch (error) {
    console.error("MEDICATION_MARK_UNTAKEN ERROR:", error.message);
    return res.status(400).json({
      success: false,
      error: error.message,
    });
  }
});

router.post("/missed-medication-reminders", async (req, res) => {
  console.log("Missed medication reminders requested:", requestMeta(req, {
    profileUserId: req.body?.profileUserId,
  }));

  try {
    const { userId, uid, profileUserId, childProfileId, limit } = req.body || {};
    const requesterUserId = userId || uid;
    const targetProfileUserId = medicationTargetId({
      userId: profileUserId || childProfileId || requesterUserId,
      profileUserId,
      childProfileId,
    });

    if (!requesterUserId || !targetProfileUserId) {
      throw new Error("Missing userId and/or profileUserId");
    }

    const allowed = await canAccessProfile(requesterUserId, targetProfileUserId);
    if (!allowed) {
      return res.status(403).json({
        success: false,
        error: "You do not have access to this profile's reminders",
      });
    }

    const snapshot = await db
      .collection("notifications")
      .where("userId", "==", String(targetProfileUserId))
      .where("type", "==", "missed_medication_reminder")
      .where("isMissed", "==", true)
      .where("read", "==", false)
      .limit(50)
      .get();

    const remindersByDose = new Map();
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const reminder = { id: doc.id, ...data };
      const doseKey = [
        data.medicationId || "",
        data.scheduledWindowStart || data.windowStart || "",
        data.day || data.date || "",
        normalizeClockTime(data.scheduledTime || data.time) || "",
      ].join("|");
      const key = doseKey.replace(/\|/g, "") ? doseKey : doc.id;
      const existing = remindersByDose.get(key);
      const existingTime = existing?.timestamp?.toMillis
        ? existing.timestamp.toMillis()
        : 0;
      const currentTime = data.timestamp?.toMillis ? data.timestamp.toMillis() : 0;
      if (!existing || currentTime >= existingTime) {
        remindersByDose.set(key, reminder);
      }
    }

    const reminders = Array.from(remindersByDose.values()).sort((a, b) => {
      const aTime = a.timestamp?.toMillis ? a.timestamp.toMillis() : 0;
      const bTime = b.timestamp?.toMillis ? b.timestamp.toMillis() : 0;
      return bTime - aTime;
    });

    return res.status(200).json({
      success: true,
      profileUserId: targetProfileUserId,
      reminders: reminders.slice(0, Number(limit) > 0 ? Number(limit) : 20),
    });
  } catch (error) {
    console.error("MISSED_MEDICATION_REMINDERS ERROR:", error.message);
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
    const medicationUserId = medicationTargetId({
      userId: req.query.userId,
      uid: req.query.uid,
      profileUserId: req.query.profileUserId,
      childProfileId: req.query.childProfileId,
      child_profile_id: req.query.child_profile_id,
    });

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

    const existing = decryptHealthDocument(doc.data() || {});
    if (!canAccessMedication(existing, medicationUserId, req.query.userId || req.query.uid)) {
      return res.status(403).json({
        success: false,
        error: "Medication does not belong to this user",
      });
    }

    await docRef.delete();
    await cleanupMedicationReminderArtifacts({
      medicationId,
      profileUserId: medicationUserId,
      scheduledTimes:
        Array.isArray(existing.scheduled_times) && existing.scheduled_times.length > 0
          ? existing.scheduled_times
          : [existing.start_time || existing.time],
    });

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
  console.log("Save medication requested:", requestMeta(req));

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
    const medicationUserId = medicationTargetId({
      userId,
      uid,
      profileUserId,
      childProfileId,
    });
    const requestedChildProfileId = profileUserId || childProfileId;

    if (!medicationUserId || !medicationNameValue || !frequency_type || !start_time) {
      throw new Error("Missing required medication fields");
    }

    const medicationPayload = cleanObject({
      userId: medicationUserId,
      uid: medicationUserId,
      childProfileId: requestedChildProfileId || medicationUserId,
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
  console.log("Update medication requested:", requestMeta(req, {
    medicationId: req.body.medicationId,
  }));

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

    const requesterUserId = userId || uid;
    const targetProfileId = profileUserId || childProfileId || userId || uid;
    const medicationNameValue = medication_name || medicationName || name;

    if (!targetProfileId || !medicationId) {
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

    const existing = decryptHealthDocument(doc.data() || {});
    const ownerId = String(
      existing.userId || existing.uid || existing.childProfileId || "",
    ).trim();
    const normalizedTargetProfileId = String(targetProfileId || "").trim();
    const normalizedRequesterId = String(requesterUserId || "").trim();
    const ownerMatchesTarget =
      ownerId && normalizedTargetProfileId && ownerId === normalizedTargetProfileId;
    const ownerMatchesRequester =
      ownerId && normalizedRequesterId && ownerId === normalizedRequesterId;

    // Allow updates if the medication belongs to either:
    // - the selected profile (child/self), or
    // - the requester (caregiver) for legacy records.
    if (!canAccessMedication(existing, normalizedTargetProfileId, normalizedRequesterId)) {
      return res.status(403).json({
        success: false,
        error: "Medication does not belong to this user",
      });
    }

    const medicationPayload = cleanObject({
      // Normalize ownership under the selected profile (fixes legacy meds that were
      // accidentally stored under the caregiver user id).
      userId: normalizedTargetProfileId,
      uid: normalizedTargetProfileId,
      childProfileId: normalizedTargetProfileId,
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
  console.log("Delete medication requested:", requestMeta(req, {
    medicationId: req.body.medicationId,
  }));

  try {
    const { userId, uid, profileUserId, childProfileId, medicationId } = req.body;
    const medicationUserId = medicationTargetId({
      userId,
      uid,
      profileUserId,
      childProfileId,
    });

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

    const existing = decryptHealthDocument(doc.data() || {});
    if (!canAccessMedication(existing, medicationUserId, userId || uid)) {
      return res.status(403).json({
        success: false,
        error: "Medication does not belong to this user",
      });
    }

    await docRef.delete();
    await cleanupMedicationReminderArtifacts({
      medicationId,
      profileUserId: medicationUserId,
      scheduledTimes:
        Array.isArray(existing.scheduled_times) && existing.scheduled_times.length > 0
          ? existing.scheduled_times
          : [existing.start_time || existing.time],
    });

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
  const explicitWaterMl = Number(
    data.totalFluidContributionMl ??
      data.total_fluid_contribution_ml ??
      data.waterMl ??
      data.water_ml ??
      data.fluid_ml,
  );
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

module.exports = router;
