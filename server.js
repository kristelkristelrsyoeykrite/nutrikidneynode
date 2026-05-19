const express = require("express");
const cors = require("cors");
const crypto = require("crypto");
const dns = require("dns").promises;
const fs = require("fs");
const path = require("path");

function loadLocalEnv() {
  const envPath = path.join(__dirname, ".env");
  if (!fs.existsSync(envPath)) return;

  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const equalsIndex = trimmed.indexOf("=");
    if (equalsIndex <= 0) continue;

    const key = trimmed.slice(0, equalsIndex).trim();
    let value = trimmed.slice(equalsIndex + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

loadLocalEnv();

const { admin, db, auth } = require("./firebase/admin");
const {
  encryptValue,
  encryptHealthProfile,
  decryptHealthProfile,
} = require("./utils/encryption");
const {
  isValidAuthenticatorCode,
  normalizeSecuritySettings,
  toPublicSecuritySettings,
  verifyTotpCode,
} = require("./services/authenticatorMfaService");
const { caregiverLinkCodeDocId } = require("./utils/caregiverLinkCodes");
const { createRateLimiter, identityKey } = require("./utils/rateLimiter");
const { initializeReminderScheduler } = require("./services/reminderScheduler");

const app = express();

app.use(cors());
app.use(express.json({ limit: "8mb" }));

app.get("/", (req, res) => {
  res.send("NutriKidney API running");
});

const PASSWORD_KEYLEN = 64;

const authAttemptLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 10,
  keyPrefix: "auth",
  keyGenerator: (req) => identityKey(req, ["email", "phoneNumber", "uid"]),
});

const verificationAttemptLimiter = createRateLimiter({
  windowMs: 10 * 60 * 1000,
  max: 12,
  keyPrefix: "verification",
  keyGenerator: (req) => identityKey(req, ["email", "phoneNumber", "uid"]),
});

const passwordResetLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 5,
  keyPrefix: "password-reset",
  keyGenerator: (req) => identityKey(req, ["email", "phoneNumber", "uid"]),
});

// Normalize phone number to E.164 format (+63XXXXXXXXXX)
// Firebase requires E.164 format for phone numbers
function normalizePhoneNumber(phone) {
  if (!phone) return null;

  // Remove spaces, hyphens, parentheses
  let normalized = phone.replace(/[\s\-\(\)]/g, "");

  // If already in E.164 format (starts with +), return as is
  if (normalized.startsWith("+")) {
    return normalized;
  }

  // If starts with 63 (Philippines country code without +), add +
  if (normalized.startsWith("63") && normalized.length > 2) {
    return "+" + normalized;
  }

  // If starts with 09 (Philippines mobile prefix), replace with +639
  if (normalized.startsWith("09")) {
    return "+63" + normalized.substring(1);
  }

  // If starts with 9 (Philippines mobile prefix without leading 0), add +63.
  // Example: 9535687265 -> +639535687265
  if (normalized.startsWith("9") && normalized.length === 10) {
    return "+63" + normalized;
  }

  // Default: assume Philippines country code
  if (normalized.length === 10) {
    // Assume it's a mobile number without country code
    return "+63" + normalized;
  }

  // If none of the above, try to add + if it looks like a valid number
  if (/^\d{10,15}$/.test(normalized)) {
    return "+" + normalized;
  }

  return normalized; // Return as-is if unsure
}

function isE164PhoneNumber(phone) {
  return /^\+[1-9]\d{7,14}$/.test(phone);
}

function normalizePhoneNumberOrThrow(phone, fieldName = "phone number") {
  const normalizedPhone = normalizePhoneNumber(phone);
  if (!normalizedPhone || !isE164PhoneNumber(normalizedPhone)) {
    const error = new Error(`Invalid ${fieldName}`);
    error.code = "app/invalid-phone-number";
    throw error;
  }
  return normalizedPhone;
}

function hashPassword(password, salt = crypto.randomBytes(16).toString("hex")) {
  const hash = crypto
    .scryptSync(password, salt, PASSWORD_KEYLEN)
    .toString("hex");
  return { salt, hash };
}

function verifyPassword(password, salt, expectedHash) {
  const computedHash = crypto
    .scryptSync(password, salt, PASSWORD_KEYLEN)
    .toString("hex");
  return crypto.timingSafeEqual(
    Buffer.from(computedHash, "hex"),
    Buffer.from(expectedHash, "hex"),
  );
}

async function isCompletedVerifiedUser(uid) {
  if (!uid) return false;
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) {
    return false;
  }

  const profile = decryptHealthProfile(userDoc.data() || {});
  return isProfileVerified(profile);
}

function isProfileVerified(profile = {}) {
  return (
    profile.status === "verified" ||
    profile.emailVerified === true ||
    profile.phoneVerified === true
  );
}

function isUserVerified({ authUser = null, profile = {} } = {}) {
  return (
    isProfileVerified(profile) ||
    authUser?.emailVerified === true ||
    !!authUser?.phoneNumber
  );
}

function isCaregiverRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  return normalized === "parent_caregiver" || normalized === "caregiver";
}

function normalizeStoredRole(role) {
  const normalized = String(role || "").trim().toLowerCase();
  if (!normalized) return null;
  if (normalized === "parent_caregiver") return "caregiver";
  return normalized;
}

function isLinkOnlyCaregiverProfile(profile = {}) {
  return isCaregiverRole(profile.role) && profile.childAgeGroup === "13-18";
}

function hasManagedChildProfile(profile = {}) {
  if (!isCaregiverRole(profile.role)) return false;
  if (Array.isArray(profile.linkedChildren) && profile.linkedChildren.length > 0) {
    return true;
  }
  return Boolean(
    profile.childProfileCreated === true ||
      profile.activeDirectChildProfileId ||
      profile.linkedChildUserId,
  );
}

function hasAcceptedPrivacyConsent(profile = {}) {
  return (
    profile.privacyConsentAccepted === true ||
    profile.dataPrivacyConsentAccepted === true ||
    profile.consentAccepted === true
  );
}

function isProfileComplete(profile = {}) {
  if (
    isCaregiverRole(profile.role) ||
    isLinkOnlyCaregiverProfile(profile) ||
    hasManagedChildProfile(profile)
  ) {
    return true;
  }

  return Boolean(
    profile.baselineNutritionTargetId && profile.medicalProfileId,
  );
}

function buildNeedsProfileSetup(profile = {}, verified = false) {
  return verified === true && !isProfileComplete(profile);
}

function generateLinkingCode(length = 6) {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let index = 0; index < length; index += 1) {
    const randomIndex = crypto.randomInt(0, alphabet.length);
    code += alphabet[randomIndex];
  }
  return code;
}

function applyUserProfileIdentityFields(
  target,
  {
    uid,
    fullName,
    email,
    phoneNumber,
    userRole,
    role,
    status,
    emailVerified,
    phoneVerified,
  } = {},
  existingProfile = {},
) {
  if (uid) {
    target.uid = uid;
  } else if (existingProfile.uid) {
    target.uid = existingProfile.uid;
  }

  target.fullName = fullName ?? existingProfile.fullName ?? "";
  target.email = email ?? existingProfile.email ?? "";
  target.phoneNumber = phoneNumber ?? existingProfile.phoneNumber ?? "";

  if (status !== undefined) {
    target.status = status;
  } else if (existingProfile.status !== undefined) {
    target.status = existingProfile.status;
  }

  if (emailVerified !== undefined) {
    target.emailVerified = emailVerified === true;
  } else if (existingProfile.emailVerified !== undefined) {
    target.emailVerified = existingProfile.emailVerified === true;
  }

  if (phoneVerified !== undefined) {
    target.phoneVerified = phoneVerified === true;
  } else if (existingProfile.phoneVerified !== undefined) {
    target.phoneVerified = existingProfile.phoneVerified === true;
  }

  const normalizedRole = normalizeStoredRole(userRole ?? role ?? existingProfile.role);
  if (normalizedRole) {
    target.role = normalizedRole;
  }

  if (!existingProfile.createdAt) {
    target.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }
  target.updatedAt = admin.firestore.FieldValue.serverTimestamp();

  return target;
}


function normalizeReminderSettings(profile = {}) {
  const rawSettings =
    profile.reminderSettings && typeof profile.reminderSettings === "object"
      ? profile.reminderSettings
      : {};
  const rawMealSettings =
    rawSettings.mealReminders && typeof rawSettings.mealReminders === "object"
      ? rawSettings.mealReminders
      : {};

  return {
    medicationReminders: rawSettings.medicationReminders === true,
    hydrationAlerts: rawSettings.hydrationAlerts === true,
    mealReminders: {
      breakfast: rawMealSettings.breakfast === true,
      lunch: rawMealSettings.lunch === true,
      snack: rawMealSettings.snack === true,
      dinner: rawMealSettings.dinner === true,
    },
  };
}

function normalizeDeviceToken(token) {
  return String(token || "").trim();
}

function buildDeviceTokenRecord(token, profile = {}, platform) {
  const existing =
    profile.deviceTokens && typeof profile.deviceTokens === "object"
      ? profile.deviceTokens
      : {};

  return {
    ...existing,
    [token]: {
      token,
      platform: String(platform || existing[token]?.platform || "unknown"),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  };
}

async function removeDeviceTokenFromOtherUsers(token, activeUid) {
  const snapshot = await db.collection("users").get();
  const batch = db.batch();
  let updateCount = 0;

  snapshot.forEach((doc) => {
    if (doc.id === activeUid) return;

    const profile = doc.data() || {};
    const deviceTokens =
      profile.deviceTokens && typeof profile.deviceTokens === "object"
        ? profile.deviceTokens
        : {};
    let changed = false;
    const nextDeviceTokens = {};

    Object.entries(deviceTokens).forEach(([key, value]) => {
      if (key === token || value?.token === token) {
        changed = true;
        return;
      }
      nextDeviceTokens[key] = value;
    });

    if (changed) {
      batch.set(
        doc.ref,
        {
          deviceTokens: nextDeviceTokens,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      updateCount += 1;
    }
  });

  if (updateCount > 0) {
    await batch.commit();
  }

  return updateCount;
}

function deviceTokenEntries(profile = {}) {
  const raw = profile.deviceTokens;
  if (!raw || typeof raw !== "object") return [];
  return Object.values(raw).filter(
    (entry) => entry && typeof entry.token === "string" && entry.token.trim(),
  );
}

async function sendPushNotificationToProfile(profile = {}, message = {}) {
  const entries = deviceTokenEntries(profile);
  if (entries.length === 0) {
    return { successCount: 0, failureCount: 0, responses: [] };
  }

  const tokens = entries.map((entry) => entry.token);
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: message.title || "NutriKidney",
      body: message.body || "You have a new notification.",
    },
    data: Object.entries(message.data || {}).reduce((map, [key, value]) => {
      map[key] = String(value ?? "");
      return map;
    }, {}),
    android: {
      priority: "high",
      notification: {
        channelId: "nutrikidney_reminders",
      },
    },
  });

  return {
    successCount: response.successCount,
    failureCount: response.failureCount,
    responses: response.responses,
  };
}

