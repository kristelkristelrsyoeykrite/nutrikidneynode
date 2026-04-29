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
  } = deps;

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

      const recalculation =
        recalculateNutritionTargets === true
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
}

module.exports = { registerRecordRoutes };
