import 'package:ethos/data/routine_store.dart';
import 'package:ethos/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dashboard renders the app title', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RoutineStore(accountSyncService: LocalOnlyAccountSync());
    await store.load();
    await tester.pumpWidget(MaterialApp(home: DashboardScreen(store: store)));

    expect(find.text('ethos'), findsOneWidget);
    store.dispose();
  });
}
