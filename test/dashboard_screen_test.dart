import 'package:ethos/data/routine_store.dart';
import 'package:ethos/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('switches between weekly and monthly calendars', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RoutineStore();
    await store.load();

    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(store: store)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsNothing);
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
  });
}
