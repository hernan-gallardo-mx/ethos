import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/routine.dart';
import '../services/account_sync_service.dart';

class RoutineStore extends ChangeNotifier {
  static const _routinesKey = 'ethos.routines.v1';
  static const _completionsKey = 'ethos.completions.v1';
  static const _accountOwnerKey = 'ethos.account.owner.v1';
  static const _starterDataKey = 'ethos.data.isStarter.v1';

  RoutineStore({AccountSyncGateway? accountSyncService})
      : _accountSyncService = accountSyncService ?? AccountSyncService();

  final AccountSyncGateway _accountSyncService;

  List<Routine> _routines = [];
  Set<String> _completions = {};
  bool _isReady = false;
  bool _hasStoredData = false;
  bool _isStarterData = false;
  bool _isSyncing = false;
  String? _accountOwnerUid;
  String? _accountUid;
  String? _accountEmail;
  String? _syncError;
  StreamSubscription<CloudRoutineData>? _cloudSubscription;

  List<Routine> get routines => List.unmodifiable(_routines);
  Set<String> get completions => Set.unmodifiable(_completions);
  bool get isReady => _isReady;
  bool get isSyncing => _isSyncing;
  bool get isSignedIn => _accountUid != null;
  String? get accountEmail => _accountEmail;
  String? get syncError => _syncError;
  bool get supportsCloudSync => _accountSyncService.supportsCloudSync;

  @override
  void dispose() {
    final subscription = _cloudSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final rawRoutines = preferences.getString(_routinesKey);
    final rawCompletions = preferences.getString(_completionsKey);
    _accountOwnerUid = preferences.getString(_accountOwnerKey);
    _isStarterData =
        rawRoutines == null || preferences.getBool(_starterDataKey) == true;
    _hasStoredData =
        (rawRoutines != null || rawCompletions != null) && !_isStarterData;

    if (rawRoutines == null) {
      _routines = _starterRoutines();
      await _saveRoutines(preferences);
      await preferences.setBool(_starterDataKey, true);
    } else {
      final decoded = jsonDecode(rawRoutines) as List<Object?>;
      _routines = decoded
          .map((value) => Routine.fromJson(value as Map<String, Object?>))
          .toList();
    }

    _completions = rawCompletions == null
        ? {}
        : (jsonDecode(rawCompletions) as List<Object?>)
            .map((value) => value as String)
            .toSet();
    _isReady = true;
    notifyListeners();
  }

  Future<void> restoreAccount() async {
    if (!supportsCloudSync) return;
    try {
      final user = await _accountSyncService.currentUser();
      if (user != null) await _connectAccount(user.uid, user.email);
    } on FirebaseException catch (error) {
      _setSyncError(
        'Could not restore cloud account: ${error.message ?? error.code}',
      );
    } on PlatformException catch (error) {
      _setSyncError(
        'Could not restore cloud account: ${error.message ?? error.code}',
      );
    }
  }

