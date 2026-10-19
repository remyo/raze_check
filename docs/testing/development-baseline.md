# Development baseline — 19 October 2026

## Workspace and toolchain

The standalone Dart pub workspace contains the Flutter host and
`raze_check_core`, `raze_check_local`, and `raze_check_feature`. All three packages
use `resolution: workspace`, share root `pubspec.lock`, and have no Raze Store
path dependency. Core is pure Dart; native adapters and reusable UI have separate
Flutter packages. `.superpowers/` remains ignored.

Flutter 3.44.7 (framework 84fc5cbb22, engine 69c8c61792), Dart 3.12.2, macOS
26.3.1 on arm64, Xcode 26.6 (17F113), CocoaPods 1.17.0, Android SDK 36.1.0,
and Android Studio's JDK 21.0.10 were observed. Flutter generated AGP 9.0.1,
Kotlin 2.3.20, and Gradle 9.1.0. SDK selection is `.fvmrc` plus an explicit
command path or process-local PATH; no shell startup files were changed.

Android development namespace/application ID and iOS bundle ID are
`com.remyo.razecheck`. Android minimum SDK is API 24; compile/target are the
Flutter 3.44.7 defaults (36). iOS minimum deployment target is 16.0. Display name
is Raze Check on both platforms. No personal signing team is committed.
Flutter's generated Swift Package Manager integration is used for iOS.

## Dependency resolution

The original pins failed resolution:

```text
Because raze_check_local depends on drift_dev 2.35.1 which depends on analyzer
>=13.0.0 <15.0.0, analyzer >=13.0.0 <15.0.0 is required.
So, because raze_check_core depends on test 1.31.0 which depends on analyzer
>=8.0.0 <13.0.0, version solving failed.
```

Published manifests also show build_runner 2.16.2 requires analyzer >=14.3.0
<15.0.0. To preserve Flutter's test/test_api compatibility, the committed pins
are Drift 2.34.0, drift_dev 2.34.0, and build_runner 2.15.1. Their intersection
resolves analyzer 12.1.0 and build 4.0.7. No dependency overrides were used.
The lockfile resolves file_selector_ios 0.5.3+6, compatible with this Flutter
SDK; sqlite3 3.5.2 provides Drift's native assets without another SQLite binary
package. The remaining prescribed dependency pins are retained, including
Riverpod 3.4.3, test 1.31.0, and timezone 0.11.0. Bundled latest timezone data
is initialized at startup. Local archive support is due in Task 10.

Branding uses the approved original master PNG and preserved generation prompt.
`flutter_launcher_icons` 0.14.4 creates Android/iOS launcher assets from that
master with `dart run flutter_launcher_icons`; no design was regenerated.

## Reproduction

Use the SDK explicitly on this workstation, or put its `bin` directory on the
PATH of the current process only:

```sh
export PATH="/Users/rem/fvm/versions/3.44.7/bin:$PATH"
flutter pub get
(cd packages/raze_check_core && dart test test/contracts_test.dart)
(cd packages/raze_check_core && dart test)
flutter test
flutter analyze --no-pub
flutter build apk --debug --no-pub
flutter build ios --simulator --debug --no-pub
```

Run `pub get` sequentially before no-pub verification commands: simultaneous
Flutter commands with automatic pub generation can race over iOS ephemeral
Swift packages. An initial parallel analysis attempt encountered `Unable to
delete ... ios/Flutter/ephemeral/Packages/.packages`; rerunning analysis with
`--no-pub` succeeded without source changes.

## Evidence and limits

Contract TDD: the initial test failed to load because SecureIds and contracts
were absent; after implementation, all four tests passed. The initial startup
widget test failed to find Raze Check in the generated counter app; after
replacement the root suite passed (one test), including bundled timezone lookup.
`flutter analyze --no-pub` reported `No issues found!`.

The iOS simulator build succeeded: `Xcode build done. 57.5s` and
`Built build/ios/iphonesimulator/Runner.app`.

Android debug build succeeded on its third attempt: `Running Gradle task
'assembleDebug'... 44.5s` and `Built build/app/outputs/flutter-apk/app-debug.apk`.
The first two attempts failed downloading sqlite3 3.5.2 precompiled Android
assets from GitHub release storage (`HttpException: Connection reset by peer`),
first arm64 then x64. Retrying the unchanged build populated the native-asset
cache and completed. No alternate SQLite binary package or hook override was
introduced. No license/signing gate blocked these debug builds.

