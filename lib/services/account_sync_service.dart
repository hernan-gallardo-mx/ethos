import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/routine.dart';

class CloudRoutineData {
  const CloudRoutineData({
    required this.routines,
    required this.completions,
  });

  final List<Routine> routines;
  final Set<String> completions;

  bool get isEmpty => routines.isEmpty && completions.isEmpty;
}

class CloudAccount {
  const CloudAccount({required this.uid, this.email});

  final String uid;
  final String? email;
}

abstract interface class AccountSyncGateway {
  bool get supportsCloudSync;
  Future<CloudAccount?> currentUser();
  Future<CloudAccount> signInWithGoogle();
  Future<void> signOut();
  Future<CloudRoutineData> load(String uid);
  Stream<CloudRoutineData> watch(String uid);
  Future<void> mergeAndUpload(
    String uid,
    CloudRoutineData mergedData,
    CloudRoutineData remoteData,
  );
  Future<void> saveRoutine(String uid, Routine routine);
  Future<void> deleteRoutineAndSave(
    String uid,
    String routineId,
    List<Routine> updatedRoutines,
  );
  Future<void> setCompletion(String uid, String key, bool isComplete);
}

CloudRoutineData mergeRoutineData(
  CloudRoutineData localData,
  CloudRoutineData remoteData,
) {
  final routinesById = {
    for (final routine in remoteData.routines) routine.id: routine,
    for (final routine in localData.routines) routine.id: routine,
  };
  return CloudRoutineData(
    routines: routinesById.values.toList(),
    completions: {...remoteData.completions, ...localData.completions},
  );
}

class AccountSyncService implements AccountSyncGateway {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _firebaseInitialized = false;
  bool _googleInitialized = false;

  @override
  bool get supportsCloudSync =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<CloudAccount?> currentUser() async {
    await _ensureFirebaseInitialized();
    final user = await FirebaseAuth.instance.authStateChanges().first;
    return user == null ? null : CloudAccount(uid: user.uid, email: user.email);
  }

  @override
  Future<CloudAccount> signInWithGoogle() async {
    await _ensureFirebaseInitialized();
    await _ensureGoogleInitialized();
    if (!_googleSignIn.supportsAuthenticate()) {
      throw UnsupportedError('Google sign-in is unavailable on this device.');
    }

    final googleUser = await _googleSignIn.authenticate();
    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google sign-in did not return an ID token.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final user =
        (await FirebaseAuth.instance.signInWithCredential(credential)).user;
    if (user == null) throw StateError('Firebase sign-in returned no user.');
    return CloudAccount(uid: user.uid, email: user.email);
  }

  @override
  Future<void> signOut() async {
    await _ensureFirebaseInitialized();
    await FirebaseAuth.instance.signOut();
    await _ensureGoogleInitialized();
    await _googleSignIn.signOut();
  }

  @override
  Future<CloudRoutineData> load(String uid) async {
    final user = FirebaseFirestore.instance.collection('users').doc(uid);
    final routineSnapshot = await user.collection('routines').get();
    final completionSnapshot = await user.collection('completions').get();

    return CloudRoutineData(
      routines: routineSnapshot.docs
          .map((document) =>
              Routine.fromJson(Map<String, Object?>.from(document.data())))
          .toList(),
      completions:
          completionSnapshot.docs.map((document) => document.id).toSet(),
    );
  }

  @override
  Stream<CloudRoutineData> watch(String uid) {
    final user = FirebaseFirestore.instance.collection('users').doc(uid);
    final controller = StreamController<CloudRoutineData>();
    List<Routine>? routines;
    Set<String>? completions;

    void emitIfReady() {
      if (routines != null && completions != null) {
        controller.add(CloudRoutineData(
          routines: routines!,
          completions: completions!,
        ));
      }
    }

    final routineSubscription = user
        .collection('routines')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) =>
                  Routine.fromJson(Map<String, Object?>.from(document.data())))
              .toList(),
        )
        .listen((value) {
      routines = value;
      emitIfReady();
    }, onError: controller.addError);
    final completionSubscription =
        user.collection('completions').snapshots().listen(
      (snapshot) {
        completions = snapshot.docs.map((document) => document.id).toSet();
        emitIfReady();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await routineSubscription.cancel();
      await completionSubscription.cancel();
    };
    return controller.stream;
  }

  @override
  Future<void> mergeAndUpload(
    String uid,
    CloudRoutineData mergedData,
    CloudRoutineData remoteData,
  ) async {
    final completionsToWrite =
        mergedData.completions.difference(remoteData.completions).toList();

    await _writeRoutines(uid, mergedData.routines);
    await _writeCompletions(uid, completionsToWrite);
  }

  @override
  Future<void> saveRoutine(String uid, Routine routine) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('routines')
        .doc(routine.id)
        .set(routine.toJson());
  }

  @override
  Future<void> deleteRoutineAndSave(
    String uid,
    String routineId,
    List<Routine> updatedRoutines,
  ) async {
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('routines');
    final batch = FirebaseFirestore.instance.batch()
      ..delete(collection.doc(routineId));
    for (final routine in updatedRoutines) {
      batch.set(collection.doc(routine.id), routine.toJson());
    }
    await batch.commit();
  }

  @override
  Future<void> setCompletion(
    String uid,
    String key,
    bool isComplete,
  ) async {
    final reference = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('completions')
        .doc(key);
    if (isComplete) {
      await reference.set({'key': key});
    } else {
      await reference.delete();
    }
  }

  Future<void> _writeRoutines(String uid, List<Routine> routines) async {
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('routines');
    for (var start = 0; start < routines.length; start += 450) {
      final batch = FirebaseFirestore.instance.batch();
      for (final routine in routines.skip(start).take(450)) {
        batch.set(collection.doc(routine.id), routine.toJson());
      }
      await batch.commit();
    }
  }

  Future<void> _writeCompletions(String uid, List<String> keys) async {
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('completions');
    for (var start = 0; start < keys.length; start += 450) {
      final batch = FirebaseFirestore.instance.batch();
      for (final key in keys.skip(start).take(450)) {
        batch.set(collection.doc(key), {'key': key});
      }
      await batch.commit();
    }
  }

  Future<void> _ensureFirebaseInitialized() async {
    if (_firebaseInitialized) return;
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    _firebaseInitialized = true;
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await _googleSignIn.initialize();
    _googleInitialized = true;
  }
}