async function resolveReminderSettingsTarget(actingUserId, requestedProfileUserId) {
  if (!actingUserId) {
    const error = new Error("Missing userId");
    error.statusCode = 400;
    throw error;
  }

  const actingUserRef = db.collection("users").doc(actingUserId);
  const actingUserDoc = await actingUserRef.get();
  if (!actingUserDoc.exists) {
    const error = new Error("Acting user profile not found");
    error.statusCode = 404;
    throw error;
  }

  const actingUser = actingUserDoc.data() || {};
  const targetUserId = requestedProfileUserId || actingUserId;
  const isLinkedCaregiverEditingChild =
    targetUserId !== actingUserId &&
    isCaregiverRole(actingUser.role) &&
    actingUser.linkedChildAccount === true &&
    actingUser.linkedChildUserId === targetUserId;

  if (targetUserId !== actingUserId && !isLinkedCaregiverEditingChild) {
    const error = new Error("You are not allowed to manage these reminders");
    error.statusCode = 403;
    throw error;
  }

  const targetRef = db.collection("users").doc(targetUserId);
  const targetDoc = await targetRef.get();
  if (!targetDoc.exists) {
    const error = new Error("User profile not found");
    error.statusCode = 404;
    throw error;
  }

  const targetProfile = targetDoc.data() || {};
  const canManage =
    targetUserId === actingUserId || isLinkedCaregiverEditingChild;

  if (!canManage) {
    const error = new Error(
      "You are not allowed to manage these reminders",
    );
    error.statusCode = 403;
    throw error;
  }

  return {
    actingUser,
    targetUserId,
    targetRef,
    targetProfile,
  };
}

async function getUserVerificationState(uid) {
  let authUser = null;
  try {
    authUser = await auth.getUser(uid);
  } catch (_) {}

  const userDoc = await db.collection("users").doc(uid).get();
  const profile = userDoc.exists
    ? decryptHealthProfile(userDoc.data() || {})
    : {};

  const emailVerified =
    authUser?.emailVerified === true || profile.emailVerified === true;
  const phoneVerified =
    !!authUser?.phoneNumber || profile.phoneVerified === true;

  return {
    authUser,
    profile,
    emailVerified,
    phoneVerified,
    status: isUserVerified({ authUser, profile })
      ? "verified"
      : profile.status || "pending",
  };
}

async function savePasswordSecret(uid, password) {
  if (!uid || !password) return;
  const { salt, hash } = hashPassword(password);
  await db.collection("userSecrets").doc(uid).set(
    {
      passwordSalt: salt,
      passwordHash: hash,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

////////////////////// SIGNUP ROUTE //////////////////////
// This endpoint only validates signup data. Does NOT create user yet.
// User creation happens only AFTER verification (phone OTP or email link).
app.post("/signup", verificationAttemptLimiter, async (req, res) => {
  console.log("SIGNUP received:", {
    email: req.body.email,
    hasPhoneNumber: Boolean(req.body.phoneNumber),
    userRole: req.body.userRole,
  });

  const { email, phoneNumber, password, fullName, userRole } = req.body;

  try {
    // Validate that we have required fields
    if (!fullName || !password) {
      return res.status(400).json({
        success: false,
        error: "Full name and password are required",
      });
    }

    // Must have either email or phoneNumber
    if (!email && !phoneNumber) {
      return res.status(400).json({
        success: false,
        error: "Either email or phone number is required",
      });
    }

    // Check if user already exists by email or phone
    if (phoneNumber) {
      const normalizedPhone = normalizePhoneNumberOrThrow(
        phoneNumber,
        "phone number",
      );
      try {
        await auth.getUserByPhoneNumber(normalizedPhone);
        // User already exists
        return res.status(400).json({
          success: false,
          error: "Phone number already registered",
        });
      } catch (e) {
        // User doesn't exist (expected)
        if (e.code !== "auth/user-not-found") {
          throw e;
        }
      }
    }

    if (email) {
      try {
        const existingEmailUser = await auth.getUserByEmail(email);
        const completedVerified = await isCompletedVerifiedUser(
          existingEmailUser.uid,
        );
        if (existingEmailUser.emailVerified === true && completedVerified) {
          return res.status(400).json({
            success: false,
            error: "Email already registered",
          });
        }

        console.log(
          "SIGNUP: Found stale unverified email account, allowing reuse:",
          existingEmailUser.uid,
        );
      } catch (e) {
        // User doesn't exist (expected)
        if (e.code !== 'auth/user-not-found') {
          throw e;
        }
      }
    }

    // All validations passed - just return success
    // Client will store this data and call verify endpoint after verification
    console.log("SIGNUP: Validation passed. Awaiting client-side verification (OTP or email link)");

    res.status(200).json({
      success: true,
      message: "Signup data validated. Please verify your phone/email.",
    });
  } catch (error) {
    console.error("SIGNUP ERROR:", error.code || error.message);
    if (error.code === "app/invalid-phone-number") {
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }
    res.status(500).json({
      success: false,
      error: error.message || 'Signup validation failed',
    });
  }
});

////////////////////// CHECK USER EXISTS //////////////////////
// Check if email or phone number already exists in the system
app.post("/check-user", verificationAttemptLimiter, async (req, res) => {
  console.log("CHECK_USER received:", {
    email: req.body.email,
    hasPhoneNumber: Boolean(req.body.phoneNumber),
  });

  const { email, phoneNumber } = req.body;

  try {
    if (!email && !phoneNumber) {
      return res.status(400).json({
        success: false,
        error: "Either email or phone number is required",
      });
    }

    // Check if email exists
    if (email) {
      try {
        const existingEmailUser = await auth.getUserByEmail(email);
        const completedVerified = await isCompletedVerifiedUser(
          existingEmailUser.uid,
        );
        if (existingEmailUser.emailVerified === true && completedVerified) {
          console.log("CHECK_USER: Verified email found - already exists");
          return res.status(200).json({
            success: true,
            exists: true,
            message: "Email already exists",
          });
        }

        console.log(
          "CHECK_USER: Unverified email found - treating as available",
          existingEmailUser.uid,
        );
        return res.status(200).json({
          success: true,
          exists: false,
          message: "Email is available until verification is completed",
        });
      } catch (e) {
        // User doesn't exist (expected)
        if (e.code !== 'auth/user-not-found') {
          throw e;
        }
      }
    }

    // Check if phone number exists
    if (phoneNumber) {
      const normalizedPhone = normalizePhoneNumberOrThrow(
        phoneNumber,
        "phone number",
      );
      console.log(
        `CHECK_USER: Normalizing phone: '${phoneNumber}' -> '${normalizedPhone}'`,
      );

      try {
        const existingPhoneUser = await auth.getUserByPhoneNumber(normalizedPhone);
        const userDoc = await db.collection("users").doc(existingPhoneUser.uid).get();
        const profile = userDoc.exists
          ? decryptHealthProfile(userDoc.data() || {})
          : {};
        if (isUserVerified({ authUser: existingPhoneUser, profile })) {
          console.log("CHECK_USER: Verified phone found - already exists");
          return res.status(200).json({
            success: true,
            exists: true,
            message: "Phone number already exists",
          });
        }

        console.log(
          "CHECK_USER: Unverified phone found - treating as available",
          existingPhoneUser.uid,
        );
        return res.status(200).json({
          success: true,
          exists: false,
          message: "Phone number is available until verification is completed",
        });
      } catch (e) {
        // User doesn't exist (expected)
        if (e.code !== 'auth/user-not-found') {
          throw e;
        }
      }
    }

    // Neither email nor phone number exists
    console.log("CHECK_USER: Email/phone available");
    res.status(200).json({
      success: true,
      exists: false,
      message: "Email/phone number is available",
    });
  } catch (error) {
    console.error("CHECK_USER ERROR:", error.code || error.message);
    if (error.code === "app/invalid-phone-number") {
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }
    res.status(500).json({
      success: false,
      error: error.message || 'Error checking user existence',
    });
  }
});

////////////////////// VERIFY PHONE PASSWORD //////////////////////
app.post("/verify-phone-password", authAttemptLimiter, async (req, res) => {
  console.log("VERIFY_PHONE_PASSWORD received:", {
    hasPhoneNumber: Boolean(req.body.phoneNumber),
    hasPassword: Boolean(req.body.password),
  });

  const { phoneNumber, password } = req.body;

  try {
    if (!phoneNumber || !password) {
      return res.status(400).json({
        success: false,
        error: "Phone number and password are required",
      });
    }

    const normalizedPhone = normalizePhoneNumberOrThrow(
      phoneNumber,
      "phone number",
    );

    let user;
    try {
      user = await auth.getUserByPhoneNumber(normalizedPhone);
    } catch (e) {
      if (e.code === "auth/user-not-found") {
        return res.status(200).json({
          success: true,
          valid: false,
          reason: "user-not-found",
        });
      }
      throw e;
    }

    const secretSnap = await db.collection("userSecrets").doc(user.uid).get();
    if (!secretSnap.exists) {
      return res.status(200).json({
        success: true,
        valid: false,
        reason: "password-not-set",
      });
    }

    const secret = secretSnap.data() || {};
    if (!secret.passwordSalt || !secret.passwordHash) {
      return res.status(200).json({
        success: true,
        valid: false,
        reason: "password-not-set",
      });
    }

    const userDoc = await db.collection("users").doc(user.uid).get();
    const profile = userDoc.exists
      ? decryptHealthProfile(userDoc.data() || {})
      : {};
    if (!isUserVerified({ authUser: user, profile })) {
      return res.status(200).json({
        success: true,
        valid: false,
        reason: "profile-not-found",
      });
    }

    const valid = verifyPassword(password, secret.passwordSalt, secret.passwordHash);
    return res.status(200).json({
      success: true,
      valid,
      reason: valid ? "ok" : "wrong-password",
      userId: valid ? user.uid : undefined,
    });
  } catch (error) {
    console.error("VERIFY_PHONE_PASSWORD ERROR:", error.code || error.message);
    if (error.code === "app/invalid-phone-number") {
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to verify phone password",
    });
  }
});

app.post("/api/user/profile-status", async (req, res) => {
  console.log("PROFILE_STATUS received:", {
    uid: req.body.uid,
    hasEmail: Boolean(req.body.email),
    hasPhoneNumber: Boolean(req.body.phoneNumber),
  });

  const { uid, email, phoneNumber } = req.body;

  try {
    let resolvedUid = uid;

    if (!resolvedUid && email) {
      try {
        const user = await auth.getUserByEmail(email);
        resolvedUid = user.uid;
      } catch (e) {
        if (e.code !== "auth/user-not-found") {
          throw e;
        }
      }
    }

    if (!resolvedUid && phoneNumber) {
      const normalizedPhone = normalizePhoneNumberOrThrow(
        phoneNumber,
        "phone number",
      );
      try {
        const user = await auth.getUserByPhoneNumber(normalizedPhone);
        resolvedUid = user.uid;
      } catch (e) {
        if (e.code !== "auth/user-not-found") {
          throw e;
        }
      }
    }

    if (!resolvedUid) {
      return res.status(200).json({
        success: true,
        exists: false,
        verified: false,
      });
    }

    const userDoc = await db.collection("users").doc(resolvedUid).get();
    const profile = userDoc.exists
      ? decryptHealthProfile(userDoc.data() || {})
      : {};
    let verified = isProfileVerified(profile);

    // Avoid the slower Auth lookup unless Firestore cannot already answer
    // whether this app account is verified.
    if (!verified) {
      const authUser = await auth.getUser(resolvedUid).catch(() => null);
      verified = isUserVerified({ authUser, profile });
    }
    const profileComplete = isProfileComplete(profile);

    return res.status(200).json({
      success: true,
      exists: userDoc.exists,
      verified,
      profileComplete,
      needsProfileSetup: buildNeedsProfileSetup(profile, verified),
      uid: resolvedUid,
      profile,
    });
  } catch (error) {
    console.error("PROFILE_STATUS ERROR:", error.code || error.message);
    if (error.code === "app/invalid-phone-number") {
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to get profile status",
    });
  }
});

////////////////////// RESET PASSWORD //////////////////////
app.post("/reset-password", passwordResetLimiter, async (req, res) => {
  console.log("RESET_PASSWORD received:", {
    ...req.body,
    newPassword: req.body.newPassword ? "[REDACTED]" : undefined,
    idToken: req.body.idToken ? "[REDACTED]" : undefined,
  });

  const { email, phoneNumber, newPassword, idToken } = req.body;

  try {
    if ((!email && !phoneNumber) || !newPassword) {
      return res.status(400).json({
        success: false,
        error: "A contact value and new password are required",
      });
    }

    let user;
    if (email) {
      user = await auth.getUserByEmail(email);
    } else {
      const normalizedPhone = normalizePhoneNumberOrThrow(
        phoneNumber,
        "phone number",
      );
      user = await auth.getUserByPhoneNumber(normalizedPhone);
    }

    if (phoneNumber) {
      if (!idToken) {
        return res.status(401).json({
          success: false,
          error: "Phone password reset requires a verified session",
        });
      }

      const decodedToken = await auth.verifyIdToken(idToken);
      if (decodedToken.uid !== user.uid) {
        return res.status(403).json({
          success: false,
          error: "Verified account does not match the requested phone number",
        });
      }
    }

    await auth.updateUser(user.uid, { password: newPassword });
    await savePasswordSecret(user.uid, newPassword);

    return res.status(200).json({
      success: true,
      message: "Password updated successfully",
      userId: user.uid,
    });
  } catch (error) {
    console.error("RESET_PASSWORD ERROR:", error.code || error.message);

    if (error.code === "auth/user-not-found") {
      return res.status(404).json({
        success: false,
        error: "Account not found",
      });
    }
    if (error.code === "app/invalid-phone-number") {
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }

    return res.status(500).json({
      success: false,
      error: error.message || "Failed to reset password",
    });
  }
});

////////////////////// VERIFY EMAIL DOMAIN //////////////////////
// Check if email domain has mail servers (MX records)
app.post("/verify-email-domain", verificationAttemptLimiter, async (req, res) => {
  console.log("VERIFY_EMAIL_DOMAIN received:", {
    hasEmail: Boolean(req.body.email),
  });

  const { email } = req.body;

  try {
    if (!email || !email.includes("@")) {
      return res.status(400).json({
        success: false,
        error: "Valid email is required",
      });
    }

    // Extract domain from email
    const domain = email.split("@")[1];
    
    // Check if domain has MX records (mail servers)
    try {
      const mxRecords = await dns.resolveMx(domain);
      
      if (!mxRecords || mxRecords.length === 0) {
        console.log("VERIFY_EMAIL_DOMAIN: Domain has no MX records");
        return res.status(200).json({
          success: true,
          valid: false,
          message: "Email domain does not have mail servers configured. Please use a valid email domain.",
        });
      }

      console.log(`VERIFY_EMAIL_DOMAIN: Domain ${domain} has ${mxRecords.length} MX records`);
      res.status(200).json({
        success: true,
        valid: true,
        message: "Email domain is valid and can receive messages",
      });
    } catch (dnsError) {
      console.log(`VERIFY_EMAIL_DOMAIN: DNS lookup failed for ${domain}:`, dnsError.code);
      
      // ENOTFOUND means domain doesn't exist
      if (dnsError.code === 'ENOTFOUND' || dnsError.code === 'ENODATA') {
        return res.status(200).json({
          success: true,
          valid: false,
          message: "Email domain does not exist. Please check the email address.",
        });
      }
      
      // ECONNREFUSED = DNS server unreachable (system config issue, not fake domain)
      // Allow it to proceed since real domains like gmail.com may fail due to system DNS issues
      if (dnsError.code === 'ECONNREFUSED') {
        console.log(`VERIFY_EMAIL_DOMAIN: DNS server unreachable, but allowing ${domain} to proceed`);
        return res.status(200).json({
          success: true,
          valid: true,
          message: "Email domain accepted (DNS server unreachable, but domain looks valid)",
        });
      }
      
      // For other DNS errors, reject as invalid
      console.log(`VERIFY_EMAIL_DOMAIN: DNS error - treating as invalid:`, dnsError.code);
      return res.status(200).json({
        success: true,
        valid: false,
        message: "Unable to verify email domain. Please check the email address and try again.",
      });
    }
  } catch (error) {
    console.error("VERIFY_EMAIL_DOMAIN ERROR:", error.message);
    res.status(500).json({
      success: false,
      error: error.message || 'Error verifying email domain',
    });
  }
});

////////////////////// SEND EMAIL VERIFICATION TOKEN //////////////////////
// This endpoint is now kept for compatibility but email sending is done on client
app.post("/send-email-verification", verificationAttemptLimiter, async (req, res) => {
  console.log("SEND_EMAIL_VERIFICATION received (client handles email now):", {
    hasEmail: Boolean(req.body.email),
  });

  const { email } = req.body;

  try {
    if (!email) {
      return res.status(400).json({
        success: false,
        error: "Email is required",
      });
    }

    // Just acknowledge - client is handling the Firebase email sending
    res.status(200).json({
      success: true,
      message: "Ready for client-side email verification via Firebase",
    });
  } catch (error) {
    console.error("SEND_EMAIL_VERIFICATION ERROR:", error.message);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to process verification',
    });
  }
});

