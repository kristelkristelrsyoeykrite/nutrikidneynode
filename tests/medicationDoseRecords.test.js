const assert = require("assert");

class DocRef {
  constructor(store, id) {
    this.store = store;
    this.id = id;
  }

  async get() {
    return {
      exists: this.store.has(this.id),
      id: this.id,
      data: () => this.store.get(this.id),
    };
  }

  async set(data, options) {
    const previous = options?.merge && this.store.has(this.id)
      ? this.store.get(this.id)
      : {};
    this.store.set(this.id, { ...previous, ...data });
  }

  async delete() {
    this.store.delete(this.id);
  }

  async create(data) {
    if (this.store.has(this.id)) {
      const error = new Error("already exists");
      error.code = 6;
      throw error;
    }
    this.store.set(this.id, data);
  }
}

class CollectionRef {
  constructor(store) {
    this.store = store;
  }

  doc(id) {
    return new DocRef(this.store, id);
  }
}

const stores = new Map();
let mockServerNow = new Date("2026-05-20T15:00:00.000Z");
const db = {
  collection(name) {
    if (!stores.has(name)) stores.set(name, new Map());
    return new CollectionRef(stores.get(name));
  },
};

const admin = {
  firestore: {
    Timestamp: {
      fromDate: (date) => ({
        toMillis: () => date.getTime(),
        toDate: () => date,
      }),
    },
    FieldValue: {
      serverTimestamp: () => mockServerNow,
      delete: () => undefined,
    },
  },
};

require.cache[require.resolve("../firebase/admin")] = { exports: { admin, db } };
require.cache[require.resolve("../utils/encryption")] = {
  exports: { decryptHealthDocument: (value) => value },
};

const dose = require("../utils/medicationDoseRecords");

const atManila = (date, time) => {
  const [year, month, day] = date.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  return Date.UTC(year, month - 1, day, hour - 8, minute, 0, 0);
};

async function fixedTimesMedicationWindowTest() {
  const userId = "user_fixed";
  const medicationId = "med_fixed";
  const medicationDoc = {
    isActive: true,
    startDate: "2026-05-20",
    endDate: "2026-05-22",
    scheduledTimes: ["06:30", "22:30"],
  };

  const windows = dose.doseWindowsAround({
    medicationDoc,
    nowMs: atManila("2026-05-20", "22:30"),
    beforeDays: 0,
    afterDays: 2,
  });
  const window = windows.find(
    (item) => item.expectedDate === "2026-05-20" && item.expectedTime === "22:30",
  );
  assert(window, "expected 22:30 window exists");
  assert.equal(window.startAt.toISOString(), "2026-05-20T14:30:00.000Z");
  assert.equal(window.missedReminderAt.toISOString(), "2026-05-20T14:35:00.000Z");
  assert.equal(window.endAt.toISOString(), "2026-05-20T22:30:00.000Z");

  const statusAt = async (time) => (
    await dose.resolveDoseWindowStatus({
      userId,
      medicationId,
      window,
      nowMs: atManila("2026-05-20", time),
    })
  ).status;

  assert.equal(await statusAt("22:34"), "due");
  assert.equal(await statusAt("22:35"), "missed");
  assert.equal(await statusAt("23:00"), "missed");

  const notificationId = dose.notificationWindowId({
    userId,
    medicationId,
    expectedDate: window.expectedDate,
    expectedTime: window.expectedTime,
  });
  const notificationRef = db.collection("notifications").doc(notificationId);
  await notificationRef.create({ notificationId });
  await assert.rejects(() => notificationRef.create({ notificationId }), /already exists/);

  const taken = await dose.markWindowTaken({
    userId,
    medicationId,
    medicationDoc,
    expectedDate: "2026-05-20",
    expectedTime: "22:30",
    nowMs: atManila("2026-05-20", "23:00"),
  });
  assert.equal(taken.status, "taken");
  assert.equal(taken.late, false);
  assert.equal(await statusAt("23:01"), "taken");

  const undone = await dose.undoWindowTaken({
    userId,
    medicationId,
    medicationDoc,
    expectedDate: "2026-05-20",
    expectedTime: "22:30",
    nowMs: atManila("2026-05-20", "23:02"),
  });
  assert.equal(undone.status, "missed");

  const late = await dose.markWindowTaken({
    userId,
    medicationId,
    medicationDoc,
    expectedDate: "2026-05-20",
    expectedTime: "22:30",
    nowMs: atManila("2026-05-21", "06:31"),
  });
  assert.equal(late.status, "late");
  assert.equal(late.late, true);

  const lateResolved = await dose.resolveDoseWindowStatus({
    userId,
    medicationId,
    window,
    nowMs: atManila("2026-05-21", "06:32"),
  });
  assert.equal(lateResolved.status, "late");

  const undoneLate = await dose.undoWindowTaken({
    userId,
    medicationId,
    medicationDoc,
    expectedDate: "2026-05-20",
    expectedTime: "22:30",
    nowMs: atManila("2026-05-21", "06:33"),
  });
  assert.equal(undoneLate.status, "expired_missed");

  await assert.rejects(
    () => dose.markWindowTaken({
      userId,
      medicationId,
      medicationDoc,
      expectedDate: "2026-05-21",
      expectedTime: "22:30",
      nowMs: atManila("2026-05-21", "10:00"),
    }),
    /not started/,
  );
}