`flutter doctor -v` still reports `Some Android licenses not accepted`.
No license terms were accepted automatically. If a later SDK component requires
those licenses, the user must review them through `flutter doctor
--android-licenses`. Current build failures are reported by their actual cause;
a doctor warning alone is not treated as a failed license gate.

`cryptography_flutter` applies Kotlin Gradle Plugin and Flutter warns that future
Flutter versions will require Built-in Kotlin plugin migration. It remains
pinned to the approved version for this baseline.

Compilation and startup tests do not prove camera, encryption, attendance,
permissions, recovery, physical-device behavior, or release signing. No app was
distributed, uploaded, or submitted to an app store.

## Local identity and vault boundary (Task 2)

Profiles are local identities, without a network account. The small v1 profile
and installation catalog lives at application-support `raze_check/profiles.v1.enc`.
It is AES-256-GCM encrypted and replaced through a flushed staging file and
same-directory atomic rename. Identity mutations reject concurrent provisioning
against the same catalog across service instances in the app isolate. Domain staff/attendance records belong to Drift,
not this catalog or secure storage.

OS secure storage holds independent random 32-byte person/company vault keys,
Ed25519 installation signing seeds, and PBKDF2 unlock credential material. Every
profile has its own installation/signing identity. Installation signing keys are
not portable recovery keys. iOS keys use `unlocked_this_device` with keychain
synchronization disabled. All iOS build configurations include the plugin-required empty keychain access-group entitlement; no shared App Group is configured. Android disables the plugin's destructive `resetOnError` behavior; failed key reads preserve all stored material.
A missing key for encrypted state returns `recoveryRequired`; no read path
silently generates a key. Key creation is a separate provisioning operation.

Unlock verifiers use PBKDF2-HMAC-SHA256, 600,000 iterations, a random 16-byte salt,
and 32-byte output. Derivation runs in a worker isolate. Creation requires at
least 12 Unicode scalar values and UI confirmation. The verifier comparison
accumulates byte differences. Sessions are private live objects authorized by a
service-owned identity map, expire after five minutes of inactivity, and are
never serialized. Explicit lock clears live handles and removes protected views;
resume revalidates the original session. Clock rollback fails closed.

AES payload v1 is `1 | 12-byte nonce | ciphertext | 16-byte GCM tag`; each seal
uses secure randomness. GCM associated data encodes a domain plus scope ID,
record ID, and revision as an unambiguous JSON list. Scope keys are not derived
from passphrases. Ed25519 verification accepts only 32-byte public keys and
64-byte signatures and remains possible without the private key.

Key-bound local state must not migrate through operating-system backups.
Android disables automatic backup and explicitly excludes private roots, files,
databases, preferences, and external data from cloud backup and device transfer.
iOS marks the private application-support directory excluded from backup through
a narrow native path-checked channel before services start. Portable recovery
must use the explicitly encrypted archives in Tasks 10–11. These configuration
choices and unit tests are not proof of secure-storage parity on hardware.

### Pending device verification matrix

| Gate | Android physical | iOS physical |
| --- | --- | --- |
| Create profile, force-stop, relaunch and unlock with the same IDs/keys | Pending Task 13 | Pending Task 13 |
| Sign and decrypt after relaunch; wrong secret fails | Pending Task 13 | Pending Task 13 |
| Background for five minutes, resume, protected views are cleared | Pending Task 13 | Pending Task 13 |
| OS backup/transfer excludes key-bound records and keys | Pending Task 13 | Pending Task 13 |
| Missing key over existing encrypted data requires recovery | Pending Task 13 | Pending Task 13 |
| Secure storage behavior across device lock, reboot, reinstall | Pending Task 13 | Pending Task 13 |

No device key persistence, reinstall recovery, or platform parity is claimed by
Task 2. Explicit archive export/import remains a later implementation gate.

Host KDF benchmark: PBKDF2-HMAC-SHA256, 600,000 iterations, in a worker isolate
took 3,546 ms on the host debug Dart VM while native verification was running.
This is a workstation observation, not a mobile-device performance guarantee.