////////////////////// VERIFY EMAIL TOKEN //////////////////////
// Called by frontend after user verifies email in Firebase
// Just needs to confirm verification happened client-side
app.post("/verify-email-token", verificationAttemptLimiter, async (req, res) => {
  console.log("VERIFY_EMAIL_TOKEN received:", {
    hasEmail: Boolean(req.body.email),
  });

  const { email } = req.body;

  try {
    if (!email) {
      return res.status(400).json({
        success: false,
        error: "Email is required",
      });
    }

    // Client indicated email is verified - just acknowledge
    console.log("VERIFY_EMAIL_TOKEN: Email verification confirmed for:", email);

    res.status(200).json({
      success: true,
      message: "Email verification confirmed",
    });
  } catch (error) {
    console.error("VERIFY_EMAIL_TOKEN ERROR:", error.message);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to verify email token',
    });
  }
});

////////////////////// VERIFY EMAIL AND CREATE USER //////////////////////
app.post("/verify-email-and-create-user", verificationAttemptLimiter, async (req, res) => {
  console.log("VERIFY_EMAIL_AND_CREATE_USER received:", {
    email: req.body.email,
    hasPhoneNumber: Boolean(req.body.phoneNumber),
    userRole: req.body.userRole,
  });

  const { email, phoneNumber, password, fullName, userRole } = req.body;

  try {
    if (!email || !fullName) {
      return res.status(400).json({
        success: false,
        error: "Email and full name are required",
      });
    }

    // Double check: remove pending verification record before creating user
    await db.collection("pendingVerifications").doc(email).delete().catch(() => {});

    // Check if user already exists in Firebase Auth (created client-side for email verification)
    let user;
    try {
      user = await auth.getUserByEmail(email);
      console.log("VERIFY_EMAIL_AND_CREATE_USER: User already exists in Firebase Auth, using existing UID:", user.uid);
    } catch (e) {
      // User doesn't exist in Firebase Auth - create them (happens in phone-based flow)
      if (e.code === 'auth/user-not-found') {
        const createPayload = {
          email,
          password,
          displayName: fullName,
          emailVerified: true,
        };
        if (phoneNumber) {
          createPayload.phoneNumber = normalizePhoneNumberOrThrow(
            phoneNumber,
            "phone number",
          );
        }

        user = await auth.createUser(createPayload);
        console.log("VERIFY_EMAIL_AND_CREATE_USER: Created new user with UID:", user.uid);
      } else {
        throw e;
      }
    }

    // Create profile in Firestore
    const existingProfileDoc = await db.collection("users").doc(user.uid).get();
    const existingProfile =
      existingProfileDoc.exists
        ? decryptHealthProfile(existingProfileDoc.data() || {})
        : {};
    const profile = applyUserProfileIdentityFields(
      {},
      {
        uid: user.uid,
        fullName,
        email,
        phoneNumber: phoneNumber
          ? normalizePhoneNumberOrThrow(phoneNumber, "phone number")
          : "",
        userRole,
        status: "verified",
        emailVerified: true,
        phoneVerified: existingProfile.phoneVerified ?? false,
      },
      existingProfile,
    );

    await db
      .collection("users")
      .doc(user.uid)
      .set(encryptHealthProfile(profile), { merge: true });
    await savePasswordSecret(user.uid, password);

    console.log("VERIFY_EMAIL_AND_CREATE_USER: Profile created/updated for UID:", user.uid);

    res.status(200).json({
      success: true,
      message: "User verified and profile created successfully",
      userId: user.uid,
    });
  } catch (error) {
    console.error("VERIFY_EMAIL_AND_CREATE_USER ERROR:", error.code || error.message);
    if (error.code === "app/invalid-phone-number") {
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }

    res.status(500).json({
      success: false,
      error: error.message || 'Failed to create user after email verification',
    });
  }
});
// Called after phone OTP is verified by client
app.post("/verify-phone-and-create-user", verificationAttemptLimiter, async (req, res) => {
  console.log("VERIFY_PHONE_AND_CREATE_USER received:", {
    email: req.body.email,
    hasPhoneNumber: Boolean(req.body.phoneNumber),
    uid: req.body.uid,
    userRole: req.body.userRole,
  });
  console.log("VERIFY_PHONE_AND_CREATE_USER UID:", req.body.uid);
  
  const { email, phoneNumber, password, fullName, uid, userRole } = req.body;

  try {
    if (!phoneNumber || !password || !fullName) {
      return res.status(400).json({
        success: false,
        error: "Phone number, password, and full name are required",
      });
    }

    const normalizedPhone = normalizePhoneNumberOrThrow(
      phoneNumber,
      "phone number",
    );

    let user;
    
    // If UID is provided, the user was already created in Firebase Auth during OTP verification
    if (uid && uid.trim() !== "") {
      console.log("VERIFY_PHONE_AND_CREATE_USER: Using existing UID from OTP verification:", uid);
      try {
        user = await auth.getUser(uid);
        console.log("VERIFY_PHONE_AND_CREATE_USER: Found user with UID:", user.uid);
      } catch (e) {
        console.log("VERIFY_PHONE_AND_CREATE_USER: Error getting user with UID:", e.code);
        return res.status(400).json({
          success: false,
          error: "User UID not found in Firebase Auth",
        });
      }
    } else {
      console.log("VERIFY_PHONE_AND_CREATE_USER: No UID provided, creating new user");
      // Check if phone number already exists BEFORE creating
      try {
        const existingUser = await auth.getUserByPhoneNumber(normalizedPhone);
        return res.status(400).json({
          success: false,
          error: "This phone number is already registered. Please log in instead.",
          userExists: true,
        });
      } catch (e) {
        // User doesn't exist (expected) - continue
        if (e.code !== 'auth/user-not-found') {
          throw e;
        }
      }

      // Create user in Firebase Auth
      const createPayload = {
        phoneNumber: normalizedPhone,
        password,
        displayName: fullName,
      };
      if (email) createPayload.email = email;

      user = await auth.createUser(createPayload);
      console.log("VERIFY_PHONE_AND_CREATE_USER: Created new user with UID:", user.uid);
    }

    // Create profile in Firestore
    const existingProfileDoc = await db.collection("users").doc(user.uid).get();
    const existingProfile =
      existingProfileDoc.exists
        ? decryptHealthProfile(existingProfileDoc.data() || {})
        : {};
    const profile = applyUserProfileIdentityFields(
      {},
      {
        uid: user.uid,
        fullName,
        email: email || "",
        phoneNumber: normalizedPhone,
        userRole,
        status: "verified",
        emailVerified: existingProfile.emailVerified ?? false,
        phoneVerified: true,
      },
      existingProfile,
    );

    await db.collection("users").doc(user.uid).set(profile, { merge: true });
    await savePasswordSecret(user.uid, password);

    console.log("VERIFY_PHONE_AND_CREATE_USER: Profile created/updated for UID:", user.uid);

    res.status(200).json({
      success: true,
      message: "User verified and profile created successfully",
      userId: user.uid,
    });
  } catch (error) {
    console.error("VERIFY_PHONE_AND_CREATE_USER ERROR:", error.code || error.message);

    // Check if it's a duplicate user error
    if (error.code === 'auth/phone-number-already-exists' || error.code === 'auth/email-already-exists') {
      return res.status(400).json({
        success: false,
        error: "This phone number or email is already registered",
      });
    }
    if (error.code === "app/invalid-phone-number") {
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }

    res.status(500).json({
      success: false,
      error: error.message || 'Failed to create user after phone verification',
    });
  }
});

