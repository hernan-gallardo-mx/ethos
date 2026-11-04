import 'package:calendar_bridge/calendar_bridge.dart';
import 'package:ethos/models/routine.dart';
import 'package:ethos/services/calendar_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeCalendarGateway gateway;
  late CalendarExportService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
    gateway = _FakeCalendarGateway();
    service = CalendarExportService(gateway: gateway);
  });

  test('requests calendar access and sorts writable calendars by default',
      () async {
    gateway.granted = false;
    gateway.requestResult = true;
    gateway.calendars = const [
      Calendar(id: 'other', name: 'Other'),
      Calendar(id: 'default', name: 'Personal', isDefault: true),
    ];

    final calendars = await service.calendars(requestPermission: true);

    expect(gateway.permissionRequests, 1);
    expect(calendars.map((calendar) => calendar.id), ['default', 'other']);
    expect(await service.calendars(), hasLength(2));
  });

  test('returns no calendars when access is denied', () async {
    gateway.granted = false;
    gateway.requestResult = false;

    expect(await service.calendars(), isEmpty);
    expect(gateway.permissionRequests, 0);
    expect(await service.calendars(requestPermission: true), isEmpty);
    expect(gateway.permissionRequests, 1);
    expect(gateway.calendarReads, 0);
  });

  test('creates recurring events and updates only tracked routine events',
      () async {
    await service.selectCalendar('personal');
    const routine = Routine(
      id: 'stretch',
      title: 'Stretch',
      note: 'Take a breath',
      frequency: RoutineFrequency.daily,
      times: [480, 1200],
      exportToCalendar: true,
    );

    await service.syncRoutine(routine);
    expect(gateway.events, hasLength(2));
    expect(gateway.created, hasLength(2));
    expect(gateway.events.values.first.title, 'Stretch');
    expect(gateway.events.values.first.description, 'Take a breath');
    expect(
      gateway.events.values.first.recurrenceRule?.frequency,
      Frequency.daily,
    );
    expect(
      gateway.events.values.first.end!
          .difference(gateway.events.values.first.start!),
      const Duration(hours: 1),
    );

    await service.syncRoutine(routine.copyWith(
      title: 'Morning stretch',
      times: const [480],
    ));

    expect(gateway.events, hasLength(1));
    expect(gateway.events.values.single.title, 'Morning stretch');
    expect(gateway.updated, hasLength(1));
    expect(gateway.deleted, hasLength(1));

    await service.syncRoutine(routine.copyWith(exportToCalendar: false));
    expect(gateway.events, isEmpty);
    expect(gateway.deleted, hasLength(2));
  });

  test('creates weekly and monthly recurrence rules', () async {
    await service.selectCalendar('personal');
    const weekly = Routine(
      id: 'weekly',
      title: 'Weekly',
      frequency: RoutineFrequency.custom,
      times: [600],
      weekdays: {1, 4},
      exportToCalendar: true,
    );
    const monthly = Routine(
      id: 'monthly',
      title: 'Monthly',
      frequency: RoutineFrequency.monthly,
      times: [720],
      monthDay: 15,
      exportToCalendar: true,
    );

    await service.syncRoutine(weekly);
    await service.syncRoutine(monthly);

    final weeklyRule = gateway.events.values
        .singleWhere((event) => event.title == 'Weekly')
        .recurrenceRule!;
    final monthlyRule = gateway.events.values
        .singleWhere((event) => event.title == 'Monthly')
        .recurrenceRule!;
    expect(weeklyRule.frequency, Frequency.weekly);
    expect(weeklyRule.byWeekDays.map((day) => day.day), [1, 4]);
    expect(monthlyRule.frequency, Frequency.monthly);
    expect(monthlyRule.byMonthDays, [15]);
  });

  test('recreates externally removed events and skips already removed IDs',
      () async {
    await service.selectCalendar('personal');
    const routine = Routine(
      id: 'routine',
      title: 'Routine',
      frequency: RoutineFrequency.daily,
      times: [540],
      exportToCalendar: true,
    );
    await service.syncRoutine(routine);
    gateway.events.clear();

    await service.syncRoutine(routine);
    expect(gateway.events, hasLength(1));
    expect(gateway.created, hasLength(2));

    await service.removeRoutine(routine.id);
    expect(gateway.events, isEmpty);
    expect(gateway.deleted, hasLength(1));
  });

  test('reconciles removed and disabled routines without requiring a target',
      () async {
    await service.selectCalendar('personal');
    const exported = Routine(
      id: 'exported',
      title: 'Exported',
      frequency: RoutineFrequency.daily,
      times: [540],
      exportToCalendar: true,
    );
    const disabled = Routine(
      id: 'disabled',
      title: 'Disabled',
      frequency: RoutineFrequency.daily,
      times: [600],
      exportToCalendar: true,
    );
    await service.syncRoutine(exported);
    await service.syncRoutine(disabled);

    await service.syncAll([exported]);
    expect(gateway.events, hasLength(1));
    expect(gateway.events.values.single.title, 'Exported');

    await service.selectCalendar(null);
    await service.syncAll([]);
    expect(gateway.events, isEmpty);
  });

  test('requires a selected calendar to export', () async {
    const routine = Routine(
      id: 'routine',
      title: 'Routine',
      frequency: RoutineFrequency.daily,
      times: [540],
      exportToCalendar: true,
    );

    await expectLater(
      service.syncRoutine(routine),
      throwsA(isA<StateError>()),
    );
  });

  test('moves tracked events when the selected calendar changes', () async {
    await service.selectCalendar('first');
    const routine = Routine(
      id: 'routine',
      title: 'Routine',
      frequency: RoutineFrequency.daily,
      times: [540],
      exportToCalendar: true,
    );
    await service.syncRoutine(routine);
    final oldId = gateway.events.keys.single;

    await service.selectCalendar('second');
    await service.syncRoutine(routine);

    expect(gateway.events, hasLength(1));
    expect(gateway.events.values.single.calendarId, 'second');
    expect(gateway.events.containsKey(oldId), isFalse);
    expect(gateway.deleted, [oldId]);

    await service.syncRoutine(routine.copyWith(times: const []));
    expect(gateway.events, isEmpty);
  });

  test('rejects schedules without a future matching day', () async {
    await service.selectCalendar('personal');
    const routine = Routine(
      id: 'invalid-weekly',
      title: 'Invalid weekly',
      frequency: RoutineFrequency.weekly,
      times: [540],
      weekdays: {},
      exportToCalendar: true,
    );

    await expectLater(
      service.syncRoutine(routine),
      throwsA(isA<StateError>()),
    );
  });

  test('device gateway delegates permission and event operations', () async {
    final repository = _FakeCalendarRepository();
    var timezoneReads = 0;
    final deviceGateway = DeviceCalendarExportGateway(
      bridge: CalendarBridge.custom(repository: repository),
      localTimezone: () async {
        timezoneReads++;
        return 'America/Mexico_City';
      },
    );
    final start = tz.TZDateTime.now(tz.local);
    final event = CalendarEvent(
      calendarId: 'personal',
      title: 'Test',
      start: start,
      end: start.add(const Duration(hours: 1)),
    );

    expect(await deviceGateway.hasPermissions(), isTrue);
    expect(await deviceGateway.requestPermissions(), isTrue);
    expect(await deviceGateway.writableCalendars(), hasLength(1));
    await deviceGateway.prepare();
    await deviceGateway.prepare();
    expect(await deviceGateway.createEvent(event), 'new-event');
    final existingEvent = event.copyWith(eventId: 'existing-event');
    expect(await deviceGateway.updateEvent(existingEvent), 'existing-event');
    await deviceGateway.deleteEvent('personal', 'existing-event');

    expect(timezoneReads, 1);
    expect(repository.created, event);
    expect(repository.updated, existingEvent);
    expect(repository.deleted, 'existing-event');
  });
}

