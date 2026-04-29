const { admin, db } = require("../firebase/admin");

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

function todayDateKey() {
  const now = new Date();
  return `${now.getFullYear().toString().padLeft(4, '0')}-${(now.getMonth() + 1)
    .toString()
    .padLeft(2, '0')}-${now.getDate().toString().padLeft(2, '0')}`;
}

String.prototype.padLeft = function (length, char) {
  return char.repeat(Math.max(0, length - this.length)) + this;
};

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
 * Check if medication has been logged/taken today
 */
async function hasMedicationBeenTakenToday(userId) {
  try {
    const today = todayDateKey();
    const snapshot = await db
      .collection("medications")
      .where("userId", "==", userId)
      .where("status", "==", "Taken")
      .where("date", "==", today)
      .limit(1)
      .get();

    return !snapshot.empty;
  } catch (error) {
    console.error("Error checking medication logs:", error.message);
    return false;
  }
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

    const validTokens = Object.values(deviceTokens)
      .filter((entry) => entry && entry.token)
      .map((entry) => entry.token);

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
        userId: userId,
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
    // Get all users with meal reminders enabled
    const usersSnapshot = await db
      .collection("users")
      .where("reminderSettings.mealReminders.enabled", "==", true)
      .get();

    for (const userDoc of usersSnapshot.docs) {
      const user = userDoc.data();
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

      // Send reminder
      await sendReminderToDevices(userId, {
        type: "meal_reminder",
        title: "Time to Log Your Meal",
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
      const user = userDoc.data();
      const userId = userDoc.id;

      // Skip if "do not remind me" was just clicked
      if (user.reminderSettings?.dontRemindUntil) {
        const dontRemindUntil = user.reminderSettings.dontRemindUntil.toMillis?.() || 0;
        if (Date.now() < dontRemindUntil) {
          continue;
        }
      }

      // Check if medication was taken today
      const medTaken = await hasMedicationBeenTakenToday(userId);
      if (medTaken) {
        continue; // Already taken, don't remind
      }

      // Check if enough time passed since last reminder
      const lastReminder = await getLastReminderTimestamp(userId, "medication");
      if (!shouldRemindAgain(lastReminder, 30)) {
        continue; // Too soon to remind again
      }

      // Send reminder
      await sendReminderToDevices(userId, {
        type: "medication_reminder",
        title: "Time for Your Medication",
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
      const user = userDoc.data();
      const userId = userDoc.id;

      // Get fluid restriction limit
      const medicalProfileDoc = await db
        .collection("medicalProfile")
        .doc(user.medicalProfileId)
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

      // Send reminder
      await sendReminderToDevices(userId, {
        type: "hydration_reminder",
        title: "Stay Hydrated!",
        body: `Log your fluid intake. Goal: ${fluidLimitMl}mL`,
      });

      await updateLastReminderTimestamp(userId, "hydration");
    }
  } catch (error) {
    console.error("Error in hydration reminder check:", error.message);
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

    // Run all reminder checks in parallel
    await Promise.all([
      checkMealReminders(),
      checkMedicationReminders(),
      checkHydrationReminders(),
    ]);

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

  // Run every 5 minutes (300000 ms)
  setInterval(() => {
    runReminderScheduler();
  }, 5 * 60 * 1000);

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
