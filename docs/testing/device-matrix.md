# Device acceptance matrix

Inventory rechecked during Task13 on 2026-10-20; selectors/account identifiers omitted. Inventory alone is readiness evidence; actual execution below is recorded separately.

| Target | Observed availability | Acceptance state |
| --- | --- | --- |
| Android SM-S931Q, Android16/API36 | Authorized USB; owned synthetic installs verified by exact APK hashes | Current native suite/matrix passed; prior three OS process-death cases retained; normal preview installed |
| Android API24 floor | No configured AVD/system image from prior inventory; current AVD list empty | Unverified floor |
| Wired iPhone12Pro, iOS17.6.1 | Earlier owned artifacts signed with prior team; new selected-team build has account/profile gap | Earlier native/process/lifecycle passes retained; current signing/testing deferred by user |
| iOS16 floor | No available runtime/device | Unverified floor |
| iOS26.5 simulator | Installed runtime | Current normal simulator build passed; no simulator runtime/camera/key pass claimed |

## Per-platform operator matrix

Record OS/device class, exact compiled entrypoint/revision/artifact hash, date, command/procedure, result and evidence path for actual execution. Do not convert a host mock or another OS/device's pass into parity.

| Scenario | Android | iPhone |
| --- | --- | --- |
| Real OS keys; manager/staff invitation/capture/import/ack/review/correction/reopen | Passed current native suite | Passed earlier-source native suite; current rerun deferred |
| Actual archive create/apply directory-fsync FFI, wrong-password rejection, recovery queries | Passed current native suite | Passed earlier-source native suite; current rerun deferred |
| Missing run-owned catalog key preserves bytes/fails closed | Passed current native suite | Passed earlier-source native suite; current rerun deferred |
| Force termination before commit | Passed earlier-source process case | Passed earlier-source process case; debugger attempts retained |
| Force termination after commit/pre-receipt | Passed earlier-source process case | Passed earlier-source process case |
| Force termination after visible saved receipt | Passed earlier-source process case | Passed earlier-source process case |
| Two physical installations, printed workplace camera exchange | Deferred by user | Deferred by user |
| Fresh disposable install in airplane mode: camera, PNG/JPEG image decode | Current native PNG/JPEG passed; airplane/live camera deferred | Earlier-source PNG/JPEG passed; airplane/live camera deferred |
| Permission rejection; canceled picker/share | Human interactions deferred by user | Human interactions deferred by user |
| Cloud-backed unavailable document/provider errors | Deferred by user | Deferred by user |
| Maximum1500-byte valid QR; larger intact-file fallback | Current1500-byte native PNG/JPEG decode passed; interactive fallback deferred | Earlier-source1500-byte native PNG/JPEG decode passed; interactive fallback deferred |
| Overnight/offset display; company switch after picker; expired session | Passed current native matrix (injected callback and five-minute idle clock) | Current-source native matrix deferred by user after selected-team account/profile gap |
| Storage failure; duplicate receipt; approval/correction return | Current native duplicate/review/correction and injected SQL abort/retry passed | Earlier-source duplicate/review/correction native pass; current injected failure case deferred |
| Interrupted handover and independently verified external backup | Graceful reopen/lost ack/fresh capture passed; external custody separately verified by lifecycle evidence | External custody verified by lifecycle evidence; current graceful handover case deferred by user |
| Disposable uninstall/reinstall from external backup | Passed earlier-source lifecycle with retained actual prior archive, fresh namespaced OS keys | Passed earlier-source lifecycle with retained actual prior archive, fresh namespaced OS keys; historical Keychain untouched |

The native integration helper isolates persistent paths and real secure-key namespaces by a random run ID. It retains owned synthetic evidence; it does not delete global keys or existing company data. A new absent package is not proof of empty historical iOS Keychain state. Earlier physical artifacts used existing local signing assets only. The later selected-team automatic provisioning attempt is documented below; no account edits, enrollment/trust changes or automatic Android license acceptance occurred. Use `--keep-app-running` for prebuilt drive to avoid its default uninstall cleanup.

## Current iOS signing selection

Normal Runner builds select the Israel Eusebio team with automatic signing in Debug, Profile and Release. Its existing development certificate is available, but a matching development profile for `com.remyo.razecheck` is absent. A bounded automatic build using the selected team and `Apple Development` failed with Xcode’s `No Accounts` and missing-profile errors; this describes the account state visible to that build, not every account on the computer. No account settings, certificates, device enrollment or trust were changed; before/after eligible signing identities are identical. The user explicitly chose to leave current iPhone signing/testing pending. No further signing/provisioning/device attempts are made for this gate; current physical parity remains unverified by request. The simulator does not require that profile and is not a phone-installable artifact. The earlier iPhone acceptance artifacts used the existing Jiang Xia team profile; their retained hashes and results remain evidence of those original artifacts, not of a build signed by the newly selected team.
