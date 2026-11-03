# Ethos

Ethos is a cross-platform routine tracker for building a routine you can actually keep. It includes weekly and monthly dashboard views, daily completion tracking, flexible schedules, local reminders, and an overlap rule for routines that change on the same day.

The first launch includes an editable example: minoxidil morning and evening, plus derma rolling three times a week. On roller days, minoxidil automatically appears once.

## Set up locally

1. Install the Flutter stable SDK and add `flutter/bin` to your PATH. Install Xcode on macOS for iOS builds, or Android Studio for Android builds. In Android Studio, install an Android SDK and create an emulator. On Windows, use an Android emulator or a physical Android device; iOS builds require macOS and Xcode.
2. From this repository folder, generate the native platform folders while keeping the existing Dart source:

	```sh
	flutter create --platforms=android,ios --project-name ethos .
	```

	If Flutter asks about existing files, keep the files already in this repository.
3. Fetch packages and check the toolchain:

	```sh
	flutter pub get
	flutter doctor
	```

4. Set up cloud sync:
   - Create a Firebase project, enable **Google** under Authentication providers, and create a Cloud Firestore database.
   - Register the Android and iOS apps in Firebase using the matching application IDs. Add your Android signing certificate's SHA fingerprint to the Firebase Android app.
   - Install the FlutterFire CLI (`dart pub global activate flutterfire_cli`) and configure the project:

	```sh
	flutterfire configure --project=<firebase-project-id> --platforms=android,ios
	```

   This generates the native Firebase configuration used by the app. In the iOS app's `Info.plist`, add the reversed client ID from `GoogleService-Info.plist` as a URL scheme for Google sign-in.
   - Install the Firebase CLI if needed and deploy the included per-user Firestore rules:

	```sh
	firebase deploy --project=<firebase-project-id> --only firestore:rules
	```

   The signed-in user's Firebase UID owns all their routines and completion records. Keep these rules enabled; do not use open test-mode rules for a deployed app.

5. Configure Android notifications in `android/app/src/main/AndroidManifest.xml`. Add these permissions directly under the `<manifest>` element:

	   ```xml
	   <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
	   <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
	   ```

	   Add these receivers inside the `<application>` element:

	   ```xml
	   <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
	   <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
		   <intent-filter>
			   <action android:name="android.intent.action.BOOT_COMPLETED" />
			   <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
			   <action android:name="android.intent.action.QUICKBOOT_POWERON" />
			   <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
		   </intent-filter>
	   </receiver>
	   ```

	   In `android/app/build.gradle.kts`, enable core library desugaring inside `android { compileOptions { ... } }` and add the dependency inside `dependencies { ... }`:

	   ```kotlin
	   isCoreLibraryDesugaringEnabled = true
	   ```

	   ```kotlin
	   coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
	   ```

6. Start an emulator or connect a device, then run:

	```sh
	flutter devices
	flutter run
	```

	To choose a device explicitly, use `flutter run -d <device-id>`.

## Run tests

```sh
flutter test
flutter analyze
```

GitHub Actions runs analysis and tests for pushes and pull requests. It also
fails the build if line coverage drops below 79%.

## Notes

- Routines and completion history are cached on-device with `shared_preferences` and synced to Firestore after Google sign-in. On first sign-in, existing local routines and completion history are merged into the account; if the same routine ID exists in both, the local version wins.
- Firestore sync and Google sign-in are available on Android and iOS once Firebase is configured. Without an account, the app continues to work with local-only storage.
- Each user's Firestore data is stored in separate routine and completion documents, rather than one growing document.
- Reminders are local notifications. Enable them per routine and allow notifications when prompted. Android uses inexact scheduling so the app does not require exact-alarm access.
- Weekly and custom routines use selected weekdays. Monthly routines use a day of the month; months without that day will not trigger the routine.
- The overlap adjustment reduces the selected routine to its earliest scheduled time on days when the linked routine is scheduled. It does not mark the hidden occurrence as completed.
