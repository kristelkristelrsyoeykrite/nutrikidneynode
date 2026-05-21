const { decryptHealthProfile } = require("../utils/encryption");

const AWARDS = {
  seven_day_streak: {
    title: "7-Day Streak",
    description: "Logged meals and hydration daily for 7 days.",
  },
  fourteen_day_streak: {
    title: "14-Day Streak",
    description: "Logged meals and hydration daily for 14 days.",
  },
  hydration_hero: {
    title: "Hydration Hero",
    description: "Met the water goal 10 times.",
  },
  balanced_week: {
    title: "Balanced Week",
    description: "Stayed within the app's recommended nutrition ranges for 7 days.",
  },
};

const FOOD_COLOR_KEYWORDS = [
  ["red", ["apple", "strawberry", "tomato", "cherry", "beet", "watermelon"]],
  ["orange", ["orange", "carrot", "pumpkin", "sweet potato", "papaya"]],
  ["yellow", ["banana", "corn", "pineapple", "mango", "egg"]],
  ["green", ["spinach", "broccoli", "lettuce", "kale", "cucumber", "peas"]],
  ["purple", ["eggplant", "grape", "purple cabbage", "ube", "plum"]],
  ["white", ["rice", "bread", "cauliflower", "tofu", "potato", "milk"]],
  ["brown", ["beans", "lentil", "oat", "whole wheat", "mushroom", "chicken"]],
];

