# Foundation acceptance evidence

Task13 execution is in progress from approved Task12 baseline `186ab549e3d6a469a61eebf548bbe6f010755b83`. This document will record fresh final commands and outstanding gates; no ready/release claim is made before independent whole-branch review.

## Reproducible gates

- `tool/verify.sh`: formatting includes lib/packages/test/integration_test/tool/docs/testing; analyzes the workspace; tests core/local/feature from their package directories and host tests from root. Use explicit Flutter3.44.7/Dart3.12.2 paths. Flutter invocations are serialized within each checkout because they can collide on generated iOS ephemeral files. The uninterrupted capacity baseline uses the original worktree; other gates use an owned source-only copy with independently generated build directories and a recorded source manifest. Real PBKDF2 work is retained.
- Host `offline_acceptance_test.dart`: actual manager/staff enrollment, capture, duplicate import, acknowledgment, review, correction, reopen, encrypted company recovery and authorized restored query reads. Host keys are explicitly memory-backed test keys; this does not establish native key behavior.
- Native `offline_attendance_test.dart`, `recovery_test.dart`, `secure_storage_test.dart`, `qr_transfer_test.dart`: run on owned physical Android and iPhone. `foundation_suite_test.dart` composes the same tests into an exact prebuilt iOS entrypoint. The optional interactive QR cases require compile-time `RAZE_TRANSFER_INTERACTIVE=true` and an available operator/device.
- `process_recovery_test.dart`: explicit two-launch host-controlled before/committed/visible cases; see [procedure](process-death.md). In-process graceful reopen is not a process-death pass.
- Full [100 non-owner staff / 10,000 genuine manager imports](capacity.md), including all manager-held history, reopen, bounded history and whole-manager archive restoration. Opt-in only, never a reduced silent substitute.

## Native storage and recovery boundaries

Android source sets `allowBackup=false` and full-backup/data-extraction rules exclude root, files, databases, shared preferences and external files for both cloud backup and device transfer. The Task13 debug APK was inspected with `aapt2 dump xmltree`: its packaged manifest retains `allowBackup=false`, references both rule resources, and the packaged exclusions cover all five domains. This is configuration evidence, not an OEM transfer experiment or cloud restore guarantee.

OS key storage uses Android `resetOnError:false`; iOS uses non-synchronizable `unlocked_this_device` accessibility. Existing encrypted catalog bytes with no matching vault key reject with `recoveryRequired`, and catalog writes must not generate replacement keys over them. Actual device tests remove only the run-owned test catalog key; they never inspect or clear unrelated Keychain values. An unavailable keystore must not be treated as an empty fresh catalog.

An orphaned encrypted catalog fails closed and cannot bootstrap a setup profile in that same storage root. The profile gate explains the supported route: restore a verified external archive on a fresh usable installation, and do not delete existing data before usable external recovery material is secured. Retry cannot restore a missing key. Temporary secure-storage errors retain separate Retry guidance; the focused widget test recovers the original profile after availability returns. Host tests prove ciphertext preservation and real archive recovery into fresh storage; physical clean-install recovery is separately verified below. An OS-restored encrypted catalog alone is not recoverable without its device-bound key.

## Evidence retention

[Full-shell captures](screenshots/full-shell-metadata.txt) preserve the accepted Task12 actual Flutter screens and synthetic metadata. [Implementation decisions](implementation-decisions.md) retain all chronological controller rulings and costs, refreshed from the final ledger before cleanup. Huge raw logs, signing details, device selectors, private test seeds and full database files remain in owned local scratch; commit only sanitized commands/results and necessary small synthetic evidence.

Final verification/results and limitations will be appended after execution. Physical, build, process and capacity claims remain independent.

## Recorded build and focused-test results

Flutter3.44.7/Dart3.12.2,2026-10-20; source BASE186ab549e3d6a469a61eebf548bbe6f010755b83 plus Task13 source manifests. The isolated source/build copy contains no user data or historical keychain material.

