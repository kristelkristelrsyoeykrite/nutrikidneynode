const assert = require("assert");

process.env.ENCRYPTION_KEY =
  process.env.ENCRYPTION_KEY ||
  "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

const {
  decryptHealthDocument,
  encryptHealthDocument,
} = require("../utils/encryption");

function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function isFluidRestrictionEnabled(value) {
  const normalized = String(value ?? "").trim().toLowerCase();
  return ["yes", "true", "enabled", "restricted", "fluid_restricted"].includes(
    normalized,
  );
}

const encryptedMedicalProfile = encryptHealthDocument({
  fluidRestrictionStatus: "yes",
  fluid_restriction_status: "yes",
});
const encryptedTargets = encryptHealthDocument({
  dailyFluidLimitMl: 1200,
  daily_fluid_limit_ml: 1200,
});

assert.strictEqual(
  isFluidRestrictionEnabled(encryptedMedicalProfile.fluidRestrictionStatus),
  false,
  "raw encrypted fluidRestrictionStatus should reproduce the old disabled-read bug",
);
assert.strictEqual(
  numberOrNull(encryptedTargets.dailyFluidLimitMl),
  null,
  "raw encrypted fluid limit should reproduce the old missing-limit bug",
);

const medicalProfile = decryptHealthDocument(encryptedMedicalProfile);
const targets = decryptHealthDocument(encryptedTargets);

assert.strictEqual(isFluidRestrictionEnabled(medicalProfile.fluidRestrictionStatus), true);
assert.strictEqual(numberOrNull(targets.dailyFluidLimitMl), 1200);

console.log("fluid restriction encryption tests passed");
