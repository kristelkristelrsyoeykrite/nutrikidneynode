const { admin, db } = require("../firebase/admin");
const { decryptHealthDocument, decryptHealthProfile } = require("../utils/encryption");
const {
  doseWindowsAround,
  dateKeyFromUtcMs,
  MISSED_NOTIFICATION_DELAY_MS,
  notificationWindowId,
  resolveMedicationDoseStatus,
  resolveDoseWindowStatus,
  todayDateKey,
} = require("../utils/medicationDoseRecords");

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

/**
 * Backend Reminder Scheduler
 * 
 * This service:
 * - Runs every 5 minutes to check for due reminders
 * - Checks if conditions are met (meal logged, medication taken, etc)
 * - Sends FCM notifications to registered devices
 * - Handles caregiver-to-child delivery
 * - Respects "do not remind me" settings
 */

function numberOrZero(value) {
  const num = Number(value);
  return Number.isFinite(num) ? num : 0;
}

function safeDecryptHealthProfile(profileData) {
  if (!profileData || typeof profileData !== "object") return profileData;
  try {
    return decryptHealthProfile(profileData);
  } catch (_) {
    // If ENCRYPTION_KEY is missing/misconfigured, don't break reminders.
    return profileData;
  }
}

function displayNameFromProfile(profile = {}) {
  // Match existing hydration reminder behavior, but guard against non-string values
  // so we never end up with "Missed medication for [object Object]".
  const candidates = [
    profile.childFullName,
    profile.child_name,
    profile.childName,
    profile.fullName,
    profile.displayName,
    profile.name,
  ];

  for (const candidate of candidates) {
    if (typeof candidate !== "string") continue;
    const text = candidate.trim();
    if (text) return text;
  }

  return "there";
}

async function deleteSnapshotInBatches(snapshot) {
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

async function cleanupOldReminderCollections() {
  try {
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 24 * 60 * 60 * 1000),
    );
    const collections = [
      { name: "upcomingReminders", field: "timestamp" },
      { name: "upcomingReminders", field: "dueTime" },
      { name: "reminderLogs", field: "sentAt" },
    ];

    let totalDeleted = 0;
    for (const { name, field } of collections) {
      const snapshot = await db
        .collection(name)
        .where(field, "<", cutoff)
        .limit(400)
        .get();
      totalDeleted += await deleteSnapshotInBatches(snapshot);
    }

    const oldDay = new Date(Date.now() - 24 * 60 * 60 * 1000)
      .toISOString()
      .slice(0, 10);
    const oldUpcomingByDay = await db
      .collection("upcomingReminders")
      .where("day", "<", oldDay)
      .limit(400)
      .get();
    totalDeleted += await deleteSnapshotInBatches(oldUpcomingByDay);

    if (totalDeleted > 0) {
      console.log(`[Reminders] Cleaned ${totalDeleted} old reminder documents`);
    }
  } catch (error) {
    console.error("[Reminders] Reminder cleanup failed:", error.message);
  }
}

/**
 * Check if a meal has been logged for today
 */
async function hasMealBeenLoggedToday(userId) {
  try {
    const today = todayDateKey();
    const snapshot = await db
      .collection("foodLogs")
      .where("userId", "==", userId)
      .where("date", "==", today)
      .limit(1)
      .get();

    return !snapshot.empty;
  } catch (error) {
    console.error("Error checking meal logs:", error.message);
    return false;
  }
}

/**
 * Check if there are still medications that need reminders.
 */
async function hasPendingMedicationReminders(userId) {
  try {
    const snapshot = await db
      .collection("medications")
      .where("userId", "==", userId)
      .get();

    if (snapshot.empty) return false;

    const nowMs = Date.now();

    for (const doc of snapshot.docs) {
      const medicationId = doc.id;
      const medication = decryptHealthDocument(doc.data() || {});
      const doseStatus = await resolveMedicationDoseStatus({
        userId,
        medicationId,
        medicationDoc: medication,
        nowMs,
      });
      if (doseStatus.dueNow > 0 || doseStatus.missedCountToday > 0) {
        return true;
      }
    }

    return false;
  } catch (error) {
    console.error("Error checking medication logs:", error.message);
    return true;
  }
}

async function hasMedicationBeenTakenToday(userId) {
  return !(await hasPendingMedicationReminders(userId));
}

/**
 * Check if hydration target has been met today
 */
