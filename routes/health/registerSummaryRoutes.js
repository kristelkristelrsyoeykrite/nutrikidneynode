function registerSummaryRoutes(router, deps) {
  const {
    getGamificationSummary,
    recomputeGamificationForDate,
  } = require("../../services/gamificationService");

  const {
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
  } = deps;

  function isCaregiverRole(role) {
    const normalized = String(role || "").trim().toLowerCase();
    return normalized === "parent_caregiver" || normalized === "caregiver";
  }

  function toIsoString(value) {
    if (value?.toDate) {
      return value.toDate().toISOString();
    }
    return null;
  }

  async function resolveViewerTarget(userId) {
    const viewerDoc = await db.collection("users").doc(userId).get();
    if (!viewerDoc.exists) {
      return null;
    }

    const viewer = { id: viewerDoc.id, ...viewerDoc.data() };
    let user = viewer;
    let dataUserId = userId;
    let caregiverDashboardState = null;

    if (isCaregiverRole(viewer.role)) {
      caregiverDashboardState = {
        isCaregiver: true,
        childAgeGroup: viewer.childAgeGroup || null,
        linkedChildAccount: viewer.linkedChildAccount === true,
        linkedChildUserId: viewer.linkedChildUserId || null,
        linkStatus: viewer.linkStatus || "none",
        activeLinkingCode: viewer.activeLinkingCode || null,
        linkCodeExpiresAt: toIsoString(viewer.linkCodeExpiresAt),
      };

      if (
        viewer.childAgeGroup === "13-18" &&
        viewer.linkedChildAccount === true &&
        viewer.linkedChildUserId
      ) {
        const linkedChildDoc = await db
          .collection("users")
          .doc(viewer.linkedChildUserId)
          .get();
        if (linkedChildDoc.exists) {
          user = { id: linkedChildDoc.id, ...linkedChildDoc.data() };
          dataUserId = linkedChildDoc.id;
        } else {
          caregiverDashboardState.linkedChildAccount = false;
          caregiverDashboardState.linkedChildUserId = null;
          caregiverDashboardState.linkStatus = "pending";
        }
      }
    }

    return {
      viewer,
      user,
      dataUserId,
      caregiverDashboardState,
    };
  }

  router.post("/dashboard-summary", async (req, res) => {
    console.log("Dashboard summary requested:", req.body);

    try {
      const { userId, date } = req.body;

      if (!userId) {
        throw new Error("Missing userId");
      }

      const resolved = await resolveViewerTarget(userId);
      if (!resolved) {
        return res.status(404).json({
          success: false,
          error: "User profile not found",
        });
      }
      const { viewer, user, dataUserId, caregiverDashboardState } = resolved;

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
        (await getFirstUserDocument("labResults", dataUserId));
      const anthropometricHistoryByUser = await getUserDocuments(
        "anthropometrics",
        dataUserId,
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
        dataUserId,
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
      const intakeData = await getDailyIntakeData(dataUserId, date, user);
      const gamificationDate = date || todayDateKey();
      await recomputeGamificationForDate({
        admin,
        db,
        userId: dataUserId,
        date: gamificationDate,
      });
      const gamification = await getGamificationSummary({
        db,
        userId: dataUserId,
        date: gamificationDate,
      });

      return res.status(200).json({
        success: true,
        viewer,
        user,
        dashboardOwnerId: dataUserId,
        caregiverDashboardState,
        nutritionTargets,
        medicalProfile,
        phase2DecisionSupport,
        labResults,
        anthropometrics,
        intakeData,
        gamification,
        medicationData:
          medications.length > 0 ? { count: medications.length } : null,
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

  router.post("/analytics-summary", async (req, res) => {
    console.log("Analytics summary requested:", req.body);

    try {
      const { userId, range, endDate } = req.body;

      if (!userId) {
        throw new Error("Missing userId");
      }

      const resolved = await resolveViewerTarget(userId);
      if (!resolved) {
        return res.status(404).json({
          success: false,
          error: "User profile not found",
        });
      }
      const { viewer, user, dataUserId, caregiverDashboardState } = resolved;
      const resolvedRange = dateRangeForAnalytics(range, endDate || todayDateKey());

      console.log(
        `Fetching analytics for user ${dataUserId}, range: ${resolvedRange.startDate} to ${resolvedRange.endDate}`,
      );

      const { childProfileId, summaries } = await getDailyIntakeSummariesForRange(
        dataUserId,
        user,
        resolvedRange.startDate,
        resolvedRange.endDate,
      );

      console.log(
        `Found ${summaries.length} summaries for range ${resolvedRange.startDate}-${resolvedRange.endDate}`,
      );

      const aggregated = aggregateDailySummaries(
        summaries,
        resolvedRange.startDate,
        resolvedRange.endDate,
      );
      const summaryDocumentId = analyticsSummaryDocumentId(
        childProfileId,
        resolvedRange.periodType,
        resolvedRange.startDate,
        resolvedRange.endDate,
      );
      const summaryPayload = {
        userId,
        childProfileId,
        periodType: resolvedRange.periodType,
        label: analyticsPeriodLabel(
          resolvedRange.periodType,
          resolvedRange.startDate,
          resolvedRange.endDate,
        ),
        startDate: resolvedRange.startDate,
        endDate: resolvedRange.endDate,
        activeDays: aggregated.activeDays,
        totalDays: aggregated.totalDays,
        totals: aggregated.totals,
        averages: aggregated.averages,
        dailySummaries: aggregated.dailySummaries,
        source: "dailyIntakeSummaries",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db
        .collection("analyticsSummaries")
        .doc(summaryDocumentId)
        .set(summaryPayload, { merge: true });

      console.log(
        `Analytics summary computed: ${aggregated.activeDays} active days, ${aggregated.totalDays} total days`,
      );

      return res.status(200).json({
        success: true,
        viewer,
        user,
        dashboardOwnerId: dataUserId,
        caregiverDashboardState,
        summaryDocumentId,
        summary: {
          ...summaryPayload,
          updatedAt: new Date().toISOString(),
        },
      });
    } catch (error) {
      console.error("ANALYTICS_SUMMARY ERROR:", error.message);
      console.error("Stack:", error.stack);
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

      const resolved = await resolveViewerTarget(userId);
      if (!resolved) {
        return res.status(404).json({
          success: false,
          error: "User profile not found",
        });
      }
      const { viewer, user, dataUserId, caregiverDashboardState } = resolved;
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
        dataUserId,
      );
      const historicalLabResultsHistory = await getUserDocuments(
        "historicalLabResults",
        dataUserId,
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
        dataUserId,
      );
      const anthropometricHistoryByProfile = await getDocumentsByField(
        "anthropometrics",
        "medicalProfileId",
        user.medicalProfileId,
      );
      const historicalAnthropometricHistoryByUser = await getUserDocuments(
        "historicalAnthropometrics",
        dataUserId,
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
      const medicationUserIds = [
        dataUserId,
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
        viewer,
        user,
        profileOwnerId: dataUserId,
        caregiverDashboardState,
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
}

module.exports = { registerSummaryRoutes };
