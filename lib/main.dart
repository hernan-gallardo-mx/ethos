import 'package:flutter/material.dart';

import 'data/routine_store.dart';
import 'models/routine.dart';
import 'screens/dashboard_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _store.load().then((_) async {
      await _store.restoreAccount();
      await ReminderService.instance.sync(_store.routines);
    });
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF245B53);
    return MaterialApp(
      title: 'Ethos',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light, seed),
      darkTheme: _theme(Brightness.dark, const Color(0xFF8DD3B5)),
      home: DashboardScreen(store: _store),
    );
  }

  ThemeData _theme(Brightness brightness, Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: brightness == Brightness.light
          ? const Color(0xFFF7F8F5)
          : const Color(0xFF151B19),
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
            : const Color(0xFF202825),
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
