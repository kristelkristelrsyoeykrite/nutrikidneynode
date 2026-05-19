function registerSummaryRoutes(router, deps) {
  const {
    getGamificationSummary,
    recomputeGamificationForDate,
  } = require("../../services/gamificationService");
  const {
    resolveMedicationDoseStatus,
  } = require("../../utils/medicationDoseRecords");

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
    decryptHealthProfile,
  } = deps;
  function requestMeta(req, extra = {}) {
    const body = req.body && typeof req.body === "object" ? req.body : {};
    return {
      userId: body.userId,
      profileUserId: body.profileUserId,
      keys: Object.keys(body).length,
      ...extra,
    };
  }

  function medicationDoseLogOwnerId(medication = {}, fallbackUserId) {
    return [
      medication.userId,
      medication.uid,
      medication.profileUserId,
      medication.childProfileId,
      medication.child_profile_id,
    ]
      .map((value) => String(value || "").trim())
      .find(Boolean) || String(fallbackUserId || "").trim();
  }

  async function medicationsWithWindowStatus({ medications, dataUserId, nowMs = Date.now() }) {
    let dosesDueNow = 0;
    let dosesTakenToday = 0;
    let missedDosesToday = 0;

    const resolved = await Promise.all(
      medications.map(async (medication) => {
        const logUserId = medicationDoseLogOwnerId(medication, dataUserId);
        const doseStatus = await resolveMedicationDoseStatus({
          userId: logUserId,
          medicationId: medication.id,
          medicationDoc: medication,
          nowMs,
        });

        dosesDueNow += doseStatus.dueNow;
        dosesTakenToday += doseStatus.takenTimesToday.length;
        missedDosesToday += doseStatus.missedCountToday;

        return {
          ...medication,
          takenTimesToday: doseStatus.takenTimesToday,
          nextDoseTime: doseStatus.nextDoseTime,
          missedCountToday: doseStatus.missedCountToday,
          doseWindow: doseStatus.doseWindow,
          doseWindowsToday: doseStatus.doseWindowsToday,
        };
      }),
    );

    return {
      medications: resolved,
      medicationData:
        resolved.length > 0
          ? {
              count: resolved.length,
              totalActiveMedications: resolved.length,
              dosesDueNow,
              dosesTakenToday,
              missedDosesToday,
            }
          : {
              count: 0,
              totalActiveMedications: 0,
              dosesDueNow: 0,
              dosesTakenToday: 0,
              missedDosesToday: 0,
            },
    };
  }

  function isCaregiverRole(role) {
    const normalized = String(role || "").trim().toLowerCase();
    return normalized === "parent_caregiver" || normalized === "caregiver";
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

  function toIsoString(value) {
    if (value?.toDate) {
      return value.toDate().toISOString();
    }
    return null;
  }

  function childDisplayName(child = {}, childProfile = {}) {
    return (
      childProfile.childFullName ||
      childProfile.child_name ||
      childProfile.fullName ||
      childProfile.name ||
      child.name ||
      child.fullName ||
      child.childFullName ||
      "Child Profile"
    );
  }

  async function enrichLinkedChildren(linkedChildren = []) {
    return Promise.all(
      linkedChildren.map(async (child) => {
        const childId = child?.userId || child?.uid || child?.id;
        if (!childId) return child;
        const childDoc = await db.collection("users").doc(String(childId)).get();
        const childProfile = childDoc.exists
          ? decryptHealthProfile(childDoc.data() || {})
          : {};
        return {
          ...child,
          id: child.id || String(childId),
          userId: child.userId || String(childId),
          uid: child.uid || String(childId),
          name: childDisplayName(child, childProfile),
          fullName: childProfile.fullName || child.fullName || child.name || null,
          childFullName:
            childProfile.childFullName ||
            childProfile.child_name ||
            child.childFullName ||
            null,
          age: childProfile.ageYears || childProfile.age_years || child.age || null,
          ageYears:
            childProfile.ageYears || childProfile.age_years || child.ageYears || null,
        };
      }),
    );
  }

  async function resolveViewerTarget(userId, requestedProfileUserId = null) {
    const viewerDoc = await db.collection("users").doc(userId).get();
    if (!viewerDoc.exists) {
      return null;
    }

    const viewer = { id: viewerDoc.id, ...decryptHealthProfile(viewerDoc.data() || {}) };
    let user = viewer;
    let dataUserId = userId;
    let caregiverDashboardState = null;

    if (isCaregiverRole(viewer.role)) {
      const linkedChildren = Array.isArray(viewer.linkedChildren)
        ? viewer.linkedChildren
        : [];
      const enrichedLinkedChildren = await enrichLinkedChildren(linkedChildren);
      const hasLinkedAdolescentAccount = enrichedLinkedChildren.some(
        (child) => !isDirectManagedChildEntry(child),
      );
      caregiverDashboardState = {
        isCaregiver: true,
        childAgeGroup: viewer.childAgeGroup || null,
        activeDirectChildProfileId: viewer.activeDirectChildProfileId || null,
        linkedChildAccount:
          hasLinkedAdolescentAccount ||
          (linkedChildren.length === 0 && viewer.linkedChildAccount === true),
        linkedChildUserId:
          hasLinkedAdolescentAccount || viewer.linkedChildAccount === true
            ? viewer.linkedChildUserId || null
            : null,
        linkedChildren: enrichedLinkedChildren,
        linkStatus: viewer.linkStatus || "none",
        hasActiveLinkingCode: Boolean(
          viewer.activeLinkingCodeHash || viewer.activeLinkingCode,
        ),
        linkCodeExpiresAt: toIsoString(viewer.linkCodeExpiresAt),
      };

      const requestedLinkedChild =
        requestedProfileUserId &&
        enrichedLinkedChildren.some((child) => {
          const childId = child?.userId || child?.uid || child?.id;
          return String(childId || "") === String(requestedProfileUserId);
        });
      const firstManagedChildId =
        enrichedLinkedChildren[0]?.userId ||
        enrichedLinkedChildren[0]?.uid ||
        enrichedLinkedChildren[0]?.id;
      const activeDirectChildId =
        viewer.activeDirectChildProfileId &&
        enrichedLinkedChildren.some((child) => {
          const childId = child?.userId || child?.uid || child?.id;
          return String(childId || "") === String(viewer.activeDirectChildProfileId);
        })
          ? viewer.activeDirectChildProfileId
          : null;
      const linkedAdolescentChildId =
        hasLinkedAdolescentAccount || viewer.linkedChildAccount === true
          ? viewer.linkedChildUserId
          : null;
      const targetLinkedChildId = requestedLinkedChild
        ? requestedProfileUserId
        : activeDirectChildId || firstManagedChildId || linkedAdolescentChildId;

      if (targetLinkedChildId) {
        const linkedChildDoc = await db
          .collection("users")
          .doc(targetLinkedChildId)
          .get();
        if (linkedChildDoc.exists) {
          user = {
            id: linkedChildDoc.id,
            ...decryptHealthProfile(linkedChildDoc.data() || {}),
          };
          dataUserId = linkedChildDoc.id;
          caregiverDashboardState.linkedChildUserId = linkedChildDoc.id;
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
    console.log("Dashboard summary requested:", requestMeta(req, {
      date: req.body.date,
    }));

    try {
      const { userId, profileUserId, date } = req.body;

      if (!userId) {
        throw new Error("Missing userId");
      }

      const resolved = await resolveViewerTarget(userId, profileUserId);
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
      const medicalProfile = decryptHealthProfile(
        await getDocumentData("medicalProfile", user.medicalProfileId),
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
      const {
        medications: medicationsWithDoseStatus,
        medicationData,
      } = await medicationsWithWindowStatus({
        medications,
        dataUserId,
      });
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
        medicationData,
        medications: medicationsWithDoseStatus,
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
    console.log("Analytics summary requested:", requestMeta(req, {
      range: req.body.range,
      hasEndDate: Boolean(req.body.endDate),
    }));

    try {
      const { userId, profileUserId, range, endDate } = req.body;

      if (!userId) {
        throw new Error("Missing userId");
      }

      const resolved = await resolveViewerTarget(userId, profileUserId);
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
    console.log("Health summary requested:", requestMeta(req));

    try {
      const { userId, profileUserId } = req.body;

      if (!userId) {
        throw new Error("Missing userId");
      }

      const resolved = await resolveViewerTarget(userId, profileUserId);
      if (!resolved) {
        return res.status(404).json({
          success: false,
          error: "User profile not found",
        });
      }
      const { viewer, user, dataUserId, caregiverDashboardState } = resolved;
      const medicalProfile = decryptHealthProfile(
        await getDocumentData("medicalProfile", user.medicalProfileId),
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

      const {
        medications: medicationsWithDoseStatus,
        medicationData,
      } = await medicationsWithWindowStatus({
        medications,
        dataUserId,
      });

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
        medicationData,
        medications: medicationsWithDoseStatus,
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
