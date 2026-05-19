function registerRecordRoutes(router, deps) {
  const {
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
    encryptHealthDocument,
  } = deps;

  function requestMeta(req, extra = {}) {
    const body = req.body && typeof req.body === "object" ? req.body : {};
    return {
      userId: body.userId || body.uid,
      profileUserId: body.profileUserId,
      keys: Object.keys(body).length,
      ...extra,
    };
  }

  function isCaregiverRole(role) {
    const normalized = String(role || "").trim().toLowerCase();
    return normalized === "parent_caregiver" || normalized === "caregiver";
  }

  function isManagedChild(user, profileUserId) {
    if (!profileUserId) return false;
    const linkedChildren = Array.isArray(user.linkedChildren)
      ? user.linkedChildren
      : [];
    return linkedChildren.some((child) => {
      const childId = child?.userId || child?.uid || child?.id;
      return String(childId || "") === String(profileUserId);
    });
  }

  async function resolveWritableProfileUserId(userId, profileUserId) {
    if (!profileUserId || String(profileUserId) === String(userId)) {
      return userId;
    }

    const viewerDoc = await db.collection("users").doc(userId).get();
    if (!viewerDoc.exists) return userId;

    const viewer = viewerDoc.data() || {};
    if (isCaregiverRole(viewer.role) && isManagedChild(viewer, profileUserId)) {
      return profileUserId;
    }

    return userId;
  }

  function buildLabMetricDeleteUpdates(metricType) {
    const metric = String(metricType).trim().toLowerCase();
    const updates = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (metric === "creatinine") updates.creatinine = null;
    else if (metric === "potassium") updates.potassium = null;
    else if (metric === "phosphorus") {
      updates.phosphorus = null;
      updates.phosphorus_status = null;
    } else if (metric === "sodium") {
      updates.sodium = null;
      updates.sodium_status = null;
    } else if (metric === "calcium") updates.calcium = null;
    else if (metric === "egfr") {
      updates.egfr = null;
      updates.eGFR = null;
    } else {
      throw new Error("Unsupported lab result type");
    }
    return { metric, updates };
  }

  function hasRemainingLabMetric(labResult) {
    return [
      "creatinine",
      "potassium",
      "phosphorus",
      "sodium",
      "calcium",
      "egfr",
      "eGFR",
    ].some((field) => {
      const value = labResult[field];
      return value !== undefined && value !== null && value !== "";
    });
  }

  async function clearArchivedLabMetricCopies({
    labResultId,
    labResult,
    updates,
    labUserId,
  }) {
    const archiveCandidates = uniqueDocumentsById([
      ...(await getDocumentsByField(
        "historicalLabResults",
        "originalId",
        labResultId,
      )),
      ...(await getDocumentsByField(
        "historicalLabResults",
        "sourceId",
        labResultId,
      )),
      ...(await getDocumentsByField(
        "historicalLabResults",
        "labResultId",
        labResultId,
      )),
      ...(labResult?.date
        ? await getDocumentsByField("historicalLabResults", "userId", labUserId)
        : []),
    ]);

    await Promise.all(
      archiveCandidates.map(async (archive) => {
        if (
          archive.userId &&
          archive.userId !== labUserId &&
          archive.originalUserId !== labUserId
        ) {
          return;
        }
        if (
          archive.id !== labResultId &&
          archive.originalId !== labResultId &&
          archive.sourceId !== labResultId &&
          archive.labResultId !== labResultId &&
          labResult?.date &&
          archive.date !== labResult.date
        ) {
          return;
        }

        const archiveRef = db.collection("historicalLabResults").doc(archive.id);
        const nextArchive = { ...archive, ...updates };
        if (hasRemainingLabMetric(nextArchive)) {
          await archiveRef.set(encryptHealthDocument(updates), { merge: true });
        } else {
          await archiveRef.delete();
        }
      }),
    );
  }

  router.post("/save-measurement", async (req, res) => {
    console.log("Save measurement requested:", requestMeta(req, {
      metricType: req.body.metricType,
      hasDate: Boolean(req.body.date),
    }));

    try {
      const {
        userId,
        profileUserId,
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

      const profileOwnerId = await resolveWritableProfileUserId(
        userId,
        profileUserId,
      );
      const userDoc = await db.collection("users").doc(profileOwnerId).get();
      if (!userDoc.exists) {
        return res.status(404).json({
          success: false,
          error: "User profile not found",
        });
      }

      const user = userDoc.data() || {};
      const anthropometricRecords = sortByNewest(
        uniqueDocumentsById([
          ...(await getUserDocuments("anthropometrics", profileOwnerId)),
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
        userId: profileOwnerId,
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
        await db.collection("users").doc(profileOwnerId).set(
          {
            bmi: payload.bmi,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      const recalculation =
        recalculateNutritionTargets === true
          ? await recalculateNutritionArtifacts(profileOwnerId)
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
    console.log("Save lab result requested:", requestMeta(req, {
      labResultId: req.body.labResultId,
      metricType: req.body.metricType,
      hasResultDate: Boolean(req.body.resultDate),
    }));

    try {
      const { userId, uid, profileUserId, labResultId, metricType, value, resultDate } = req.body;
      const labUserId = await resolveWritableProfileUserId(
        userId || uid,
        profileUserId,
      );

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

      if (currentLabResult?.userId && currentLabResult.userId !== labUserId) {
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
          await docRef.set(encryptHealthDocument(labResultPayload), { merge: true });
        } else {
          labResultPayload.createdAt = admin.firestore.FieldValue.serverTimestamp();
          await docRef.set(encryptHealthDocument(labResultPayload));
        }
      } else {
        labResultPayload.createdAt = admin.firestore.FieldValue.serverTimestamp();
        docRef = await db
          .collection("labResults")
          .add(encryptHealthDocument(labResultPayload));
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

  router.post("/delete-lab-result", async (req, res) => {
    console.log("Delete lab result requested:", requestMeta(req, {
      labResultId: req.body.labResultId,
      metricType: req.body.metricType,
    }));

    try {
      const { userId, uid, profileUserId, labResultId, metricType } = req.body;
      const labUserId = await resolveWritableProfileUserId(
        userId || uid,
        profileUserId,
      );

      if (!labUserId) throw new Error("Missing userId");
      if (!labResultId) throw new Error("Missing lab result ID");
      if (!metricType) throw new Error("Missing lab metric type");

      const userDoc = await db.collection("users").doc(labUserId).get();
      const user = userDoc.exists ? userDoc.data() || {} : {};
      let collectionName = "labResults";
      let docRef = db.collection(collectionName).doc(labResultId);
      let doc = await docRef.get();
      if (!doc.exists) {
        collectionName = "historicalLabResults";
        docRef = db.collection(collectionName).doc(labResultId);
        doc = await docRef.get();
      }
      if (!doc.exists) {
        if (user.labResultId === labResultId) {
          await db.collection("users").doc(labUserId).set(
            {
              labResultId: admin.firestore.FieldValue.delete(),
            },
            { merge: true },
          );
        }
        return res.status(200).json({
          success: true,
          labResultId,
          deletedMetric: String(metricType).trim().toLowerCase(),
          alreadyDeleted: true,
        });
      }

      const labResult =
        (await getDocumentData(collectionName, labResultId)) || {
          id: doc.id,
          ...doc.data(),
        };
      const isLinkedFromProfile = user.labResultId === labResultId;
      if (
        labResult.userId &&
        labResult.userId !== labUserId &&
        !isLinkedFromProfile
      ) {
        return res.status(403).json({
          success: false,
          error: "Lab result does not belong to this user",
        });
      }

      const { metric, updates } = buildLabMetricDeleteUpdates(metricType);

      const nextLabResult = { ...labResult, ...updates };
      const hasRemainingMetric = hasRemainingLabMetric(nextLabResult);

      if (hasRemainingMetric) {
        await docRef.set(encryptHealthDocument(updates), { merge: true });
      } else {
        await docRef.delete();
        if (user.labResultId === labResultId) {
          await db.collection("users").doc(labUserId).set(
            {
              labResultId: admin.firestore.FieldValue.delete(),
            },
            { merge: true },
          );
        }
      }

      await clearArchivedLabMetricCopies({
        labResultId,
        labResult,
        updates,
        labUserId,
      });

      return res.status(200).json({
        success: true,
        labResultId,
        deletedMetric: metric,
        deletedDocument: !hasRemainingMetric,
      });
    } catch (error) {
      console.error("DELETE_LAB_RESULT ERROR:", error.message);
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }
  });
}

module.exports = { registerRecordRoutes };
