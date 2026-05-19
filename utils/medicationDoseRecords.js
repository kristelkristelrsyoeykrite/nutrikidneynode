const { admin, db } = require("../firebase/admin");
const { decryptHealthDocument } = require("./encryption");

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const UNDO_WINDOW_MS = 2 * 60 * 1000;

function todayDateKey(nowMs = Date.now()) {
  return dateKeyFromUtcMs(nowMs);
}

function dateKeyFromUtcMs(utcMs) {
  return new Date(utcMs + MANILA_OFFSET_MS).toISOString().slice(0, 10);
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

function manilaDateKeyToUtcStartMs(dateKey) {
  const parts = manilaDatePartsFromKey(dateKey);
  if (!parts) return null;
  return Date.UTC(parts.year, parts.monthIndex, parts.day, -8, 0, 0, 0);
}

function addDaysToDateKey(dateKey, deltaDays) {
  const startMs = manilaDateKeyToUtcStartMs(dateKey);
  if (!Number.isFinite(startMs)) return null;
  return dateKeyFromUtcMs(startMs + deltaDays * DAY_MS);
}

function parseClockTime(text) {
  if (typeof text !== "string") return null;
  const match = text.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return {
    hour,
    minute,
    text: `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`,
  };
}

function minutesToClock(totalMinutes) {
  const minutesInDay = 24 * 60;
  const normalized = ((Math.round(totalMinutes) % minutesInDay) + minutesInDay) % minutesInDay;
  const hour = Math.floor(normalized / 60);
  const minute = normalized % 60;
  return {
    hour,
    minute,
    text: `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`,
  };
}

function clockToMinutes(clock) {
  return clock.hour * 60 + clock.minute;
}

function dateForManilaClock({ dateKey, clock }) {
  const dayStartMs = manilaDateKeyToUtcStartMs(dateKey);
  if (!Number.isFinite(dayStartMs) || !clock) return null;
  return new Date(dayStartMs + clockToMinutes(clock) * 60 * 1000);
}

function normalizeMedicationSchedule(medication) {
  const raw = decryptHealthDocument(medication || {});
  const scheduleType = String(raw.scheduleType || raw.schedule_type || "").trim();
  const frequencyType = String(raw.frequency_type || raw.frequencyType || "").trim();
  const frequencyText = String(raw.frequency || raw.display_freq || "").trim();
  const isActive = raw.isActive !== false && raw.is_active !== false;

  const startDate = raw.startDate || raw.start_date || null;
  const endDate = raw.endDate || raw.end_date || null;
  const dailyTime = raw.dailyTime || raw.daily_time || raw.start_time || raw.startTime || null;
  const scheduledTimes =
    raw.scheduledTimes || raw.scheduled_times || raw.display_times || raw.time || raw.schedule || [];
  const timesPerDay = raw.timesPerDay ?? raw.times_per_day ?? raw.frequency_value ?? null;
  const intervalHours = raw.intervalHours ?? raw.interval_hours ?? raw.frequency_value ?? null;

  return {
    scheduleType,
    frequencyType,
    frequencyText,
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

function frequencyCountFromText(text) {
  const normalized = String(text || "").toLowerCase();
  const match = normalized.match(/(\d+)\s*(?:x|times?)\s*(?:per|a)?\s*day|(\d+)\s*daily/);
  const value = Number(match?.[1] || match?.[2]);
  return Number.isFinite(value) && value > 0 ? value : null;
}

function scheduleKind(normalized) {
  const scheduleType = normalized.scheduleType.toLowerCase();
  const frequencyType = normalized.frequencyType.toLowerCase();
  const frequencyText = normalized.frequencyText.toLowerCase();

  if (
    scheduleType === "every_x_hours" ||
    scheduleType === "every x hours" ||
    scheduleType === "interval" ||
    frequencyType === "interval" ||
    frequencyType === "every_x_hours" ||
    frequencyText.includes("hour")
  ) {
    return "interval";
  }

  if (
    scheduleType === "once_daily" ||
    scheduleType === "once daily" ||
    scheduleType === "once"
  ) {
    return "once";
  }

  if (
    scheduleType === "multiple_times_daily" ||
    scheduleType === "multiple times daily" ||
    scheduleType === "multiple" ||
    frequencyType === "times_per_day" ||
    frequencyType === "fixed_frequency"
  ) {
    return "frequency";
  }

  if (normalized.scheduledTimes.length > 0) return "fixed_times";
  if (normalized.timesPerDay && normalized.timesPerDay > 1) return "frequency";
  return "once";
}

function scheduleClocksForDate({ medicationDoc, dateKey }) {
  const normalized = normalizeMedicationSchedule(medicationDoc);
  if (!normalized.isActive) return [];
  if (!isDateKeyInRange(dateKey, normalized.startDate, normalized.endDate)) return [];

  const kind = scheduleKind(normalized);
  const clocks = [];
  const addClock = (value) => {
    const parsed = parseClockTime(value);
    if (parsed) clocks.push(parsed);
  };

  if (kind === "interval") {
    const interval = normalized.intervalHours;
    const startClock = parseClockTime(normalized.dailyTime);
    if (!startClock || !Number.isFinite(interval) || interval <= 0) return [];
    const stepMinutes = Math.round(interval * 60);
    for (let offset = 0; offset < 24 * 60; offset += stepMinutes) {
      clocks.push(minutesToClock(clockToMinutes(startClock) + offset));
      if (stepMinutes <= 0 || clocks.length >= 48) break;
    }
    return uniqueClocks(clocks);
  }

  if (kind === "frequency") {
    const explicitCount = normalized.timesPerDay || frequencyCountFromText(normalized.frequencyText);
    const count = Math.max(1, Math.floor(Number(explicitCount) || 1));
    const startClock = parseClockTime(normalized.dailyTime);
    if (!startClock) return [];
    const stepMinutes = (24 * 60) / count;
    for (let i = 0; i < count; i += 1) {
      clocks.push(minutesToClock(clockToMinutes(startClock) + i * stepMinutes));
    }
    return uniqueClocks(clocks);
  }

  if (kind === "fixed_times") {
    for (const time of normalized.scheduledTimes) addClock(time);
    return uniqueClocks(clocks);
  }

  addClock(normalized.dailyTime);
  if (clocks.length === 0) {
    for (const time of normalized.scheduledTimes) addClock(time);
  }
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
  out.sort((a, b) => clockToMinutes(a) - clockToMinutes(b));
  return out;
}

function windowsForDateRange({ medicationDoc, startDateKey, days }) {
  const starts = [];
  for (let offset = 0; offset < days; offset += 1) {
    const dateKey = addDaysToDateKey(startDateKey, offset);
    const clocks = scheduleClocksForDate({ medicationDoc, dateKey });
    for (const clock of clocks) {
      const startDate = dateForManilaClock({ dateKey, clock });
      if (!startDate) continue;
      starts.push({
        startDateKey: dateKey,
        startTime: clock.text,
        startMs: startDate.getTime(),
      });
    }
  }

  const uniqueStarts = Array.from(
    new Map(starts.map((start) => [`${start.startDateKey}_${start.startTime}`, start])).values(),
  ).sort((a, b) => a.startMs - b.startMs);

  return uniqueStarts.slice(0, -1).map((start, index) => {
    const end = uniqueStarts[index + 1];
    return {
      id: `${start.startDateKey}_${start.startTime}`,
      expectedDate: start.startDateKey,
      expectedTime: start.startTime,
      startMs: start.startMs,
      endMs: end.startMs,
      startAt: new Date(start.startMs),
      endAt: new Date(end.startMs),
    };
  });
}

function doseWindowsAround({ medicationDoc, nowMs = Date.now(), beforeDays = 2, afterDays = 2 }) {
  const today = todayDateKey(nowMs);
  const startDateKey = addDaysToDateKey(today, -beforeDays);
  return windowsForDateRange({
    medicationDoc,
    startDateKey,
    days: beforeDays + afterDays + 2,
  });
}

function doseRecordId({ userId, medicationId, expectedDate, expectedTime }) {
  return `${userId}_${medicationId}_${expectedDate}_${expectedTime}`;
}

function notificationWindowId({ userId, medicationId, expectedDate, expectedTime }) {
  return `${userId}_missed_medication_${medicationId}_${expectedDate}_${expectedTime}`;
}

function getActiveDoseWindow({ medicationDoc, nowMs = Date.now() }) {
  return doseWindowsAround({ medicationDoc, nowMs }).find(
    (window) => window.startMs <= nowMs && nowMs < window.endMs,
  ) || null;
}

function getTodayDoseWindows({ medicationDoc, nowMs = Date.now() }) {
  const today = todayDateKey(nowMs);
  return doseWindowsAround({ medicationDoc, nowMs }).filter(
    (window) =>
      window.expectedDate === today || dateKeyFromUtcMs(window.endMs) === today,
  );
}

function timestampMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value._seconds === "number") return value._seconds * 1000;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function logBelongsToWindow(log = {}, window) {
  const takenMs = timestampMs(log.takenAt || log.createdAt);
  if (!takenMs) return true;
  return takenMs >= window.startMs && takenMs < window.endMs;
}

async function getWindowLog({ userId, medicationId, window }) {
  const id = doseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });
  const snap = await db.collection("medicationIntakeLogs").doc(id).get();
  if (!snap.exists) return null;
  const log = { id: snap.id, ...(snap.data() || {}) };
  return logBelongsToWindow(log, window) ? log : null;
}

