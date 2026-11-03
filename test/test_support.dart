import 'dart:async';

import 'package:ethos/models/routine.dart';
import 'package:ethos/services/account_sync_service.dart';

class LocalOnlyAccountSync implements AccountSyncGateway {
  @override
  bool get supportsCloudSync => false;

  @override
  Future<CloudAccount?> currentUser() async => null;

  @override
  Future<CloudAccount> signInWithGoogle() =>
      throw UnsupportedError('Cloud sync is disabled in this test.');

  @override
  Future<void> signOut() async {}

  @override
  Future<CloudRoutineData> load(String uid) async =>
      const CloudRoutineData(routines: [], completions: {});

  @override
  Stream<CloudRoutineData> watch(String uid) => const Stream.empty();

  @override
  Future<void> mergeAndUpload(
    String uid,
    CloudRoutineData mergedData,
    CloudRoutineData remoteData,
  ) async {}

  @override
  Future<void> saveRoutine(String uid, Routine routine) async {}

  @override
  Future<void> deleteRoutineAndSave(
    String uid,
    String routineId,
    List<Routine> updatedRoutines,
  ) async {}

  @override
  Future<void> setCompletion(String uid, String key, bool isComplete) async {}
}

class ConnectedAccountSync extends LocalOnlyAccountSync {
  CloudAccount account = const CloudAccount(
    uid: 'user-1',
    email: 'user@example.com',
  );
  CloudRoutineData data = const CloudRoutineData(
    routines: [],
    completions: {},
  );
  Object? signInError;
  Object? loadError;
  Object? uploadError;
  Object? signOutError;
  final updates = StreamController<CloudRoutineData>.broadcast();

  @override
  bool get supportsCloudSync => true;

  @override
  Future<CloudAccount?> currentUser() async => account;

  @override
  Future<CloudAccount> signInWithGoogle() async {
    if (signInError case final error?) throw error;
    return account;
  }

  @override
  Future<void> signOut() async {
    if (signOutError case final error?) throw error;
  }

  @override
  Future<CloudRoutineData> load(String uid) async {
    if (loadError case final error?) throw error;
    return data;
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
  }

  Future<void> dispose() => updates.close();
}
