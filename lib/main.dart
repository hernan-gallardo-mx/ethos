import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'data/routine_store.dart';
import 'models/routine.dart';
import 'screens/dashboard_screen.dart';
import 'services/calendar_export_service.dart';
import 'services/reminder_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EthosApp());
}

class EthosApp extends StatefulWidget {
  const EthosApp({super.key});

  @override
  State<EthosApp> createState() => _EthosAppState();
}

class _EthosAppState extends State<EthosApp> {
  final RoutineStore _store = RoutineStore();
  final CalendarExportService _calendarExportService =
      CalendarExportService.instance;
  String? _lastCalendarRoutineSnapshot;

  @override
  void initState() {
    super.initState();
    _store.addListener(_syncCalendarExports);
    _store.load().then((_) async {
      await _store.restoreAccount();
      await ReminderService.instance.sync(_store.routines);
    });
  }

  @override
  void dispose() {
    _store.removeListener(_syncCalendarExports);
    _store.dispose();
    super.dispose();
  }

  void _syncCalendarExports() {
    if (!_store.isReady) return;
    final snapshot = jsonEncode(
      _store.routines.map((routine) => routine.toJson()).toList(),
    );
    if (snapshot == _lastCalendarRoutineSnapshot) return;
    _lastCalendarRoutineSnapshot = snapshot;
    unawaited(_calendarExportService.syncAll(_store.routines).catchError(
      (Object error, StackTrace stackTrace) {
        _lastCalendarRoutineSnapshot = null;
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'calendar export',
          context: ErrorDescription('while syncing routine calendar events'),
        ));
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF173B75);
    return MaterialApp(
      title: 'Ethos',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light, seed),
      darkTheme: _theme(Brightness.dark, seed),
      home: DashboardScreen(
        store: _store,
        calendarExportService: _calendarExportService,
      ),
    );
  }

  ThemeData _theme(Brightness brightness, Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: brightness == Brightness.light
          ? const Color(0xFFF5F7FC)
          : const Color(0xFF101827),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF18243A),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

Future<void> saveRoutineAndRefresh(RoutineStore store, Routine routine) async {
  await store.saveRoutine(routine);
  await ReminderService.instance.sync(store.routines);
}