async function resolveDoseWindowStatus({ userId, medicationId, window, nowMs = Date.now() }) {
  const log = await getWindowLog({ userId, medicationId, window });
  if (log) return { status: "taken", log };
  if (nowMs >= window.endMs) return { status: "missed", log: null };
  if (nowMs >= window.startMs) return { status: "due", log: null };
  return { status: "upcoming", log: null };
}

async function resolveMedicationDoseStatus({ userId, medicationId, medicationDoc, nowMs = Date.now() }) {
  const activeWindow = getActiveDoseWindow({ medicationDoc, nowMs });
  const todayWindows = getTodayDoseWindows({ medicationDoc, nowMs });
  const takenTimesToday = [];
  let missedCountToday = 0;
  let dueNow = 0;

  const resolvedWindows = [];
  for (const window of todayWindows) {
    const resolved = await resolveDoseWindowStatus({ userId, medicationId, window, nowMs });
    if (resolved.status === "taken") takenTimesToday.push(window.expectedTime);
    if (resolved.status === "missed") missedCountToday += 1;
    if (activeWindow?.id === window.id && resolved.status === "due") dueNow = 1;
    resolvedWindows.push(serializeWindow(window, resolved.status));
  }

  let activeResolved = null;
  if (activeWindow) {
    const resolved = await resolveDoseWindowStatus({ userId, medicationId, window: activeWindow, nowMs });
    activeResolved = {
      ...serializeWindow(activeWindow, resolved.status),
      notificationId: notificationWindowId({
        userId,
        medicationId,
        expectedDate: activeWindow.expectedDate,
        expectedTime: activeWindow.expectedTime,
      }),
    };
  }

  const nextUpcoming = doseWindowsAround({ medicationDoc, nowMs }).find(
    (window) => window.startMs > nowMs,
  );

  return {
    times: scheduleClocksForDate({ medicationDoc, dateKey: todayDateKey(nowMs) }).map((clock) => clock.text),
    takenTimesToday,
    nextDoseTime: nextUpcoming?.expectedTime || null,
    missedCountToday,
    dueNow,
    doseWindow: activeResolved,
    doseWindowsToday: resolvedWindows,
  };
}

