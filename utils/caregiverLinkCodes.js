const crypto = require("crypto");

function getLinkingCodeHashKey() {
  const configuredKey = process.env.LINKING_CODE_HASH_KEY || process.env.ENCRYPTION_KEY;
  if (!configuredKey) {
    throw new Error("LINKING_CODE_HASH_KEY or ENCRYPTION_KEY is required for caregiver link codes.");
  }
  return String(configuredKey).trim().replace(/^['"]|['"]$/g, "");
}

function caregiverLinkCodeDocId(code) {
  const normalizedCode = String(code || "").trim().toUpperCase();
  const digest = crypto
    .createHmac("sha256", getLinkingCodeHashKey())
    .update(normalizedCode)
    .digest("hex");
  return `v2_${digest}`;
}

module.exports = {
  caregiverLinkCodeDocId,
  getLinkingCodeHashKey,
};
