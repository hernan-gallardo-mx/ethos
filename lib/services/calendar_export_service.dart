import 'dart:convert';
import 'dart:async';

import 'package:calendar_bridge/calendar_bridge.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/routine.dart';

class DeviceCalendar {
  const DeviceCalendar({required this.id, required this.name});

  final String id;
  final String name;
}

abstract interface class RoutineCalendarSync {
  Future<List<DeviceCalendar>> calendars({bool requestPermission = false});
  Future<String?> selectedCalendarId();
  Future<void> selectCalendar(String? calendarId);
  Future<void> syncRoutine(Routine routine);
  Future<void> syncAll(List<Routine> routines);
  Future<void> removeRoutine(String routineId);
}

abstract interface class CalendarExportGateway {
  Future<void> prepare();
  Future<bool> hasPermissions();
  Future<bool> requestPermissions();
  Future<List<Calendar>> writableCalendars();
  Future<String> createEvent(CalendarEvent event);
  Future<String> updateEvent(CalendarEvent event);
  Future<void> deleteEvent(String calendarId, String eventId);
}

class DeviceCalendarExportGateway implements CalendarExportGateway {
  DeviceCalendarExportGateway({
    CalendarBridge? bridge,
    Future<String> Function()? localTimezone,
  })  : _bridge = bridge ?? CalendarBridge(),
        _localTimezone = localTimezone ?? FlutterTimezone.getLocalTimezone;

  final CalendarBridge _bridge;
  final Future<String> Function() _localTimezone;
  Future<void>? _timezoneInitialization;

  @override
  Future<bool> hasPermissions() async =>
      (await _bridge.hasPermissions()).isGranted;

  @override
  Future<void> prepare() => _initializeTimezone();

  @override
  Future<bool> requestPermissions() => _bridge.requestPermissions();

  @override
  Future<List<Calendar>> writableCalendars() => _bridge.getWritableCalendars();

  @override
  Future<String> createEvent(CalendarEvent event) async {
    await _initializeTimezone();
    return _bridge.createEvent(event);
  }

  @override
  Future<String> updateEvent(CalendarEvent event) async {
    await _initializeTimezone();
    return _bridge.updateEvent(event);
  }

  @override
  Future<void> deleteEvent(String calendarId, String eventId) async {
    await _bridge.deleteEvent(calendarId, eventId);
  }

  Future<void> _initializeTimezone() {
    return _timezoneInitialization ??= _loadTimezone();
  }

  Future<void> _loadTimezone() async {
    tz_data.initializeTimeZones();
    final timezoneName = await _localTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName));
  }
}

class CalendarExportService implements RoutineCalendarSync {
  CalendarExportService({
    CalendarExportGateway? gateway,
    Future<SharedPreferences> Function()? preferences,
  })  : _gateway = gateway ?? DeviceCalendarExportGateway(),
        _preferences = preferences ?? SharedPreferences.getInstance;

  static final CalendarExportService instance = CalendarExportService();

  static const _selectedCalendarKey = 'ethos.calendar.selected.v1';
  static const _eventMappingsKey = 'ethos.calendar.events.v1';

  final CalendarExportGateway _gateway;
  final Future<SharedPreferences> Function() _preferences;
  Future<void> _operations = Future.value();

  @override
  Future<List<DeviceCalendar>> calendars({
    bool requestPermission = false,
  }) async {
    var granted = await _gateway.hasPermissions();
    if (!granted && requestPermission) {
      granted = await _gateway.requestPermissions();
    }
    if (!granted) return const [];

    final calendars = List<Calendar>.of(await _gateway.writableCalendars());
    calendars.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return calendars
        .map((calendar) => DeviceCalendar(id: calendar.id, name: calendar.name))
        .toList();
  }

  @override
  Future<String?> selectedCalendarId() async {
    final preferences = await _preferences();
    return preferences.getString(_selectedCalendarKey);
  }

  @override
  Future<void> selectCalendar(String? calendarId) async {
    final preferences = await _preferences();
    if (calendarId == null) {
      await preferences.remove(_selectedCalendarKey);
      return;
    }
    await preferences.setString(_selectedCalendarKey, calendarId);
  }

  @override
  Future<void> syncRoutine(Routine routine) async {
    return _enqueue(() => _syncRoutine(routine));
  }

