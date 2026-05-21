const { admin, db } = require("../firebase/admin");
const { decryptHealthDocument } = require("./encryption");

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const MISSED_NOTIFICATION_DELAY_MS = 5 * 60 * 1000;
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

function manilaDateKeyToUtcEndMs(dateKey) {
  const startMs = manilaDateKeyToUtcStartMs(dateKey);
  if (!Number.isFinite(startMs)) return null;
  return startMs + DAY_MS;
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

  if (normalized.scheduledTimes.length > 0) return "fixed_times";

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

  if (normalized.timesPerDay && normalized.timesPerDay > 1) return "frequency";
  return "once";
}

function usesDoseWindowHandoff(normalized) {
  const kind = scheduleKind(normalized);
  if (kind === "interval") return true;
  if (kind === "frequency") {
    const count =
      normalized.timesPerDay || frequencyCountFromText(normalized.frequencyText);
    return Number(count) > 1;
  }
  return kind === "fixed_times" && normalized.scheduledTimes.length > 1;
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
  const normalized = normalizeMedicationSchedule(medicationDoc);
  const useDoseWindowHandoff = usesDoseWindowHandoff(normalized);
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

  const startsWithEnds = useDoseWindowHandoff
    ? uniqueStarts.slice(0, -1).map((start, index) => ({
        start,
        endMs: uniqueStarts[index + 1].startMs,
      }))
    : uniqueStarts.map((start) => ({
        start,
        endMs: manilaDateKeyToUtcEndMs(start.startDateKey) || start.startMs + DAY_MS,
      }));

  return startsWithEnds.map(({ start, endMs }) => {
    const missedReminderAtMs = start.startMs + MISSED_NOTIFICATION_DELAY_MS;
    return {
      id: `${start.startDateKey}_${start.startTime}`,
      expectedDate: start.startDateKey,
      expectedTime: start.startTime,
      startMs: start.startMs,
      endMs,
      missedReminderAtMs,
      startAt: new Date(start.startMs),
      endAt: new Date(endMs),
      missedReminderAt: new Date(missedReminderAtMs),
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

function lateDoseRecordId({ userId, medicationId, expectedDate, expectedTime }) {
  return `${doseRecordId({ userId, medicationId, expectedDate, expectedTime })}_late`;
}

function notificationWindowId({ userId, medicationId, expectedDate, expectedTime }) {
  return `${userId}_missed_medication_${medicationId}_${expectedDate}_${expectedTime}`;
}

function getActiveDoseWindow({ medicationDoc, nowMs = Date.now() }) {
  return doseWindowsAround({ medicationDoc, nowMs }).find(
    (window) => window.startMs <= nowMs && nowMs < window.endMs,
  ) || null;
}

function findWindowByTime({ medicationDoc, expectedTime, expectedDate, nowMs = Date.now() }) {
  const normalizedTime = parseClockTime(expectedTime)?.text;
  if (!normalizedTime) return null;
  const matching = doseWindowsAround({ medicationDoc, nowMs }).filter(
    (window) =>
      window.expectedTime === normalizedTime &&
      (!expectedDate || window.expectedDate === String(expectedDate)),
  );
  return matching.find(
    (window) => window.startMs <= nowMs && nowMs < window.endMs,
  ) || matching.find(
    (window) => dateKeyFromUtcMs(window.startMs) === todayDateKey(nowMs),
  ) || matching[0] || null;
}

function getTodayDoseWindows({ medicationDoc, nowMs = Date.now() }) {
  const today = todayDateKey(nowMs);
  const normalized = normalizeMedicationSchedule(medicationDoc);
  const includeHandoffWindows = usesDoseWindowHandoff(normalized);
  return doseWindowsAround({ medicationDoc, nowMs }).filter(
    (window) =>
      window.expectedDate === today ||
      (includeHandoffWindows && dateKeyFromUtcMs(window.endMs) === today),
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
  const logDate = String(log.date || log.expectedDate || "").trim();
  const logTime = parseClockTime(String(log.time || log.expectedTime || ""))?.text;
  const takenMs = timestampMs(log.takenAt || log.createdAt);
  if (logDate === window.expectedDate && logTime === window.expectedTime && !takenMs) {
    return true;
  }
  if (!takenMs) return false;
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
  if (snap.exists) {
    const log = { id: snap.id, ...(snap.data() || {}) };
    if (logBelongsToWindow(log, window)) return log;
  }

  const lateId = lateDoseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });
  const lateSnap = await db.collection("medicationLateIntakeLogs").doc(lateId).get();
  if (!lateSnap.exists) return null;
  const lateLog = { id: lateSnap.id, late: true, ...(lateSnap.data() || {}) };
  return logBelongsToWindow(lateLog, window) ? lateLog : null;
}

async function resolveDoseWindowStatus({ userId, medicationId, window, nowMs = Date.now() }) {
  const log = await getWindowLog({ userId, medicationId, window });
  if (log) return { status: log.late ? "late" : "taken", log };
  if (nowMs < window.startMs) return { status: "upcoming", log: null };
  if (nowMs < window.missedReminderAtMs) return { status: "due", log: null };
  if (nowMs < window.endMs) return { status: "missed", log: null };
  return { status: "expired_missed", log: null };
}

async function resolveMedicationDoseStatus({ userId, medicationId, medicationDoc, nowMs = Date.now() }) {
  const activeWindow = getActiveDoseWindow({ medicationDoc, nowMs });
  const todayWindows = getTodayDoseWindows({ medicationDoc, nowMs });
  const today = todayDateKey(nowMs);
  const takenTimesToday = [];
  let missedCountToday = 0;
  let dueNow = 0;

  const resolvedWindows = [];
  for (const window of todayWindows) {
    const resolved = await resolveDoseWindowStatus({ userId, medicationId, window, nowMs });
    const isExpectedToday = window.expectedDate === today;
    if (isExpectedToday && resolved.status === "taken") takenTimesToday.push(window.expectedTime);
    if (isExpectedToday && ["missed", "expired_missed"].includes(resolved.status)) {
      missedCountToday += 1;
    }
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
    times: scheduleClocksForDate({ medicationDoc, dateKey: today }).map((clock) => clock.text),
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
    missedReminderAt: window.missedReminderAt.toISOString(),
    status,
  };
}

async function deleteDoseLogsForWindow({ userId, medicationId, window }) {
  const docId = doseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });
  const lateDocId = lateDoseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });
  const currentSnap = await db.collection("medicationIntakeLogs").doc(docId).get();
  const legacyLateId = currentSnap.exists ? currentSnap.data()?.lateIntakeLogId : null;

  await db.collection("medicationIntakeLogs").doc(docId).delete();
  await db.collection("medicationLateIntakeLogs").doc(lateDocId).delete().catch(() => {});
  if (legacyLateId && legacyLateId !== lateDocId) {
    await db.collection("medicationLateIntakeLogs").doc(String(legacyLateId)).delete().catch(() => {});
  }

  return { docId, lateDocId };
}

