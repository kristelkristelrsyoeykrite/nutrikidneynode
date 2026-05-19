const OTPAuth = require("otpauth");
const QRCode = require("qrcode");
const { decryptValue } = require("../utils/encryption");

function readSecret(value) {
  const decrypted = decryptValue(value);
  return String(decrypted || "").trim();
}

function normalizeSecuritySettings(profile = {}) {
  const rawSettings =
    profile.securitySettings && typeof profile.securitySettings === "object"
      ? profile.securitySettings
      : {};

  const fallbackPhone =
    typeof profile.phoneNumber === "string" ? profile.phoneNumber : "";
  const fallbackEmail = typeof profile.email === "string" ? profile.email : "";
  
  const authenticatorSecret = readSecret(rawSettings.mfaSecret || profile.mfaSecret || "");
  const tempSecret = readSecret(rawSettings.mfaTempSecret || profile.mfaTempSecret || "");
  
  const storedMethod = String(rawSettings.mfaMethod || "").trim();
  const mfaEnabledFlag = rawSettings.mfaEnabled === true || profile.mfaEnabled === true;

  // Resolve the active method based on explicit enabled flag and configuration
  let resolvedMethod = "none";
  if (mfaEnabledFlag) {
    if (storedMethod === "authenticator") {
      resolvedMethod = storedMethod;
    } else if (authenticatorSecret) {
      // Fallback for older records where mfaEnabled was true but method wasn't set
      resolvedMethod = "authenticator";
    }
  }

  // MFA is only truly enabled if the flag is true AND we have a valid method
  const mfaEnabled = mfaEnabledFlag && resolvedMethod !== "none";

  const authenticatorEnabled = mfaEnabled && resolvedMethod === "authenticator";

  return {
    mfaEnabled,
    mfaMethod: resolvedMethod,
    authenticatorEnabled,
    emailMfaEnabled: false,
    hasAuthenticatorSecret: Boolean(authenticatorSecret),
    hasPendingEnrollment: Boolean(tempSecret),
    mfaSecret: authenticatorSecret,
    mfaTempSecret: tempSecret,
    mfaPhoneNumber: String(
      rawSettings.mfaPhoneNumber || fallbackPhone || "",
    ).trim(),
    mfaEmail: String(rawSettings.mfaEmail || fallbackEmail || "").trim(),
    emailChallengeCodeHash: String(rawSettings.emailChallengeCodeHash || "").trim(),
    emailChallengeLinkHash: String(rawSettings.emailChallengeLinkHash || "").trim(),
    emailChallengeExpiresAt: rawSettings.emailChallengeExpiresAt || null,
    emailChallengePurpose: String(rawSettings.emailChallengePurpose || "").trim(),
    emailChallengeLinkVerified: rawSettings.emailChallengeLinkVerified === true,
  };
}

function toPublicSecuritySettings(securitySettings = {}) {
  return {
    mfaEnabled: securitySettings.mfaEnabled === true,
    mfaMethod: securitySettings.mfaMethod || "none",
    authenticatorEnabled: securitySettings.authenticatorEnabled === true,
    emailMfaEnabled: securitySettings.emailMfaEnabled === true,
    hasAuthenticatorSecret: securitySettings.hasAuthenticatorSecret === true,
    hasPendingEnrollment: securitySettings.hasPendingEnrollment === true,
    mfaPhoneNumber: securitySettings.mfaPhoneNumber || "",
    mfaEmail: securitySettings.mfaEmail || "",
    emailChallengeExpiresAt: securitySettings.emailChallengeExpiresAt || null,
    emailChallengePurpose: securitySettings.emailChallengePurpose || "",
    emailChallengeLinkVerified:
      securitySettings.emailChallengeLinkVerified === true,
  };
}

function buildTotp(secret, { label, issuer = "NutriKidney" } = {}) {
  return new OTPAuth.TOTP({
    issuer,
    label,
    algorithm: "SHA1",
    digits: 6,
    period: 30,
    secret: OTPAuth.Secret.fromBase32(secret),
  });
}

function generateTotpSecret() {
  return new OTPAuth.Secret({ size: 20 }).base32;
}

function parseCode(code) {
  return String(code || "").replace(/\s+/g, "");
}

function isValidAuthenticatorCode(code) {
  return /^\d{6}$/.test(parseCode(code));
}

function verifyTotpCode(secret, code) {
  if (!secret || !isValidAuthenticatorCode(code)) {
    return false;
  }

  const totp = buildTotp(secret);
  const delta = totp.validate({
    token: parseCode(code),
    window: 1,
  });
  return delta !== null;
}

async function buildAuthenticatorEnrollmentPayload({
  uid,
  email,
  profile = {},
  authUser = null,
}) {
  const accountEmail =
    String(email || profile.email || authUser?.email || "").trim();
  const label = accountEmail || uid;
  const tempSecret = generateTotpSecret();
  const totp = buildTotp(tempSecret, { label });
  const otpauthUrl = totp.toString();
  const qrCodeDataUrl = await QRCode.toDataURL(otpauthUrl);

  return {
    tempSecret,
    otpauthUrl,
    qrCodeDataUrl,
  };
}

module.exports = {
  buildAuthenticatorEnrollmentPayload,
  buildTotp,
  generateTotpSecret,
  isValidAuthenticatorCode,
  normalizeSecuritySettings,
  toPublicSecuritySettings,
  verifyTotpCode,
};
