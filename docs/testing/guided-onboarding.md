# Help & Guides

The standalone app introduces Raze Check on first open. Use **Next** and **Back** to read the five welcome pages, **Skip** to leave, or **Get started** on the last page to continue to the profile chooser. Reopen the introduction through **Settings → Help & Guides → Replay introduction**.

After unlocking and choosing a company, contextual **Show me how** invitations and the library explain the controls available to that session. **Start**, **Continue**, and **Restart** open explanations; **Show me** opens a supported destination after validating the current session and permissions. A missing or hidden control leaves a readable explanation. Guide controls remain scrollable in short or enlarged-text layouts.

**Next** only advances an explanation. It does not check in, read a code, send a message, approve attendance, export a file, create or restore an archive, confirm an external backup, freeze a source device, or activate recovery. **Viewed** records that a guide was finished; it does not certify that a business operation succeeded. Use the actual screen controls to perform each operation and read its real result.

## Available topics

The catalog contains ten guides and 46 authored step positions. The 23 audience/path pairs adapt those positions to the current context, including management-side staff replacement within the same five device-move positions and four recovery paths.

| Guide | What it explains |
| --- | --- |
| Welcome to Raze Check | Offline records, profiles, receipts, status and protection |
| Set up and switch companies | Company creation, joining, time zone and company selection |
| Invite staff or join a company | Invitations, identity checks, requests, approval and membership |
| Check in and check out | Workplace codes and separate attendance receipts |
| Send receipts and receive updates | Receipt delivery, acknowledgments and returned decisions |
| Review attendance and corrections | Details, decisions, corrections and signed history |
| Manage staff and operator access | Staff records and company-scoped permissions |
| Read and export attendance reports | Report scope, dates and permitted CSV export |
| Back up and restore records | Encrypted archives, external custody and passive restore |
| Move to a new device | Staff replacement and owner source, target or lost-source paths |

Before unlock, only the introduction and general safety explanations are available. Reading a guide never grants a role or permission. The recovery library follows the recovery workspace's selected company, membership and path; the dashboard's selection does not substitute for that context. Restricted company operators cannot open the personal/company backup screen. Passive restore does not activate membership or management authority. Staff replacement applies the received-record archive before the grant; owner source handover explicitly freezes the source before its snapshot. Missing records cannot be reconstructed by an explanation or a recovery flow.

## Progress and embedding

Progress is shared across profiles on this installation, keyed only by guide and variant. Continuing resumes an available saved step; restarting begins its explanation again. Dismissing an invitation does not perform or finish its workflow. Progress stores no person/company identifiers, passphrases, receipt contents or permission grants. Its bounded local preference file is separate from attendance records and excluded from recovery archives. A preference failure leaves the app usable; a host without a progress adapter keeps progress for the session.

The standalone host enables automatic welcome. Embedded `RazeCheckFeature` hosts default to automatic welcome off and can supply `CheckFeatureHost.guideProgress` and `GuidePresentationConfig(automaticWelcome: true)`. Settings and guide routes retain the original protected session boundary. Lock, backgrounding, company/permission changes and host exit suspend or invalidate protected explanations rather than retaining stale authority.

## Verification and captures

The final visual test passed 7/7. All eight final synthetic images were opened and inspected. [Capture metadata](screenshots/guides/metadata.json) records source commit, dirty visual-source SHA-256, exact command/timing, toolchain, fixture state and final PNG hashes.

| File | Actual feature scene | Viewport | Text scale |
| --- | --- | --- | --- |
| [welcome-light.png](screenshots/guides/welcome-light.png) | First welcome page, light | 390×844 | 1 |
| [welcome-dark.png](screenshots/guides/welcome-dark.png) | First welcome page, dark | 390×844 | 1 |
| [staff-guides.png](screenshots/guides/staff-guides.png) | Staff Help & Guides library | 390×844 | 1 |
| [capture-highlight.png](screenshots/guides/capture-highlight.png) | Staff capture guide at the actual Check in control | 390×844 | 1 |
| [management-review.png](screenshots/guides/management-review.png) | Owner review guide over received attendance, dark | 390×844 | 1 |
| [backup-tablet.png](screenshots/guides/backup-tablet.png) | Owner backup guide | 768×1024 | 1 |
| [welcome-large-text.png](screenshots/guides/welcome-large-text.png) | First welcome page with enlarged text | 320×900 | 2 |
| [capture-landscape.png](screenshots/guides/capture-landscape.png) | Existing Staff capture scene after rotation | 844×390 | 1 |

