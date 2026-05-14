const { admin, db } = require("../firebase/admin");
const { decryptHealthDocument } = require("./encryption");

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
const GRACE_PERIOD_MS = 5 * 60 * 1000;
const UNDO_WINDOW_MS = 2 * 60 * 1000;

function todayDateKey(nowMs = Date.now()) {
  return new Date(nowMs + MANILA_OFFSET_MS).toISOString().slice(0, 10);
}

function manilaNowParts(nowMs = Date.now()) {
  const manila = new Date(nowMs + MANILA_OFFSET_MS);
  return {
    dateKey: manila.toISOString().slice(0, 10),
    hour: manila.getUTCHours(),
    minute: manila.getUTCMinutes(),
  };
}

function parseClockTime(text) {
  if (typeof text !== "string") return null;
  const match = text.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return { hour, minute, text: `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}` };
}

function manilaDatePartsFromKey(dateKey) {
  const match = String(dateKey || "").match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  return {
    year: Number(match[1]),
    monthIndex: Number(match[2]) - 1,
    day: Number(match[3]),
  };
}

function dateForManilaClock({ dateKey, clock }) {
  const parts = manilaDatePartsFromKey(dateKey);
  if (!parts || !clock) return null;
  // Build a UTC instant that corresponds to local Manila time (UTC+8, no DST).
  return new Date(Date.UTC(parts.year, parts.monthIndex, parts.day, clock.hour - 8, clock.minute, 0, 0));
}

function addDaysToDateKey(dateKey, deltaDays) {
  const parts = manilaDatePartsFromKey(dateKey);
  if (!parts || !Number.isFinite(deltaDays)) return null;
  const baseUtcMs = Date.UTC(parts.year, parts.monthIndex, parts.day, 0, 0, 0, 0);
  const next = new Date(baseUtcMs + deltaDays * 24 * 60 * 60 * 1000);
  return next.toISOString().slice(0, 10);
}

function normalizeMedicationSchedule(medication) {
  const raw = decryptHealthDocument(medication || {});
  const scheduleType = String(raw.scheduleType || raw.schedule_type || "").trim();
  const isActive = raw.isActive !== false && raw.is_active !== false;

  const startDate =
    raw.startDate || raw.start_date || null;
  const endDate =
    raw.endDate || raw.end_date || null;

  const dailyTime = raw.dailyTime || raw.daily_time || raw.start_time || raw.startTime || null;
  const scheduledTimes =
    raw.scheduledTimes || raw.scheduled_times || raw.display_times || raw.time || raw.schedule || [];
  const timesPerDay = raw.timesPerDay ?? raw.times_per_day ?? null;
  const intervalHours = raw.intervalHours ?? raw.interval_hours ?? raw.frequency_value ?? null;

  return {
    scheduleType,
    isActive,
    startDate: typeof startDate === "string" ? startDate : null,
    endDate: typeof endDate === "string" ? endDate : null,
    dailyTime: typeof dailyTime === "string" ? dailyTime : null,
    scheduledTimes: Array.isArray(scheduledTimes) ? scheduledTimes : [],
    timesPerDay: Number.isFinite(Number(timesPerDay)) ? Number(timesPerDay) : null,
    intervalHours: Number.isFinite(Number(intervalHours)) ? Number(intervalHours) : null,
    raw,
  };
}

function isDateKeyInRange(dateKey, startDate, endDate) {
  if (!dateKey) return false;
  if (startDate && String(dateKey) < String(startDate)) return false;
  if (endDate && String(dateKey) > String(endDate)) return false;
  return true;
}

