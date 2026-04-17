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
      try {
        await auth.getUserByPhoneNumber(phoneNumber);
        // User already exists
        return res.status(400).json({
          success: false,
          error: "Phone number already registered",
        });
      } catch (e) {
        // User doesn't exist (expected)
      }
    }

    if (email) {
      try {
        await auth.getUserByEmail(email);
        // User already exists
        return res.status(400).json({
          success: false,
          error: "Email already registered",
        });
      } catch (e) {
        // User doesn't exist (expected)
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
        await auth.getUserByEmail(email);
        // User exists
        console.log("CHECK_USER: Email found - already exists");
        return res.status(200).json({
          success: true,
          exists: true,
          message: "Email already exists",
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
      try {
        await auth.getUserByPhoneNumber(phoneNumber);
        // User exists
        console.log("CHECK_USER: Phone number found - already exists");
        return res.status(200).json({
          success: true,
          exists: true,
          message: "Phone number already exists",
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

    let user;
    try {
      user = await auth.getUserByPhoneNumber(phoneNumber);
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

    const valid = verifyPassword(password, secret.passwordSalt, secret.passwordHash);
    return res.status(200).json({
      success: true,
      valid,
      reason: valid ? "ok" : "wrong-password",
      userId: valid ? user.uid : undefined,
    });
  } catch (error) {
    console.error("VERIFY_PHONE_PASSWORD ERROR:", error.code || error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to verify phone password",
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
      user = await auth.getUserByPhoneNumber(phoneNumber);
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
  
  const { email, phoneNumber, password, fullName } = req.body;

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
        if (phoneNumber) createPayload.phoneNumber = phoneNumber;

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
      emailVerified: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (phoneNumber) profile.phoneNumber = phoneNumber;

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
  
  const { email, phoneNumber, password, fullName, uid } = req.body;

  try {
    if (!phoneNumber || !password || !fullName) {
      return res.status(400).json({
        success: false,
        error: "Phone number, password, and full name are required",
      });
    }

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
        const existingUser = await auth.getUserByPhoneNumber(phoneNumber);
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
        phoneNumber,
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
      phoneVerified: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (email) profile.email = email;
    if (phoneNumber) profile.phoneNumber = phoneNumber;

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

    res.status(500).json({
      success: false,
      error: error.message || 'Failed to create user after phone verification',
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