////////////////////// CREATE USER (Firebase Auth) //////////////////////
// Create a new user in Firebase Auth (called during signup after user provides credentials)
app.post("/api/user/create", verificationAttemptLimiter, async (req, res) => {
  console.log("CREATE_USER received:", {
    email: req.body.email,
    hasPhoneNumber: Boolean(req.body.phoneNumber),
    hasPassword: Boolean(req.body.password),
    userRole: req.body.userRole,
    privacyConsentAccepted: req.body.privacyConsentAccepted === true,
  });

  const {
    email,
    phoneNumber,
    password,
    fullName,
    userRole,
    privacyConsentAccepted,
  } = req.body;

  try {
    if (!fullName || !password) {
      return res.status(400).json({
        success: false,
        error: "Full name and password are required",
      });
    }

    if (!email && !phoneNumber) {
      return res.status(400).json({
        success: false,
        error: "Either email or phone number is required",
      });
    }

    if (email) {
      try {
        const existingEmailUser = await auth.getUserByEmail(email);
        const completedVerified = await isCompletedVerifiedUser(
          existingEmailUser.uid,
        );
        if (existingEmailUser.emailVerified === true && completedVerified) {
          return res.status(400).json({
            success: false,
            error: "Email already registered",
          });
        }

        console.log(
          "CREATE_USER: Removing stale unverified email account:",
          existingEmailUser.uid,
        );
        await auth.deleteUser(existingEmailUser.uid);
        await db.collection("users").doc(existingEmailUser.uid).delete().catch(() => {});
        await db.collection("userSecrets").doc(existingEmailUser.uid).delete().catch(() => {});
      } catch (e) {
        if (e.code !== 'auth/user-not-found') {
          throw e;
        }
      }
    }

    if (phoneNumber) {
      const normalizedPhone = normalizePhoneNumberOrThrow(
        phoneNumber,
        "phone number",
      );
      try {
        const existingPhoneUser = await auth.getUserByPhoneNumber(normalizedPhone);
        const completedVerified = await isCompletedVerifiedUser(
          existingPhoneUser.uid,
        );
        if (!completedVerified) {
          console.log(
            "CREATE_USER: Removing stale unverified phone account:",
            existingPhoneUser.uid,
          );
          await auth.deleteUser(existingPhoneUser.uid);
          await db.collection("users").doc(existingPhoneUser.uid).delete().catch(() => {});
          await db.collection("userSecrets").doc(existingPhoneUser.uid).delete().catch(() => {});
        } else {
        console.log(
          "CREATE_USER: Existing phone account detected:",
          existingPhoneUser.uid,
        );
        return res.status(400).json({
          success: false,
          error: "Phone number already registered",
        });
        }
      } catch (e) {
        if (e.code !== 'auth/user-not-found') {
          throw e;
        }
      }
    }

    // Create user in Firebase Auth
    const createPayload = {
      password,
      displayName: fullName,
    };
    if (email) createPayload.email = email;
    if (phoneNumber) {
      createPayload.phoneNumber = normalizePhoneNumberOrThrow(
        phoneNumber,
        "phone number",
      );
    }

    const user = await auth.createUser(createPayload);
    console.log("CREATE_USER: Successfully created user:", user.uid);

    const existingProfileDoc = await db.collection("users").doc(user.uid).get();
    const existingProfile =
      existingProfileDoc.exists
        ? decryptHealthProfile(existingProfileDoc.data() || {})
        : {};
    const profileData = applyUserProfileIdentityFields(
      {},
      {
        uid: user.uid,
        fullName,
        email: email || "",
        phoneNumber: phoneNumber
          ? normalizePhoneNumberOrThrow(phoneNumber, "phone number")
          : "",
        userRole,
        status: "pendingVerification",
        emailVerified: false,
        phoneVerified: false,
      },
      existingProfile,
    );
    if (privacyConsentAccepted === true) {
      profileData.privacyConsentAccepted = true;
      profileData.privacyConsentAcceptedAt =
        admin.firestore.FieldValue.serverTimestamp();
    }

    await db
      .collection("users")
      .doc(user.uid)
      .set(encryptHealthProfile(profileData), { merge: true });
    console.log("CREATE_USER: Seeded Firestore profile for UID:", user.uid);

    res.status(200).json({
      success: true,
      message: "User created successfully",
      uid: user.uid,
      email: user.email,
      phoneNumber: user.phoneNumber,
    });
  } catch (error) {
    console.error("CREATE_USER ERROR:", error.code || error.message);

    if (error.code === 'auth/email-already-exists') {
      return res.status(400).json({
        success: false,
        error: "Email already registered",
      });
    }
    if (error.code === 'auth/phone-number-already-exists') {
      return res.status(400).json({
        success: false,
        error: "Phone number already registered",
      });
    }
    if (error.code === 'auth/weak-password') {
      return res.status(400).json({
        success: false,
        error: "Password is too weak. Must be at least 8 characters.",
      });
    }
    if (error.code === "app/invalid-phone-number") {
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }

    res.status(500).json({
      success: false,
      error: error.message || "Failed to create user",
    });
  }
});

////////////////////// SEND EMAIL VERIFICATION //////////////////////
// Email verification links are sent by the Flutter Firebase SDK.
// Keep this endpoint as a compatibility no-op for older clients so the backend
// does not try to generate links and fail with auth/internal-error.
app.post("/api/user/send-email-verification", verificationAttemptLimiter, async (req, res) => {
  console.log("SEND_EMAIL_VERIFICATION received:", {
    hasUid: Boolean(req.body.uid),
  });

  const { uid } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) is required",
      });
    }

    const user = await auth.getUser(uid);
    if (!user.email) {
      return res.status(400).json({
        success: false,
        error: "User does not have an email address",
      });
    }

    console.log("SEND_EMAIL_VERIFICATION: Client should send Firebase link for:", user.email);
    res.status(200).json({
      success: true,
      message: "Use Firebase client SDK sendEmailVerification() to send the verification link",
      uid: uid,
      email: user.email,
      clientHandlesEmail: true,
    });
  } catch (error) {
    console.error("SEND_EMAIL_VERIFICATION ERROR:", error.code || error.message);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to send email verification",
    });
  }
});

////////////////////// VERIFY PHONE OTP REQUEST //////////////////////
// Request OTP to be sent to phone number
app.post("/api/user/send-phone-otp", verificationAttemptLimiter, async (req, res) => {
  console.log("SEND_PHONE_OTP received:", {
    hasUid: Boolean(req.body.uid),
    hasPhoneNumber: Boolean(req.body.phoneNumber),
  });

  const { uid, phoneNumber } = req.body;

  try {
    if (!uid || !phoneNumber) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) and phone number are required",
      });
    }

    const user = await auth.getUser(uid);

    const normalizedPhone = normalizePhoneNumberOrThrow(
      phoneNumber,
      "phone number",
    );

    // Update user phone number if provided
    if (phoneNumber && user.phoneNumber !== normalizedPhone) {
      await auth.updateUser(uid, { phoneNumber: normalizedPhone });
      console.log("SEND_PHONE_OTP: Updated phone number for UID:", uid);
    }

    // Note: Firebase does not expose a direct OTP sending method via Admin SDK
    // The Flutter app will use Firebase's verifyPhoneNumber method client-side
    // This endpoint mainly logs the request and validates the user exists
    
    res.status(200).json({
      success: true,
      message: "Phone OTP will be sent via Firebase client SDK",
      uid: uid,
      phoneNumber: normalizedPhone,
    });
  } catch (error) {
    console.error("SEND_PHONE_OTP ERROR:", error.code || error.message);
    if (error.code === "app/invalid-phone-number") {
      return res.status(400).json({
        success: false,
        error: error.message,
      });
    }
    res.status(500).json({
      success: false,
      error: error.message || "Failed to send phone OTP",
    });
  }
});