`packages/raze_check_feature/test/guide_visual_test.dart` uses the actual feature entry, real synthetic local services, bundled Manrope/MaterialIcons and a boundary above the complete navigator and guide presentation. Assertions check representative light/dark, phone/tablet, enlarged-text and rotated layouts, visible/missing targets, reduced motion, labeled semantics, 48-pixel guide controls, anchor alignment and panel separation. Existing presentation tests cover the broader layout combinations. Screenshots are actual Flutter widget renders of synthetic data; they are separate from physical-device evidence.

Run from the feature package with the workspace Flutter version:

```sh
RAZE_VISUAL_DIR=/absolute/path/to/raze_check/docs/testing/screenshots/guides "$FLUTTER_BIN" test --no-pub --concurrency=1 test/guide_visual_test.dart
```

The capture source is `c0aa12f` plus the visual-test input recorded by SHA-256 in metadata; that test and these PNGs were committed in `9ea8161`. Subsequent native-transfer guards, contextual management copy and failure/restart notices do not alter these normal captured states. Screenshots retain their actual capture revision rather than being relabeled as later builds.

Verification uses Flutter 3.44.7 / Dart 3.12.2 at `/Users/rem/fvm/versions/3.44.7/bin/`. The following commands all exited 0. Private raw logs preserve exact commands, input hashes and UTC start/end times under `build/artifacts/guided-onboarding/task7/`.

| CWD | Command | Result and source |
| --- | --- | --- |
| Root | `dart format --output=none --set-exit-if-changed lib packages test` | Clean at Task7 inputs and `df10eac` |
| Root | `flutter analyze --no-pub` | No issues at Task7 inputs and `df10eac` |
| Feature package | `flutter test --no-pub --concurrency=1 test/guide_visual_test.dart` with `RAZE_VISUAL_DIR` set as above | 7/7; eight inspected images; capture revision above |
| Feature package | `flutter test --no-pub --concurrency=2` | 164/164; Task7 code later committed as `9ea8161` |
| Root | `flutter test --no-pub test --concurrency=2` | 11/11; Task7 code in `9ea8161`, including both actual restricted-operator entry cases |
| Core package | `dart test test/guide_progress_test.dart` | 2/2; `9ea8161` inputs; immutable bounded contract |
| Local package | `flutter test --no-pub test/guide_progress_store_test.dart` | 11/11; `9ea8161` inputs; bounded atomic persistence and failure behavior |
| Feature package | Final-review affected guide/native/report/enrollment/recovery/transfer test set | 136/136; final-fix report for `df10eac` |
| Feature package | `flutter test --no-pub test/guide_native_callbacks_test.dart test/guide_presentation_test.dart --name 'pauses exact scene\|feature notice'` | 6/6 after analyzer fixes; `df10eac` |

The final fix affected set comprises `guide_catalog_test.dart`, `guide_controller_test.dart`, `guide_presentation_test.dart`, `guide_library_test.dart`, `guide_navigation_test.dart`, `guide_entry_test.dart`, `guide_workflows_test.dart`, `guide_recovery_test.dart`, `guide_native_callbacks_test.dart`, `report_screen_test.dart`, `enrollment_flow_test.dart`, `recovery_screen_test.dart`, `replacement_operator_test.dart` and `transfer_context_test.dart`. It covers 23 audience pairs, guarded native CSV/history callbacks, both actual operator permission flows, manager replacement anchors/counterpart instructions, lost-source fallback and narrow/large-text accessible notices. The final welcome projection at `6ded4d6` added 3/3 passing targeted checks for obsolete saved-step restart with/without save failure and existing failed-preference exit; scoped analysis/format were clean. The full feature/root/business suites were preserved rather than repeated after this targeted fix wave.