function addDays(dateString, days) {
  const date = new Date(`${dateString}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function todayDateKey() {
  const manilaOffsetMs = 8 * 60 * 60 * 1000;
  return new Date(Date.now() + manilaOffsetMs).toISOString().slice(0, 10);
}

function numberOrZero(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function textValue(...values) {
  for (const value of values) {
    const text = String(value || "").trim();
    if (text) return text;
  }
  return "";
}

function leaderboardDisplayName(user = {}) {
  return (
    textValue(
      user.childFullName,
      user.fullName,
      user.displayName,
      user.name,
    ) || "NutriKidney user"
  );
}

function leaderboardInitials(displayName) {
  return (
    String(displayName || "NK")
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase())
      .join("") || "NK"
  );
}

function normalizeMealType(value) {
  const text = String(value || "").trim().toLowerCase();
  if (["morning", "breakfast", "breakfast / morning meal"].some((item) => text.includes(item))) {
    return "morning";
  }
  if (text.includes("lunch")) return "lunch";
  if (["dinner", "evening", "supper"].some((item) => text.includes(item))) {
    return "dinner";
  }
  return text;
}

function extractFoodColors(log = {}) {
  const raw = log.raw && typeof log.raw === "object" ? log.raw : {};
  const explicit = raw.foodColor || raw.food_color || log.foodColor || log.food_color;
  if (explicit) return [String(explicit).trim().toLowerCase()].filter(Boolean);

  const text = [
    log.name,
    log.foodName,
    log.food_name,
    raw.name,
    raw.food_name,
    raw.foodName,
    raw.display_food_name,
  ].filter(Boolean).join(" ").toLowerCase();

  return FOOD_COLOR_KEYWORDS
    .filter(([, keywords]) => keywords.some((keyword) => text.includes(keyword)))
    .map(([color]) => color);
}

function nutritionTargetValue(targets = {}, keys = []) {
  for (const key of keys) {
    const value = numberOrZero(targets[key]);
    if (value > 0) return value;
  }
  return 0;
}

function nutrientsInRange(totals = {}, targets = {}) {
  const sodiumLimit = nutritionTargetValue(targets, [
    "sodium",
    "sodiumLimitMg",
    "sodium_limit_mg",
    "maxSodiumMg",
  ]);
  const potassiumLimit = nutritionTargetValue(targets, [
    "potassium",
    "potassiumLimitMg",
    "potassium_limit_mg",
    "maxPotassiumMg",
  ]);
  const phosphorusLimit = nutritionTargetValue(targets, [
    "phosphorus",
    "phosphorusLimitMg",
    "phosphorus_limit_mg",
  ]);
  const proteinMax = nutritionTargetValue(targets, [
    "proteinMax",
    "protein_max",
    "maxProteinG",
  ]);

  const checks = [
    sodiumLimit <= 0 || numberOrZero(totals.sodium) <= sodiumLimit,
    potassiumLimit <= 0 || numberOrZero(totals.potassium) <= potassiumLimit,
    phosphorusLimit <= 0 || numberOrZero(totals.phosphorus) <= phosphorusLimit,
    proteinMax <= 0 || numberOrZero(totals.protein) <= proteinMax,
  ];
  return checks.every(Boolean);
}

async function getUserTargets(db, userId) {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) return {};
  const user = userDoc.data() || {};
  if (!user.baselineNutritionTargetId) return {};
  const targetDoc = await db
    .collection("nutritionTargets")
    .doc(user.baselineNutritionTargetId)
    .get();
  return targetDoc.exists ? targetDoc.data() || {} : {};
}

async function buildDailyStatus({ db, userId, date }) {
  const userSnapshot = await db
    .collection("foodLogs")
    .where("userId", "==", userId)
    .where("date", "==", date)
    .get();
  const childProfileSnapshot = await db
    .collection("foodLogs")
    .where("childProfileId", "==", userId)
    .where("date", "==", date)
    .get();
  const logs = new Map();
  userSnapshot.docs.forEach((doc) => logs.set(doc.id, doc));
  childProfileSnapshot.docs.forEach((doc) => logs.set(doc.id, doc));

  const totals = {
    calories: 0,
    protein: 0,
    carbohydrate: 0,
    fat: 0,
    sodium: 0,
    potassium: 0,
    phosphorus: 0,
  };
  const foodColors = new Set();
  let hasMorningMeal = false;
  let hasLunchMeal = false;
  let hasDinnerMeal = false;
  let hasHydrationLog = false;
  let waterMl = 0;
  let mealLogCount = 0;

  logs.forEach((doc) => {
    const log = doc.data() || {};
    if (log.deletedAt) return;
    mealLogCount += 1;
    const mealType = normalizeMealType(log.mealType || log.meal_type);
    hasMorningMeal = hasMorningMeal || mealType === "morning";
    hasLunchMeal = hasLunchMeal || mealType === "lunch";
    hasDinnerMeal = hasDinnerMeal || mealType === "dinner";

    const logWaterMl = numberOrZero(log.waterMl ?? log.water_ml ?? log.fluid_ml);
    waterMl += logWaterMl;
    hasHydrationLog = hasHydrationLog || logWaterMl > 0;
    extractFoodColors(log).forEach((color) => foodColors.add(color));

    const nutrients = log.finalNutrients || log.final_nutrients || log;
    Object.keys(totals).forEach((key) => {
      totals[key] += numberOrZero(nutrients[key]);
    });
  });

  const targets = await getUserTargets(db, userId);
  const waterGoalMl = nutritionTargetValue(targets, [
    "fluid_limit_ml",
    "fluidLimitMl",
    "waterGoalMl",
    "water_goal_ml",
  ]);
  const metWaterGoal = waterGoalMl > 0 && waterMl >= waterGoalMl;
  const isCompleteDay =
    hasMorningMeal && hasLunchMeal && hasDinnerMeal && hasHydrationLog;

  return {
    date,
    hasMorningMeal,
    hasLunchMeal,
    hasDinnerMeal,
    hasHydrationLog,
    metWaterGoal,
    waterMl,
    waterGoalMl,
    nutrientsInRange: mealLogCount > 0 && nutrientsInRange(totals, targets),
    foodColors: [...foodColors].sort(),
    isCompleteDay,
    mealLogCount,
    points:
      (hasMorningMeal ? 5 : 0) +
      (hasLunchMeal ? 5 : 0) +
      (hasDinnerMeal ? 5 : 0) +
      (hasHydrationLog ? 5 : 0) +
      (isCompleteDay ? 20 : 0) +
      (metWaterGoal ? 10 : 0) +
      (mealLogCount > 0 && nutrientsInRange(totals, targets) ? 15 : 0),
  };
}

async function countBackCompleteDays(db, userId, date) {
  let currentDate = date;
  let count = 0;
  while (count < 365) {
    const doc = await db
      .collection("users")
      .doc(userId)
      .collection("dailyLogStatus")
      .doc(currentDate)
      .get();
    const storedStatus = doc.exists ? doc.data() : null;
    const dayStatus = storedStatus?.isCompleteDay === true
      ? storedStatus
      : await buildDailyStatus({ db, userId, date: currentDate });
    if (dayStatus?.isCompleteDay !== true) break;
    count += 1;
    currentDate = addDays(currentDate, -1);
  }
  return count;
}

async function unlockAward({ admin, db, userId, awardId, unlockedAwards }) {
  if (unlockedAwards.includes(awardId)) return;
  const award = AWARDS[awardId];
  if (!award) return;
  unlockedAwards.push(awardId);
  await db
    .collection("users")
    .doc(userId)
    .collection("awards")
    .doc(awardId)
    .set({
      awardId,
      ...award,
      unlockedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}

async function recomputeGamificationForDate({ admin, db, userId, date }) {
  const userRef = db.collection("users").doc(userId);
  const statusRef = userRef.collection("dailyLogStatus").doc(date);
  const status = await buildDailyStatus({ db, userId, date });
  await statusRef.set(
    {
      ...status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const statusSnapshot = await userRef.collection("dailyLogStatus").limit(400).get();
  const statuses = statusSnapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => String(a.date || a.id).localeCompare(String(b.date || b.id)));

  const currentStreak = await countBackCompleteDays(db, userId, date);
  const waterGoalMetCount = statuses.filter((day) => day.metWaterGoal === true).length;
  const points = statuses.reduce((sum, day) => sum + numberOrZero(day.points), 0);
  const previousStatusDoc = await userRef.collection("gamification").doc("status").get();
  const previous = previousStatusDoc.exists ? previousStatusDoc.data() || {} : {};
  const unlockedAwards = Array.isArray(previous.unlockedAwards)
    ? [...previous.unlockedAwards]
    : [];

  if (currentStreak >= 7) await unlockAward({ admin, db, userId, awardId: "seven_day_streak", unlockedAwards });
  if (currentStreak >= 14) await unlockAward({ admin, db, userId, awardId: "fourteen_day_streak", unlockedAwards });
  if (waterGoalMetCount >= 10) await unlockAward({ admin, db, userId, awardId: "hydration_hero", unlockedAwards });

  const lastSeven = statuses.slice(-7);
  const nutrientsInRangeFor7Days =
    lastSeven.length === 7 && lastSeven.every((day) => day.nutrientsInRange === true);
  if (nutrientsInRangeFor7Days) {
    await unlockAward({ admin, db, userId, awardId: "balanced_week", unlockedAwards });
  }

  const longestStreak = Math.max(numberOrZero(previous.longestStreak), currentStreak);
  const gamificationStatus = {
    currentStreak,
    displayStreak: currentStreak,
    longestStreak,
    lastCompleteLogDate: status.isCompleteDay ? date : previous.lastCompleteLogDate || null,
    waterGoalMetCount,
    unlockedAwards,
    points,
    leaderboardOptIn: previous.leaderboardOptIn === true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await userRef.collection("gamification").doc("status").set(gamificationStatus, { merge: true });
  return { dailyStatus: status, gamificationStatus };
}

async function getGamificationSummary({ db, userId, date }) {
  const userRef = db.collection("users").doc(userId);
  const statusDoc = await userRef.collection("gamification").doc("status").get();
  const dailyDoc = await userRef.collection("dailyLogStatus").doc(date).get();
  const awardsSnapshot = await userRef.collection("awards").get();

  return {
    status: statusDoc.exists ? statusDoc.data() : {},
    today: dailyDoc.exists ? dailyDoc.data() : {},
    awards: awardsSnapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    awardDefinitions: AWARDS,
  };
}

async function getLeaderboard({ admin, db, limit = 10 }) {
  const usersSnapshot = await db.collection("users").limit(500).get();
  const entries = [];
  const today = todayDateKey();
  const weekStart = addDays(today, -6);

  for (const userDoc of usersSnapshot.docs) {
    const user = decryptHealthProfile(userDoc.data() || {});
    const statusDoc = await userDoc.ref.collection("gamification").doc("status").get();
    const previousStatus = statusDoc.exists ? statusDoc.data() || {} : {};
    if (previousStatus.leaderboardOptIn !== true) continue;

    const recomputed = admin
      ? await recomputeGamificationForDate({
          admin,
          db,
          userId: userDoc.id,
          date: today,
        })
      : null;
    const status = recomputed?.gamificationStatus || previousStatus;

    const dailySnapshot = await userDoc.ref.collection("dailyLogStatus").get();
    const weeklyPoints = dailySnapshot.docs
      .map((doc) => doc.data() || {})
      .filter((day) => day.date >= weekStart && day.date <= today)
      .reduce((sum, day) => sum + numberOrZero(day.points), 0);

    const displayName = leaderboardDisplayName(user);
    entries.push({
      userId: userDoc.id,
      displayName,
      avatarInitials: leaderboardInitials(displayName),
      weeklyPoints,
      currentStreak: numberOrZero(status.displayStreak || status.currentStreak),
      badges: Array.isArray(status.unlockedAwards) ? status.unlockedAwards : [],
    });
  }

  return entries
    .sort((a, b) => b.weeklyPoints - a.weeklyPoints || b.currentStreak - a.currentStreak)
    .slice(0, limit);
}

module.exports = {
  AWARDS,
  recomputeGamificationForDate,
  getGamificationSummary,
  getLeaderboard,
};
