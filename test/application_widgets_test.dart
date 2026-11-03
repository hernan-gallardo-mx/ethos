import 'package:ethos/data/routine_store.dart';
import 'package:ethos/models/routine.dart';
import 'package:ethos/screens/dashboard_screen.dart';
import 'package:ethos/screens/routine_editor_screen.dart';
import 'package:ethos/services/reminder_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

class FakeReminderService implements RoutineReminderSync {
  bool permissionGranted = true;
  int permissionRequests = 0;
  Object? syncError;
  final syncCalls = <List<Routine>>[];

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> sync(List<Routine> routines) async {
    syncCalls.add(List.of(routines));
    if (syncError case final error?) throw error;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('editor validates, creates, and saves a weekly routine',
      (tester) async {
    final store = RoutineStore(accountSyncService: LocalOnlyAccountSync());
    final reminders = FakeReminderService();
    await store.load();
    await tester.pumpWidget(MaterialApp(
      home: RoutineEditorScreen(store: store, reminderService: reminders),
    ));

    await tester.tap(find.byTooltip('Save routine'));
    await tester.pump();
    expect(find.text('Give your routine a name first.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '  Stretch  ');
    await tester.enterText(find.byType(TextField).last, '  Gently  ');
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    final mondayChip =
        find.ancestor(of: find.text('Mo'), matching: find.byType(FilterChip));
    await tester.ensureVisible(mondayChip);
    await tester.tap(mondayChip);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add time'));
    await tester.tap(find.text('Add time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('ON OVERLAPPING DAYS'));
    final overlapDropdown = find.byType(DropdownButtonFormField<String?>);
    await tester.ensureVisible(overlapDropdown);
    await tester.tap(overlapDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('“Apply minoxidil” is scheduled').last);
    await tester.pumpAndSettle();

    reminders.permissionGranted = false;
    await tester.ensureVisible(find.text('Remind me'));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(reminders.permissionRequests, 1);
    expect(
        find.text('Notifications are not enabled for Ethos.'), findsOneWidget);

    reminders.permissionGranted = true;
    await tester.ensureVisible(find.text('Remind me'));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create routine'));
    await tester.pumpAndSettle();

    final saved = store.routines.singleWhere((item) => item.title == 'Stretch');
    expect(saved.note, 'Gently');
    expect(saved.frequency, RoutineFrequency.weekly);
    expect(saved.weekdays.length, 6);
    expect(saved.reduceOnRoutineId, store.routines.first.id);
    expect(saved.remindersEnabled, isTrue);
    expect(reminders.permissionRequests, 2);
    expect(reminders.syncCalls, hasLength(1));
    store.dispose();
  });

  testWidgets(
      'editor edits a routine, handles empty weekdays, and monthly dates',
      (tester) async {
    const routine = Routine(
      id: 'existing',
      title: 'Existing',
      note: 'Old note',
      frequency: RoutineFrequency.weekly,
      times: [540, 600],
      weekdays: {},
      monthDay: 1,
      remindersEnabled: true,
    );
    final store = RoutineStore(accountSyncService: LocalOnlyAccountSync());
    final reminders = FakeReminderService();
    await store.load();
    await store.saveRoutine(routine);
    await tester.pumpWidget(MaterialApp(
      home: RoutineEditorScreen(
        store: store,
        routine: routine,
        reminderService: reminders,
      ),
    ));

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    final dayLabel = find.text('of each month');
    await tester.ensureVisible(dayLabel);
    final dayRow =
        find.ancestor(of: dayLabel, matching: find.byType(Row)).first;
    await tester.tap(find.descendant(
      of: dayRow,
      matching: find.byIcon(Icons.add_rounded),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    final mondayChip =
        find.ancestor(of: find.text('Mo'), matching: find.byType(FilterChip));
    await tester.scrollUntilVisible(
      mondayChip,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(mondayChip);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove time').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove time'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Updated');
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final saved = store.routines.singleWhere((item) => item.id == 'existing');
    expect(saved.title, 'Updated');
    expect(saved.times, [600]);
    expect(saved.frequency, RoutineFrequency.weekly);
    expect(saved.weekdays, {DateTime.now().weekday, DateTime.monday});
    expect(reminders.syncCalls, hasLength(1));
    store.dispose();
  });

  testWidgets('saving returns to dashboard even if reminder sync fails',
      (tester) async {
    final store = RoutineStore(accountSyncService: LocalOnlyAccountSync());
    final reminders = FakeReminderService()
      ..syncError = PlatformException(code: 'notifications-unavailable');
    await store.load();
    await tester.pumpWidget(MaterialApp(
      home: DashboardScreen(store: store, reminderService: reminders),
    ));

    await tester.tap(find.byTooltip('Add a routine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'New habit');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create routine'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Create routine'));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(
        store.routines.any((routine) => routine.title == 'New habit'), isTrue);
    expect(
      occurrencesForDate(store.routines, DateTime.now())
          .any((item) => item.routine.title == 'New habit'),
      isTrue,
    );
    expect(find.text('0/3'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('New habit'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('New habit'), findsAtLeastNWidgets(1));
    expect(
      find.textContaining('Routine saved, but reminders could not be updated'),
      findsOneWidget,
    );
    store.dispose();
  });

  testWidgets('dashboard account dialog shows local-only platform message',
      (tester) async {
    final store = RoutineStore(accountSyncService: LocalOnlyAccountSync());
    await store.load();
    await tester.pumpWidget(MaterialApp(home: DashboardScreen(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sync across devices'));
    await tester.pumpAndSettle();
    expect(find.text('Cloud sync is available on Android and iOS.'),
        findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    store.dispose();
  });

  testWidgets('account dialog handles Google sign-in, retry, and sign-out',
      (tester) async {
    final sync = ConnectedAccountSync();
    final store = RoutineStore(accountSyncService: sync);
    await store.load();
    await tester.pumpWidget(MaterialApp(home: DashboardScreen(store: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sync across devices'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);

    sync.signInError = const GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
    );
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Account sync failed'), findsNothing);

    sync.signInError = PlatformException(code: 'google-failed');
    await tester.tap(find.byTooltip('Sync across devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('google-failed'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(DashboardScreen)))
        .clearSnackBars();

    sync.signInError = null;
    sync.loadError = FirebaseException(plugin: 'test', message: 'offline');
    await tester.tap(find.byTooltip('Sync across devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('offline'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(DashboardScreen)))
        .clearSnackBars();

    sync.loadError = null;
    await tester.tap(find.byTooltip('Cloud sync needs attention'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Account and cloud sync'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as user@example.com'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    sync.signOutError = PlatformException(code: 'signout-failed');
    await tester.tap(find.byTooltip('Account and cloud sync'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.textContaining('signout-failed'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(DashboardScreen)))
        .clearSnackBars();

    store.dispose();
    await sync.dispose();
  });

  testWidgets(
      'dashboard navigates periods, tracks completions and edits routines',
      (tester) async {
    final store = RoutineStore(accountSyncService: LocalOnlyAccountSync());
    final reminders = FakeReminderService();
    await store.load();
    const afternoon = Routine(
      id: 'afternoon',
      title: 'Afternoon walk',
      frequency: RoutineFrequency.daily,
      times: [900],
      remindersEnabled: true,
    );
    await store.saveRoutine(afternoon);
    await tester.pumpWidget(MaterialApp(
      home: DashboardScreen(store: store, reminderService: reminders),
    ));
    await tester.pumpAndSettle();

    expect(find.text('MORNING'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('AFTERNOON'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reminders on'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(store.completions, hasLength(1));

    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(find.textContaining('–'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    final firstOfMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final firstOfMonthLabel = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label ==
              '${_monthName(firstOfMonth.month)} ${firstOfMonth.day}',
    );
    final monthDayButton = find.descendant(
      of: firstOfMonthLabel,
      matching: find.byType(InkWell),
    );
    await tester.tap(monthDayButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Routine options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    expect(find.text('Edit routine'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Routine options').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(store.routines.any((item) => item.id == 'afternoon'), isFalse);
    expect(reminders.syncCalls, hasLength(1));
    store.dispose();
  });

  testWidgets('dashboard distinguishes an empty schedule from a clear day',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final store = RoutineStore(accountSyncService: LocalOnlyAccountSync());
    await store.load();
    for (final routine in store.routines.toList()) {
      await store.deleteRoutine(routine.id);
    }
    await tester.pumpWidget(MaterialApp(home: DashboardScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Start with one routine that matters to you.'),
        findsOneWidget);

    final today = DateTime.now();
    final weekStart = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - DateTime.monday));
    final tuesday = weekStart.add(const Duration(days: 1));
    final tuesdayLabel = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label ==
              '${_weekdayShort(tuesday.weekday)}, ${tuesday.day}',
    );
    await tester.tap(find.descendant(
      of: tuesdayLabel,
      matching: find.byType(InkWell),
    ));
    await tester.pumpAndSettle();
    await store.saveRoutine(const Routine(
      id: 'only-monday',
      title: 'Monday only',
      frequency: RoutineFrequency.weekly,
      times: [480],
      weekdays: {DateTime.monday},
    ));
    await tester.pumpAndSettle();
    expect(find.text('A clear day. Enjoy the breathing room.'), findsOneWidget);
    semantics.dispose();
    store.dispose();
  });
}

String _monthName(int month) => const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][month - 1];

String _weekdayShort(int weekday) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];