## Normal build and device evidence

Normal artifacts use source `6ded4d61511d11fe5dd1d63c1ea6423ba3fa6424`, default `lib/main.dart` (SHA-256 `303fbdb47816373cae59b4a8a177e3d83f3611ce07b20237bbfcc51559edb2c0`) and no modified Dart source inputs. README/evidence drafts do not enter the compiled app. No acceptance entry point or synthetic test data is used in these builds. Android API 24 / iOS 16.0 floors and the dependency lockfile are retained. Prior foundation artifacts remain at their separate ignored paths.

| Root command | Result | Retained ignored artifact |
| --- | --- | --- |
| `flutter build apk --debug --no-pub` | Exit 0 | `build/artifacts/guided-onboarding/task7/final/android/raze-check-normal-debug.apk` |
| `flutter build ios --simulator --debug --no-pub` | Exit 0 | `build/artifacts/guided-onboarding/task7/final/ios-simulator/Runner.app` |

Android APK SHA-256: `32179d0035db9f97a555404ce162ea6685287a24564c492104924009b61b0d90`. The iOS simulator app contains 91 files. Its SHA-256 manifest hash is `aa150056e16119df1a1e764a0b3f115283c667d34c1154c1cf00c7b4bde5f12f`. The manifest sorts regular files by POSIX relative path, writes each file SHA-256 followed by two spaces and its relative path on a UTF-8 LF line, then hashes the complete manifest bytes. This identifies directory content rather than treating a directory as one file. Exact build commands, file manifest and UTC start/end times are retained in private stage records. No physical iPhone signing retry has been attempted.

The authorized Android phone received that same normal APK through `adb install -r` (exit 0, Success), without uninstalling, clearing storage or manufacturing a reset. `am start -W` exited 0 with Status ok/COLD; first-install time remained unchanged. A physical runtime capture on 2026-10-20 at 12:34:49 UTC was opened and inspected: first Welcome page, Step 1 of 5, Offline attendance, approved logo and teal navigation controls. The raw screenshot/device details remain private; this runtime observation is separate from the eight synthetic images.

Physical iPhone installation remains deferred because the selected signing team lacks a usable Xcode account/profile. Two-phone printed-camera exchange and hands-on native picker/share checks also remain deferred by the user. An iOS simulator build, synthetic widget render or Android welcome screenshot does not establish those manual checks or two-device parity. See the [device matrix](device-matrix.md) for the broader device boundaries.

## Implementation decisions

- Settings and custom host routes borrow the original validated audience and anchor registry. Domain validation stays separate from route visibility; outer-route, lock and stale-context tests cover the added internal context access.
- Settings/library **Show me** returns through a controlled original scene token under the same authority. This preserves guarded navigation and draft state; unrelated navigation, user actions and lock still cancel it.
- Passive guide-target wrappers were prepared in parallel in exclusively owned leaf files. Shared state, runtime checks and Git writes stayed serialized; the primary reconciled the combined targets and workflow tests before review.
- Backup/device guides remain contextual to their actual recovery page and its Settings entry. This follows the selected recovery company/path without carrying dashboard authority across domains; a universal navigation index would be separate work.
- Visual fixtures were prepared in their exclusively owned test while product integration finished. Capture, full integration verification and review waited for stable recovery interfaces and coordinated runtime ownership; stale fixture assumptions were corrected through real renders.
- The final reviewer began read-only review of committed product tasks while verification/builds ran, then receives the final evidence delta before one final verdict. This overlaps independent work; final integration review and no-push-until-approved remain required.
- The manager approval page uses a `staff-management` audience variant within the existing new-device guide. It keeps the five semantic positions/four recovery paths and both membership-management and attendance-export checks, with real manager controls and staff-side counterpart instructions; the extra catalog/progress variant requires maintenance and permission/copy tests.
- Welcome also presents an obsolete-step restart explanation together with any persistent save-failure copy, using its existing scrollable/live-region presentation. A narrow regression completed the original notice fix without a broad review/test restart; this adds one message to maintain and final evidence identifies the source actually built.
