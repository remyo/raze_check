# Offline QR and file transfer

The standalone host now supplies real camera, local QR-image decode, document import, and system share adapters. Package versions remain pinned. Android explicitly keeps mobile_scanner's bundled ML Kit model. Only CAMERA was added to the source permission manifest; debug merged manifests also contain Flutter's debug INTERNET permission and dependency-provided network-state/internal receiver permissions. No photos, storage, or location permission was added. iOS has the specific offline QR camera purpose string.

## Automated checks

Use Flutter/Dart 3.44.7 from `/Users/rem/fvm/versions/3.44.7/bin` or an equivalent configured installation.

```sh
flutter test --no-pub packages/raze_check_local/test/transfer_adapter_test.dart packages/raze_check_feature/test/transfer_context_test.dart --concurrency=1
flutter test --no-pub packages/raze_check_feature/test/enrollment_flow_test.dart packages/raze_check_feature/test/capture_flow_test.dart packages/raze_check_feature/test/review_flow_test.dart test --concurrency=1
flutter analyze --no-pub
flutter build apk --debug --no-pub
flutter build ios --debug --no-codesign --no-pub
flutter build ios --simulator --debug --no-pub
```

From `android`, `./gradlew :app:testDebugUnitTest --offline` tests the actual Kotlin streaming helper. The Swift Foundation helper can be checked on macOS by extracting the section of `ios/Runner/AppDelegate.swift` beginning at `struct DocumentLimitError`, prepending `import Foundation`, appending `docs/testing/check_native_streaming.swift`, and running that temporary `.swift` file with `swift`. These helper tests do not prove document-provider behavior.

## Physical acceptance procedure (unverified in Task 9)

Recheck device availability and exact package ownership immediately before every installation. Do not replace a newly present app of unknown ownership. Do not alter an actively used device's foreground or network state. Obtain a coordinated free-device window for operator-led airplane-mode testing. Use only existing local signing assets; no account/provisioning updates or automatic license acceptance.

`integration_test/qr_transfer_test.dart` contains automatic physical PNG/JPEG decoding tests using a public deterministic signed attendance fixture padded to exactly 1,500 original UTF-8 bytes. Both exact bytes and signature verification must pass. It injects the staged image path only; the decoder is actual mobile_scanner native ML Kit/Vision. This path injection is not evidence for the native Files bridge. iOS Simulator cannot satisfy native image decoding.

After target ownership and signing are established, run the integration test on each physical device in airplane mode, with Wi-Fi also off. The default run does not drive system pickers or the camera. `--dart-define=RAZE_TRANSFER_INTERACTIVE=true` additionally enables live scan, actual native Files selection, and system sharing tests. An operator must present the exact fixture QR on another display/print and select its message/image files. Skipped interactive tests are pending gates, never passing hardware evidence.

Generate fixture files on the workstation:

```sh
flutter test --no-pub docs/testing/generate_transfer_fixture.dart
sips -s format jpeg /tmp/raze-task9-fixture.png --out /tmp/raze-task9-fixture.jpg
```

Prepare those public test-only files in the target device's Files provider without overwriting user data. The checked-in JPEG/transport Dart fixture is generated from those same bytes. Test local message visibility for `.razecheck-message`, local PNG and JPEG, multiple QRs, camera permission denial, unavailable cloud-provider content, picker cancel, share dismissal, and actual receiving-app readability after the share sheet returns. Include iPad anchoring when hardware is available. Share completion is never delivery or backup persistence.

If using a prebuilt iOS integration app with `flutter drive --use-application-binary`, use `--keep-app-running`; default drive cleanup may uninstall the app. Record every test install and fixture namespace before allowing destructive Task 13 scenarios.

## Current evidence and gates

Task 9 compiled Android debug, unsigned iOS device (including integration target), and iOS Simulator debug targets. Native Kotlin and Swift streaming helper checks passed. Physical runtime tests were not executed: Android was occupied by an unrelated Flutter run, while the iPhone explicit manual-signing build rejected the existing matching Xcode-managed profile. Swift package resource targets also rejected a globally supplied provisioning profile. No provisioning settings/accounts were changed and no app was installed. Read-only package rechecks found the target absent on Android's current user 0 and on the connected iPhone; that observation does not authorize a future overwrite or prove an empty iOS Keychain.

**Disposable installation ledger: none created on either platform by Task 9.** No device data was read, cleared, or uninstalled, and no device airplane/network mode was changed. Minimum OS execution, first-install offline camera availability, physical exact-byte PNG/JPEG/live QR decoding, native picker/provider behavior, permission denial, recipient readability, and iPad presentation remain unverified.

The macOS host slept repeatedly during some test/build runs (power logs show 902–903 second Maintenance Sleep intervals). Those timed-out tests were rerun successfully with a temporary process-scoped `caffeinate -is` assertion; no power preferences were changed.
