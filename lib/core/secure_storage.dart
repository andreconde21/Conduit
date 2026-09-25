import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The app's one secure storage configuration.
///
/// macOS: the data protection keychain (the plugin default) needs the
/// restricted `keychain-access-groups` entitlement, which an ad-hoc signed
/// desktop build cannot carry (the app is killed at launch). The login
/// keychain works without entitlements, so the desktop test builds use it.
/// Other platforms keep their defaults (Android Keystore, iOS Keychain,
/// libsecret on Linux, Windows Credential Manager).
const conductoreSecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);
