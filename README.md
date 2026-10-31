# sales_tracking

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android release APK

To build an installable release APK, configure release signing with the same
keystore used for the previously installed version. Without the original
keystore, Android will reject an update; uninstalling the old app first allows
a fresh install but deletes its local app data.

Create `android/key.properties` with the credentials for your existing
keystore. Keep this file and the keystore private; both are excluded from Git.
For example, if the keystore is `android/upload-keystore.jks`:

```properties
storeFile=upload-keystore.jks
storePassword=YOUR_KEYSTORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

Then build the APK with `flutter build apk --release`. The output is
`build/app/outputs/flutter-apk/app-release.apk`. If the old keystore is unavailable, create a new keystore. Android will not
install an APK signed with this new key over an app signed with the previous
key. Uninstall the existing app before installing this release; uninstalling
deletes local app data. Back up the new keystore and `key.properties` securely
for future updates, and never commit either file.