| Gate | Result |
| --- | --- |
| Focused feature guidance and scanner/service tests |10passed,26s|
| Focused real recovery, missing key and3101-event diagnostic probe |3passed,39s|
| Main Android debug APK |Passed,32.2s; SHA256`a35b6008c5d0adc0a3e2e04599dc57386092e99541a3f9086f5fedf6b5d40f63`|
| Main iOS simulator debug app |Passed,44.5s; preserved file-manifest SHA256`0aadf924c99e9172eee5d15c21c21c4bfe7cbc10095943324f4e1588b59a937f`|
| Exact Android foundation-suite debug APK |Passed,13.1s; preserved SHA256`c81b9c6e3f74fe6175946fb5a76135b085323334046d260b94221cc9894da264`|
| Exact unsigned iPhone foundation suite |Passed,28.3s; privately signed using existing matching local assets, six nested code objects plus app individually verified|

Local signing checked certificate/profile/device compatibility, concrete app/keychain entitlements, unchanged embedded profile and strict signatures. It changed no account, provisioning, trust or keychain settings. Signed app file-manifest SHA256`70955bbe16fa66e18bf0f39b439811cf24f4e0254260ad6a2a255e32d3d6d627`. Local signature checks alone do not prove physical installation or runtime behavior. Source/build-input manifest SHA256`1cd2d2974be63bcf50a3851c87dfb958e23afc18c6a338624ca9f94873ab5ff1`; later host-test braces formatting does not enter these compiled targets.

The first workspace gate stopped on a new test-helper braces lint; the next stopped on formatting of that fix. These were corrected before the third complete gate passed (43 core,159 local plus2explicit opt-in skips,40 feature,9 root tests; formatting and analysis clean). Final verification after subsequent test additions remains pending. The focused scanner test initially stalled because real I/O began in a fake-time continuation; starting the route and continuation inside the real-I/O zone fixed the harness, with a bounded completion check. Drift's multiple-database warning in acceptance setup is expected for independent manager/staff/target paths and executors; reopen awaits the predecessor's close, and teardown closes each device. No blanket warning suppression was added.

## Physical execution results

On2026-10-20, both newly owned synthetic installations ran the exact prebuilt `foundation_suite_test.dart` through `flutter drive --no-pub --debug --use-application-binary=<retained artifact> --target=integration_test/foundation_suite_test.dart --driver=<explicit integration driver> --test-arguments=--packages=<copy package_config.json> --device-id=<selected physical device> --keep-app-running`. The iPhone app used verified existing local signing assets. Android completed in113s; iPhone49s, both exit0, six behavioral tests plus the framework teardown reported as seven passes, with three interactive cases explicitly skipped. Actual OS secure keys, signed attendance flow, directory-fsync archive create/apply, wrong-password rejection, missing run-owned catalog key preservation and native PNG/JPEG decoding of exact1500-byte signed messages passed. [Small synthetic native artifacts](native-evidence/) retain original receipts and metadata.

[Physical process evidence](process-evidence/README.md) records before/committed/visible cases on each phone:6/6passed. The host independently observed the old PID absent and a distinct new process on the same installation before retrieving post assertions. iOS Debug required closing only the owned LLDB session before CoreDevice SIGKILL and waiting for the fresh PID’s stopped event before continuing. Initial failed debugger attempts remain disclosed; they are not app persistence failures or passing runs.

Android disposable uninstall/reinstall recovered its actual previously exported20,420-byte archive retained outside the phone before uninstall; [host and result records](lifecycle-evidence/) bind the external bytes and exact test APK. Reopened authorized queries retained the original signed receipt, approved review and two decision/correction history records. The test supplies host-held bytes to the fresh test app, so it does not prove Files-picker behavior. No global Keychain cleanup is used. The iPhone counterpart also passed using its own prior20,498-byte external archive, with the same exact-byte/history/query checks and fresh namespace. Historical iOS Keychain values were neither cleared nor assumed absent.

The user deferred hands-on printed/screen camera positioning and native picker/share interactions. These are unverified by request, not unavailable equipment and not automated passes. Airplane mode was not changed; no offline-radio proof is claimed. Android24/iOS16 floors remain unverified. Both-platform native suite success does not substitute for those separate gates.

**Capacity is still pending.** The uninterrupted real100staff/10,000import run has not yet reached its target or whole-archive assertions. Partial counts and diagnostic probes are measurements, not a capacity pass. Heavy host memory pressure was observed during concurrent native builds; after those completed, further Task13 Flutter builds/probes/tests were held while the baseline continued. Final current-source workspace verification and normal-entrypoint builds remain pending.
