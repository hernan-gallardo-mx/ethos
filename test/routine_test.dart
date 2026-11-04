import 'package:flutter_test/flutter_test.dart';
import 'package:ethos/models/routine.dart';

void main() {
  group('routine occurrences', () {
    const minoxidil = Routine(
      id: 'minoxidil',
      title: 'Apply minoxidil',
      frequency: RoutineFrequency.daily,
      times: [480, 1200],
      reduceOnRoutineId: 'roller',
    );
    const roller = Routine(
      id: 'roller',
      title: 'Derma roll',
      frequency: RoutineFrequency.weekly,
      times: [1200],
      weekdays: {2, 4, 6},
    );

    test('reduces linked routine to one occurrence on overlap days', () {
      final tuesday = DateTime(2026, 11, 3);
      final items = occurrencesForDate([minoxidil, roller], tuesday);

      expect(
          items.where((item) => item.routine.id == 'minoxidil'), hasLength(1));
      expect(items.where((item) => item.routine.id == 'roller'), hasLength(1));
    });

    test('keeps all occurrences when there is no overlap', () {
      final monday = DateTime(2026, 11, 2);
      final items = occurrencesForDate([minoxidil, roller], monday);

      expect(
          items.where((item) => item.routine.id == 'minoxidil'), hasLength(2));
      expect(items.where((item) => item.routine.id == 'roller'), isEmpty);
    });

    test('matches monthly routines on their chosen day', () {
      const routine = Routine(
        id: 'monthly',
        title: 'Monthly check-in',
        frequency: RoutineFrequency.monthly,
        times: [600],
        monthDay: 15,
      );

      expect(routine.isScheduledOn(DateTime(2026, 11, 15)), isTrue);
      expect(routine.isScheduledOn(DateTime(2026, 11, 14)), isFalse);
    });

    test('supports daily, custom, weekly, and monthly schedules', () {
      final date = DateTime(2026, 11, 3);
      expect(minoxidil.isScheduledOn(date), isTrue);
      expect(roller.isScheduledOn(date), isTrue);
      const custom = Routine(
        id: 'custom',
        title: 'Custom',
        frequency: RoutineFrequency.custom,
        times: [],
        weekdays: {dateTuesday},
      );
      expect(custom.isScheduledOn(date), isTrue);
      expect(custom.isScheduledOn(DateTime(2026, 11, 4)), isFalse);
    });

    test('copies fields and can explicitly clear a linked routine', () {
      final updated = minoxidil.copyWith(
        title: 'New title',
        note: 'New note',
        frequency: RoutineFrequency.custom,
        times: const [600],
        weekdays: const {1},
        monthDay: 15,
        reduceOnRoutineId: 'other',
        remindersEnabled: true,
        exportToCalendar: true,
      );
      expect(updated.title, 'New title');
      expect(updated.note, 'New note');
      expect(updated.frequency, RoutineFrequency.custom);
      expect(updated.times, [600]);
      expect(updated.weekdays, {1});
      expect(updated.monthDay, 15);
      expect(updated.reduceOnRoutineId, 'other');
      expect(updated.remindersEnabled, isTrue);
      expect(updated.exportToCalendar, isTrue);
      expect(
        minoxidil.copyWith(reduceOnRoutineId: 'roller').reduceOnRoutineId,
        'roller',
      );
      expect(minoxidil.copyWith(id: 'copy').id, 'copy');
      expect(minoxidil.copyWith(clearReduceOnRoutineId: true).reduceOnRoutineId,
          isNull);
    });

    test('round trips routine JSON and applies defaults for older data', () {
      const routine = Routine(
        id: 'round-trip',
        title: 'Routine',
        note: 'note',
        frequency: RoutineFrequency.custom,
        times: [480, 720],
        weekdays: {1, 3},
        monthDay: 15,
        reduceOnRoutineId: 'linked',
        remindersEnabled: true,
        exportToCalendar: true,
      );
      final decoded = Routine.fromJson(routine.toJson());
      expect(decoded.toJson(), routine.toJson());
      expect(
        Routine.fromJson({
          'id': 'old',
          'title': 'Old format',
          'frequency': 'not-a-frequency',
        }).toJson(),
        {
          'id': 'old',
          'title': 'Old format',
          'note': '',
          'frequency': 'daily',
          'times': [540],
          'weekdays': [],
          'monthDay': 1,
          'reduceOnRoutineId': null,
          'remindersEnabled': false,
          'exportToCalendar': false,
        },
      );
    });

    test('returns sorted occurrences and formatted time/completion key', () {
      const routine = Routine(
        id: 'scheduled',
        title: 'Scheduled',
        frequency: RoutineFrequency.daily,
        times: [1200, 480],
      );
      final occurrences = occurrencesForDate([routine], DateTime(2026, 11, 2));
      expect(occurrences.map((item) => item.minuteOfDay), [480, 1200]);
      expect(occurrences.first.completionKey(DateTime(2026, 11, 2)),
          'scheduled:2026-11-2:0');
      expect(occurrences.first.time.hour, 8);
      expect(occurrences.first.time.minute, 0);
      expect(occurrences.last.time.hour, 20);
    });

    test('ignores absent linked routines and omits unscheduled occurrences',
        () {
      const unlinked = Routine(
        id: 'orphan',
        title: 'Orphan',
        frequency: RoutineFrequency.daily,
        times: [600],
        reduceOnRoutineId: 'missing',
      );
      final items = occurrencesForDate(
        [
          unlinked,
          const Routine(
            id: 'wednesday',
            title: 'Wednesday',
            frequency: RoutineFrequency.weekly,
            times: [700],
            weekdays: {3},
          ),
        ],
        DateTime(2026, 11, 2),
      );
      expect(items.map((item) => item.routine.id), ['orphan']);
    });
  });
}

const dateTuesday = 2;