function expectedTimesForDate({ medicationDoc, dateKey }) {
  const normalized = normalizeMedicationSchedule(medicationDoc);
  if (!normalized.isActive) return [];
  if (!isDateKeyInRange(dateKey, normalized.startDate, normalized.endDate)) return [];

  const clocks = [];
  const addClock = (value) => {
    const parsed = parseClockTime(value);
    if (parsed) clocks.push(parsed);
  };

  const scheduleType = normalized.scheduleType.toLowerCase();

  if (scheduleType === "once_daily" || scheduleType === "once daily" || scheduleType === "once") {
    addClock(normalized.dailyTime);
    return uniqueClocks(clocks);
  }

  if (
    scheduleType === "multiple_times_daily" ||
    scheduleType === "multiple times daily" ||
    scheduleType === "multiple"
  ) {
    for (const time of normalized.scheduledTimes) addClock(time);
    return uniqueClocks(clocks);
  }

  if (
    scheduleType === "every_x_hours" ||
    scheduleType === "every x hours" ||
    scheduleType === "interval"
  ) {
    const interval = normalized.intervalHours;
    if (!Number.isFinite(interval) || interval <= 0) return [];
    const startClock = parseClockTime(normalized.dailyTime);
    if (!startClock) return [];

    // Generate within the requested day.
    // Treat the day as Manila-local; generate repeated times wrapping within 24h.
    const startMinutes = startClock.hour * 60 + startClock.minute;
    const stepMinutes = Math.round(interval * 60);
    if (stepMinutes <= 0) return [];

    // Up to 48 to guard against weird configs.
    for (let i = 0; i < 48; i += 1) {
      const minutes = (startMinutes + i * stepMinutes) % (24 * 60);
      const hour = Math.floor(minutes / 60);
      const minute = minutes % 60;
      clocks.push({
        hour,
        minute,
        text: `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`,
      });

      if (i > 0 && (startMinutes + i * stepMinutes) >= 24 * 60) break;
    }
    return uniqueClocks(clocks);
  }

  // Backward-compat: scheduled_times array, else start_time.
  for (const time of normalized.scheduledTimes) addClock(time);
  if (clocks.length === 0) addClock(normalized.dailyTime);
  return uniqueClocks(clocks);
}

function uniqueClocks(clocks) {
  const seen = new Set();
  const out = [];
  for (const clock of clocks) {
    if (!clock || !clock.text) continue;
    if (seen.has(clock.text)) continue;
    seen.add(clock.text);
    out.push(clock);
  }
  out.sort((a, b) => a.hour * 60 + a.minute - (b.hour * 60 + b.minute));
  return out;
}

function doseRecordId({ userId, medicationId, expectedDate, expectedTime }) {
  return `${userId}_${medicationId}_${expectedDate}_${expectedTime}`;
}

function getActiveDoseWindow({ medicationDoc, nowMs = Date.now() }) {
  const now = manilaNowParts(nowMs);
  const clocks = expectedTimesForDate({ medicationDoc, dateKey: now.dateKey });
  if (clocks.length === 0) return null;

  const nowMinutes = now.hour * 60 + now.minute;
  const minutesList = clocks.map((c) => c.hour * 60 + c.minute);

  let activeIndex = -1;
  for (let i = 0; i < minutesList.length; i += 1) {
    if (minutesList[i] <= nowMinutes) activeIndex = i;
    else break;
  }

  let activeClock = null;
  let activeDate = now.dateKey;
  let nextClock = null;
  let nextDate = now.dateKey;

  if (activeIndex === -1) {
    // Before the first scheduled time: active is yesterday's last dose window.
    activeClock = clocks[clocks.length - 1];
    activeDate = addDaysToDateKey(now.dateKey, -1);
    nextClock = clocks[0];
    nextDate = now.dateKey;
  } else {
    activeClock = clocks[activeIndex];
    if (activeIndex < clocks.length - 1) {
      nextClock = clocks[activeIndex + 1];
      nextDate = now.dateKey;
    } else {
      nextClock = clocks[0];
      nextDate = addDaysToDateKey(now.dateKey, 1);
    }
  }

  return {
    active: { expectedDate: activeDate, expectedTime: activeClock.text },
    next: nextClock ? { expectedDate: nextDate, expectedTime: nextClock.text } : null,
    scheduleDate: now.dateKey,
  };
}