async function hasHydrationTargetBeenMetToday(userId, fluidLimitMl) {
  try {
    const today = todayDateKey();
    const snapshot = await db
      .collection("foodLogs")
      .where("userId", "==", userId)
      .where("date", "==", today)
      .get();

    let totalWaterMl = 0;
    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      if (!data.deletedAt) {
        const waterMl = numberOrZero(
          data.waterMl ?? data.water_ml ?? data.fluid_ml
        );
        totalWaterMl += waterMl;
      }
    });

    // Consider hydration met if logged 80% of target
    return totalWaterMl >= fluidLimitMl * 0.8;
  } catch (error) {
    console.error("Error checking hydration:", error.message);
    return false;
  }
}

/**
 * Get last reminder timestamp for a user
 */
async function getLastReminderTimestamp(userId, reminderType) {
  try {
    const doc = await db
      .collection("reminderState")
      .doc(`${userId}_${reminderType}`)
      .get();

    if (doc.exists) {
      const data = doc.data();
      return data.lastSentAt?.toMillis?.() || 0;
    }
    return 0;
  } catch (error) {
    console.error("Error getting last reminder time:", error.message);
    return 0;
  }
}

/**
 * Update last reminder timestamp
 */
async function updateLastReminderTimestamp(userId, reminderType) {
  try {
    await db
      .collection("reminderState")
      .doc(`${userId}_${reminderType}`)
      .set(
        {
          userId,
          reminderType,
          lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
  } catch (error) {
    console.error("Error updating reminder timestamp:", error.message);
  }
}

/**
 * Check if enough time has passed since last reminder
 */
function shouldRemindAgain(lastReminderMs, intervalMinutes = 30) {
  const nowMs = Date.now();
  const intervalMs = intervalMinutes * 60 * 1000;
  return nowMs - lastReminderMs >= intervalMs;
}

function reminderTargetIdsForUser(userId, user = {}) {
  const ids = new Set([String(userId || "").trim()]);
  const linkedChildren = Array.isArray(user.linkedChildren)
    ? user.linkedChildren
    : [];

  for (const child of linkedChildren) {
    [
      child?.userId,
      child?.uid,
      child?.id,
      child?.childProfileId,
      child?.profileUserId,
    ].forEach((value) => {
      const text = String(value || "").trim();
      if (text) ids.add(text);
    });
  }

  [
    user.activeDirectChildProfileId,
    user.childProfileId,
    user.linkedChildUserId,
  ].forEach((value) => {
    const text = String(value || "").trim();
    if (text) ids.add(text);
  });

  return Array.from(ids).filter(Boolean);
}

/**
 * Send FCM message to user's devices
 */
function deviceTokenEntries(profile = {}) {
  const raw = profile.deviceTokens;
  if (!raw || typeof raw !== "object") return [];
  return Object.values(raw)
    .filter((entry) => entry && typeof entry.token === "string" && entry.token.trim())
    .map((entry) => ({ ...entry, token: entry.token.trim() }));
}

function tokenKey(token) {
  return String(token || "").trim();
}

function caregiverIdsForProfile(profile = {}) {
  return [
    profile.caregiverUserId,
    profile.caregiverId,
    profile.parentUserId,
    profile.caregiverSettings?.caregiverId,
  ]
    .map((value) => String(value || "").trim())
    .filter(Boolean);
}

async function addRecipientDeviceTokens(recipients, recipientUserId, targetUserId) {
  if (!recipientUserId || recipients.has(recipientUserId)) return;

  const doc = await db.collection("users").doc(recipientUserId).get();
  if (!doc.exists) return;

  const profile = safeDecryptHealthProfile(doc.data() || {});
  const tokens = deviceTokenEntries(profile);
  if (tokens.length === 0) return;

  recipients.set(recipientUserId, {
    userId: recipientUserId,
    targetUserId,
    tokens,
  });
}

async function reminderRecipientsForUser(userId, profile = {}, extraRecipientUserIds = []) {
  const recipients = new Map();
  await addRecipientDeviceTokens(recipients, userId, userId);

  for (const caregiverId of [
    ...caregiverIdsForProfile(profile),
    ...extraRecipientUserIds,
  ]) {
    await addRecipientDeviceTokens(recipients, caregiverId, userId);
  }

  return Array.from(recipients.values());
}

function uniqueRecipientTokens(recipients = []) {
  const seen = new Set();
  const out = [];
  for (const recipient of recipients) {
    for (const entry of recipient.tokens || []) {
      const token = tokenKey(entry.token);
      if (!token || seen.has(token)) continue;
      seen.add(token);
      out.push({
        recipientUserId: recipient.userId,
        targetUserId: recipient.targetUserId,
        token,
      });
    }
  }
  return out;
}

async function sendReminderToDevices(userId, reminderData, options = {}) {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.warn(`User ${userId} not found`);
      return;
    }

    const user = safeDecryptHealthProfile(userDoc.data() || {});
    const recipients = await reminderRecipientsForUser(
      userId,
      user,
      options.extraRecipientUserIds,
    );
    const validTokens = uniqueRecipientTokens(recipients);

    if (validTokens.length === 0) {
      console.log(`No device tokens for reminder target ${userId}`);
      return;
    }

    const baseMessage = {
      notification: {
        title: reminderData.title,
        body: reminderData.body,
      },
      android: {
        priority: "high",
        notification: {
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
          channelId: "nutrikidney_reminders",
        },
      },
    };

    // Send to all devices
    const results = await Promise.allSettled(
      validTokens.map((entry) =>
        admin.messaging().send({
          ...baseMessage,
          data: {
            type: String(reminderData.type || ""),
            userId: entry.recipientUserId,
            targetUserId: entry.targetUserId,
            timestamp: Date.now().toString(),
          },
          token: entry.token,
        }),
      ),
    );

    const successful = results.filter((r) => r.status === "fulfilled").length;
    const failed = results.filter((r) => r.status === "rejected").length;

    console.log(
      `Sent reminder to ${userId}: ${successful} succeeded, ${failed} failed`
    );

    // Log reminder attempt for analytics
    await db.collection("reminderLogs").add({
      userId,
      reminderType: reminderData.type,
      title: reminderData.title,
      body: reminderData.body,
      devicesTargeted: validTokens.length,
      devicesSucceeded: successful,
      devicesFailed: failed,
      recipientUserIds: [...new Set(validTokens.map((entry) => entry.recipientUserId))],
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { successful, failed };
  } catch (error) {
    console.error("Error sending reminder:", error.message);
    throw error;
  }
}

/**
 * Check and send meal reminders
 */
async function checkMealReminders() {
  console.log("[Reminders] Checking meal reminders...");

  try {
    // Get all users with meal reminders enabled
    const usersSnapshot = await db
      .collection("users")
      .where("reminderSettings.mealReminders.enabled", "==", true)
      .get();

    for (const userDoc of usersSnapshot.docs) {
      const user = safeDecryptHealthProfile(userDoc.data() || {});
      const userId = userDoc.id;

      // Skip if "do not remind me" was just clicked
      if (user.reminderSettings?.dontRemindUntil) {
        const dontRemindUntil = user.reminderSettings.dontRemindUntil.toMillis?.() || 0;
        if (Date.now() < dontRemindUntil) {
          continue;
        }
      }

      // Check if meal was logged today
      const mealLogged = await hasMealBeenLoggedToday(userId);
      if (mealLogged) {
        continue; // Already logged, don't remind
      }

      // Check if enough time passed since last reminder
      const lastReminder = await getLastReminderTimestamp(userId, "meal");
      if (!shouldRemindAgain(lastReminder, 30)) {
        continue; // Too soon to remind again
      }

      const childName = displayNameFromProfile(user);

      // Send reminder
      await sendReminderToDevices(userId, {
        type: "meal_reminder",
        title: `Reminder for ${childName}!`,
        body: "Have you eaten? Log your meal to track your nutrition.",
      });

      await updateLastReminderTimestamp(userId, "meal");
    }
  } catch (error) {
    console.error("Error in meal reminder check:", error.message);
  }
}

/**
 * Check and send medication reminders
 */
async function checkMedicationReminders() {
  console.log("[Reminders] Checking medication reminders...");

  try {
    // Get all users with medication reminders enabled
    const usersSnapshot = await db
      .collection("users")
      .where("reminderSettings.medicationReminders", "==", true)
      .get();

    for (const userDoc of usersSnapshot.docs) {
      const user = safeDecryptHealthProfile(userDoc.data() || {});
      const userId = userDoc.id;

      // Skip if "do not remind me" was just clicked
      if (user.reminderSettings?.dontRemindUntil) {
        const dontRemindUntil = user.reminderSettings.dontRemindUntil.toMillis?.() || 0;
        if (Date.now() < dontRemindUntil) {
          continue;
        }
      }

      // Stop reminding once all medication statuses are marked as Taken.
      const hasPendingMedication = await hasPendingMedicationReminders(userId);
      if (!hasPendingMedication) {
        continue;
      }

      // Check if enough time passed since last reminder
      const lastReminder = await getLastReminderTimestamp(userId, "medication");
      if (!shouldRemindAgain(lastReminder, 24 * 60)) {
        continue; // Too soon to remind again
      }

      const childName = displayNameFromProfile(user);

      // Send reminder
      await sendReminderToDevices(userId, {
        type: "medication_reminder",
        title: `Reminder for ${childName}!`,
        body: "Don't forget to take your medication.",
      });

      await updateLastReminderTimestamp(userId, "medication");
    }
  } catch (error) {
    console.error("Error in medication reminder check:", error.message);
  }
}

/**
 * Check and send hydration reminders
 */
async function checkHydrationReminders() {
  console.log("[Reminders] Checking hydration reminders...");

  try {
    // Get all users with hydration alerts enabled
    const usersSnapshot = await db
      .collection("users")
      .where("reminderSettings.hydrationAlerts", "==", true)
      .get();

    for (const userDoc of usersSnapshot.docs) {
      const user = safeDecryptHealthProfile(userDoc.data() || {});
      const userId = userDoc.id;
      const medicalProfileId = String(user.medicalProfileId || "").trim();
      if (!medicalProfileId) {
        continue;
      }

      // Get fluid restriction limit
      const medicalProfileDoc = await db
        .collection("medicalProfile")
        .doc(medicalProfileId)
        .get();

      if (!medicalProfileDoc.exists) {
        continue;
      }

      const medicalProfile = medicalProfileDoc.data();
      const fluidLimitMl = numberOrZero(
        medicalProfile.fluid_limit_ml ?? medicalProfile.fluidLimitMl
      );

      if (fluidLimitMl <= 0) {
        continue; // No fluid restriction
      }

      // Skip if "do not remind me" was just clicked
      if (user.reminderSettings?.dontRemindUntil) {
        const dontRemindUntil = user.reminderSettings.dontRemindUntil.toMillis?.() || 0;
        if (Date.now() < dontRemindUntil) {
          continue;
        }
      }

      // Check if hydration target was met
      const hydrationMet = await hasHydrationTargetBeenMetToday(
        userId,
        fluidLimitMl
      );
      if (hydrationMet) {
        continue; // Target met, don't remind
      }

      // Check if enough time passed since last reminder
      const lastReminder = await getLastReminderTimestamp(userId, "hydration");
      if (!shouldRemindAgain(lastReminder, 120)) {
        // 2 hour interval for hydration
        continue;
      }

      const childName = displayNameFromProfile(user);

      // Send reminder
      await sendReminderToDevices(userId, {
        type: "hydration_reminder",
        title: `Reminder for ${childName}!`,
        body: `Log your fluid intake. Goal: ${fluidLimitMl}mL`,
      });

      await updateLastReminderTimestamp(userId, "hydration");
    }
  } catch (error) {
    console.error("Error in hydration reminder check:", error.message);
  }
}

/**
 * Check and create missed medication reminders
 * Sends notifications for medications not taken 1 hour after initial reminder
 */
async function checkMissedMedicationReminders() {
  console.log("[Reminders] Checking missed medication reminders...");

  try {
    // Get all users with medication reminders enabled
    const usersSnapshot = await db
      .collection("users")
      .where("reminderSettings.medicationReminders", "==", true)
      .get();

    for (const userDoc of usersSnapshot.docs) {
      const user = safeDecryptHealthProfile(userDoc.data() || {});
      const userId = userDoc.id;

      const nowMs = Date.now();
      const targetUserIds = reminderTargetIdsForUser(userId, user);

      for (const targetUserId of targetUserIds) {
        let targetProfile = user;
        if (targetUserId !== userId) {
          const targetDoc = await db.collection("users").doc(targetUserId).get();
          targetProfile = targetDoc.exists
            ? safeDecryptHealthProfile(targetDoc.data() || {})
            : {};
        }
        const childName = displayNameFromProfile(targetProfile);

        const medicationsSnapshot = await db
          .collection("medications")
          .where("userId", "==", targetUserId)
          .get();

        if (medicationsSnapshot.empty) continue;

        for (const medicationDoc of medicationsSnapshot.docs) {
          const medicationId = medicationDoc.id;
          const medication = decryptHealthDocument(medicationDoc.data() || {});
          const name =
            String(
              medication.medication_name ??
                medication.medicationName ??
                medication.name ??
                "Medication",
            ).trim() || "Medication";

          const completedWindows = doseWindowsAround({
            medicationDoc: medication,
            nowMs,
            beforeDays: 2,
            afterDays: 1,
          }).filter(
            (window) =>
              window.endMs + MISSED_NOTIFICATION_DELAY_MS <= nowMs &&
              dateKeyFromUtcMs(window.endMs) === todayDateKey(nowMs),
          );

          for (const window of completedWindows) {
            const resolved = await resolveDoseWindowStatus({
              userId: targetUserId,
              medicationId,
              window,
              nowMs,
            });
            if (resolved.status !== "missed") continue;

            const notificationId = notificationWindowId({
              userId: targetUserId,
              medicationId,
              expectedDate: window.expectedDate,
              expectedTime: window.expectedTime,
            });
            const notificationRef = db.collection("notifications").doc(notificationId);
            const notificationSnap = await notificationRef.get();
            if (notificationSnap.exists) continue;

            const missedNotification = {
              userId: targetUserId,
              type: "missed_medication_reminder",
              title: `Missed medication for ${childName}`,
              body: `You missed your ${name} reminder at ${window.expectedTime}. Please take your medication if possible.`,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              isMissed: true,
              priority: "high",
              color: "red",
              read: false,
              medicationId,
              medicationName: name,
              scheduledTime: window.expectedTime,
              windowStartAt: admin.firestore.Timestamp.fromDate(window.startAt),
              windowEndAt: admin.firestore.Timestamp.fromDate(window.endAt),
              dueTime: admin.firestore.Timestamp.fromDate(window.startAt),
              day: window.expectedDate,
              notificationId,
            };

            try {
              await notificationRef.create(missedNotification);
            } catch (error) {
              const code = String(error?.code || error?.message || "");
              if (
                error?.code === 6 ||
                code.includes("ALREADY_EXISTS") ||
                code.includes("already exists")
              ) {
                continue;
              }
              throw error;
            }

            await sendReminderToDevices(
              targetUserId,
              {
                type: "missed_medication_reminder",
                title: `Missed medication for ${childName}`,
                body: `You missed your ${name} reminder at ${window.expectedTime}. Please take your medication if possible.`,
              },
              { extraRecipientUserIds: targetUserId === userId ? [] : [userId] },
            );

            await updateLastReminderTimestamp(targetUserId, notificationId);

            console.log(
              `Sent missed medication reminder to ${targetUserId} for ${medicationId} window ${window.id}`,
            );
          }
        }
      }
    }
  } catch (error) {
    console.error("Error in missed medication reminder check:", error.message);
  }
}

/**
 * Main scheduler function - runs every 5 minutes
 */
async function runReminderScheduler() {
  try {
    const manilaTime = new Intl.DateTimeFormat("en-US", {
      timeZone: "Asia/Manila",
      dateStyle: "short",
      timeStyle: "medium",
    }).format(new Date());
    console.log(
      `[Reminders] Scheduler running at ${new Date().toISOString()} (${manilaTime} Asia/Manila)`
    );

    // Only backend-generate alerts that are tied to an actual scheduled dose.
    // Meal, hydration, and generic medication reminders are scheduled locally
    // by the Flutter app; sending them here caused extra "unscheduled" pushes.
    await cleanupOldReminderCollections();
    await checkMissedMedicationReminders();

    console.log("[Reminders] Scheduler check complete");
  } catch (error) {
    console.error("[Reminders] Scheduler error:", error.message);
  }
}

/**
 * Initialize the reminder scheduler
 */
function initializeReminderScheduler() {
  console.log("[Reminders] Initializing reminder scheduler...");

  const intervalMs = Math.max(
    10_000,
    Number(process.env.REMINDER_SCHEDULER_INTERVAL_MS) || 60 * 1000,
  );

  // Run on an interval; keep it configurable.
  setInterval(() => {
    runReminderScheduler();
  }, intervalMs);

  // Also run immediately on startup
  runReminderScheduler();

  console.log("[Reminders] Scheduler initialized");
}

module.exports = {
  initializeReminderScheduler,
  runReminderScheduler,
  sendReminderToDevices,
  hasMealBeenLoggedToday,
  hasMedicationBeenTakenToday,
  hasHydrationTargetBeenMetToday,
};