////////////////////// COMPLETE EMAIL VERIFICATION //////////////////////
// Mark email as verified after user clicks verification link
app.post("/api/user/complete-email-verification", verificationAttemptLimiter, async (req, res) => {
  console.log("COMPLETE_EMAIL_VERIFICATION received:", {
    hasUid: Boolean(req.body.uid),
  });

  const { uid } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) is required",
      });
    }

    const user = await auth.getUser(uid);
    if (!user.email) {
      return res.status(400).json({
        success: false,
        error: "User does not have an email address",
      });
    }

    if (user.emailVerified !== true) {
      return res.status(409).json({
        success: false,
        error: "Email is not verified yet. Please click the verification link in your email first.",
        uid,
        email: user.email,
        emailVerified: false,
      });
    }

    await db.collection("users").doc(uid).set(
      {
        email: user.email,
        emailVerified: true,
        status: "verified",
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    console.log("COMPLETE_EMAIL_VERIFICATION: Confirmed verified email for UID:", uid);

    res.status(200).json({
      success: true,
      message: "Email verified successfully",
      uid: uid,
      email: user.email,
      emailVerified: true,
    });
  } catch (error) {
    console.error("COMPLETE_EMAIL_VERIFICATION ERROR:", error.code || error.message);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to complete email verification",
    });
  }
});

////////////////////// COMPLETE PHONE VERIFICATION //////////////////////
// Mark phone as verified after OTP confirmation
app.post("/api/user/complete-phone-verification", verificationAttemptLimiter, async (req, res) => {
  console.log("COMPLETE_PHONE_VERIFICATION received:", {
    hasUid: Boolean(req.body.uid),
  });

  const { uid } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) is required",
      });
    }

    // In Firebase, phone verification is done via OTP on client
    // This endpoint just logs the completion and marks status in Firestore
    const user = await auth.getUser(uid);
    
    // Create/update user profile with verification status
    await db.collection("users").doc(uid).set(
      {
        status: "verified",
        phoneVerified: true,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    console.log("COMPLETE_PHONE_VERIFICATION: Marked as verified for UID:", uid);

    res.status(200).json({
      success: true,
      message: "Phone verified successfully",
      uid: uid,
      phoneVerified: true,
    });
  } catch (error) {
    console.error("COMPLETE_PHONE_VERIFICATION ERROR:", error.code || error.message);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to complete phone verification",
    });
  }
});

////////////////////// SAVE USER PROFILE (after verification) //////////////////////
// Save/update user profile in Firestore with verified status
app.post("/api/user/profile/save", async (req, res) => {
  console.log("SAVE_USER_PROFILE received:", {
    hasUid: Boolean(req.body.uid),
    keys: Object.keys(req.body || {}).length,
  });

  const { uid, fullName, email, phoneNumber, status, userRole } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) is required",
      });
    }

    const verificationState = await getUserVerificationState(uid);

    const existingDoc = await db.collection("users").doc(uid).get();
    const existingProfile = existingDoc.exists
      ? decryptHealthProfile(existingDoc.data() || {})
      : {};
    const profileData = applyUserProfileIdentityFields(
      {},
      {
        uid,
        fullName: fullName || "",
        email: email || "",
        phoneNumber: phoneNumber || "",
        status: status || verificationState.status,
        emailVerified: verificationState.emailVerified,
        phoneVerified: verificationState.phoneVerified,
        userRole,
      },
      existingProfile,
    );

    await db
      .collection("users")
      .doc(uid)
      .set(encryptHealthProfile(profileData), { merge: true });
    
    // Also save password secret if needed
    if (req.body.password) {
      const { salt, hash } = hashPassword(req.body.password);
      await db.collection("userSecrets").doc(uid).set(
        {
          passwordSalt: salt,
          passwordHash: hash,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    console.log("SAVE_USER_PROFILE: Saved profile for UID:", uid);

    res.status(200).json({
      success: true,
      message: "User profile saved successfully",
      uid: uid,
      profile: profileData,
    });
  } catch (error) {
    console.error("SAVE_USER_PROFILE ERROR:", error.code || error.message);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to save user profile",
    });
  }
});

app.post("/api/user/caregiver-child-age", async (req, res) => {
  const { uid, userId, childAgeGroup } = req.body;
  const resolvedUid = uid || userId;

  try {
    if (!resolvedUid) {
      return res.status(400).json({
        success: false,
        error: "User ID is required",
      });
    }

    if (
      childAgeGroup !== "5-12" &&
      childAgeGroup !== "5-13" &&
      childAgeGroup !== "13-18" &&
      childAgeGroup !== "13-18-direct"
    ) {
      return res.status(400).json({
        success: false,
        error: "Child age group must be either 5-12 or 13-18",
      });
    }

    const userRef = db.collection("users").doc(resolvedUid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const profile = decryptHealthProfile(userDoc.data() || {});
    if (!isCaregiverRole(profile.role)) {
      return res.status(400).json({
        success: false,
        error: "Only caregiver accounts can set a child age group",
      });
    }

    const payload = {
      pendingChildAgeGroup: childAgeGroup,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const linkedChildren = Array.isArray(profile.linkedChildren)
      ? profile.linkedChildren
      : [];
    if (linkedChildren.length >= 3) {
      return res.status(400).json({
        success: false,
        error: "This caregiver account can manage up to 3 child profiles",
      });
    }

    await userRef.set(payload, { merge: true });

    return res.status(200).json({
      success: true,
      message: "Caregiver child profile setup staged",
      childAgeGroup,
      profileComplete: isProfileComplete({ ...profile, ...payload }),
      needsProfileSetup: buildNeedsProfileSetup(
        { ...profile, ...payload },
        isProfileVerified(profile),
      ),
    });
  } catch (error) {
    console.error("CAREGIVER_CHILD_AGE ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to save caregiver child age group",
    });
  }
});

app.post("/api/user/generate-caregiver-link-code", verificationAttemptLimiter, async (req, res) => {
  const { uid, userId } = req.body;
  const resolvedUid = uid || userId;

  try {
    if (!resolvedUid) {
      return res.status(400).json({
        success: false,
        error: "User ID is required",
      });
    }

    const caregiverRef = db.collection("users").doc(resolvedUid);
    const caregiverDoc = await caregiverRef.get();
    if (!caregiverDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "Caregiver profile not found",
      });
    }

    const caregiver = caregiverDoc.data() || {};
    if (!isCaregiverRole(caregiver.role)) {
      return res.status(400).json({
        success: false,
        error: "Only caregiver accounts can generate linking codes",
      });
    }

    const linkedChildren = Array.isArray(caregiver.linkedChildren)
      ? caregiver.linkedChildren
      : caregiver.linkedChildUserId
        ? [{ userId: caregiver.linkedChildUserId }]
        : [];
    if (linkedChildren.length >= 3) {
      return res.status(400).json({
        success: false,
        error: "This caregiver account can manage up to 3 child accounts",
      });
    }

    let code = generateLinkingCode();
    let codeDocId = caregiverLinkCodeDocId(code);
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const existingCodeDoc = await db.collection("caregiverLinkCodes").doc(codeDocId).get();
      if (!existingCodeDoc.exists) {
        break;
      }
      code = generateLinkingCode();
      codeDocId = caregiverLinkCodeDocId(code);
    }
    const linkedAccountChild =
      linkedChildren.find((child) => child?.type !== "direct") || null;
    const existingLinkedChildUserId =
      linkedAccountChild?.userId ||
      linkedAccountChild?.uid ||
      linkedAccountChild?.id ||
      caregiver.linkedChildUserId ||
      null;

    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
    const expiresAtTimestamp = admin.firestore.Timestamp.fromDate(expiresAt);

    await db.collection("caregiverLinkCodes").doc(codeDocId).set({
      codeHash: codeDocId,
      caregiverUserId: resolvedUid,
      status: "active",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: expiresAtTimestamp,
    });

    await caregiverRef.set(
      {
        linkedChildAccount: Boolean(existingLinkedChildUserId),
        linkedChildUserId: existingLinkedChildUserId,
        linkStatus: "pending",
        activeLinkingCode: admin.firestore.FieldValue.delete(),
        activeLinkingCodeHash: codeDocId,
        linkCodeExpiresAt: expiresAtTimestamp,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      code,
      expiresAt: expiresAt.toISOString(),
    });
  } catch (error) {
    console.error("GENERATE_CAREGIVER_LINK_CODE ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to generate caregiver linking code",
    });
  }
});