function serializeWindow(window, status) {
  return {
    id: window.id,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
    startAt: window.startAt.toISOString(),
    endAt: window.endAt.toISOString(),
    status,
  };
}

async function markActiveWindowTaken({ userId, medicationId, medicationDoc, nowMs = Date.now() }) {
  const window = getActiveDoseWindow({ medicationDoc, nowMs });
  if (!window) {
    throw new Error("No active dose window found for this medication.");
  }
  const status = await resolveDoseWindowStatus({ userId, medicationId, window, nowMs });
  if (status.status === "missed") {
    const lateRef = await db.collection("medicationLateIntakeLogs").add({
      userId: String(userId),
      medicationId: String(medicationId),
      expectedDate: window.expectedDate,
      expectedTime: window.expectedTime,
      windowStartAt: admin.firestore.Timestamp.fromDate(window.startAt),
      windowEndAt: admin.firestore.Timestamp.fromDate(window.endAt),
      takenAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "manual_mark_taken_after_window",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      late: true,
      lateLogId: lateRef.id,
      window,
      status: "missed",
    };
  }

  const docId = doseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });
  await db.collection("medicationIntakeLogs").doc(docId).set(
    {
      id: docId,
      userId: String(userId),
      medicationId: String(medicationId),
      date: window.expectedDate,
      time: window.expectedTime,
      windowStartAt: admin.firestore.Timestamp.fromDate(window.startAt),
      windowEndAt: admin.firestore.Timestamp.fromDate(window.endAt),
      takenAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "manual_mark_taken",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    late: false,
    docId,
    window,
    status: "taken",
  };
}

