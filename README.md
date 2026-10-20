# Raze Check

An offline Android/iOS attendance foundation. A management installation enrolls staff, receives signed attendance receipts, records review decisions and corrections, exports CSV reports, and creates encrypted recovery archives. Staff keep their original receipts; local saving, manager receipt and approval are separate states.

The Flutter host composes `raze_check_core` (contracts and protocol), `raze_check_local` (SQLite, encryption, OS keys and native adapters), and `raze_check_feature` (embeddable UI). No Raze Store installation, cloud account or backend is required. Schedules, leave, overtime, payroll, remote coordination and Store integration remain later work.

## First use on two phones

1. On both phones, choose **Create local profile** and **Save profile**. Keep each profile passphrase. On the manager phone choose **Create company**, enter its details and select its IANA time zone.
2. Manager: **Invite staff → Create invitation → Send invitation**. Staff: **Join company**, read the invitation, compare its root fingerprint with the manager, then **Confirm and request to join**. Manager: **Read join request → Approve and send membership**. Staff: **Receive membership** to activate access. Transfer menus offer **Scan QR**, **QR image from Files**, or **Message from Files**.
3. Manager: **Workplace QR → Display workplace code**. Staff: **Record attendance**, choose **Check in** or **Check out**, then read that workplace code. Wait for **Saved on this device**; this is still separate from manager receipt and approval.
4. Staff sends **Share receipt**. Manager opens **Attendance → Import receipt or correction**, reads it, and opens **View attendance**. Return **Show receipt acknowledgment** / **Share selected return** to the staff’s **Receive attendance update**. Use **Approve attendance** or **Reject attendance**, then return the selected decision the same way.
5. Open **Backup / recovery → Encrypted backup and passive restore**, choose the intended scope, and **Create encrypted backup** with its passphrase. Use **Save or share encrypted backup**. Confirm **I verified a saved copy outside this app** only after independently checking that external file.

These are current UI labels for later hands-on testing. The two-phone printed-camera and native picker/share interaction checks remain deferred by the user; see the device matrix for what was actually verified.

## Development

Use Flutter **3.44.7 / Dart 3.12.2** and the committed workspace lockfile:

```sh
flutter pub get
FLUTTER_BIN=/absolute/path/to/flutter DART_BIN=/absolute/path/to/dart ./tool/verify.sh
flutter build apk --debug --no-pub
flutter build ios --simulator --debug --no-pub
```

The verification script runs formatting, analysis, core/local/feature suites in their own package directories, and root host tests. Native device suites and the expensive full capacity fixture are explicit separate gates; a passing host script does not establish physical parity. Generator maintenance, when needed, runs `dart run build_runner build` from `packages/raze_check_local`.

See [acceptance evidence](docs/testing/foundation-acceptance.md), [device matrix](docs/testing/device-matrix.md), [capacity procedure](docs/testing/capacity.md), [process-death procedure](docs/testing/process-death.md), and [implementation decisions](docs/testing/implementation-decisions.md). The [synthetic dashboard captures](docs/testing/screenshots/full-shell-metadata.txt) are actual Flutter widget renders, not phone acceptance results.

Private app storage and local keys are not an external backup. Export an encrypted archive through the system share sheet and independently verify that the external file exists and can be opened with its passphrase. Opening a share sheet alone does not establish delivery. Android backup rules request exclusion from automatic cloud/device transfer; iOS device-bound keys are non-synchronizable. Uninstall or lost keys can make local records unavailable. Recovery only restores records actually present in the chosen archive; it cannot reconstruct unsent receipts or unseen authority history.