app.post("/api/user/link-caregiver-account", verificationAttemptLimiter, async (req, res) => {
  const { uid, userId, linkingCode } = req.body;
  const adolescentUserId = uid || userId;
  const normalizedCode = String(linkingCode || "").trim().toUpperCase();

  try {
    if (!adolescentUserId) {
      return res.status(400).json({
        success: false,
        error: "User ID is required",
      });
    }

    if (!normalizedCode) {
      return res.status(400).json({
        success: false,
        error: "A linking code is required",
      });
    }

    const adolescentRef = db.collection("users").doc(adolescentUserId);
    const adolescentDoc = await adolescentRef.get();
    if (!adolescentDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "Adolescent profile not found",
      });
    }

    const adolescent = adolescentDoc.data() || {};
    if (String(adolescent.role || "").trim().toLowerCase() !== "adolescent") {
      return res.status(400).json({
        success: false,
        error: "Only adolescent accounts can use a caregiver linking code",
      });
    }

    let codeRef = db.collection("caregiverLinkCodes").doc(caregiverLinkCodeDocId(normalizedCode));
    let codeDoc = await codeRef.get();
    if (!codeDoc.exists) {
      // Legacy fallback for unexpired plaintext document IDs created before hashed storage.
      codeRef = db.collection("caregiverLinkCodes").doc(normalizedCode);
      codeDoc = await codeRef.get();
    }
    if (!codeDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "Linking code not found",
      });
    }

    const codeData = codeDoc.data() || {};
    const expiresAt = codeData.expiresAt?.toDate?.();
    if (codeData.status !== "active") {
      return res.status(400).json({
        success: false,
        error: "This linking code is no longer active",
      });
    }
    if (!expiresAt || expiresAt.getTime() <= Date.now()) {
      await codeRef.set(
        {
          status: "expired",
          code: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return res.status(400).json({
        success: false,
        error: "This linking code has expired",
      });
    }

    const caregiverUserId = codeData.caregiverUserId;
    const caregiverRef = db.collection("users").doc(caregiverUserId);
    const caregiverDoc = await caregiverRef.get();
    if (!caregiverDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "Caregiver profile not found",
      });
    }

    const caregiver = caregiverDoc.data() || {};
    if (!isCaregiverRole(caregiver.role)) {
      return res.status(400).json({
        success: false,
        error: "This caregiver account is not eligible for adolescent linking",
      });
    }

    const linkedChildren = Array.isArray(caregiver.linkedChildren)
      ? caregiver.linkedChildren
      : caregiver.linkedChildUserId
        ? [{ userId: caregiver.linkedChildUserId }]
        : [];
    const alreadyLinked = linkedChildren.some(
      (child) => child?.userId === adolescentUserId || child?.uid === adolescentUserId,
    );
    if (!alreadyLinked && linkedChildren.length >= 3) {
      return res.status(400).json({
        success: false,
        error: "This caregiver account can manage up to 3 child accounts",
      });
    }

    const nextLinkedChildren = alreadyLinked
      ? linkedChildren
      : [
          ...linkedChildren,
          {
            userId: adolescentUserId,
            name: adolescent.fullName || adolescent.name || "Adolescent",
            email: adolescent.email || null,
            linkedAt: new Date().toISOString(),
            relationship: "adolescent",
          },
        ];

    const caregiverSettings = {
      wantsCaregiverLink: true,
      caregiverLinked: true,
      caregiverId: caregiverUserId,
      consentConfirmed: true,
      linkStatus: "linked",
    };

    await Promise.all([
      caregiverRef.set(
        {
          linkedChildAccount: true,
          linkedChildUserId: adolescentUserId,
          linkedChildren: nextLinkedChildren,
          linkStatus: "linked",
          activeLinkingCode: admin.firestore.FieldValue.delete(),
          activeLinkingCodeHash: admin.firestore.FieldValue.delete(),
          linkCodeExpiresAt: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      ),
      adolescentRef.set(
        {
          caregiverSettings,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      ),
      codeRef.set(
        {
          status: "used",
          code: admin.firestore.FieldValue.delete(),
          linkedAdolescentUserId: adolescentUserId,
          usedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      ),
    ]);

    return res.status(200).json({
      success: true,
      message: "Caregiver and adolescent accounts linked successfully",
      caregiverUserId,
      adolescentUserId,
      caregiverSettings,
    });
  } catch (error) {
    console.error("LINK_CAREGIVER_ACCOUNT ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to link caregiver account",
    });
  }
});

app.post("/api/user/unlink-caregiver-child", async (req, res) => {
  const { uid, userId, linkedChildUserId } = req.body;
  const caregiverUserId = uid || userId;

  try {
    if (!caregiverUserId) {
      return res.status(400).json({
        success: false,
        error: "User ID is required",
      });
    }

    const caregiverRef = db.collection("users").doc(caregiverUserId);
    const caregiverDoc = await caregiverRef.get();
    if (!caregiverDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "Caregiver profile not found",
      });
    }

    const caregiver = caregiverDoc.data() || {};
    if (!isCaregiverRole(caregiver.role)) {
      return res.status(403).json({
        success: false,
        error: "Only caregivers can remove a linked child",
      });
    }

    const targetChildUserId =
      linkedChildUserId || caregiver.linkedChildUserId || null;
    if (!targetChildUserId) {
      return res.status(400).json({
        success: false,
        error: "No linked child account was found",
      });
    }

    const adolescentRef = db.collection("users").doc(targetChildUserId);
    const adolescentDoc = await adolescentRef.get();
    const nextLinkedChildren = Array.isArray(caregiver.linkedChildren)
      ? caregiver.linkedChildren.filter((child) => {
          const childId = child?.userId || child?.uid || child?.id;
          return String(childId || "") !== String(targetChildUserId);
        })
      : [];

    await caregiverRef.set(
      {
        linkedChildAccount: nextLinkedChildren.length > 0,
        linkedChildUserId:
          nextLinkedChildren[0]?.userId ||
          nextLinkedChildren[0]?.uid ||
          nextLinkedChildren[0]?.id ||
          null,
        linkedChildren: nextLinkedChildren,
        linkStatus: nextLinkedChildren.length > 0 ? "linked" : "pending",
        activeLinkingCode: admin.firestore.FieldValue.delete(),
        activeLinkingCodeHash: admin.firestore.FieldValue.delete(),
        linkCodeExpiresAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (adolescentDoc.exists) {
      await adolescentRef.set(
        {
          caregiverSettings: {
            wantsCaregiverLink: false,
            caregiverLinked: false,
            caregiverId: null,
            consentConfirmed: true,
            linkStatus: "none",
          },
          editPermissions: {
            canEditSensitive: true,
            requiresApproval: false,
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    return res.status(200).json({
      success: true,
      message: "Linked child removed successfully",
      caregiverUserId,
      linkedChildUserId: targetChildUserId,
    });
  } catch (error) {
    console.error("UNLINK_CAREGIVER_CHILD ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to remove linked child",
    });
  }
});

app.post("/api/user/privacy-consent", async (req, res) => {
  const { uid, accepted } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID is required",
      });
    }

    await db.collection("users").doc(uid).set(
      {
        privacyConsentAccepted: accepted === true,
        dataPrivacyConsentAccepted: accepted === true,
        privacyConsentAcceptedAt:
          accepted === true
            ? admin.firestore.FieldValue.serverTimestamp()
            : admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      privacyConsentAccepted: accepted === true,
    });
  } catch (error) {
    console.error("PRIVACY_CONSENT ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to update privacy consent",
    });
  }
});

app.post("/api/user/archive-direct-child-profile", async (req, res) => {
  const { uid, userId, childProfileId } = req.body;
  const caregiverUserId = uid || userId;

  try {
    if (!caregiverUserId) {
      return res.status(400).json({
        success: false,
        error: "User ID is required",
      });
    }

    const caregiverRef = db.collection("users").doc(caregiverUserId);
    const caregiverDoc = await caregiverRef.get();
    if (!caregiverDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "Caregiver profile not found",
      });
    }

    const caregiver = caregiverDoc.data() || {};
    if (!isCaregiverRole(caregiver.role)) {
      return res.status(403).json({
        success: false,
        error: "Only caregivers can archive directly managed profiles",
      });
    }

    const linkedChildren = Array.isArray(caregiver.linkedChildren)
      ? caregiver.linkedChildren
      : [];
    const targetChildId =
      childProfileId ||
      caregiver.activeDirectChildProfileId ||
      linkedChildren.find((child) => child?.type === "direct")?.userId ||
      linkedChildren.find((child) => child?.type === "direct")?.uid ||
      linkedChildren.find((child) => child?.type === "direct")?.id ||
      null;

    if (!targetChildId) {
      return res.status(400).json({
        success: false,
        error: "Child profile ID is required",
      });
    }

    const targetChild = linkedChildren.find((child) => {
      const id = child?.userId || child?.uid || child?.id;
      return String(id || "") === String(targetChildId);
    });

    if (!targetChild) {
      return res.status(404).json({
        success: false,
        error: "Child profile was not found under this caregiver",
      });
    }
    if (targetChild.type !== "direct") {
      return res.status(400).json({
        success: false,
        error: "Linked adolescent accounts can only be unlinked, not deleted",
      });
    }

    const remainingChildren = linkedChildren.filter((child) => {
      const id = child?.userId || child?.uid || child?.id;
      return String(id || "") !== String(targetChildId);
    });
    const remainingLinkedAccount = remainingChildren.find(
      (child) =>
        child?.relationship === "adolescent" ||
        child?.type === "linked" ||
        child?.type === "adolescent",
    );
    const remainingDirectChild = remainingChildren.find(
      (child) => child?.type === "direct",
    );

    const childDoc = await db.collection("users").doc(targetChildId).get();
    const childProfile = childDoc.exists ? childDoc.data() || {} : {};

    async function deleteDocById(collectionName, docId) {
      if (!docId) return 0;
      await db.collection(collectionName).doc(docId).delete();
      return 1;
    }

    async function deleteWhere(collectionName, field, value) {
      if (!value) return 0;
      const snapshot = await db
        .collection(collectionName)
        .where(field, "==", value)
        .get();
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

    const childCollections = [
      "medicalProfile",
      "anthropometrics",
      "historicalAnthropometrics",
      "labResults",
      "historicalLabResults",
      "nutritionTargets",
      "phase2DecisionSupport",
      "medications",
      "foodLogs",
      "dailyIntakeSummaries",
      "analyticsSummaries",
      "reminderSettings",
    ];
    for (const collectionName of childCollections) {
      await deleteWhere(collectionName, "userId", targetChildId);
      await deleteWhere(collectionName, "uid", targetChildId);
      await deleteWhere(collectionName, "childProfileId", targetChildId);
    }

    await deleteDocById("medicalProfile", childProfile.medicalProfileId);
    await deleteDocById("nutritionTargets", childProfile.baselineNutritionTargetId);
    await deleteDocById(
      "phase2DecisionSupport",
      childProfile.phase2DecisionSupportId,
    );
    await deleteDocById("labResults", childProfile.labResultId);
    if (Array.isArray(childProfile.medicationIds)) {
      for (const medicationId of childProfile.medicationIds) {
        await deleteDocById("medications", medicationId);
      }
    }
    await db.collection("users").doc(targetChildId).delete();

    await caregiverRef.set(
      {
        childProfileArchived: true,
        childProfileArchivedAt: admin.firestore.FieldValue.serverTimestamp(),
        childProfileCreated: remainingChildren.length > 0,
        activeDirectChildProfileId:
          remainingDirectChild?.userId ||
          remainingDirectChild?.uid ||
          remainingDirectChild?.id ||
          null,
        linkedChildAccount: Boolean(remainingLinkedAccount),
        linkedChildUserId:
          remainingLinkedAccount?.userId ||
          remainingLinkedAccount?.uid ||
          remainingLinkedAccount?.id ||
          null,
        linkedChildren: remainingChildren,
        childAgeGroup:
          remainingDirectChild?.childAgeGroup || caregiver.childAgeGroup || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      message: "Directly managed child profile deleted successfully",
      caregiverUserId,
      childProfileId: targetChildId,
    });
  } catch (error) {
    console.error(
      "ARCHIVE_DIRECT_CHILD_PROFILE ERROR:",
      error.code || error.message,
    );
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to archive child profile",
    });
  }
});

