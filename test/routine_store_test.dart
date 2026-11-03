import 'dart:async';
import 'dart:convert';

import 'package:ethos/data/routine_store.dart';
import 'package:ethos/models/routine.dart';
import 'package:ethos/services/account_sync_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const localRoutine = Routine(
  id: 'local',
  title: 'Local',
  frequency: RoutineFrequency.daily,
  times: [480],
);

const cloudRoutine = Routine(
  id: 'cloud',
  title: 'Cloud',
  frequency: RoutineFrequency.weekly,
  times: [600],
  weekdays: {1},
);

class FakeAccountSync implements AccountSyncGateway {
  CloudAccount? account;
  CloudRoutineData remoteData = const CloudRoutineData(
    routines: [],
    completions: {},
  );
  Object? currentUserError;
  Object? loadError;
  Object? uploadError;
  Object? saveError;
  Object? deleteError;
  Object? completionError;
  Object? signOutError;
  @override
  bool supportsCloudSync = true;
  final updates = StreamController<CloudRoutineData>.broadcast();
  final saved = <Routine>[];
  final deleted = <String>[];
  final completionWrites = <(String, bool)>[];
  final uploaded = <CloudRoutineData>[];
  int signOutCount = 0;

  @override
  Future<CloudAccount?> currentUser() async {
    if (currentUserError case final error?) throw error;
    return account;
  }

  @override
  Future<CloudAccount> signInWithGoogle() async {
    account = const CloudAccount(uid: 'user-1', email: 'user@example.com');
    return account!;
  }

  @override
  Future<void> signOut() async {
    if (signOutError case final error?) throw error;
    signOutCount++;
    account = null;
  }

  @override
  Future<CloudRoutineData> load(String uid) async {
    if (loadError case final error?) throw error;
    return remoteData;
  }

  @override
  Stream<CloudRoutineData> watch(String uid) => updates.stream;

  @override
  Future<void> mergeAndUpload(
    String uid,
    CloudRoutineData mergedData,
    CloudRoutineData remoteData,
  ) async {
    if (uploadError case final error?) throw error;
    uploaded.add(mergedData);
  }

  @override
  Future<void> saveRoutine(String uid, Routine routine) async {
    if (saveError case final error?) throw error;
    saved.add(routine);
  }

  @override
  Future<void> deleteRoutineAndSave(
    String uid,
    String routineId,
    List<Routine> updatedRoutines,
  ) async {
    if (deleteError case final error?) throw error;
    deleted.add(routineId);
    saved.addAll(updatedRoutines);
  }

  @override
  Future<void> setCompletion(
    String uid,
    String key,
    bool isComplete,
  ) async {
    if (completionError case final error?) throw error;
    completionWrites.add((key, isComplete));
  }

