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

  function parseClockTime(value) {
    const text = String(value || "").trim();
    const match = text.match(/^(\d{1,2}):(\d{2})$/);
    if (!match) return null;
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return {
      hour,
      minute,
      text: `${hour.toString().padStart(2, "0")}:${minute.toString().padStart(2, "0")}`,
    };
  }

  function medicationScheduleTimes(medication) {
    const times = [];
    const scheduledTimes =
      medication?.scheduled_times ?? medication?.scheduledTimes;
    if (Array.isArray(scheduledTimes)) {
      for (const entry of scheduledTimes) {
        const parsed = parseClockTime(entry);
        if (parsed) times.push(parsed.text);
      }
    }

    if (times.length > 0) return Array.from(new Set(times));

    const startTime = medication?.start_time ?? medication?.startTime;
    const parsed = parseClockTime(startTime);
    return parsed ? [parsed.text] : [];
  }

  function nextUpcomingDoseTime({ times, takenTimes, now }) {
    const taken = new Set(takenTimes || []);
    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    const remaining = [];

    for (const timeText of times) {
      if (taken.has(timeText)) continue;
      const parsed = parseClockTime(timeText);
      if (!parsed) continue;
      const minutes = parsed.hour * 60 + parsed.minute;
      if (minutes > nowMinutes) {
        remaining.push({ timeText, minutes });
      }
    }

    remaining.sort((a, b) => a.minutes - b.minutes);
    return remaining.length > 0 ? remaining[0].timeText : null;
  }

  function countMissedDoses({ times, takenTimes, now, graceMinutes = 5 }) {
    const taken = new Set(takenTimes || []);
    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    const threshold = nowMinutes - graceMinutes;
    let missed = 0;

    for (const timeText of times) {
      if (taken.has(timeText)) continue;
      const parsed = parseClockTime(timeText);
      if (!parsed) continue;
      const minutes = parsed.hour * 60 + parsed.minute;
      if (minutes <= threshold) {
        missed += 1;
      }
    }

    return missed;
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
      const today = todayDateKey();
      const now = new Date();
      const medicationsWithDoseStatus = await Promise.all(
        medications.map(async (medication) => {
          const times = medicationScheduleTimes(medication);
          if (times.length === 0) {
            return { ...medication, takenTimesToday: [], nextDoseTime: null };
          }

          const logIds = times.map(
            (timeText) => `${dataUserId}_${medication.id}_${today}_${timeText}`,
          );
          const logs = await Promise.all(
            logIds.map((id) =>
              db.collection("medicationIntakeLogs").doc(id).get(),
            ),
          );

          const takenTimesToday = [];
          for (let i = 0; i < logs.length; i += 1) {
            if (logs[i].exists) {
              takenTimesToday.push(times[i]);
            }
          }

          const nextDoseTime = nextUpcomingDoseTime({
            times,
            takenTimes: takenTimesToday,
            now,
          });

          const missedCountToday = countMissedDoses({
            times,
            takenTimes: takenTimesToday,
            now,
            graceMinutes: 5,
          });

          return {
            ...medication,
            takenTimesToday,
            nextDoseTime,
            missedCountToday,
          };
        }),
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
          medicationsWithDoseStatus.length > 0
            ? { count: medicationsWithDoseStatus.length }
            : null,
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

      const today = todayDateKey();
      const now = new Date();
      const medicationsWithDoseStatus = await Promise.all(
        medications.map(async (medication) => {
          const times = medicationScheduleTimes(medication);
          if (times.length === 0) {
            return { ...medication, takenTimesToday: [], nextDoseTime: null };
          }

          const logIds = times.map(
            (timeText) => `${dataUserId}_${medication.id}_${today}_${timeText}`,
          );
          const logs = await Promise.all(
            logIds.map((id) =>
              db.collection("medicationIntakeLogs").doc(id).get(),
            ),
          );

          const takenTimesToday = [];
          for (let i = 0; i < logs.length; i += 1) {
            if (logs[i].exists) {
              takenTimesToday.push(times[i]);
            }
          }

          const nextDoseTime = nextUpcomingDoseTime({
            times,
            takenTimes: takenTimesToday,
            now,
          });

          const missedCountToday = countMissedDoses({
            times,
            takenTimes: takenTimesToday,
            now,
            graceMinutes: 5,
          });

          return {
            ...medication,
            takenTimesToday,
            nextDoseTime,
            missedCountToday,
          };
        }),
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