  Future<void> signInWithGoogle() async {
    if (!supportsCloudSync) {
      throw UnsupportedError('Cloud sync is available on Android and iOS.');
    }
    _isSyncing = true;
    _syncError = null;
    notifyListeners();
    try {
      final user = await _accountSyncService.signInWithGoogle();
      try {
        await _connectAccount(user.uid, user.email);
      } on FirebaseException catch (error) {
        _setSyncError('Cloud sync failed: ${error.message ?? error.code}');
        rethrow;
      } on PlatformException catch (error) {
        _setSyncError('Cloud sync failed: ${error.message ?? error.code}');
        rethrow;
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> retryCloudSync() async {
    final uid = _accountUid;
    if (uid == null) return;
    _isSyncing = true;
    notifyListeners();
    try {
      await _connectAccount(uid, _accountEmail);
    } on FirebaseException catch (error) {
      _setSyncError('Cloud sync failed: ${error.message ?? error.code}');
    } on PlatformException catch (error) {
      _setSyncError('Cloud sync failed: ${error.message ?? error.code}');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isSyncing = true;
    notifyListeners();
    try {
      await _accountSyncService.signOut();
      await _cloudSubscription?.cancel();
      _cloudSubscription = null;
      _accountUid = null;
      _accountEmail = null;
      _syncError = null;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> saveRoutine(Routine routine) async {
    final index = _routines.indexWhere((item) => item.id == routine.id);
    if (index == -1) {
      _routines = [..._routines, routine];
    } else {
      _routines = [
        for (var itemIndex = 0; itemIndex < _routines.length; itemIndex++)
          if (itemIndex == index) routine else _routines[itemIndex],
      ];
    }
    await _persist();
    await _syncRemote(
        () => _accountSyncService.saveRoutine(_accountUid!, routine));
  }

  Future<void> deleteRoutine(String id) async {
    final updatedRoutines = <Routine>[];
    _routines = _routines.where((routine) => routine.id != id).toList();
    _routines = _routines.map((routine) {
      if (routine.reduceOnRoutineId != id) return routine;
      final updated = routine.copyWith(clearReduceOnRoutineId: true);
      updatedRoutines.add(updated);
      return updated;
    }).toList();
    await _persist();
    await _syncRemote(() async {
      await _accountSyncService.deleteRoutineAndSave(
        _accountUid!,
        id,
        updatedRoutines,
      );
    });
  }

  Future<void> toggleCompletion(String key) async {
    final isComplete = _completions.add(key);
    if (!isComplete) _completions.remove(key);
    await _persist();
    await _syncRemote(
      () => _accountSyncService.setCompletion(_accountUid!, key, isComplete),
    );
  }

  Future<void> _connectAccount(String uid, String? email) async {
    final remoteData = await _accountSyncService.load(uid);
    final canMergeLocal =
        (_accountOwnerUid == null || _accountOwnerUid == uid) && _hasStoredData;
    late final CloudRoutineData mergedData;

    if (canMergeLocal) {
      mergedData = mergeRoutineData(
        CloudRoutineData(routines: _routines, completions: _completions),
        remoteData,
      );
    } else if (!remoteData.isEmpty) {
      mergedData = remoteData;
    } else if (_accountOwnerUid == null) {
      mergedData = CloudRoutineData(
        routines: _routines,
        completions: _completions,
      );
    } else {
      mergedData = CloudRoutineData(
        routines: _starterRoutines(),
        completions: {},
      );
    }

    _routines = mergedData.routines;
    _completions = mergedData.completions;
    _accountUid = uid;
    _accountEmail = email;
    _accountOwnerUid = uid;
    _hasStoredData = true;
    _syncError = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_accountOwnerKey, uid);
    await _persist();
    await _accountSyncService.mergeAndUpload(uid, mergedData, remoteData);
    await _cloudSubscription?.cancel();
    _cloudSubscription = _accountSyncService.watch(uid).listen(
          _applyCloudData,
          onError: (Object error) => _setSyncError('Cloud sync failed: $error'),
        );
  }

  Future<void> _applyCloudData(CloudRoutineData data) async {
    _routines = data.routines;
    _completions = data.completions;
    await _persist();
  }

  Future<void> _syncRemote(Future<void> Function() action) async {
    final uid = _accountUid;
    if (uid == null) return;
    try {
      await action();
      _syncError = null;
    } on FirebaseException catch (error) {
      _syncError = 'Cloud sync failed: ${error.message ?? error.code}';
    } on PlatformException catch (error) {
      _syncError = 'Cloud sync failed: ${error.message ?? error.code}';
    }
    notifyListeners();
  }

  void _setSyncError(String message) {
    _syncError = message;
    notifyListeners();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await _saveRoutines(preferences);
    await preferences.setString(
        _completionsKey, jsonEncode(_completions.toList()));
    if (_isStarterData) {
      _isStarterData = false;
      await preferences.setBool(_starterDataKey, false);
    }
    _hasStoredData = true;
    notifyListeners();
  }

  Future<void> _saveRoutines(SharedPreferences preferences) async {
    await preferences.setString(
      _routinesKey,
      jsonEncode(_routines.map((routine) => routine.toJson()).toList()),
    );
  }

  List<Routine> _starterRoutines() {
    final now = DateTime.now();
    final suffix = '${now.microsecondsSinceEpoch}-${Random().nextInt(9999)}';
    final rollerId = 'roller-$suffix';
    return [
      Routine(
        id: 'minoxidil-$suffix',
        title: 'Apply minoxidil',
        note: 'Beard care',
        frequency: RoutineFrequency.daily,
        times: const [480, 1200],
        reduceOnRoutineId: rollerId,
      ),
      Routine(
        id: rollerId,
        title: 'Derma roll',
        note: 'Three times a week',
        frequency: RoutineFrequency.weekly,
        times: const [480],
        weekdays: const {2, 4, 6},
      ),
    ];
  }
}