  Future<void> dispose() => updates.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loads starter examples and persists CRUD and completion toggles',
      () async {
    final sync = FakeAccountSync();
    final store = RoutineStore(accountSyncService: sync);
    await store.load();
    expect(store.isReady, isTrue);
    expect(store.routines.map((routine) => routine.title),
        ['Apply minoxidil', 'Derma roll']);
    expect(store.routines.first.reduceOnRoutineId, store.routines.last.id);

    await store.saveRoutine(localRoutine);
    await store.saveRoutine(localRoutine.copyWith(title: 'Updated'));
    expect(store.routines, hasLength(3));
    expect(store.routines.firstWhere((item) => item.id == 'local').title,
        'Updated');

    await store.toggleCompletion('local:2026-01-01:0');
    expect(store.completions, {'local:2026-01-01:0'});
    await store.toggleCompletion('local:2026-01-01:0');
    expect(store.completions, isEmpty);

    final linkedId = store.routines.first.reduceOnRoutineId!;
    await store.deleteRoutine(linkedId);
    expect(store.routines.any((item) => item.id == linkedId), isFalse);
    expect(store.routines.first.reduceOnRoutineId, isNull);
    expect(store.routines.first.id, startsWith('minoxidil-'));

    final reloaded = RoutineStore(accountSyncService: FakeAccountSync());
    await reloaded.load();
    expect(_encodeRoutines(reloaded.routines), _encodeRoutines(store.routines));
    expect(reloaded.completions, isEmpty);
    store.dispose();
    reloaded.dispose();
    await sync.dispose();
  });

  test('restores a signed-in account and applies live cloud updates', () async {
    final sync = FakeAccountSync()
      ..account = const CloudAccount(uid: 'user-1', email: 'user@example.com')
      ..remoteData = const CloudRoutineData(
        routines: [cloudRoutine],
        completions: {'cloud-done'},
      );
    final store = RoutineStore(accountSyncService: sync);
    await store.load();
    await store.restoreAccount();

    expect(store.isSignedIn, isTrue);
    expect(store.accountEmail, 'user@example.com');
    expect(store.routines, [cloudRoutine]);
    expect(store.completions, {'cloud-done'});
    expect(sync.uploaded.single.routines, [cloudRoutine]);

    sync.updates.add(const CloudRoutineData(
      routines: [localRoutine],
      completions: {'new-cloud-done'},
    ));
    await Future<void>.delayed(Duration.zero);
    expect(store.routines, [localRoutine]);
    expect(store.completions, {'new-cloud-done'});

    await store.signOut();
    expect(store.isSignedIn, isFalse);
    expect(sync.signOutCount, 1);
    store.dispose();
    await sync.dispose();
  });

  test('merges locally edited data and completions when signing in', () async {
    SharedPreferences.setMockInitialValues({
      'ethos.routines.v1': jsonEncode([localRoutine.toJson()]),
      'ethos.completions.v1': '["local-done"]',
    });
    final sync = FakeAccountSync()
      ..remoteData = const CloudRoutineData(
        routines: [cloudRoutine],
        completions: {'cloud-done'},
      );
    final store = RoutineStore(accountSyncService: sync);
    await store.load();
    await store.signInWithGoogle();

    expect(_encodeRoutines(store.routines),
        _encodeRoutines([cloudRoutine, localRoutine]));
    expect(store.completions, {'cloud-done', 'local-done'});
    expect(store.accountEmail, 'user@example.com');
    store.dispose();
    await sync.dispose();
  });

  test('does not replace another account local cache with empty cloud data',
      () async {
    SharedPreferences.setMockInitialValues({
      'ethos.routines.v1': jsonEncode([localRoutine.toJson()]),
      'ethos.completions.v1': '[]',
      'ethos.account.owner.v1': 'previous-user',
      'ethos.data.isStarter.v1': false,
    });
    final sync = FakeAccountSync()
      ..account = const CloudAccount(uid: 'new-user')
      ..remoteData = const CloudRoutineData(
        routines: [],
        completions: {},
      );
    final store = RoutineStore(accountSyncService: sync);
    await store.load();
    await store.restoreAccount();

    expect(store.routines.map((item) => item.title),
        ['Apply minoxidil', 'Derma roll']);
    expect(store.routines, isNot(contains(localRoutine)));
    store.dispose();
    await sync.dispose();
  });

  test('surfaces restore, upload, mutation, and retry errors', () async {
    final sync = FakeAccountSync()
      ..currentUserError = FirebaseException(
        plugin: 'test',
        message: 'offline',
      );
    final store = RoutineStore(accountSyncService: sync);
    await store.load();
    await store.restoreAccount();
    expect(store.syncError, contains('offline'));

    sync.currentUserError = PlatformException(code: 'offline');
    await store.restoreAccount();
    expect(store.syncError, contains('offline'));

    sync.currentUserError = null;
    sync.remoteData = const CloudRoutineData(routines: [], completions: {});
    await store.signInWithGoogle();

    sync.saveError = FirebaseException(plugin: 'test', code: 'denied');
    await store.saveRoutine(localRoutine);
    expect(store.syncError, contains('denied'));

    sync.saveError = null;
    sync.uploadError = null;
    sync.saveError = PlatformException(code: 'write-failed');
    await store.saveRoutine(localRoutine);
    expect(store.syncError, contains('write-failed'));

    sync.saveError = null;
    sync.completionError = FirebaseException(plugin: 'test', code: 'denied');
    await store.toggleCompletion('k');
    expect(store.syncError, contains('denied'));

    sync.completionError = null;
    sync.deleteError = PlatformException(code: 'delete-failed');
    await store.deleteRoutine('missing');
    expect(store.syncError, contains('delete-failed'));

    sync.uploadError = PlatformException(code: 'retry-failed');
    await store.retryCloudSync();
    expect(store.syncError, contains('retry-failed'));
    sync.uploadError = null;
    await store.retryCloudSync();
    expect(store.syncError, isNull);

    sync.signOutError = PlatformException(code: 'signout-failed');
    await expectLater(store.signOut(), throwsA(isA<PlatformException>()));
    expect(store.isSyncing, isFalse);
    store.dispose();
    await sync.dispose();
  });

  test('handles unsupported sync and an unauthenticated restore', () async {
    final sync = FakeAccountSync()..supportsCloudSync = false;
    final store = RoutineStore(accountSyncService: sync);
    await store.load();
    await store.restoreAccount();
    expect(store.isSignedIn, isFalse);
    await expectLater(
      store.signInWithGoogle(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(store.isSyncing, isFalse);
    store.dispose();
    await sync.dispose();
  });
}

String _encodeRoutines(List<Routine> routines) =>
    jsonEncode(routines.map((routine) => routine.toJson()).toList());