////////////////////// LOGIN (EMAIL/PASSWORD) //////////////////////
// Authenticate user with email and password
app.post("/api/user/login", authAttemptLimiter, async (req, res) => {
  console.log("LOGIN received:", {
    hasEmail: Boolean(req.body.email),
  });

  const { email, password } = req.body;

  try {
    if (!email || !password) {
      return res.status(400).json({
        success: false,
        error: "Email and password are required",
      });
    }

    // Get user by email from Firebase
    const user = await auth.getUserByEmail(email);
    
    // Verify password (compare with stored hash if using custom passwords)
    const [userSecret, profileSnap] = await Promise.all([
      db.collection("userSecrets").doc(user.uid).get(),
      db.collection("users").doc(user.uid).get(),
    ]);

    if (!profileSnap.exists) {
      return res.status(404).json({
        success: false,
        error: "Account not found. Please create an account first.",
      });
    }

    if (!userSecret.exists) {
      return res.status(401).json({
        success: false,
        error: "Invalid email or password",
      });
    }

    const { passwordSalt, passwordHash } = userSecret.data();
    if (!passwordSalt || !passwordHash || !verifyPassword(password, passwordSalt, passwordHash)) {
      return res.status(401).json({
        success: false,
        error: "Invalid email or password",
      });
    }

    const profile = decryptHealthProfile(profileSnap.data() || {});
    const securitySettings = normalizeSecuritySettings(profile);
    const isDbVerified =
      profile.status === "verified" || profile.emailVerified === true;
    const profileComplete = isProfileComplete(profile);

    if (user.email && !isDbVerified && user.emailVerified !== true) {
      return res.status(403).json({
        success: false,
        error:
          "Email not verified. Please click the verification link in your email before signing in.",
        uid: user.uid,
        email: user.email,
        emailVerified: false,
      });
    }

    if (
      securitySettings.mfaMethod === "authenticator" &&
      securitySettings.authenticatorEnabled &&
      !securitySettings.hasAuthenticatorSecret
    ) {
      return res.status(409).json({
        success: false,
        error:
          "Authenticator MFA is enabled, but no active authenticator secret is stored.",
      });
    }

    console.log("LOGIN: Successfully authenticated user:", user.uid);

    res.status(200).json({
      success: true,
      message: "Login successful",
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      profileComplete,
      needsProfileSetup: buildNeedsProfileSetup(profile, true),
      mfaRequired: securitySettings.mfaEnabled,
      mfaMethod: securitySettings.mfaMethod,
      securitySettings: toPublicSecuritySettings(securitySettings),
    });
  } catch (error) {
    console.error("LOGIN ERROR:", error.code || error.message);
    
    if (error.code === 'auth/user-not-found') {
      return res.status(401).json({
        success: false,
        error: "User not found",
      });
    }

    res.status(500).json({
      success: false,
      error: error.message || "Failed to login",
    });
  }
});

app.post("/api/user/security-settings", async (req, res) => {
  console.log("SECURITY_SETTINGS received:", {
    hasUid: Boolean(req.body.uid),
  });

  const { uid } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) is required",
      });
    }

    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const profile = decryptHealthProfile(userDoc.data() || {});
    const authUser = await auth.getUser(uid).catch(() => null);
    const securitySettings = normalizeSecuritySettings({
      ...profile,
      phoneNumber: profile.phoneNumber || authUser?.phoneNumber || "",
      email: profile.email || authUser?.email || "",
    });

    return res.status(200).json({
      success: true,
      securitySettings: toPublicSecuritySettings(securitySettings),
    });
  } catch (error) {
    console.error("SECURITY_SETTINGS ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to load security settings",
    });
  }
});

app.post("/api/user/update-security-settings", authAttemptLimiter, async (req, res) => {
  console.log("UPDATE_SECURITY_SETTINGS received:", {
    uid: req.body.uid,
    mfaEnabled: req.body.mfaEnabled,
    mfaMethod: req.body.mfaMethod,
  });

  const { uid, mfaEnabled, mfaMethod, mfaCode } = req.body;

  try {
    if (!uid || typeof mfaEnabled !== "boolean") {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) and MFA enabled state are required",
      });
    }

    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const profile = decryptHealthProfile(userDoc.data() || {});
    const securitySettings = normalizeSecuritySettings(profile);
    const requestedMethod =
      mfaEnabled == true
        ? (mfaMethod == "authenticator"
            ? mfaMethod
            : securitySettings.mfaMethod)
        : "none";

    if (mfaEnabled && requestedMethod === "authenticator" && !securitySettings.hasAuthenticatorSecret) {
      return res.status(400).json({
        success: false,
        error:
          "Complete authenticator enrollment before enabling multi-factor authentication.",
      });
    }

    if (
      mfaEnabled === false &&
      securitySettings.authenticatorEnabled &&
      securitySettings.mfaSecret
    ) {
      if (!isValidAuthenticatorCode(mfaCode)) {
        return res.status(400).json({
          success: false,
          error: "Enter a valid 6-digit authenticator code to disable MFA.",
        });
      }

      if (!verifyTotpCode(securitySettings.mfaSecret, mfaCode)) {
        return res.status(401).json({
          success: false,
          error: "Invalid authenticator code.",
        });
      }
    }

    await userRef.set(
      {
        mfaEnabled,
        mfaSecret: admin.firestore.FieldValue.delete(),
        mfaTempSecret: admin.firestore.FieldValue.delete(),
        securitySettings: {
          mfaEnabled,
          mfaMethod: requestedMethod,
          authenticatorEnabled: mfaEnabled && requestedMethod === "authenticator",
          emailMfaEnabled: false,
          mfaEmail: securitySettings.mfaEmail,
          mfaSecret: securitySettings.mfaSecret
            ? encryptValue(securitySettings.mfaSecret)
            : admin.firestore.FieldValue.delete(),
          mfaTempSecret: admin.firestore.FieldValue.delete(),
          emailChallengeCodeHash: admin.firestore.FieldValue.delete(),
          emailChallengeExpiresAt: admin.firestore.FieldValue.delete(),
          emailChallengePurpose: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(mfaEnabled
            ? {
              mfaVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
            }
            : {}),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      message: "Security settings updated",
      securitySettings: toPublicSecuritySettings(normalizeSecuritySettings({
        ...profile,
        mfaEnabled,
        securitySettings: {
          ...(profile.securitySettings || {}),
          mfaEnabled,
          mfaMethod: requestedMethod,
          authenticatorEnabled: mfaEnabled && requestedMethod === "authenticator",
          emailMfaEnabled: false,
          mfaEmail: securitySettings.mfaEmail,
          mfaSecret: securitySettings.mfaSecret || null,
        },
      })),
    });
  } catch (error) {
    console.error("UPDATE_SECURITY_SETTINGS ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to update security settings",
    });
  }
});

app.post("/api/user/reminder-settings", async (req, res) => {
  console.log("REMINDER_SETTINGS received:", {
    uid: req.body.uid,
    profileUserId: req.body.profileUserId,
  });

  const actingUserId = req.body.uid;
  const requestedProfileUserId = req.body.profileUserId;

  try {
    const { targetProfile, targetUserId } = await resolveReminderSettingsTarget(
      actingUserId,
      requestedProfileUserId,
    );

    return res.status(200).json({
      success: true,
      profileUserId: targetUserId,
      reminderSettings: normalizeReminderSettings(targetProfile),
    });
  } catch (error) {
    console.error("REMINDER_SETTINGS ERROR:", error.code || error.message);
    return res.status(error.statusCode || 500).json({
      success: false,
      error: error.message || "Failed to load reminder settings",
    });
  }
});

app.post("/api/user/update-reminder-settings", async (req, res) => {
  console.log("UPDATE_REMINDER_SETTINGS received:", {
    uid: req.body.uid,
    profileUserId: req.body.profileUserId,
    hasMealReminders: Boolean(req.body.mealReminders),
    hasMedicationReminders: Boolean(req.body.medicationReminders),
    hasHydrationReminders: Boolean(req.body.hydrationReminders),
  });

  const actingUserId = req.body.uid;
  const requestedProfileUserId = req.body.profileUserId;

  try {
    const { targetRef } = await resolveReminderSettingsTarget(
      actingUserId,
      requestedProfileUserId,
    );

    const mealReminders =
      req.body.mealReminders && typeof req.body.mealReminders === "object"
        ? req.body.mealReminders
        : {};

    const reminderSettings = {
      medicationReminders: req.body.medicationReminders === true,
      hydrationAlerts: req.body.hydrationAlerts === true,
      mealReminders: {
        breakfast: mealReminders.breakfast === true,
        lunch: mealReminders.lunch === true,
        snack: mealReminders.snack === true,
        dinner: mealReminders.dinner === true,
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await targetRef.set(
      {
        reminderSettings,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      message: "Reminder settings updated",
      reminderSettings: normalizeReminderSettings({ reminderSettings }),
    });
  } catch (error) {
    console.error("UPDATE_REMINDER_SETTINGS ERROR:", error.code || error.message);
    return res.status(error.statusCode || 500).json({
      success: false,
      error: error.message || "Failed to update reminder settings",
    });
  }
});

app.post("/api/user/device-token/register", async (req, res) => {
  console.log("REGISTER_DEVICE_TOKEN received:", {
    uid: req.body.uid,
    platform: req.body.platform,
    tokenPreview: String(req.body.token || "").slice(0, 16),
  });

  const { uid, token, platform } = req.body;

  try {
    if (!uid || !token) {
      return res.status(400).json({
        success: false,
        error: "User ID and device token are required",
      });
    }

    const normalizedToken = normalizeDeviceToken(token);
    if (!normalizedToken) {
      return res.status(400).json({
        success: false,
        error: "Device token is invalid",
      });
    }

    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const profile = decryptHealthProfile(userDoc.data() || {});
    const removedFromOtherUsers = await removeDeviceTokenFromOtherUsers(
      normalizedToken,
      uid,
    );
    await userRef.set(
      {
        deviceTokens: buildDeviceTokenRecord(normalizedToken, profile, platform),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      message: "Device token registered",
      removedFromOtherUsers,
    });
  } catch (error) {
    console.error("REGISTER_DEVICE_TOKEN ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to register device token",
    });
  }
});

app.post("/api/user/device-token/unregister", async (req, res) => {
  console.log("UNREGISTER_DEVICE_TOKEN received:", {
    uid: req.body.uid,
    tokenPreview: String(req.body.token || "").slice(0, 16),
  });

  const { uid, token } = req.body;

  try {
    if (!uid || !token) {
      return res.status(400).json({
        success: false,
        error: "User ID and device token are required",
      });
    }

    const normalizedToken = normalizeDeviceToken(token);
    const userRef = db.collection("users").doc(uid);
    await userRef.set(
      {
        [`deviceTokens.${normalizedToken}`]:
          admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      message: "Device token unregistered",
    });
  } catch (error) {
    console.error("UNREGISTER_DEVICE_TOKEN ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to unregister device token",
    });
  }
});

