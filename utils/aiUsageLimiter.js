const DEFAULT_DAILY_LIMIT = 5;
const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

function dailyAiLimit() {
  const configured = Number(process.env.AI_IMAGE_DAILY_LIMIT);
  return Number.isFinite(configured) && configured > 0
    ? Math.floor(configured)
    : DEFAULT_DAILY_LIMIT;
}

function manilaDateKey(date = new Date()) {
  return new Date(date.getTime() + MANILA_OFFSET_MS)
    .toISOString()
    .slice(0, 10);
}

function usageDocId(uid, feature, dateKey) {
  return [uid, feature, dateKey]
    .map((part) => String(part || "").trim().replace(/[^A-Za-z0-9_.-]/g, "_"))
    .join("_");
}

function normalizeFeature(feature) {
  const normalized = String(feature || "").trim().toLowerCase();
  if (normalized === "food" || normalized === "food_image") return "food_image";
  if (
    normalized === "medication" ||
    normalized === "medication_ocr" ||
    normalized === "prescription_ocr"
  ) {
    return "medication_ocr";
  }
  return normalized;
}

async function getAiUsageStatus({ db, uid, feature, limit = dailyAiLimit() }) {
  const cleanUid = String(uid || "").trim();
  const cleanFeature = normalizeFeature(feature);
  if (!cleanUid) {
    const error = new Error("User ID is required for AI scan usage.");
    error.statusCode = 400;
    throw error;
  }
  if (!cleanFeature) {
    const error = new Error("AI scan feature is required.");
    error.statusCode = 400;
    throw error;
  }

  const date = manilaDateKey();
  const ref = db.collection("aiUsageLimits").doc(usageDocId(cleanUid, cleanFeature, date));
  const snap = await ref.get();
  const count = snap.exists ? Number((snap.data() || {}).count) || 0 : 0;
  return {
    uid: cleanUid,
    feature: cleanFeature,
    date,
    used: count,
    count,
    limit,
    remaining: Math.max(limit - count, 0),
  };
}

async function consumeAiUsage({ db, admin, uid, feature, limit = dailyAiLimit() }) {
  const cleanUid = String(uid || "").trim();
  const cleanFeature = normalizeFeature(feature);
  if (!cleanUid) {
    const error = new Error("User ID is required for AI scan usage.");
    error.statusCode = 400;
    throw error;
  }
  if (!cleanFeature) {
    const error = new Error("AI scan feature is required.");
    error.statusCode = 400;
    throw error;
  }

  const date = manilaDateKey();
  const ref = db.collection("aiUsageLimits").doc(usageDocId(cleanUid, cleanFeature, date));

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const existing = snap.exists ? snap.data() || {} : {};
    const currentCount = Number(existing.count) || 0;

    if (currentCount >= limit) {
      const error = new Error(
        "You have exceeded today's AI scan limit. Please try again tomorrow.",
      );
      error.statusCode = 429;
      error.aiUsage = {
        uid: cleanUid,
        feature: cleanFeature,
        date,
        used: currentCount,
        count: currentCount,
        limit,
        remaining: 0,
      };
      throw error;
    }

    const nextCount = currentCount + 1;
    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.set(
      ref,
      {
        uid: cleanUid,
        feature: cleanFeature,
        date,
        count: nextCount,
        limit,
        updatedAt: now,
        ...(snap.exists ? {} : { createdAt: now }),
      },
      { merge: true },
    );

    return {
      uid: cleanUid,
      feature: cleanFeature,
      date,
      used: nextCount,
      count: nextCount,
      limit,
      remaining: Math.max(limit - nextCount, 0),
    };
  });
}

module.exports = {
  consumeAiUsage,
  getAiUsageStatus,
  manilaDateKey,
  normalizeFeature,
};
