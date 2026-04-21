const express = require("express");
const cors = require("cors");
const crypto = require("crypto");
const dns = require("dns").promises;
const { admin, db, auth } = require("./firebase/admin");

const app = express();

app.use(cors());
app.use(express.json());

app.get("/", (req, res) => {
  res.send("NutriKidney API running");
});

const PASSWORD_KEYLEN = 64;

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

  const profile = userDoc.data() || {};
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

async function getUserVerificationState(uid) {
  let authUser = null;
  try {
    authUser = await auth.getUser(uid);
  } catch (_) {}

  const userDoc = await db.collection("users").doc(uid).get();
  const profile = userDoc.exists ? userDoc.data() || {} : {};

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
app.post("/signup", async (req, res) => {
  console.log("SIGNUP received:", req.body);

  const { email, phoneNumber, password, fullName } = req.body;

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
app.post("/check-user", async (req, res) => {
  console.log("CHECK_USER received:", req.body);

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
        const profile = userDoc.exists ? userDoc.data() || {} : {};
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
app.post("/verify-phone-password", async (req, res) => {
  console.log("VERIFY_PHONE_PASSWORD received:", req.body);

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
    const profile = userDoc.exists ? userDoc.data() || {} : {};
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
  console.log("PROFILE_STATUS received:", req.body);

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
    const profile = userDoc.exists ? userDoc.data() || {} : {};
    const authUser = await auth.getUser(resolvedUid).catch(() => null);
    const verified = isUserVerified({ authUser, profile });
    const profileComplete = Boolean(
      profile.baselineNutritionTargetId && profile.medicalProfileId,
    );

    return res.status(200).json({
      success: true,
      exists: userDoc.exists,
      verified,
      profileComplete,
      needsProfileSetup: verified && !profileComplete,
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
app.post("/reset-password", async (req, res) => {
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
app.post("/verify-email-domain", async (req, res) => {
  console.log("VERIFY_EMAIL_DOMAIN received:", req.body);

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
app.post("/send-email-verification", async (req, res) => {
  console.log("SEND_EMAIL_VERIFICATION received (client handles email now):", req.body);

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
app.post("/verify-email-token", async (req, res) => {
  console.log("VERIFY_EMAIL_TOKEN received:", req.body);

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
app.post("/verify-email-and-create-user", async (req, res) => {
  console.log("VERIFY_EMAIL_AND_CREATE_USER received:", req.body);

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
    const profile = {
      uid: user.uid,
      fullName,
      email,
      status: "verified",
      emailVerified: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (phoneNumber) {
      profile.phoneNumber = normalizePhoneNumberOrThrow(
        phoneNumber,
        "phone number",
      );
    }
    if (userRole) {
      profile.role = userRole;
    }

    await db.collection("users").doc(user.uid).set(profile, { merge: true });
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
app.post("/verify-phone-and-create-user", async (req, res) => {
  console.log("VERIFY_PHONE_AND_CREATE_USER received:", req.body);
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
    const profile = {
      uid: user.uid,
      fullName,
      status: "verified",
      phoneVerified: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (email) profile.email = email;
    if (phoneNumber) profile.phoneNumber = normalizedPhone;
    if (userRole) profile.role = userRole;

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
app.post("/api/user/create", async (req, res) => {
  console.log("CREATE_USER received:", {
    ...req.body,
    password: req.body.password ? "[REDACTED]" : undefined,
  });

  const { email, phoneNumber, password, fullName } = req.body;

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
// Send email verification link to user
app.post("/api/user/send-email-verification", async (req, res) => {
  console.log("SEND_EMAIL_VERIFICATION received for UID:", req.body.uid);

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

    // Generate verification link using Firebase REST API
    const verificationLink = await admin.auth().generateEmailVerificationLink(user.email);
    console.log("SEND_EMAIL_VERIFICATION: Generated link for:", user.email);

    // In production, send this link via email service
    // For now, we'll return it (Flutter will show it in dialog or send it)
    res.status(200).json({
      success: true,
      message: "Email verification link generated",
      uid: uid,
      email: user.email,
      verificationLink: verificationLink,
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
app.post("/api/user/send-phone-otp", async (req, res) => {
  console.log("SEND_PHONE_OTP received for UID:", req.body.uid);

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
app.post("/api/user/complete-email-verification", async (req, res) => {
  console.log("COMPLETE_EMAIL_VERIFICATION received for UID:", req.body.uid);

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
app.post("/api/user/complete-phone-verification", async (req, res) => {
  console.log("COMPLETE_PHONE_VERIFICATION received for UID:", req.body.uid);

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
  console.log("SAVE_USER_PROFILE received for UID:", req.body.uid);

  const { uid, fullName, email, phoneNumber, status, userRole } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) is required",
      });
    }

    const verificationState = await getUserVerificationState(uid);

    const profileData = {
      uid,
      fullName: fullName || "",
      email: email || "",
      phoneNumber: phoneNumber || "",
      status: status || verificationState.status,
      emailVerified: verificationState.emailVerified,
      phoneVerified: verificationState.phoneVerified,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (userRole) {
      profileData.role = userRole;
    }

    // Ensure createdAt is preserved if user already exists
    const existingDoc = await db.collection("users").doc(uid).get();
    if (!existingDoc.exists) {
      profileData.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }

    await db.collection("users").doc(uid).set(profileData, { merge: true });
    
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

////////////////////// LOGIN (EMAIL/PASSWORD) //////////////////////
// Authenticate user with email and password
app.post("/api/user/login", async (req, res) => {
  console.log("LOGIN received for email:", req.body.email);

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
    const userSecret = await db.collection("userSecrets").doc(user.uid).get();
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

    const profileSnap = await db.collection("users").doc(user.uid).get();
    const profile = profileSnap.exists ? profileSnap.data() || {} : {};
    const isDbVerified =
      profile.status === "verified" || profile.emailVerified === true;
    const profileComplete = Boolean(
      profile.baselineNutritionTargetId && profile.medicalProfileId,
    );

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

    console.log("LOGIN: Successfully authenticated user:", user.uid);

    res.status(200).json({
      success: true,
      message: "Login successful",
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      profileComplete,
      needsProfileSetup: !profileComplete,
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

////////////////////// SEND PASSWORD RESET //////////////////////
// Send password reset email
app.post("/api/user/send-password-reset", async (req, res) => {
  console.log("SEND_PASSWORD_RESET received for email:", req.body.email);

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
app.post("/api/user/reset-password", async (req, res) => {
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
    
    // Update password hash in Firestore
    const crypto = require('crypto');
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = crypto.scryptSync(newPassword, Buffer.from(salt, 'hex'), 64).toString('hex');
    
    await db.collection("userSecrets").doc(user.uid).set(
      {
        passwordSalt: salt,
        passwordHash: hash,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

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

////////////////////// START SERVER //////////////////////
app.listen(3000, "0.0.0.0", () => {
  console.log("Server running on port 3000");
});