app.post("/api/user/push-notification/send-test", async (req, res) => {
  console.log("SEND_TEST_PUSH received:", { uid: req.body.uid });

  const { uid } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID is required",
      });
    }

    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const profile = decryptHealthProfile(userDoc.data() || {});
    const result = await sendPushNotificationToProfile(profile, {
      title: "NutriKidney test",
      body: "Push notifications are working on this device.",
      data: {
        type: "test_notification",
      },
    });

    return res.status(200).json({
      success: true,
      message: "Test push notification sent",
      successCount: result.successCount,
      failureCount: result.failureCount,
    });
  } catch (error) {
    console.error("SEND_TEST_PUSH ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to send test push notification",
    });
  }
});

/**
 * POST /api/reminders/do-not-remind
 * Set a "do not remind me" period for the user
 * Request body: { uid: string, durationMinutes: number }
 */
app.post("/api/reminders/do-not-remind", async (req, res) => {
  const { uid, durationMinutes = 60 } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID is required",
      });
    }

    if (durationMinutes <= 0) {
      return res.status(400).json({
        success: false,
        error: "Duration must be greater than 0",
      });
    }

    // Calculate the time until reminders should resume
    const dontRemindUntilMs = Date.now() + durationMinutes * 60 * 1000;

    // Update user profile with "do not remind" timestamp
    await db.collection("users").doc(uid).update({
      "reminderSettings.dontRemindUntil": admin.firestore.Timestamp.fromMillis(
        dontRemindUntilMs
      ),
    });

    console.log(`[Reminders] User ${uid} set do-not-remind for ${durationMinutes} minutes`);

    return res.status(200).json({
      success: true,
      message: `Reminders disabled for ${durationMinutes} minutes`,
      dontRemindUntil: new Date(dontRemindUntilMs).toISOString(),
    });
  } catch (error) {
    console.error("Error setting do-not-remind:", error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to set do-not-remind",
    });
  }
});

/**
 * POST /api/reminders/clear-do-not-remind
 * Clear the "do not remind me" period (resume reminders immediately)
 * Request body: { uid: string }
 */
app.post("/api/reminders/clear-do-not-remind", async (req, res) => {
  const { uid } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID is required",
      });
    }

    // Clear the "do not remind" timestamp
    await db.collection("users").doc(uid).update({
      "reminderSettings.dontRemindUntil": admin.firestore.FieldValue.delete(),
    });

    console.log(`[Reminders] User ${uid} cleared do-not-remind`);

    return res.status(200).json({
      success: true,
      message: "Reminders re-enabled",
    });
  } catch (error) {
    console.error("Error clearing do-not-remind:", error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to clear do-not-remind",
    });
  }
});


////////////////////// SEND PASSWORD RESET //////////////////////
// Send password reset email
app.post("/api/user/send-password-reset", passwordResetLimiter, async (req, res) => {
  console.log("SEND_PASSWORD_RESET received:", {
    hasEmail: Boolean(req.body.email),
  });

  const { email } = req.body;

  try {
    if (!email) {
      return res.status(400).json({
        success: false,
        error: "Email is required",
      });
    }

    // Generate password reset link
    const resetLink = await admin.auth().generatePasswordResetLink(email);
    console.log("SEND_PASSWORD_RESET: Generated link for:", email);

    // In production, send this link via email service
    // For now, we'll return it
    res.status(200).json({
      success: true,
      message: "Password reset link generated",
      email: email,
      resetLink: resetLink,
    });
  } catch (error) {
    console.error("SEND_PASSWORD_RESET ERROR:", error.code || error.message);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to send password reset",
    });
  }
});

////////////////////// VERIFY PASSWORD RESET CODE //////////////////////
// Verify and process password reset code
app.post("/api/user/reset-password", passwordResetLimiter, async (req, res) => {
  console.log("RESET_PASSWORD received");

  const { oobCode, newPassword } = req.body;

  try {
    if (!oobCode || !newPassword) {
      return res.status(400).json({
        success: false,
        error: "Reset code and new password are required",
      });
    }

    // Verify the reset code and get the user
    const email = await admin.auth().verifyPasswordResetCode(oobCode);
    const user = await auth.getUserByEmail(email);

    // Confirm password reset in Firebase
    await admin.auth().confirmPasswordReset(oobCode, newPassword);
    
    await savePasswordSecret(user.uid, newPassword);

    console.log("RESET_PASSWORD: Successfully reset password for user:", user.uid);

    res.status(200).json({
      success: true,
      message: "Password reset successfully",
      uid: user.uid,
      email: email,
    });
  } catch (error) {
    console.error("RESET_PASSWORD ERROR:", error.code || error.message);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to reset password",
    });
  }
});

app.post("/api/user/change-password", authAttemptLimiter, async (req, res) => {
  console.log("CHANGE_PASSWORD received:", {
    uid: req.body.uid,
    verificationContact: req.body.verificationContact,
    currentPassword: req.body.currentPassword ? "[REDACTED]" : undefined,
    newPassword: req.body.newPassword ? "[REDACTED]" : undefined,
  });

  const { uid, currentPassword, newPassword, verificationContact } = req.body;

  try {
    if (!uid || !currentPassword || !newPassword || !verificationContact) {
      return res.status(400).json({
        success: false,
        error:
          "User ID, current password, new password, and verification contact are required",
      });
    }

    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const profile = decryptHealthProfile(userDoc.data() || {});
    const authUser = await auth.getUser(uid).catch(() => null);
    const storedEmail = String(profile.email || authUser?.email || "")
      .trim()
      .toLowerCase();
    const storedPhone = String(profile.phoneNumber || authUser?.phoneNumber || "").trim();
    const typedContact = String(verificationContact || "").trim();
    const normalizedTypedContact = typedContact.toLowerCase();

    const verificationMatches =
      (storedEmail && normalizedTypedContact === storedEmail) ||
      (storedPhone && typedContact === storedPhone);

    if (!verificationMatches) {
      return res.status(403).json({
        success: false,
        error:
          "Verification contact does not match the linked account contact",
      });
    }

    const userSecret = await db.collection("userSecrets").doc(uid).get();
    if (!userSecret.exists) {
      return res.status(401).json({
        success: false,
        error: "Current password could not be verified",
      });
    }

    const { passwordSalt, passwordHash } = userSecret.data() || {};
    if (
      !passwordSalt ||
      !passwordHash ||
      !verifyPassword(currentPassword, passwordSalt, passwordHash)
    ) {
      return res.status(401).json({
        success: false,
        error: "Current password is incorrect",
      });
    }

    await auth.updateUser(uid, { password: newPassword });
    await savePasswordSecret(uid, newPassword);
    await db.collection("users").doc(uid).set(
      {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    res.status(200).json({
      success: true,
      message: "Password updated successfully",
      uid,
    });
  } catch (error) {
    console.error("CHANGE_PASSWORD ERROR:", error.code || error.message);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to change password",
    });
  }
});

////////////////////// SIGN OUT //////////////////////
// Sign out user (backend cleanup, if needed)
app.post("/api/user/sign-out", async (req, res) => {
  console.log("SIGN_OUT received for UID:", req.body.uid);

  const { uid } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) is required",
      });
    }

    // Log the sign out in database
    await db.collection("users").doc(uid).set(
      {
        lastSignOut: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    console.log("SIGN_OUT: User signed out:", uid);

    res.status(200).json({
      success: true,
      message: "Signed out successfully",
      uid: uid,
    });
  } catch (error) {
    console.error("SIGN_OUT ERROR:", error.code || error.message);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to sign out",
    });
  }
});

////////////////////// CANCEL VERIFICATION & DELETE USER //////////////////////
// Called when user cancels email/phone verification during signup
// Deletes user from Firebase Auth and removes all database records
app.post("/api/user/cancel-verification", async (req, res) => {
  console.log("CANCEL_VERIFICATION received for UID:", req.body.uid);

  const { uid } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) is required",
      });
    }

    console.log("CANCEL_VERIFICATION: Starting deletion for UID:", uid);

    // Delete from Firebase Auth
    try {
      await auth.deleteUser(uid);
      console.log("CANCEL_VERIFICATION: Deleted from Firebase Auth:", uid);
    } catch (authError) {
      console.warn("CANCEL_VERIFICATION: Firebase Auth deletion warning:", authError.code || authError.message);
      // Don't throw - continue to database cleanup even if auth deletion fails
    }

    // Delete user profile from Firestore
    try {
      await db.collection("users").doc(uid).delete();
      console.log("CANCEL_VERIFICATION: Deleted user profile from Firestore:", uid);
    } catch (dbError) {
      console.warn("CANCEL_VERIFICATION: Firestore deletion warning:", dbError.message);
      // Don't throw - continue to next cleanup
    }

    // Delete user secrets from Firestore
    try {
      await db.collection("userSecrets").doc(uid).delete();
      console.log("CANCEL_VERIFICATION: Deleted user secrets from Firestore:", uid);
    } catch (dbError) {
      console.warn("CANCEL_VERIFICATION: User secrets deletion warning:", dbError.message);
      // Don't throw - continue to next cleanup
    }

    // Delete any pending verification records
    try {
      const pendingDocs = await db.collection("pendingVerifications").where("uid", "==", uid).get();
      for (const doc of pendingDocs.docs) {
        await doc.ref.delete();
      }
      console.log("CANCEL_VERIFICATION: Deleted pending verification records:", uid);
    } catch (dbError) {
      console.warn("CANCEL_VERIFICATION: Pending verification deletion warning:", dbError.message);
    }

    console.log("CANCEL_VERIFICATION: Completed for UID:", uid);

    res.status(200).json({
      success: true,
      message: "User account and all related data deleted successfully",
      deletedUid: uid,
    });
  } catch (error) {
    console.error("CANCEL_VERIFICATION ERROR:", error.code || error.message);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to cancel verification and delete user",
    });
  }
});

////////////////////// HEALTH ROUTES //////////////////////
const healthRoutes = require("./routes/healthRoutes");
app.use("/api/health", healthRoutes);

////////////////////// ENCRYPTED HEALTH PROFILE ROUTES //////////////////////
const encryptedHealthProfileRoutes = require("./routes/encryptedHealthProfileRoutes");
app.use("/api/encrypted-health-profile", encryptedHealthProfileRoutes);

////////////////////// FOOD LOG ROUTES //////////////////////
const foodLogRoutes = require("./routes/foodLogRoutes");
app.use("/api/food", foodLogRoutes);

////////////////////// GAMIFICATION ROUTES //////////////////////
const gamificationRoutes = require("./routes/gamificationRoutes");
app.use("/api/gamification", gamificationRoutes);

////////////////////// AUTHENTICATOR MFA ROUTES //////////////////////
const authenticatorMfaRoutes = require("./routes/authenticatorMfaRoutes");
app.use("/api/user/mfa/authenticator", authenticatorMfaRoutes);

////////////////////// START SERVER //////////////////////
app.listen(3000, "0.0.0.0", () => {
  console.log("Server running on port 3000");
  
  // Initialize reminder scheduler
  initializeReminderScheduler();
});
