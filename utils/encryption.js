const crypto = require("crypto");

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH_BYTES = 12;
const KEY_HEX_LENGTH = 64;

const SENSITIVE_HEALTH_FIELDS = [
  "childName",
  "childFullName",
  "child_name",
  "fullName",
  "displayName",
  "dateOfBirth",
  "date_of_birth",
  "medications",
  "name",
  "medicationName",
  "medication_name",
  "medicineName",
  "dosage",
  "dose",
  "instructions",
  "rawOcrText",
  "raw_ocr_text",
  "allergies",
  "labResults",
  "lab_results",
  "testName",
  "creatinine",
  "potassium",
  "phosphorus",
  "phosphorus_status",
  "sodium",
  "sodium_status",
  "calcium",
  "egfr",
  "eGFR",
  "prescriptions",
  "prescription",
  "diagnosisDetails",
  "diagnosis_details",
  "doctorNotes",
  "doctor_notes",
  "caregiverLinkCode",
  "activeLinkingCode",
];

const PLAIN_HEALTH_DOCUMENT_FIELDS = new Set([
  "id",
  "uid",
  "userId",
  "firebaseUid",
  "authUid",
  "profileUserId",
  "childProfileId",
  "child_profile_id",
  "caregiverUserId",
  "medicalProfileId",
  "labResultId",
  "nutritionTargetId",
  "baselineNutritionTargetId",
  "phase2DecisionSupportId",
  "medicationId",
  "medicationIds",
  "role",
  "userRole",
  "source",
  "status",
  "createdAt",
  "updatedAt",
  "generatedAt",
  "regeneratedAt",
  "archivedAt",
  "date",
  "resultDate",
]);

function getEncryptionKey() {
  let keyHex = process.env.ENCRYPTION_KEY;
  if (typeof keyHex === "string") {
    keyHex = keyHex.trim();
    if (
      (keyHex.startsWith('"') && keyHex.endsWith('"')) ||
      (keyHex.startsWith("'") && keyHex.endsWith("'"))
    ) {
      keyHex = keyHex.slice(1, -1).trim();
    }
  }

  if (!keyHex || !/^[0-9a-fA-F]+$/.test(keyHex) || keyHex.length !== KEY_HEX_LENGTH) {
    throw new Error("ENCRYPTION_KEY must be a 64-character hex string (32 bytes).");
  }

  return Buffer.from(keyHex, "hex");
}

function stringifyValue(value) {
  return typeof value === "string" ? value : JSON.stringify(value);
}

function encryptValue(value) {
  if (value === null || value === undefined) {
    return value;
  }

  if (typeof value === "object" && value.encrypted === true) {
    return value;
  }

  const iv = crypto.randomBytes(IV_LENGTH_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, getEncryptionKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(stringifyValue(value), "utf8"),
    cipher.final(),
  ]);
  const authTag = cipher.getAuthTag();

  return {
    encrypted: true,
    algorithm: ALGORITHM,
    iv: iv.toString("hex"),
    authTag: authTag.toString("hex"),
    data: encrypted.toString("hex"),
  };
}

function decryptValue(encryptedObject) {
  if (encryptedObject === null || encryptedObject === undefined) {
    return encryptedObject;
  }

  if (typeof encryptedObject !== "object" || encryptedObject.encrypted !== true) {
    return encryptedObject;
  }

  if (encryptedObject.algorithm !== ALGORITHM) {
    throw new Error(`Unsupported encryption algorithm: ${encryptedObject.algorithm}`);
  }

  const decipher = crypto.createDecipheriv(
    ALGORITHM,
    getEncryptionKey(),
    Buffer.from(encryptedObject.iv, "hex")
  );
  decipher.setAuthTag(Buffer.from(encryptedObject.authTag, "hex"));

  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(encryptedObject.data, "hex")),
    decipher.final(),
  ]).toString("utf8");

  try {
    return JSON.parse(decrypted);
  } catch (_) {
    return decrypted;
  }
}

function copyWithSensitiveFields(profileData, transform) {
  if (!profileData || typeof profileData !== "object") {
    return profileData;
  }

  const nextProfile = { ...profileData };

  for (const field of SENSITIVE_HEALTH_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(nextProfile, field)) {
      nextProfile[field] = transform(nextProfile[field]);
    }
  }

  return nextProfile;
}

function encryptHealthProfile(profileData) {
  return copyWithSensitiveFields(profileData, encryptValue);
}

function decryptHealthProfile(profileData) {
  return copyWithSensitiveFields(profileData, decryptValue);
}

function encryptHealthDocument(documentData) {
  if (!documentData || typeof documentData !== "object") {
    return documentData;
  }

  const encryptedDocument = { ...documentData };
  for (const [field, value] of Object.entries(encryptedDocument)) {
    if (!PLAIN_HEALTH_DOCUMENT_FIELDS.has(field)) {
      encryptedDocument[field] = encryptValue(value);
    }
  }
  return encryptedDocument;
}

function decryptHealthDocument(documentData) {
  if (!documentData || typeof documentData !== "object") {
    return documentData;
  }

  const decryptedDocument = { ...documentData };
  for (const [field, value] of Object.entries(decryptedDocument)) {
    decryptedDocument[field] = decryptValue(value);
  }
  return decryptedDocument;
}

module.exports = {
  ALGORITHM,
  SENSITIVE_HEALTH_FIELDS,
  encryptValue,
  decryptValue,
  encryptHealthProfile,
  decryptHealthProfile,
  encryptHealthDocument,
  decryptHealthDocument,
};