async function ensureDoseRecordsForDate({ userId, medicationId, medicationDoc, dateKey }) {
  const expectedDate = dateKey || todayDateKey();
  const clocks = expectedTimesForDate({ medicationDoc, dateKey: expectedDate });
  if (clocks.length === 0) return [];

  const created = [];
  for (const clock of clocks) {
    const expectedTime = clock.text;
    const expectedDateTime = dateForManilaClock({ dateKey: expectedDate, clock });
    const docId = doseRecordId({ userId, medicationId, expectedDate, expectedTime });
    const ref = db.collection("medicationDoseRecords").doc(docId);
    try {
      await ref.create({
        doseRecordId: docId,
        medicationId: String(medicationId),
        userId: String(userId),
        expectedDate,
        expectedTime,
        expectedDateTime: expectedDateTime ? admin.firestore.Timestamp.fromDate(expectedDateTime) : null,
        status: "pending",
        takenAt: null,
        createdAutomatically: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      created.push(docId);
    } catch (e) {
      // ALREADY_EXISTS is expected; never overwrite existing status.
      const code = e?.code || e?.details || "";
      if (String(code).includes("ALREADY_EXISTS") || String(e?.message || "").includes("ALREADY_EXISTS")) {
        continue;
      }
    }
  }
  return created;
}

async function markDoseTaken({ userId, medicationId, expectedDate, expectedTime }) {
  const docId = doseRecordId({ userId, medicationId, expectedDate, expectedTime });
  const ref = db.collection("medicationDoseRecords").doc(docId);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new Error("Dose record not found. Please refresh and try again.");
    }
    const data = snap.data() || {};
    const status = String(data.status || "pending");
    if (status === "taken") {
      return { changed: false, status };
    }
    tx.update(ref, {
      status: "taken",
      takenAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { changed: true, status: "taken" };
  });
  return { docId, ...result };
}

async function undoDoseTaken({ userId, medicationId, expectedDate, expectedTime, nowMs = Date.now() }) {
  const docId = doseRecordId({ userId, medicationId, expectedDate, expectedTime });
  const ref = db.collection("medicationDoseRecords").doc(docId);

  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new Error("Dose record not found. Please refresh and try again.");
    }
    const data = snap.data() || {};
    const status = String(data.status || "pending");
    if (status !== "taken") {
      return { changed: false, status };
    }

    const takenAtDate = data.takenAt?.toDate?.();
    if (!takenAtDate) {
      throw new Error("Cannot undo: missing taken timestamp.");
    }

    tx.update(ref, {
      status: "pending",
      takenAt: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { changed: true, status: "pending" };
  });

  return { docId, ...result };
}

async function markOverdueDosesMissed({ userId, medicationId, expectedDate, nowMs = Date.now() }) {
  const expected = expectedDate || todayDateKey(nowMs);

  const snapshot = await db
    .collection("medicationDoseRecords")
    .where("userId", "==", String(userId))
    .where("medicationId", "==", String(medicationId))
    .where("expectedDate", "==", String(expected))
    .get();

  if (snapshot.empty) return [];

  const changes = [];
  for (const doc of snapshot.docs) {
    const ref = doc.ref;
    const data = doc.data() || {};
    if (String(data.status || "pending") !== "pending") continue;
    const expectedDateTime = data.expectedDateTime?.toDate?.();
    if (!expectedDateTime) continue;
    if (nowMs < expectedDateTime.getTime() + GRACE_PERIOD_MS) continue;

    const updated = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return null;
      const latest = snap.data() || {};
      if (String(latest.status || "pending") !== "pending") return null;
      const latestExpected = latest.expectedDateTime?.toDate?.();
      if (!latestExpected) return null;
      if (nowMs < latestExpected.getTime() + GRACE_PERIOD_MS) return null;

      tx.update(ref, {
        status: "missed",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {
        doseRecordId: latest.doseRecordId || snap.id,
        expectedTime: latest.expectedTime,
        expectedDate: latest.expectedDate,
      };
    });

    if (updated) changes.push(updated);
  }

  return changes;
}

async function getDoseRecordsForDate({ userId, dateKey }) {
  const expectedDate = dateKey || todayDateKey();
  const snapshot = await db
    .collection("medicationDoseRecords")
    .where("userId", "==", String(userId))
    .where("expectedDate", "==", String(expectedDate))
    .get();

  return snapshot.docs.map((d) => ({ id: d.id, ...(d.data() || {}) }));
}

async function getDoseRecord({ userId, medicationId, expectedDate, expectedTime }) {
  const docId = doseRecordId({ userId, medicationId, expectedDate, expectedTime });
  const snap = await db.collection("medicationDoseRecords").doc(docId).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...(snap.data() || {}) };
}

module.exports = {
  GRACE_PERIOD_MS,
  UNDO_WINDOW_MS,
  todayDateKey,
  manilaNowParts,
  parseClockTime,
  expectedTimesForDate,
  getActiveDoseWindow,
  ensureDoseRecordsForDate,
  markDoseTaken,
  undoDoseTaken,
  markOverdueDosesMissed,
  getDoseRecordsForDate,
  getDoseRecord,
  doseRecordId,
};