async function writeLateDoseLog({ userId, medicationId, window }) {
  const docId = doseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });
  const lateDocId = lateDoseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });

  await db.collection("medicationIntakeLogs").doc(docId).delete().catch(() => {});
  await db.collection("medicationLateIntakeLogs").doc(lateDocId).set(
    {
      id: lateDocId,
      userId: String(userId),
      medicationId: String(medicationId),
      expectedDate: window.expectedDate,
      expectedTime: window.expectedTime,
      windowStartAt: admin.firestore.Timestamp.fromDate(window.startAt),
      windowEndAt: admin.firestore.Timestamp.fromDate(window.endAt),
      missedReminderAt: admin.firestore.Timestamp.fromDate(window.missedReminderAt),
      takenAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "manual_mark_late_after_window",
      late: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { docId, lateDocId };
}

async function writeTakenDoseLog({ userId, medicationId, window }) {
  const docId = doseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });
  const lateDocId = lateDoseRecordId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });

  await db.collection("medicationLateIntakeLogs").doc(lateDocId).delete().catch(() => {});
  await db.collection("medicationIntakeLogs").doc(docId).set(
    {
      id: docId,
      userId: String(userId),
      medicationId: String(medicationId),
      date: window.expectedDate,
      time: window.expectedTime,
      windowStartAt: admin.firestore.Timestamp.fromDate(window.startAt),
      windowEndAt: admin.firestore.Timestamp.fromDate(window.endAt),
      missedReminderAt: admin.firestore.Timestamp.fromDate(window.missedReminderAt),
      takenAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "manual_mark_taken",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { docId, lateDocId };
}

async function markActiveWindowTaken({ userId, medicationId, medicationDoc, nowMs = Date.now() }) {
  const window = getActiveDoseWindow({ medicationDoc, nowMs });
  if (!window) {
    throw new Error("No active dose window found for this medication.");
  }
  const { docId } = await writeTakenDoseLog({ userId, medicationId, window });

  return {
    late: false,
    docId,
    window,
    status: "taken",
  };
}

async function markWindowTaken({ userId, medicationId, medicationDoc, expectedTime, expectedDate, nowMs = Date.now() }) {
  const window =
    findWindowByTime({ medicationDoc, expectedTime, expectedDate, nowMs }) ||
    getActiveDoseWindow({ medicationDoc, nowMs });
  if (!window) {
    throw new Error("No matching dose window found for this medication.");
  }

  if (nowMs < window.startMs) {
    throw new Error("This dose window has not started yet.");
  }

  if (nowMs >= window.endMs) {
    const { docId, lateDocId } = await writeLateDoseLog({ userId, medicationId, window });
    return { late: true, lateLogId: lateDocId, docId, window, status: "late" };
  }

  const { docId } = await writeTakenDoseLog({ userId, medicationId, window });

  return { late: false, docId, window, status: "taken" };
}

async function undoActiveWindowTaken({ userId, medicationId, medicationDoc, nowMs = Date.now() }) {
  const window = getActiveDoseWindow({ medicationDoc, nowMs });
  if (!window) {
    throw new Error("No active dose window found for this medication.");
  }
  const { docId } = await deleteDoseLogsForWindow({ userId, medicationId, window });
  const resolved = await resolveDoseWindowStatus({ userId, medicationId, window, nowMs });
  return { docId, window, status: resolved.status };
}

async function undoWindowTaken({ userId, medicationId, medicationDoc, expectedTime, expectedDate, nowMs = Date.now() }) {
  const window =
    findWindowByTime({ medicationDoc, expectedTime, expectedDate, nowMs }) ||
    getActiveDoseWindow({ medicationDoc, nowMs });
  if (!window) {
    throw new Error("No matching dose window found for this medication.");
  }
  const { docId } = await deleteDoseLogsForWindow({ userId, medicationId, window });
  const resolved = await resolveDoseWindowStatus({ userId, medicationId, window, nowMs });
  return { docId, window, status: resolved.status };
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
  findWindowByTime,
  getTodayDoseWindows,
  resolveDoseWindowStatus,
  resolveMedicationDoseStatus,
  markActiveWindowTaken,
  markWindowTaken,
  undoActiveWindowTaken,
  undoWindowTaken,
  ensureDoseRecordsForDate,
  markDoseTaken,
  undoDoseTaken,
  markOverdueDosesMissed,
  getDoseRecordsForDate,
  getDoseRecord,
  doseRecordId,
  notificationWindowId,
  MISSED_NOTIFICATION_DELAY_MS,
};
