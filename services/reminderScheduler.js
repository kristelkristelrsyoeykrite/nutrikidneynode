const { admin, db } = require("../firebase/admin");
const { decryptHealthDocument } = require("../utils/encryption");
const {
  todayDateKey,
  ensureDoseRecordsForDate,
  markOverdueDosesMissed,
} = require("../utils/medicationDoseRecords");

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

function getDirectManagedChildUserIds(user = {}) {
  const linkedChildren = Array.isArray(user.linkedChildren)
    ? user.linkedChildren
    : [];
  return linkedChildren
    .filter((child) => isDirectManagedChildEntry(child))
    .map((child) => child?.userId || child?.uid || child?.id)
    .filter((id) => typeof id === "string" && id.trim().length > 0);
}

async function getUserProfile(userId) {
  const doc = await db.collection("users").doc(userId).get();
  return doc.exists ? doc.data() || {} : null;
}

async function sendReminderToProfileRecipients({
  caregiverUserId,
  profileUserId,
  reminderData,
  includeProfileDevices = true,
}) {
  const targetUserIds = new Set();
  if (caregiverUserId) targetUserIds.add(String(caregiverUserId));
  if (includeProfileDevices && profileUserId) targetUserIds.add(String(profileUserId));

  for (const targetUserId of targetUserIds) {
    await sendReminderToDevices(targetUserId, {
      ...reminderData,
      // Keep the original profile id in the payload so the app can route correctly.
      dataUserId: String(profileUserId || targetUserId),
    });
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
    const today = todayDateKey();

    for (const doc of snapshot.docs) {
      const medicationId = doc.id;
      const medication = decryptHealthDocument(doc.data() || {});

      for (const clock of medicationScheduleTimes(medication)) {
        const scheduled = dateForTodayClockTime(clock);
        const scheduledMs = scheduled.getTime();
        if (scheduledMs > nowMs) continue;

        const logDocId = `${userId}_${medicationId}_${today}_${clock.text}`;
        const intakeLog = await db
          .collection("medicationIntakeLogs")
          .doc(logDocId)
          .get();
        if (!intakeLog.exists) {
          return true;
        }
      }
    }

    return false;
  } catch (error) {
    console.error("Error checking medication logs:", error.message);
    return true;
  }
}

function parseClockTime(value) {
  const text = String(value || "").trim();
  const match = text.match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return { hour, minute, text };
}

function dateForTodayClockTime(clock) {
  const now = new Date();
  return new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate(),
    clock.hour,
    clock.minute,
    0,
    0,
  );
}

