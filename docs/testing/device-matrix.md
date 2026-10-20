# Device acceptance matrix

Inventory rechecked during Task13 on 2026-10-20; selectors/account identifiers omitted. Inventory alone is readiness evidence; actual execution below is recorded separately.

| Target | Observed availability | Acceptance state |
| --- | --- | --- |
| Android SM-S931Q, Android16/API36 | Authorized USB; target initially absent, then owned synthetic installs after user confirmed availability | Native suite and three OS process-death cases passed |
| Android API24 floor | No configured AVD/system image from prior inventory; current AVD list empty | Unverified floor |
| Wired iPhone12Pro, iOS17.6.1 | Connected; target initially absent; existing local signing assets verified | Native suite and three OS process-death cases passed |
| iOS16 floor | No available runtime/device | Unverified floor |
| iOS26.5 simulator | Installed runtime | Simulator build passed; no simulator runtime/camera/key pass claimed |

## Per-platform operator matrix

Record OS/device class, exact compiled entrypoint/revision/artifact hash, date, command/procedure, result and evidence path for actual execution. Do not convert a host mock or another OS/device's pass into parity.

| Scenario | Android | iPhone |
| --- | --- | --- |
| Real OS keys; manager/staff invitation/capture/import/ack/review/correction/reopen | Passed native suite | Passed native suite |
| Actual archive create/apply directory-fsync FFI, wrong-password rejection, recovery queries | Passed native suite | Passed native suite |
| Missing run-owned catalog key preserves bytes/fails closed | Passed native suite | Passed native suite |
| Force termination before commit | Passed | Passed; debugger attempts retained |
| Force termination after commit/pre-receipt | Passed | Passed |
| Force termination after visible saved receipt | Passed | Passed |
| Two physical installations, printed workplace camera exchange | Deferred by user | Deferred by user |
| Fresh disposable install in airplane mode: camera, PNG/JPEG image decode | Native PNG/JPEG passed; airplane/live camera deferred | Native PNG/JPEG passed; airplane/live camera deferred |
| Permission rejection; canceled picker/share | Human interactions deferred by user | Human interactions deferred by user |
| Cloud-backed unavailable document/provider errors | Deferred by user | Deferred by user |
| Maximum1500-byte valid QR; larger intact-file fallback | Exact 1500-byte native PNG/JPEG decode passed; interactive fallback deferred | Exact 1500-byte native PNG/JPEG decode passed; interactive fallback deferred |
| Overnight/offset display; company switch after picker; expired session | Pending | Pending |
| Storage failure; duplicate receipt; approval/correction return | Duplicate/review/correction native pass; broader injected failures host coverage only | Duplicate/review/correction native pass; broader injected failures host coverage only |
| Interrupted handover and independently verified external backup | Pending | Pending |
| Disposable uninstall/reinstall from external backup | Passed with retained actual prior archive, fresh namespaced OS keys | Passed with retained actual prior archive, fresh namespaced OS keys; historical Keychain untouched |

The native integration helper isolates persistent paths and real secure-key namespaces by a random run ID. It retains owned synthetic evidence; it does not delete global keys or existing company data. A new absent package is not proof of empty historical iOS Keychain state. Local signing uses existing assets only; no provisioning updates, account edits, enrollment/trust changes or automatic Android license acceptance. Use `--keep-app-running` for prebuilt drive to avoid its default uninstall cleanup.

## Current iOS signing selection

Normal Runner builds select the Israel Eusebio personal team with automatic signing in Debug, Profile and Release. Its local development certificate is available, but a matching local provisioning profile for `com.remyo.razecheck` is currently absent; a new physical signed build under that team has not been verified. No account or provisioning changes were made. The earlier iPhone acceptance artifacts used the existing Jiang Xia team profile; their retained hashes and results remain evidence of those original artifacts, not of a build signed by the newly selected team.
