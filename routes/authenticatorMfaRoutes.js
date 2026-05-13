const express = require("express");

const { admin, db, auth } = require("../firebase/admin");
const {
  buildAuthenticatorEnrollmentPayload,
  buildTotp,
  isValidAuthenticatorCode,
  normalizeSecuritySettings,
  verifyTotpCode,
} = require("../services/authenticatorMfaService");

const router = express.Router();

function isProfileCompleteForMfa(profile = {}) {
  const normalizedRole = String(profile.role || "").trim().toLowerCase();
  const isCaregiver =
    normalizedRole === "caregiver" || normalizedRole === "parent_caregiver";
  const isLinkOnlyCaregiver = isCaregiver && profile.childAgeGroup === "13-18";
  const hasManagedChild =
    isCaregiver &&
    (profile.childProfileCreated === true ||
      Boolean(profile.activeDirectChildProfileId) ||
      Boolean(profile.linkedChildUserId) ||
      (Array.isArray(profile.linkedChildren) && profile.linkedChildren.length > 0));
  const hasAcceptedPrivacyConsent =
    profile.privacyConsentAccepted === true ||
    profile.dataPrivacyConsentAccepted === true ||
    profile.consentAccepted === true;

  if (hasAcceptedPrivacyConsent || isLinkOnlyCaregiver || hasManagedChild) {
    return true;
  }

  return Boolean(profile.baselineNutritionTargetId && profile.medicalProfileId);
}

router.post("/setup/start", async (req, res) => {
  console.log("MFA_AUTHENTICATOR_SETUP_START received:", {
    uid: req.body.uid,
    email: req.body.email,
  });

  const { uid, email } = req.body;

  try {
    if (!uid) {
      return res.status(400).json({
        success: false,
        error: "User ID (uid) is required",
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

    const profile = userDoc.data() || {};
    if (!isProfileCompleteForMfa(profile)) {
      return res.status(409).json({
        success: false,
        error:
          "Complete registration and profile setup before enabling multi-factor authentication.",
      });
    }

    const authUser = await auth.getUser(uid).catch(() => null);
    const securitySettings = normalizeSecuritySettings(profile);
    const existingSecret =
      securitySettings.mfaSecret || securitySettings.mfaTempSecret;

    let tempSecret = existingSecret;
    let otpauthUrl;
    let qrCodeDataUrl;

    if (existingSecret) {
      const accountEmail = String(
        email || profile.email || authUser?.email || "",
      ).trim();
      const label = accountEmail || uid;
      const totp = buildTotp(existingSecret, { label });
      otpauthUrl = totp.toString();
      qrCodeDataUrl = await require("qrcode").toDataURL(otpauthUrl);
    } else {
      const payload = await buildAuthenticatorEnrollmentPayload({
        uid,
        email,
        profile,
        authUser,
      });
      tempSecret = payload.tempSecret;
      otpauthUrl = payload.otpauthUrl;
      qrCodeDataUrl = payload.qrCodeDataUrl;
    }

    await userRef.set(
      {
        // We do NOT set mfaEnabled or authenticatorEnabled to true here.
        // Enrollment setup is a pending state.
        mfaTempSecret: tempSecret,
        securitySettings: {
          ...(profile.securitySettings || {}),
          mfaTempSecret: tempSecret,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      qrCodeDataUrl,
      otpauthUrl,
      mfaMethod: "authenticator",
      reusedSecret: Boolean(existingSecret),
    });
  } catch (error) {
    console.error(
      "MFA_AUTHENTICATOR_SETUP_START ERROR:",
      error.code || error.message,
    );
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to start authenticator setup",
    });
  }
});

router.post("/setup/verify", async (req, res) => {
  console.log("MFA_AUTHENTICATOR_SETUP_VERIFY received:", {
    uid: req.body.uid,
  });

  const { uid, code } = req.body;

  try {
    if (!uid || !isValidAuthenticatorCode(code)) {
      return res.status(400).json({
        success: false,
        error: "User ID and a valid 6-digit authenticator code are required",
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

    const profile = userDoc.data() || {};
    const securitySettings = normalizeSecuritySettings(profile);
    if (!securitySettings.mfaTempSecret) {
      return res.status(409).json({
        success: false,
        error: "No pending authenticator setup was found",
      });
    }

    if (!verifyTotpCode(securitySettings.mfaTempSecret, code)) {
      return res.status(401).json({
        success: false,
        error: "Invalid authenticator code",
      });
    }

    await userRef.set(
      {
        mfaEnabled: true,
        mfaSecret: securitySettings.mfaTempSecret,
        mfaTempSecret: null,
        securitySettings: {
          ...(profile.securitySettings || {}),
          mfaEnabled: true,
          mfaMethod: "authenticator",
          authenticatorEnabled: true,
          mfaSecret: securitySettings.mfaTempSecret,
          mfaTempSecret: null,
          mfaVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({
      success: true,
      message: "Authenticator MFA enabled",
      securitySettings: {
        mfaEnabled: true,
        mfaMethod: "authenticator",
        authenticatorEnabled: true,
      },
    });
  } catch (error) {
    console.error(
      "MFA_AUTHENTICATOR_SETUP_VERIFY ERROR:",
      error.code || error.message,
    );
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to verify authenticator setup",
    });
  }
});

router.post("/verify", async (req, res) => {
  console.log("MFA_AUTHENTICATOR_VERIFY received:", {
    uid: req.body.uid,
  });

  const { uid, code } = req.body;

  try {
    if (!uid || !isValidAuthenticatorCode(code)) {
      return res.status(400).json({
        success: false,
        error: "User ID and a valid 6-digit authenticator code are required",
      });
    }

    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        error: "User profile not found",
      });
    }

    const profile = userDoc.data() || {};
    const securitySettings = normalizeSecuritySettings(profile);
    if (!securitySettings.authenticatorEnabled || !securitySettings.mfaSecret) {
      return res.status(409).json({
        success: false,
        error: "Authenticator MFA is not enabled for this account",
      });
    }

    if (!verifyTotpCode(securitySettings.mfaSecret, code)) {
      return res.status(401).json({
        success: false,
        error: "Invalid authenticator code",
      });
    }

    return res.status(200).json({
      success: true,
      message: "Authenticator code verified",
    });
  } catch (error) {
    console.error(
      "MFA_AUTHENTICATOR_VERIFY ERROR:",
      error.code || error.message,
    );
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to verify authenticator code",
    });
  }
});

module.exports = router;