function medicationScheduleTimes(medication) {
  const times = [];
  const scheduledTimes = medication.scheduled_times ?? medication.scheduledTimes;
  if (Array.isArray(scheduledTimes)) {
    for (const entry of scheduledTimes) {
      const parsed = parseClockTime(entry);
      if (parsed) times.push(parsed);
    }
  }

  if (times.length > 0) return times;

  const startTime =
    medication.start_time ?? medication.startTime ?? medication.time;
  const parsed = parseClockTime(startTime);
  if (parsed) times.push(parsed);
  return times;
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

/**
 * Send FCM message to user's devices
 */
async function sendReminderToDevices(userId, reminderData) {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.warn(`User ${userId} not found`);
      return;
    }

    const user = userDoc.data();
    const deviceTokens = user.deviceTokens || {};

    const validTokens = [
      ...new Set(
        Object.values(deviceTokens)
          .filter((entry) => entry && entry.token)
          .map((entry) => entry.token),
      ),
    ];

    if (validTokens.length === 0) {
      console.log(`No device tokens for user ${userId}`);
      return;
    }

    const message = {
      notification: {
        title: reminderData.title,
        body: reminderData.body,
      },
      data: {
        type: reminderData.type,
        userId: String(reminderData.dataUserId || userId),
        timestamp: Date.now().toString(),
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
      validTokens.map((token) =>
        admin.messaging().send({
          ...message,
          token,
        })
      )
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
    // Firestore doesn't support OR queries well here, so merge the 4 meal toggles.
    const [breakfastSnap, lunchSnap, snackSnap, dinnerSnap] =
      await Promise.all([
        db
          .collection("users")
          .where("reminderSettings.mealReminders.breakfast", "==", true)
          .get(),
        db
          .collection("users")
          .where("reminderSettings.mealReminders.lunch", "==", true)
          .get(),
        db
          .collection("users")
          .where("reminderSettings.mealReminders.snack", "==", true)
          .get(),
        db
          .collection("users")
          .where("reminderSettings.mealReminders.dinner", "==", true)
          .get(),
      ]);

    const docsById = new Map();
    for (const doc of [
      ...breakfastSnap.docs,
      ...lunchSnap.docs,
      ...snackSnap.docs,
      ...dinnerSnap.docs,
    ]) {
      docsById.set(doc.id, doc);
    }

    for (const userDoc of docsById.values()) {
      const user = userDoc.data();
      const userId = userDoc.id;
      const directChildIds = isCaregiverRole(user.role)
        ? getDirectManagedChildUserIds(user)
        : [];
      const targetProfileIds = [...new Set([userId, ...directChildIds])];

      // Skip if "do not remind me" was just clicked
      if (user.reminderSettings?.dontRemindUntil) {
        const dontRemindUntil = user.reminderSettings.dontRemindUntil.toMillis?.() || 0;
        if (Date.now() < dontRemindUntil) {
          continue;
        }
      }

      for (const profileUserId of targetProfileIds) {
        // Check if meal was logged today
        const mealLogged = await hasMealBeenLoggedToday(profileUserId);
        if (mealLogged) {
          continue; // Already logged, don't remind
        }

        // Check if enough time passed since last reminder (per profile)
        const lastReminder = await getLastReminderTimestamp(profileUserId, "meal");
        if (!shouldRemindAgain(lastReminder, 30)) {
          continue; // Too soon to remind again
        }

        const profile = profileUserId === userId ? user : await getUserProfile(profileUserId);
        if (!profile) continue;

        const childName = profile.childFullName || profile.child_name || "there";

        await sendReminderToProfileRecipients({
          caregiverUserId: isCaregiverRole(user.role) ? userId : null,
          profileUserId,
          reminderData: {
            type: "meal_reminder",
            title: `Reminder for ${childName}!`,
            body: "Have you eaten? Log your meal to track your nutrition.",
          },
          includeProfileDevices: !isCaregiverRole(user.role),
        });

        await updateLastReminderTimestamp(profileUserId, "meal");
      }
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
      const user = userDoc.data();
      const userId = userDoc.id;
      const directChildIds = isCaregiverRole(user.role)
        ? getDirectManagedChildUserIds(user)
        : [];
      const targetProfileIds = [...new Set([userId, ...directChildIds])];

      // Skip if "do not remind me" was just clicked
      if (user.reminderSettings?.dontRemindUntil) {
        const dontRemindUntil = user.reminderSettings.dontRemindUntil.toMillis?.() || 0;
        if (Date.now() < dontRemindUntil) {
          continue;
        }
      }

      for (const profileUserId of targetProfileIds) {
        // Stop reminding once all medication statuses are marked as Taken.
        const hasPendingMedication = await hasPendingMedicationReminders(profileUserId);
        if (!hasPendingMedication) {
          continue;
        }

        // Check if enough time passed since last reminder (per profile)
        const lastReminder = await getLastReminderTimestamp(profileUserId, "medication");
        if (!shouldRemindAgain(lastReminder, 24 * 60)) {
          continue; // Too soon to remind again
        }

        const profile = profileUserId === userId ? user : await getUserProfile(profileUserId);
        if (!profile) continue;

        const childName = profile.childFullName || profile.child_name || "there";

        await sendReminderToProfileRecipients({
          caregiverUserId: isCaregiverRole(user.role) ? userId : null,
          profileUserId,
          reminderData: {
            type: "medication_reminder",
            title: `Reminder for ${childName}!`,
            body: "Don't forget to take your medication.",
          },
          includeProfileDevices: !isCaregiverRole(user.role),
        });

        await updateLastReminderTimestamp(profileUserId, "medication");
      }
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
      const user = userDoc.data();
      const userId = userDoc.id;
      const directChildIds = isCaregiverRole(user.role)
        ? getDirectManagedChildUserIds(user)
        : [];
      const targetProfileIds = [...new Set([userId, ...directChildIds])];

      // Get fluid restriction limit
      // Skip if "do not remind me" was just clicked
      if (user.reminderSettings?.dontRemindUntil) {
        const dontRemindUntil = user.reminderSettings.dontRemindUntil.toMillis?.() || 0;
        if (Date.now() < dontRemindUntil) {
          continue;
        }
      }

      for (const profileUserId of targetProfileIds) {
        const profile = profileUserId === userId ? user : await getUserProfile(profileUserId);
        if (!profile) continue;

        const medicalProfileId = String(profile.medicalProfileId || "").trim();
        if (!medicalProfileId) continue;

        const medicalProfileDoc = await db
          .collection("medicalProfile")
          .doc(medicalProfileId)
          .get();

        if (!medicalProfileDoc.exists) continue;

        const medicalProfile = medicalProfileDoc.data();
        const fluidLimitMl = numberOrZero(
          medicalProfile.fluid_limit_ml ?? medicalProfile.fluidLimitMl,
        );

        if (fluidLimitMl <= 0) continue; // No fluid restriction

        // Check if hydration target was met
        const hydrationMet = await hasHydrationTargetBeenMetToday(
          profileUserId,
          fluidLimitMl,
        );
        if (hydrationMet) {
          continue; // Target met, don't remind
        }

        // Check if enough time passed since last reminder (per profile)
        const lastReminder = await getLastReminderTimestamp(profileUserId, "hydration");
        if (!shouldRemindAgain(lastReminder, 120)) {
          // 2 hour interval for hydration
          continue;
        }

        const childName = profile.childFullName || profile.child_name || "there";

        await sendReminderToProfileRecipients({
          caregiverUserId: isCaregiverRole(user.role) ? userId : null,
          profileUserId,
          reminderData: {
            type: "hydration_reminder",
            title: `Reminder for ${childName}!`,
            body: `Log your fluid intake. Goal: ${fluidLimitMl}mL`,
          },
          includeProfileDevices: !isCaregiverRole(user.role),
        });

        await updateLastReminderTimestamp(profileUserId, "hydration");
      }
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
      const user = userDoc.data();
      const userId = userDoc.id;
      const directChildIds = isCaregiverRole(user.role)
        ? getDirectManagedChildUserIds(user)
        : [];
      const targetProfileIds = [...new Set([userId, ...directChildIds])];

      const nowMs = Date.now();
      const today = todayDateKey();

      for (const profileUserId of targetProfileIds) {
        const profile = profileUserId === userId ? user : await getUserProfile(profileUserId);
        if (!profile) continue;

        // Pull the profile's medications so we can determine which scheduled doses are missed.
        const medicationsSnapshot = await db
          .collection("medications")
          .where("userId", "==", profileUserId)
          .get();

        if (medicationsSnapshot.empty) continue;

        const childName = profile.childFullName || profile.child_name || "there";

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

          // Generate today's dose records and mark overdue pending ones as missed.
          await ensureDoseRecordsForDate({
            userId: profileUserId,
            medicationId,
            medicationDoc: medicationDoc.data() || {},
            dateKey: today,
          });

          const missedUpdates = await markOverdueDosesMissed({
            userId: profileUserId,
            medicationId,
            expectedDate: today,
            nowMs,
          });

          for (const update of missedUpdates) {
            const scheduledTime = String(update.expectedTime || "").trim();
            const dueTimestamp = admin.firestore.Timestamp.fromDate(
              dateForTodayClockTime(parseClockTime(scheduledTime)),
            );

            const missedNotification = {
              userId: profileUserId,
              type: "missed_medication_reminder",
              title: "Missed Medication Reminder",
              body: `You missed your ${name} reminder at ${scheduledTime}. Please take your medication if possible.`,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              isMissed: true,
              priority: "high",
              color: "red",
              read: false,
              medicationId,
              medicationName: name,
              scheduledTime,
              dueTime: dueTimestamp,
              day: today,
              doseRecordId: update.doseRecordId,
            };

            await db.collection("notifications").add(missedNotification);
            await db.collection("upcomingReminders").add(missedNotification);

            await sendReminderToProfileRecipients({
              caregiverUserId: isCaregiverRole(user.role) ? userId : null,
              profileUserId,
              reminderData: {
                type: "missed_medication_reminder",
                title: `Missed medication for ${childName}`,
                body: `You missed your ${name} reminder at ${scheduledTime}. Please take your medication if possible.`,
              },
              includeProfileDevices: !isCaregiverRole(user.role),
            });

            console.log(
              `Marked missed + sent reminder to ${profileUserId} for ${medicationId} at ${scheduledTime}`,
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
    console.log(
      `[Reminders] Scheduler running at ${new Date().toISOString()}`
    );

    // Only backend-generate alerts that are tied to an actual scheduled dose.
    // Meal, hydration, and generic medication reminders are scheduled locally
    // by the Flutter app; sending them here caused extra "unscheduled" pushes.
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