async function undoActiveWindowTaken({ userId, medicationId, medicationDoc, nowMs = Date.now() }) {
  const window = getActiveDoseWindow({ medicationDoc, nowMs });
  if (!window) {
    throw new Error("No active dose window found for this medication.");
  }
  const docId = doseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });
  await db.collection("medicationIntakeLogs").doc(docId).delete();
  return { docId, window, status: "due" };
}

async function ensureDoseRecordsForDate({ userId, medicationId, medicationDoc, dateKey }) {
  const windows = getTodayDoseWindows({
    medicationDoc,
    nowMs: manilaDateKeyToUtcStartMs(dateKey || todayDateKey()) || Date.now(),
  });
  return windows.map((window) =>
    doseRecordId({
      userId,
      medicationId,
      expectedDate: window.expectedDate,
      expectedTime: window.expectedTime,
    }),
  );
}

async function markDoseTaken({ userId, medicationId, expectedDate, expectedTime }) {
  const id = doseRecordId({ userId, medicationId, expectedDate, expectedTime });
  await db.collection("medicationIntakeLogs").doc(id).set(
    {
      id,
      userId: String(userId),
      medicationId: String(medicationId),
      date: expectedDate,
      time: expectedTime,
      takenAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "manual_mark_taken",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { docId: id, changed: true, status: "taken" };
}

async function undoDoseTaken({ userId, medicationId, expectedDate, expectedTime }) {
  const id = doseRecordId({ userId, medicationId, expectedDate, expectedTime });
  await db.collection("medicationIntakeLogs").doc(id).delete();
  return { docId: id, changed: true, status: "pending" };
}

async function markOverdueDosesMissed() {
  return [];
}

async function getDoseRecordsForDate({ userId, dateKey }) {
  const snapshot = await db
    .collection("medicationIntakeLogs")
    .where("userId", "==", String(userId))
    .where("date", "==", String(dateKey || todayDateKey()))
    .get();
  return snapshot.docs.map((d) => ({ id: d.id, ...(d.data() || {}) }));
}

async function getDoseRecord({ userId, medicationId, expectedDate, expectedTime }) {
  const id = doseRecordId({ userId, medicationId, expectedDate, expectedTime });
  const snap = await db.collection("medicationIntakeLogs").doc(id).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...(snap.data() || {}) };
}

module.exports = {
  UNDO_WINDOW_MS,
  todayDateKey,
  dateKeyFromUtcMs,
  parseClockTime,
  expectedTimesForDate: scheduleClocksForDate,
  scheduleClocksForDate,
  doseWindowsAround,
  getActiveDoseWindow,
  getTodayDoseWindows,
  resolveDoseWindowStatus,
  resolveMedicationDoseStatus,
  markActiveWindowTaken,
  undoActiveWindowTaken,
  ensureDoseRecordsForDate,
  markDoseTaken,
  undoDoseTaken,
  markOverdueDosesMissed,
  getDoseRecordsForDate,
  getDoseRecord,
  doseRecordId,
  notificationWindowId,
};
