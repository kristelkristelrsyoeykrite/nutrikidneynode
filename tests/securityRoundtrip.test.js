const assert = require("assert");

process.env.ENCRYPTION_KEY =
  process.env.ENCRYPTION_KEY ||
  "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
process.env.LINKING_CODE_HASH_KEY =
  process.env.LINKING_CODE_HASH_KEY ||
  "test-linking-code-hash-key";

const {
  decryptHealthProfile,
  decryptValue,
  encryptHealthProfile,
  encryptValue,
} = require("../utils/encryption");
const {
  normalizeSecuritySettings,
  toPublicSecuritySettings,
} = require("../services/authenticatorMfaService");
const { caregiverLinkCodeDocId } = require("../utils/caregiverLinkCodes");

const encryptedSecret = encryptValue("JBSWY3DPEHPK3PXP");
assert.strictEqual(decryptValue(encryptedSecret), "JBSWY3DPEHPK3PXP");

const encryptedProfile = encryptHealthProfile({
  fullName: "Sensitive Name",
  role: "caregiver",
  activeLinkingCode: "ABC123",
  activeLinkingCodeHash: "v2_hash_can_stay_plain",
});
assert.notStrictEqual(encryptedProfile.fullName, "Sensitive Name");
assert.notStrictEqual(encryptedProfile.activeLinkingCode, "ABC123");

const decryptedProfile = decryptHealthProfile(encryptedProfile);
assert.strictEqual(decryptedProfile.fullName, "Sensitive Name");
assert.strictEqual(decryptedProfile.activeLinkingCode, "ABC123");
assert.strictEqual(decryptedProfile.activeLinkingCodeHash, "v2_hash_can_stay_plain");

const encryptedSecuritySettings = normalizeSecuritySettings({
  mfaEnabled: true,
  securitySettings: {
    mfaMethod: "authenticator",
    authenticatorEnabled: true,
    mfaSecret: encryptedSecret,
    mfaTempSecret: encryptValue("TEMPSECRET234567"),
  },
});
assert.strictEqual(encryptedSecuritySettings.mfaSecret, "JBSWY3DPEHPK3PXP");
assert.strictEqual(encryptedSecuritySettings.mfaTempSecret, "TEMPSECRET234567");
assert.strictEqual(encryptedSecuritySettings.hasAuthenticatorSecret, true);
assert.strictEqual(encryptedSecuritySettings.hasPendingEnrollment, true);

const legacySettings = normalizeSecuritySettings({
  mfaEnabled: true,
  mfaSecret: "LEGACYPLAINTEXT",
});
assert.strictEqual(legacySettings.mfaMethod, "authenticator");
assert.strictEqual(legacySettings.mfaSecret, "LEGACYPLAINTEXT");

const publicSettings = toPublicSecuritySettings(encryptedSecuritySettings);
assert.strictEqual(publicSettings.hasAuthenticatorSecret, true);
assert.strictEqual(Object.prototype.hasOwnProperty.call(publicSettings, "mfaSecret"), false);
assert.strictEqual(Object.prototype.hasOwnProperty.call(publicSettings, "mfaTempSecret"), false);

const hashA = caregiverLinkCodeDocId("ab c123");
const hashB = caregiverLinkCodeDocId("AB C123");
assert.strictEqual(hashA, hashB);
assert.match(hashA, /^v2_[0-9a-f]{64}$/);
assert.strictEqual(hashA.includes("ABC123"), false);

console.log("security roundtrip tests passed");
