import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/routine.dart';

abstract interface class RoutineReminderSync {
  Future<bool> requestPermission();
  Future<void> sync(List<Routine> routines);
}

class ReminderService implements RoutineReminderSync {
  ReminderService._();

  static final ReminderService instance = ReminderService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    final localTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimeZone));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await android?.requestNotificationsPermission();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return androidGranted ?? iosGranted ?? true;
  }

  @override
  Future<void> sync(List<Routine> routines) async {
    await initialize();
    await _plugin.cancelAll();

    for (final routine in routines.where((item) => item.remindersEnabled)) {
      Routine? linkedRoutine;
      for (final item in routines) {
        if (item.id == routine.reduceOnRoutineId) {
          linkedRoutine = item;
          break;
        }
      }
      // Weekly exceptions need weekday-specific repeats instead of a daily repeat.
      final hasWeeklyOverlap = routine.frequency == RoutineFrequency.daily &&
          linkedRoutine != null &&
          (linkedRoutine.frequency == RoutineFrequency.weekly ||
              linkedRoutine.frequency == RoutineFrequency.custom);
      final days = switch (routine.frequency) {
        RoutineFrequency.daily =>
          hasWeeklyOverlap ? List<int>.generate(7, (index) => index + 1) : [0],
        RoutineFrequency.weekly ||
        RoutineFrequency.custom =>
          routine.weekdays.toList()..sort(),
        RoutineFrequency.monthly => [routine.monthDay],
      };
      for (final day in days) {
        final reduceOnDay = hasWeeklyOverlap &&
            (linkedRoutine.frequency == RoutineFrequency.weekly ||
                linkedRoutine.frequency == RoutineFrequency.custom) &&
            linkedRoutine.weekdays.contains(day);
        final times = reduceOnDay ? routine.times.take(1) : routine.times;
        for (final time in times) {
          final scheduledDate = _nextDate(routine, time, day);
          if (scheduledDate == null) continue;
          await _plugin.zonedSchedule(
            _notificationId(routine.id, time, day),
            routine.title,
            routine.note.isEmpty
                ? 'A small step, right on time.'
                : routine.note,
            scheduledDate,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'ethos_routine_reminders',
                'Routine reminders',
                channelDescription: 'Timely reminders for your routines.',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: switch (routine.frequency) {
              RoutineFrequency.daily when !hasWeeklyOverlap =>
                DateTimeComponents.time,
              RoutineFrequency.daily => DateTimeComponents.dayOfWeekAndTime,
              RoutineFrequency.weekly ||
              RoutineFrequency.custom =>
                DateTimeComponents.dayOfWeekAndTime,
              RoutineFrequency.monthly => DateTimeComponents.dayOfMonthAndTime,
            },
          );
        }
      }
    }
  }

  tz.TZDateTime? _nextDate(Routine routine, int minuteOfDay, int day) {
    final now = tz.TZDateTime.now(tz.local);
    for (var offset = 0; offset <= 370; offset++) {
      final date = now.add(Duration(days: offset));
      final matches = switch (routine.frequency) {
        RoutineFrequency.daily => day == 0 || date.weekday == day,
        RoutineFrequency.weekly ||
        RoutineFrequency.custom =>
          date.weekday == day,
        RoutineFrequency.monthly => date.day == day,
      };
      if (!matches) continue;
      final candidate = tz.TZDateTime(
        tz.local,
        date.year,
        date.month,
        date.day,
        minuteOfDay ~/ 60,
        minuteOfDay % 60,
      );
      if (candidate.isAfter(now)) return candidate;
    }
    return null;
  }

  int _notificationId(String routineId, int time, int day) {
    var hash = 0x811c9dc5;
    for (final unit in '$routineId:$time:$day'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