  Future<void> _syncRoutine(Routine routine) async {
    if (!routine.exportToCalendar) {
      await _removeRoutine(routine.id);
      return;
    }

    final calendarId = await selectedCalendarId();
    if (calendarId == null) {
      throw StateError('Choose a device calendar before exporting routines.');
    }

    final mappings = await _readMappings();
    final previous = mappings[routine.id];
    if (previous != null && previous.calendarId != calendarId) {
      for (final eventId in previous.eventIds.values) {
        await _deleteIfPresent(previous.calendarId, eventId);
      }
      mappings.remove(routine.id);
      await _writeMappings(mappings);
    }
    final existingIds = previous?.calendarId == calendarId
        ? Map<String, String>.of(previous!.eventIds)
        : <String, String>{};
    final nextIds = <String, String>{};

    for (final minutes in routine.times.toSet().toList()..sort()) {
      final key = minutes.toString();
      final event = await _eventFor(routine, calendarId, minutes);
      final existingId = existingIds.remove(key);
      if (existingId == null) {
        nextIds[key] = await _gateway.createEvent(event);
      } else {
        try {
          nextIds[key] = await _gateway.updateEvent(
            event.copyWith(eventId: existingId),
          );
        } on EventNotFoundException {
          nextIds[key] = await _gateway.createEvent(event);
        }
      }
      mappings[routine.id] = _RoutineEventMapping(calendarId, nextIds);
      await _writeMappings(mappings);
    }

    for (final eventId in existingIds.values) {
      await _deleteIfPresent(calendarId, eventId);
    }

    if (nextIds.isEmpty) {
      mappings.remove(routine.id);
    } else {
      mappings[routine.id] = _RoutineEventMapping(calendarId, nextIds);
    }
    await _writeMappings(mappings);
  }

  @override
  Future<void> syncAll(List<Routine> routines) async {
    return _enqueue(() => _syncAll(routines));
  }

  Future<void> _syncAll(List<Routine> routines) async {
    final routineIds = routines.map((routine) => routine.id).toSet();
    final mappings = await _readMappings();
    for (final routineId in mappings.keys.toList()) {
      if (!routineIds.contains(routineId)) {
        await _removeRoutine(routineId);
      }
    }

    for (final routine
        in routines.where((routine) => !routine.exportToCalendar)) {
      await _removeRoutine(routine.id);
    }
    if (await selectedCalendarId() == null) return;
    for (final routine
        in routines.where((routine) => routine.exportToCalendar)) {
      await _syncRoutine(routine);
    }
  }

  @override
  Future<void> removeRoutine(String routineId) async {
    return _enqueue(() => _removeRoutine(routineId));
  }

  Future<void> _removeRoutine(String routineId) async {
    final mappings = await _readMappings();
    final mapping = mappings[routineId];
    if (mapping == null) return;

    for (final eventId in mapping.eventIds.values) {
      await _deleteIfPresent(mapping.calendarId, eventId);
    }
    mappings.remove(routineId);
    await _writeMappings(mappings);
  }

  Future<CalendarEvent> _eventFor(
    Routine routine,
    String calendarId,
    int minutes,
  ) async {
    await _gateway.prepare();
    final start = _nextScheduledStart(routine, minutes);
    final tzStart = tz.TZDateTime.from(start, tz.local);
    return CalendarEvent(
      calendarId: calendarId,
      title: routine.title,
      description: routine.note.isEmpty ? null : routine.note,
      start: tzStart,
      end: tzStart.add(const Duration(hours: 1)),
      recurrenceRule: _recurrenceFor(routine),
    );
  }

  DateTime _nextScheduledStart(Routine routine, int minutes) {
    final now = DateTime.now();
    for (var offset = 0; offset <= 366; offset++) {
      final date = DateTime(now.year, now.month, now.day + offset);
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        minutes ~/ 60,
        minutes % 60,
      );
      if (routine.isScheduledOn(start) && start.isAfter(now)) return start;
    }
    throw StateError('No upcoming date matches this routine schedule.');
  }

  RecurrenceRule _recurrenceFor(Routine routine) {
    return switch (routine.frequency) {
      RoutineFrequency.daily => RecurrenceRule(frequency: Frequency.daily),
      RoutineFrequency.weekly || RoutineFrequency.custom => RecurrenceRule(
          frequency: Frequency.weekly,
          byWeekDays: (routine.weekdays.toList()..sort())
              .map(ByWeekDayEntry.new)
              .toList(),
        ),
      RoutineFrequency.monthly => RecurrenceRule(
          frequency: Frequency.monthly,
          byMonthDays: [routine.monthDay],
        ),
    };
  }

  Future<void> _deleteIfPresent(String calendarId, String eventId) async {
    try {
      await _gateway.deleteEvent(calendarId, eventId);
    } on EventNotFoundException {
      // The event may have been removed from the calendar by the user.
    }
  }

  Future<Map<String, _RoutineEventMapping>> _readMappings() async {
    final preferences = await _preferences();
    final raw = preferences.getString(_eventMappingsKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((routineId, value) {
      final mapping = value as Map<String, dynamic>;
      final eventIds = (mapping['eventIds'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as String),
      );
      return MapEntry(
        routineId,
        _RoutineEventMapping(mapping['calendarId'] as String, eventIds),
      );
    });
  }

  Future<void> _writeMappings(
    Map<String, _RoutineEventMapping> mappings,
  ) async {
    final preferences = await _preferences();
    final json = mappings.map((routineId, mapping) {
      return MapEntry(routineId, {
        'calendarId': mapping.calendarId,
        'eventIds': mapping.eventIds,
      });
    });
    await preferences.setString(_eventMappingsKey, jsonEncode(json));
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

class _RoutineEventMapping {
  const _RoutineEventMapping(this.calendarId, this.eventIds);

  final String calendarId;
  final Map<String, String> eventIds;
}
