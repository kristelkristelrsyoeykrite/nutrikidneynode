import 'package:flutter_test/flutter_test.dart';
import 'package:nutri_kidney/services/notification_service.dart';

void main() {
  group('meal reminder scheduling', () {
    test('catches up a same-day meal reminder shortly after its time', () {
      final preferred = DateTime(2026, 5, 20, 8);
      final now = DateTime(2026, 5, 20, 8, 15);

      final scheduled = NotificationService.debugMealReminderScheduleTime(
        preferred: preferred,
        now: now,
        isToday: true,
      );

      expect(scheduled, DateTime(2026, 5, 20, 8, 16));
    });

    test('does not schedule a stale same-day meal reminder too late', () {
      final preferred = DateTime(2026, 5, 20, 8);
      final now = DateTime(2026, 5, 20, 8, 45);

      final scheduled = NotificationService.debugMealReminderScheduleTime(
        preferred: preferred,
        now: now,
        isToday: true,
      );

      expect(scheduled, isNull);
    });

    test('keeps future meal reminders at their preferred time', () {
      final preferred = DateTime(2026, 5, 20, 12);
      final now = DateTime(2026, 5, 20, 8, 15);

      final scheduled = NotificationService.debugMealReminderScheduleTime(
        preferred: preferred,
        now: now,
        isToday: true,
      );

      expect(scheduled, preferred);
    });
  });
}