async function intervalMedicationWindowTest() {
  const userId = "user_interval";
  const medicationId = "med_interval";
  const medicationDoc = {
    isActive: true,
    startDate: "2026-05-20",
    endDate: "2026-05-21",
    scheduleType: "interval",
    dailyTime: "08:00",
    intervalHours: 6,
  };

  const windows = dose.doseWindowsAround({
    medicationDoc,
    nowMs: atManila("2026-05-20", "14:00"),
    beforeDays: 0,
    afterDays: 1,
  });
  const window = windows.find(
    (item) => item.expectedDate === "2026-05-20" && item.expectedTime === "14:00",
  );
  assert(window, "expected 14:00 interval window exists");
  assert.equal(window.missedReminderAt.toISOString(), "2026-05-20T06:05:00.000Z");
  assert.equal(window.endAt.toISOString(), "2026-05-20T12:00:00.000Z");

  const statusAt = async (time) => (
    await dose.resolveDoseWindowStatus({
      userId,
      medicationId,
      window,
      nowMs: atManila("2026-05-20", time),
    })
  ).status;

  assert.equal(await statusAt("14:04"), "due");
  assert.equal(await statusAt("14:05"), "missed");
  assert.equal(await statusAt("19:59"), "missed");
  assert.equal(await statusAt("20:00"), "expired_missed");

  const taken = await dose.markWindowTaken({
    userId,
    medicationId,
    medicationDoc,
    expectedDate: "2026-05-20",
    expectedTime: "14:00",
    nowMs: atManila("2026-05-20", "19:00"),
  });
  assert.equal(taken.status, "taken");
  assert.equal(taken.late, false);

  const undone = await dose.undoWindowTaken({
    userId,
    medicationId,
    medicationDoc,
    expectedDate: "2026-05-20",
    expectedTime: "14:00",
    nowMs: atManila("2026-05-20", "19:01"),
  });
  assert.equal(undone.status, "missed");

  const late = await dose.markWindowTaken({
    userId,
    medicationId,
    medicationDoc,
    expectedDate: "2026-05-20",
    expectedTime: "14:00",
    nowMs: atManila("2026-05-20", "20:01"),
  });
  assert.equal(late.status, "late");
}

async function onceDailyMedicationResetsByDateTest() {
  const userId = "user_once";
  const medicationId = "med_once";
  const medicationDoc = {
    isActive: true,
    startDate: "2026-05-19",
    endDate: "2026-05-21",
    frequency_type: "times_per_day",
    frequency_value: 1,
    frequency: "Once daily",
    start_time: "23:50",
    scheduled_times: ["23:50"],
  };

  const windows = dose.doseWindowsAround({
    medicationDoc,
    nowMs: atManila("2026-05-20", "09:40"),
    beforeDays: 2,
    afterDays: 2,
  });
  const lastNight = windows.find(
    (item) => item.expectedDate === "2026-05-19" && item.expectedTime === "23:50",
  );
  const tonight = windows.find(
    (item) => item.expectedDate === "2026-05-20" && item.expectedTime === "23:50",
  );
  assert(lastNight, "expected last night's once-daily window");
  assert(tonight, "expected tonight's once-daily window");
  assert.equal(lastNight.endAt.toISOString(), "2026-05-19T16:00:00.000Z");
  assert.equal(tonight.startAt.toISOString(), "2026-05-20T15:50:00.000Z");

  mockServerNow = new Date(atManila("2026-05-19", "23:52"));
  const taken = await dose.markWindowTaken({
    userId,
    medicationId,
    medicationDoc,
    expectedDate: "2026-05-19",
    expectedTime: "23:50",
    nowMs: atManila("2026-05-19", "23:52"),
  });
  assert.equal(taken.status, "taken");

  const lastNightStatus = await dose.resolveDoseWindowStatus({
    userId,
    medicationId,
    window: lastNight,
    nowMs: atManila("2026-05-20", "09:40"),
  });
  assert.equal(lastNightStatus.status, "taken");

  const tonightStatus = await dose.resolveDoseWindowStatus({
    userId,
    medicationId,
    window: tonight,
    nowMs: atManila("2026-05-20", "09:40"),
  });
  assert.equal(tonightStatus.status, "upcoming");

  const summary = await dose.resolveMedicationDoseStatus({
    userId,
    medicationId,
    medicationDoc,
    nowMs: atManila("2026-05-20", "09:40"),
  });
  assert.deepEqual(summary.takenTimesToday, []);

  const earlyMorningMedicationDoc = {
    isActive: true,
    startDate: "2026-05-20",
    endDate: "2026-05-21",
    frequency_type: "times_per_day",
    frequency_value: 1,
    frequency: "Once daily",
    start_time: "00:33",
    scheduled_times: ["00:33"],
  };
  const earlyMorningTaken = await dose.markWindowTaken({
    userId: "user_once_same_day",
    medicationId: "med_once_same_day",
    medicationDoc: earlyMorningMedicationDoc,
    expectedDate: "2026-05-20",
    expectedTime: "00:33",
    nowMs: atManila("2026-05-20", "09:40"),
  });
  assert.equal(earlyMorningTaken.status, "taken");
  assert.equal(earlyMorningTaken.late, false);
}

(async () => {
  await fixedTimesMedicationWindowTest();
  await intervalMedicationWindowTest();
  await onceDailyMedicationResetsByDateTest();
  console.log("PASS medication dose window status simulation");
})();