class _FakeCalendarGateway implements CalendarExportGateway {
  bool granted = true;
  bool requestResult = true;
  int permissionRequests = 0;
  int calendarReads = 0;
  int _nextId = 0;
  List<Calendar> calendars = const [
    Calendar(id: 'personal', name: 'Personal', isDefault: true),
  ];
  final events = <String, CalendarEvent>{};
  final created = <CalendarEvent>[];
  final updated = <CalendarEvent>[];
  final deleted = <String>[];

  @override
  Future<void> prepare() async {}

  @override
  Future<bool> hasPermissions() async => granted;

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    granted = requestResult;
    return requestResult;
  }

  @override
  Future<List<Calendar>> writableCalendars() async {
    calendarReads++;
    return calendars;
  }

  @override
  Future<String> createEvent(CalendarEvent event) async {
    final id = 'event-${_nextId++}';
    events[id] = event.copyWith(eventId: id);
    created.add(event);
    return id;
  }

  @override
  Future<String> updateEvent(CalendarEvent event) async {
    final id = event.eventId!;
    if (!events.containsKey(id)) throw EventNotFoundException(id);
    events[id] = event;
    updated.add(event);
    return id;
  }

  @override
  Future<void> deleteEvent(String calendarId, String eventId) async {
    if (events.remove(eventId) == null) {
      throw EventNotFoundException(eventId);
    }
    deleted.add(eventId);
  }
}

class _FakeCalendarRepository implements CalendarRepository {
  CalendarEvent? created;
  CalendarEvent? updated;
  String? deleted;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<PermissionStatus> hasPermissions() async => PermissionStatus.granted;

  @override
  Future<List<Calendar>> getCalendars() async => const [
        Calendar(id: 'personal', name: 'Personal'),
        Calendar(id: 'readonly', name: 'Read only', isReadOnly: true),
      ];

  @override
  Future<String> createEvent(CalendarEvent event) async {
    created = event;
    return 'new-event';
  }

  @override
  Future<String> updateEvent(CalendarEvent event) async {
    updated = event;
    return 'existing-event';
  }

  @override
  Future<bool> deleteEvent(String calendarId, String eventId) async {
    deleted = eventId;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
