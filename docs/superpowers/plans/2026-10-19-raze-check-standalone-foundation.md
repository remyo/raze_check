# Raze Check Standalone Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a working offline Raze Check app for Android and iOS covering company setup, staff enrollment, QR attendance receipts, management review, and encrypted backup/replacement-device recovery.

**Architecture:** A standalone Flutter host composes reusable core, local-adapter, and feature packages. All company-scoped commands pass through permission checks and a transactional operation journal; immutable signed attendance messages use the same validation regardless of camera, image, or file delivery. Raze Store embedding, cross-app replicas, and cloud services remain separate held work.

**Tech Stack:** Flutter 3.44.7 / Dart 3.12.2; Riverpod without code generation; Drift/native SQLite with encrypted record payloads; cryptography and OS secure key storage; mobile_scanner, qr_flutter, native document picker and share sheet; Flutter unit, widget, and device integration tests.

**Spec:** [Approved product design](../specs/2026-10-18-attendance-management-design.md) and [approved integration boundaries](../specs/2026-10-19-raze-check-integration-boundaries.md). Read both before execution.

**Status:** Design approved2026-10-19; Tasks1–12 implemented and independently reviewed. Task13 measured capacity and current Android acceptance are complete under recorded reconciliation; current iPhone signing/testing and hands-on optical/picker/share checks are user-deferred, and runtime floors remain unverified. The combined source fixes passed independent review; final Task13 evidence/harness delta review approved `32ff89c6395e4fa238895ec310ff79aa7749ac90` with no Critical/Important findings and one nonblocking Minor warning-output finding. The standalone host and reusable packages now exist; Android and iOS remain joint targets. See [current acceptance evidence](../../testing/foundation-acceptance.md) for actual verification and outstanding gates. Original checklists below retain the approved execution plan; they are not a substitute for recorded results.

## Global Constraints

The following requirements are quoted from the approved specs; they apply to every task:

- "Current delivery priority is the standalone Raze Check app."
- "Keep that integration on hold."
- "Its business logic and screens must not import Raze Store internals or require Raze Store to be installed."
- "Roles belong to the membership, not globally to the person."
- "Selecting a role in the UI never grants permission."
- "Save one immutable attendance event locally before displaying success."
- "Initial default: attendance submissions require manager approval before affecting salary."
- "They do not alter the original receipt."
- "Encrypted export/import and restore belong in the first free foundation."
- "Do not rely on an uninstall callback to perform a final copy."

Additional execution constraints: Android and iOS ship together; no Raze Store edits, backend provisioning, billing, public publishing, or application-store submission. Use a `codex/` work branch and the worktree skill at execution time. Preserve existing design files and the `.superpowers/` ignore rule. App compilation/signing does not authorize distribution or changes to developer-account settings.

## Review Focus

These five failure classes have explicit tests in the owning tasks below:

1. Process death or storage failure between a punch and success/acknowledgment: retain one complete event or none; never acknowledge an uncommitted save. Tasks 3 and 7.
2. A scan, file picker, or draft belonging to company A completes after the user switches to B or their session expires: require the original authorized context; never attach it to B. Tasks 4 and 9.
3. Authentic historical receipts arrive after a device key is replaced or staff is deactivated: preserve verifiability and flag authorization uncertainty without permitting new activity. Tasks 8 and 11.
4. An encrypted backup is truncated, oversized, missing a file/key, or restored onto an existing company: staging fails safely or shows a conflict; live data remains untouched. Tasks 10 and 11.
5. Two restores from an old backup create competing authority histories: detect the fork and block silent management overwrites when they meet. Task 11.

---

## Scope, delivery sequence, and acceptance boundary

This is the first executable plan, not a plan to implement every subsystem in one release. Its end-to-end exit is: create a company on a management phone, approve a staff phone's join request, issue the membership back, capture check-in/out offline, transfer and approve receipts, export a report, and restore or move the records without duplicating identities.

Included: local personal profiles; multiple companies; owner and permission-limited management operators on the company's management device; basic staff fields; printed attendance QR; signed receipts and return acknowledgments/decisions; manager-entered attendance with reasons; staff correction requests; received/approved history; CSV attendance reports; encrypted backup/restore and device replacement. A tablet can display the company QR through the same responsive interface.

Separate later plans, preserving the approved product scope:

| Track | Later deliverable |
| --- | --- |
| Free workplace operations | Authenticated local Wi-Fi transfer; richer staff/custom fields and ID-document UI; shifts, breaks, grace rules, leave, OT, and salary summaries, with their detailed rules agreed before implementation. |
| Paid coordination | Cloud accounts, synchronization, remote admins, attachment sync, cloud backups, upgrades/downgrades, and billing. |
| Raze Store — held | Host navigation, native bridge, app linking, durable copies in both apps, replica synchronization, and companion-app recovery. Resume only when requested. |
| Optional equipment | Shared fingerprint/face identification, strict workplace-presence verification, and dedicated station credentials. |

Foundation screens must show only implemented actions and real data. Mockup leave/OT/payroll cards are not executable requirements for this phase. No schedules means no confirmed absences, late/grace calculations, or payable-hour claims. Basic reports list punches, decisions, and exceptions. Interval pairing and payable hours belong to the later schedules/salary track.

## Environment and dependency baseline

Observed during planning: SDK at `/Users/rem/fvm/versions/3.44.7`, Dart 3.12.2, Xcode 26.6, and connected physical Android/iOS devices. Devices and signing must be rechecked at execution; no device identifier is hard-coded. Shell PATH did not expose Flutter, so commands below use `FLUTTER_BIN=/Users/rem/fvm/versions/3.44.7/bin/flutter` and `DART_BIN=/Users/rem/fvm/versions/3.44.7/bin/dart`, or equivalent paths on another workstation.

`flutter doctor` reports unaccepted Android SDK licenses. Before the Android build gate, have the user review/accept the applicable licenses; do not pipe automatic acceptance into a legal agreement. Use the existing SDK by explicit path or a process-local PATH change, without editing shell startup files. An unresolved license/signing requirement is a recorded build blocker, not a reason to claim a successful build.

Proposed platform floor for plan approval: Android API 24 and iOS 16.0. Use Flutter 3.44.7's Android compile/target 36 and generated toolchain versions. Development app IDs: `com.remyo.razecheck` on both platforms, following the existing related app's namespace; validate ownership/signing before distribution. No advertising IDs, location permission, network requirement, or Wi-Fi inspection in this phase.

Use a Dart pub workspace: root application plus three packages with `resolution: workspace`. Initial dependency candidates below have been checked against published manifests/documentation, but **resolution and both native builds remain Task 1 evidence**, not a planning claim. Pin these versions initially, commit `pubspec.lock`, and make any required compatibility adjustment explicit in the plan log.

| Package | Candidate | Location/use |
| --- | --- | --- |
| flutter_riverpod | 3.4.3 | Feature/host state; no generator |
| drift / drift_dev | 2.35.2 / 2.35.1 | Local database / generator |
| build_runner | 2.16.2 | Local package dev dependency; 2.17.0 is retracted and 2.17.1 needs incompatible build 5 |
| path_provider | 2.1.6 | Private persistent/staging paths |
| flutter_secure_storage | 11.2.0 | Keys and unlock credential material |
| cryptography / cryptography_flutter | 2.9.0 / 2.3.4 | Core algorithms / local native acceleration |
| mobile_scanner | 7.4.2 | Live QR and imported image decoding |
| qr_flutter | 4.1.0 | QR rendering and PNG generation |
| file_selector | 1.1.0 | Files/document import, including QR images |
| share_plus | 13.3.1 | Receipt, CSV, and encrypted archive export |

Use the compatible transitive `file_selector_ios` 0.5.3+6: +7 requires Flutter 3.47/Dart 3.13. Verify the lockfile rather than forcing an incompatible override. Use the SQLite native asset bundled by sqlite3 through Drift; do not add another SQLite binary package. Use Dart `Random.secure` for UUIDv4 IDs, SDK `flutter_test`/`integration_test` dev dependencies, and Dart `test` 1.31.0 for pure core tests (matching the installed Flutter toolchain's test API). Add core `timezone` 0.11.0 with bundled data in Task 1 and local `archive` 4.5.2 for bounded ZIP archives in Task 10. Implement CSV quoting locally; no network/analytics SDKs.

## File map and module responsibilities

Paths below are relative to this repository. Tests live next to the package they exercise; generated Drift output is committed. Names below are public interfaces used by later tasks, not permission to create placeholder implementations for held features.

```text
lib/main.dart                         # Standalone startup/composition only
lib/app/check_app.dart                # MaterialApp, lifecycle, app-level routing
lib/app/local_composition.dart        # Constructs real services and adapters
packages/raze_check_core/lib/
  raze_check_core.dart                # Reviewed public exports
  src/contracts/                     # IDs, results, sessions, context, capabilities
  src/identity/                      # Person, installation, signing/recovery identities
  src/company/                       # Company, membership, permission policy
  src/messaging/                     # Typed versioned signed messages and limits
  src/attendance/                    # Capture, import, review, corrections, queries
  src/recovery/                      # Scope, manifest, restore and handover rules
packages/raze_check_local/lib/
  raze_check_local.dart               # Adapter exports, not raw database handles
  src/security/                      # OS keys, encryption, local unlock
  src/database/                      # Drift schema, transactions, migration
  src/files/                         # Controlled paths and attachments
  src/recovery/                      # Archive I/O and staged activation
  src/platform/                      # Camera, document picker, share sheet
packages/raze_check_feature/lib/
  raze_check_feature.dart             # Embeddable feature entry point
  src/host/                          # Service injection and host navigation callbacks
  src/theme/                         # Local tokens and host theme adaptation
  src/profile/ src/company/           # Profile, unlock, switcher, company setup
  src/enrollment/ src/attendance/     # User workflows
  src/team/ src/recovery/             # Staff management and backup/restore
  src/dashboard/ src/reports/         # Current information and attendance export
integration_test/                    # Real adapter/device tests
docs/testing/                        # Reproducible device evidence and limits
```

### Shared decisions that tasks depend on

- IDs are UUIDv4 strings; IDs are scoped/checked with company ID on every lookup. UTC instants are integer milliseconds; preserve claimed offset minutes separately. Store the company's validated IANA time-zone ID. Initialize the bundled `timezone/data/latest.dart` database in Task 1; never infer salary rules from device locale.
- `CommandContext` contains `companyId`, opaque `SessionHandle`, `operationId`, `authorityGenerationId`, and optional `expectedRevision`. Resolve actor identity from the active session, not an arbitrary caller-supplied role. `CommandResult<T>` is a sealed result: `Committed<T>(value, revision, duplicate)`, `Rejected<T>(CheckError)`, or `VersionConflict<T>(currentRevision)`.
- `CheckError` cases: `locked`, `unauthorized`, `wrongCompany`, `malformed`, `unsupportedVersion`, `invalidSignature`, `unknownIssuer`, `revokedCredential`, `duplicateConflict`, `storageFailure`, `invalidTransition`, `limitExceeded`, `incompleteArchive`, `wrongSecret`, `recoveryRequired`. User-facing messages are mapped in feature code; logs contain no employee data, secret material, or receipt payloads.
- `CheckClock.nowUtc()` and `IdGenerator.next()` are injected. Use deterministic fakes in tests. `SessionHandle` is an opaque live in-memory capability from `IdentityService`; restored JSON cannot manufacture an unlocked session. A local management-operator credential is restricted to its company and cannot impersonate the person's memberships in other companies.
- Database schema 1 has company-scoped entity rows, immutable event rows, command operation/result rows, revision journal rows, outbox messages, and recovery transaction rows. Logical payloads are AES-256-GCM encrypted. Only routing IDs, record type, revisions, and status needed to locate encrypted rows are cleartext. Names, contact data, event payloads, secret keys, and attachment content are never cleartext SQLite fields.
- Keep public verification history for old device keys. Device replacement prevents new authorized issuance under the retired key; it must not invalidate authentic historical signatures. Company authority history uses a random generation ID, parent generation ID, and sequence, so sibling restores are detectable even if sequence numbers match.
- First-use owner trust is explicit: show company name and a short root-key fingerprint from the invitation before accepting it. Store names alone do not authenticate a company. A portable company recovery signing key authorizes issuer/device replacement; current installation signing keys are distinct and never exported as active device identities.
- Passphrases for local profiles and archives have a minimum of 12 Unicode characters with confirmation at creation. Use PBKDF2-HMAC-SHA256, 600,000 iterations, random 16-byte salt, and 32-byte output; benchmark off the UI thread. Archive readers accept only this v1 work factor and reject attacker-selected unbounded KDF work. OS secure storage holds independent random keys, not record bodies. Lock on explicit logout or after 5 minutes without authorized activity, evaluated on resume; draft/file-picker completion rechecks the session and company. Biometrics are deferred convenience, never required for recovery.
- Engineering limits for this phase: QR text at most 1,500 UTF-8 bytes, message-file at most 64 KiB, selected QR image at most 20 MiB, encrypted backup at most 64 MiB, total expanded archive at most 64 MiB, `records.json` at most 64 MiB within that expanded total, every other individual file at most 8 MiB, at most 10,000 archive entries. Reject over-limit input before expensive work; explain file export or smaller scoped export as applicable. These are protective v1 format limits, not subscription/company caps.
- Native QR image import uses Files/document picker in v1, including files saved from messaging apps. Gallery-specific browsing can follow. `file_selector` does not implement mobile save-location selection; use system share/export and distinguish opening a share sheet from verified delivery or external backup persistence.

### Message payload registry

Task 5 implements this logical registry. Each payload begins with `[companyId, messageId, issuedAtUtcMs]`, followed by the fields below in order. All IDs/labels/key material are strings, integer fields are integers, optional fields use explicit `null`, and lists have fixed allowed element types. There is no arbitrary-map extension field in v1. A field named `authority` is a root-signed certificate `[generationId, parentGenerationIdOrNull, sequence, installationId, publicKeyBase64Url, issuedAtUtcMs, rootSignatureBase64Url]`; the root signature covers the first six fields as UTF-8 JSON with domain `RAZE_CHECK_AUTHORITY_V1\n`. Root public key is pinned at enrollment; generation lineage is checked against known history.

| Kind | Fields after the common prefix |
| --- | --- |
| invitation | companyLabel, timeZoneId, workplaceId, rootPublicKeyBase64Url, authority |
| joinRequest | invitationId, personId, displayName, installationId, publicKeyBase64Url |
| membershipGrant | joinOrReplacementRequestId, membershipId, membershipRevision, personId, employeeId, installationId, publicKeyBase64Url, companyLabel, timeZoneId, workplaceId, authority |
| workplace | workplaceId, codeId, authority |
| attendance | personId, employeeId, membershipId, membershipRevision, installationId, kind (`checkIn` or `checkOut`), claimedUtcMs, offsetMinutes, workplaceId, codeId, membershipAuthorityGenerationId, evidence (`staticQr`) |
| receiptAck | eventId, eventPayloadSha256Base64Url, receivedUtcMs, authority |
| attendanceDecision | eventId, eventPayloadSha256Base64Url, decisionId, decisionRevision, outcome (`pending`, `approved` or `rejected` attendance state), reason, correctionIdOrNull, correctionRequestIdOrNull, correctionOutcomeOrNull (`approved` or `rejected`), effectiveKind, effectiveUtcMs, effectiveOffsetMinutes, actorPersonId, authority |
| correctionRequest | employeeId, eventId, proposedKind, proposedUtcMs, proposedOffsetMinutes, reason |
| replacementRequest | personId, employeeIdOrNull, newInstallationId, newPublicKeyBase64Url |
| authorityTransfer | targetReplacementRequestId, snapshotManifestId, snapshotSha256Base64Url, nextAuthority, sourceAuthority |
| transferAck | transferMessageId, snapshotManifestId, snapshotSha256Base64Url, authority |

`joinRequest`/`replacementRequest` are self-signed requests, not authorization. `membershipGrant` establishes staff attendance access only; management permissions remain in the owner's local capability history. A decision without a correction carries the current effective fields and current attendance review snapshot; correction outcomes remain independent. A resolved correction receives a new decision revision and correction ID; retain the prior receipt and decision history. `messageId` is the event ID for attendance messages. The protocol document defines test vectors for this registry, not new fields without a format/version change.

### Test notation

Test snippets omit imports and fixture setup, but their names/assertions are requirements. Each package's `test/support/check_matchers.dart` defines `throwsCheckError(CheckError code)` using `throwsA(isA<CheckException>().having((e) => e.code, 'code', code))`. Task-local fixture wrappers mentioned in snippets belong in the listed test/support files and invoke the public interfaces; they do not substitute mock success for storage/permission tests. Define `CheckException(CheckError code)` with the shared result contract in Task 1.

### Archive v1 layout

Task 10 controller amendments: direct archive4.5.2 pin; explicit indexed exact-byte records grammar with 524288 logical items and 64MiB repeated-reference raw expansion cap; consistent bounded repository traversal; retired operator credential/digest tombstones preserving operation/journal provenance. Exact inner grammar, limits, staging/activation and durability behavior: [Archive v1](../../protocol/archive-v1.md). The full 100-staff/10000-external-receipt manager archive remains a measured Task13 capacity gate. No silent limit increase or subset-as-full export.

Task 10 implements a 52-byte authenticated header: 8 ASCII magic bytes `RZCKBK01`, u16 little-endian format `1`, u8 algorithm `1` (AES-256-GCM), u8 KDF `1` (PBKDF2-HMAC-SHA256), 16 salt bytes, 12 nonce bytes, u32 little-endian iterations `600000`, and u64 little-endian ciphertext length. Ciphertext follows, then the 16-byte tag. Header bytes are GCM associated data. Reject unsupported values, length mismatches, and the stated size limits before allocating or deriving keys.

Encrypted ZIP entries are exactly `manifest.json`, `records.json`, `recovery.json`, and zero or more `attachments/<sha256-hex>` files. The manifest contains `formatVersion`, `archiveId`, `createdUtcMs`, `scopeKind`, `scopeId`, `personId`, `companyRootFingerprints`, `authorityHeads`, `recordCountsByKind`, and a `files` list of `{path, byteLength, sha256}` for every entry except the manifest. `records.json` contains versioned logical records, operations/results, pending outbox bytes, and verification history; `recovery.json` contains only credentials allowed for that export scope. Preserve binary message fields as base64url. Manifest schema rejects extra fields in v1; listed hashes, authority relationships, and exact file membership must agree. Validating an archive for an existing company also requires its known root fingerprint to match.

## Task 1: Runnable mobile workspace and versioned core contracts

**Files:** Create root `pubspec.yaml`, `analysis_options.yaml`, `.fvmrc`, `lib/main.dart`, `lib/app/check_app.dart`; generated `android/` and `ios/` projects; `packages/raze_check_core/pubspec.yaml`, `packages/raze_check_local/pubspec.yaml`, `packages/raze_check_feature/pubspec.yaml`; each package's `lib/raze_check_*.dart` and `test/support/check_matchers.dart`; core `src/contracts/{ids,context,result,clock,capability}.dart`; `packages/raze_check_core/test/contracts_test.dart`. Modify `.gitignore` while retaining `.superpowers/`.

**Interfaces:** Produces `IdGenerator.next() -> String`, `CheckClock.nowUtc() -> DateTime`, `SessionHandle`, `CommandContext`, `CommandResult<T>`, and `CheckError` as defined above. `Capability` enumerates `manageCompany`, `manageStaff`, `manageMemberships`, `reviewAttendance`, `exportAttendance`, `backupCompany`, `recoverCompany`; owner-only rules are enforced in Task 4. Export only stable core types.

- [ ] Create the Flutter root with `flutter create --project-name raze_check --org com.remyo --platforms=android,ios .`, set the development IDs and platform floors, and declare the three workspace packages and initial dependencies, including SDK `integration_test` at root. Preserve docs and existing files; no Store-relative path dependency. Replace the generated counter app and remove its generated `test/widget_test.dart`; the initial app displays the app identity and startup state. Later workflow tests cover real behavior.
- [ ] Write the first contract test (before contract implementation):

```dart
test('IDs are distinct UUIDv4 strings', () {
  final ids = SecureIds();
  expect(ids.next(), matches(uuidV4Pattern));
  expect(ids.next(), isNot(ids.next()));
});
```

Define `uuidV4Pattern` in the test to check UUID version/variant, not only length. Also assert result types retain duplicate/conflict distinctions.
- [ ] Run `cd packages/raze_check_core && "$DART_BIN" test test/contracts_test.dart`; expect failure because `SecureIds`/contracts are not implemented.
- [ ] Implement contracts and the standalone boot entry; run `flutter pub get` at root, inspect resolved versions and commit the workspace lockfile. Do not suppress generator/SDK conflicts with broad overrides.
- [ ] Run the contract test, `flutter analyze`, `flutter build apk --debug`, and `flutter build ios --simulator --debug`; expect passing tests, no analyzer errors, and both build artifacts. Record toolchain/dependency changes in `docs/testing/development-baseline.md`. This proves compilation only, not camera/recovery behavior.
- [ ] Commit the files above and baseline document: `git commit -m "feat: establish standalone mobile workspace and contracts"`.

## Task 2: Local identities, unlock sessions, and encrypted vault access

**Files:** Create core `src/identity/{identity_models,identity_service,key_service}.dart`; local `src/security/{secure_key_store,payload_cipher,profile_catalog,local_identity_service}.dart`; local `src/files/app_paths.dart`; local `test/security_test.dart` and `test/support/{fake_clock,memory_key_store,temp_paths}.dart`; feature `src/profile/{profile_setup_screen,unlock_screen}.dart`; update root composition and platform secure-storage/backup configuration.

**Interfaces:** `IdentityService.createProfile(String name, String passphrase) -> Future<SessionHandle>`; `unlock(String personId, String passphrase) -> Future<SessionHandle>`; `lock() -> void`; `requireActor(SessionHandle) -> ActorIdentity`. `KeyService.sign(Uint8List bytes, String keyId) -> Future<Uint8List>` and `verify(Uint8List bytes, Uint8List signature, Uint8List publicKey) -> Future<bool>`. `PayloadCipher.seal({required String scopeId, required String recordId, required int revision, required Uint8List plain}) -> Future<Uint8List>` and `open({required String scopeId, required String recordId, required int revision, required Uint8List sealed}) -> Future<Uint8List>` authenticate all three context fields. Infrastructure failures throw the shared typed `CheckException`; application boundaries convert it to `CommandResult`.

- [ ] Write security tests with fixed fake clock and fresh keys:

```dart
final sealed = await cipher.seal(
    scopeId: 'A', recordId: 'r1', revision: 1, plain: data);
await expectLater(cipher.open(scopeId: 'B', recordId: 'r1', revision: 1, sealed: sealed),
    throwsCheckError(CheckError.invalidSignature));
```

Add wrong-passphrase, expired-session, nonce uniqueness, modified ciphertext, and missing-key tests. Missing key over existing encrypted data must return `recoveryRequired`, never create a replacement key silently.
- [ ] Run `cd packages/raze_check_local && "$FLUTTER_BIN" test test/security_test.dart`; expect missing implementation failures.
- [ ] Implement random per-person/per-company vault keys in OS secure storage, Ed25519 signing, AES-GCM payloads with fresh 12-byte nonces and authenticated context, PBKDF2 unlock verifiers, and the 5-minute session rule. Keep the small versioned profile/installation catalog in an encrypted application-support file with atomic replacement; secure storage contains keys/credential material, not staff/attendance bodies. Domain data uses Drift from Task 3. Exclude key-bound local data from automatic Android backup/transfer and iOS document backup where necessary; define this in the baseline document and use explicit archives for portable recovery.
- [ ] Add local profile creation/unlock screens with real validation and no network account requirement; lock clears active session and cached decrypted views. Permission decisions remain service-side in Task 4. Tests verify canceled setup does not leave an active half-profile.
- [ ] Run security tests and `flutter analyze`; expect pass. Add device verification of key persistence/relaunch to the final matrix; no claim of secure-storage parity until Task 13.
- [ ] Commit: `git commit -m "feat: add local identity unlock and encrypted vault access"`.

## Task 3: Transactional durable records and operation journal

**Files:** Create core `src/contracts/check_repository.dart`; local `src/database/{check_database,tables,local_check_repository}.dart` plus generated `check_database.g.dart`; local `test/{repository_test,migration_test}.dart`, `test/support/repository_fixture.dart`; update local composition.

**Interfaces:** `CheckRepository.commit(CommandContext context, {required Uint8List requestDigest, required Future<Mutation> Function(ReadView) build}) -> Future<CommandResult<StoredRecord>>`; `read(String companyId, String recordId) -> Future<StoredRecord?>`; `watchRevision(String companyId) -> Stream<int>`; `snapshot(ExportScope scope) -> Future<LogicalSnapshot>`. Define `StoredRecord(String id, String companyId, String kind, int revision, Uint8List payload)` and `Mutation(List<StoredRecord> records, List<StoredRecord> events, List<StoredRecord> outbox, StoredRecord result)`. `ReadView.read(String id)` and `list(String kind)` are bound to the transaction's company and return records; `LogicalSnapshot` contains scoped records, journal/operations/outbox, authority history, and immutable attachment manifest. `ExportScope` is `PersonalScope(personId)` or `CompanyScope(companyId)`; authorization is performed by services, not trusting the scope object. `RepositoryFixture.open()` exposes `repo`, `failBeforeCommit()`, `reopen()`, `count(kind)`, and `dispose()` for later adapter tests.

- [ ] Write tests for transaction rollback and command replay:

```dart
expect((await fixture.commitExample(operationId: 'op-1')).duplicate, isFalse);
expect((await fixture.commitExample(operationId: 'op-1')).duplicate, isTrue);
expect(await fixture.count('example'), 1);
```

Define `commitExample` in the fixture using `commit`, a fixed context/request digest, and one record/outbox item. Add same-operation/different-content conflict, wrong-company lookup, crash/reopen, failure before commit leaving zero rows/outbox, encrypted-body inspection, and consistent snapshot tests. Bind operation identity to a digest of normalized caller intent, not merely its ID or regenerated timestamps. Same intent/ID returns the journaled result before executing the mutation builder; different intent/ID reuse is a conflict. Generated keys, IDs, and signed bytes are created once within the operation and journaled.
- [ ] Run local repository and migration tests; expect absent repository/schema failure.
- [ ] Implement Drift in application-support storage with `NativeDatabase.createInBackground`, foreign keys, transactional journal+entity+outbox commits, encrypted payloads, and company-filtered reads. Never emit a successful result or revision notification before commit. Schema upgrades use versioned migrations and fail without resetting user data.
- [ ] Implement bounded logical snapshots under a consistent read transaction. Keep attachment manifests stable during snapshot; attachment bytes are immutable/content-addressed until snapshot completion. A queued UI operation has a durable operation ID before execution so retry after process death is idempotent.
- [ ] Run `cd packages/raze_check_local && "$DART_BIN" run build_runner build`, then local repository/migration tests and analysis; expect pass and deterministic generated output. The resolved generator no longer accepts the old deletion flag; regenerate and inspect only intended generated outputs.
- [ ] Commit: `git commit -m "feat: persist encrypted records and idempotent commands"`.

## Task 4: Companies, staff records, and company-scoped permissions

**Files:** Create core `src/company/{company_models,access_policy,company_service}.dart`; core `test/company_policy_test.dart`; local `test/company_service_test.dart`; feature `src/company/{company_setup_screen,company_switcher}.dart`, `src/team/{staff_list_screen,staff_detail_screen,operator_access_screen}.dart`; feature `test/company_context_test.dart`; update public exports/composition.

**Interfaces:** `CompanyService.createCompany(SessionHandle session, CompanyDraft draft, String operationId) -> Future<CommandResult<Company>>`; `createStaff(CommandContext, StaffDraft) -> Future<CommandResult<StaffRecord>>`; `updateStaff(CommandContext, StaffUpdate) -> Future<CommandResult<StaffRecord>>`; `grantCapabilities(CommandContext, String membershipId, Set<Capability>) -> Future<CommandResult<Membership>>`; `activateOperator(CommandContext, String membershipId, String passphrase) -> Future<CommandResult<OperatorCredential>>`; `deactivateStaff(CommandContext, String employeeId, String reason) -> Future<CommandResult<Membership>>`. `AccessPolicy.require(SessionHandle, Membership, Capability)` resolves the session actor and company restriction. `CompanyDraft(name, timeZoneId)` and `StaffDraft(name, employeeNumber?, contact?, birthday?, department?, position?, joiningDate?)` are defined here; birthday-derived age is display-only.

- [ ] Write tests proving isolation and owner-only grants:

```dart
expect(policy.can(staffInA, Capability.manageStaff), isFalse);
expect(policy.can(ownerInB, Capability.manageStaff), isTrue);
expect(await companies.readCompany(staffSession, companyB.id), isNull);
```

Define `can(Membership, Capability)` and `readCompany(SessionHandle, String) -> Future<Company?>` alongside the interfaces. Test that unauthorized calls leave revision unchanged, an admin cannot grant itself owner rights, and membership/person IDs survive staff edits/deactivation. In the widget test, switch company while a draft is open and verify explicit discard/keep behavior.
- [ ] Run core company-policy, local company-service, and feature company-context tests; expect failure.
- [ ] Implement company root recovery identity and initial installation authority generation, default workplace ID, local owner membership, basic staff records, and capabilities. `manageCompany`, `backupCompany`, and `recoverCompany` are owner-only in v1. Other capabilities may be granted to an approved member on the management device. Activation of a local operator requires owner-authorized setup and that operator's own company-restricted unlock credential; it must not replace their personal-profile credentials or unlock any other company. Preserve permission change history and test cross-company impersonation attempts with such an operator session.
- [ ] Wire company setup, basic staff management, operator selection, and the switcher. Multiple companies have no commercial cap. Require explicit selection of an IANA time zone from the bundled searchable list; do not infer a zone from the device's offset or abbreviation. A manual staff record can exist without an enrolled phone and supports manager-entered attendance later.
- [ ] Run the listed tests and analysis; expect pass. Service tests must call commands directly with unauthorized contexts, not only check hidden UI buttons.
- [ ] Commit: `git commit -m "feat: add isolated companies staff and operator permissions"`.

## Task 5: Signed message formats and bounded transport parsing

**Files:** Create core `src/messaging/{message_types,message_codec,message_verifier,message_limits}.dart`; core `test/{message_codec_test,message_verifier_test}.dart`; `test/fixtures/messages/` with reviewed v1 fixtures; `docs/protocol/receipt-v1.md`.

**Interfaces:** `MessageCodec.encode(SignedMessage) -> Uint8List`; `decode(Uint8List, {required int maxBytes}) -> SignedMessage`; `MessageVerifier.verify(SignedMessage, TrustContext) -> Future<VerifiedMessage>`. A `SignedMessage` retains original payload bytes, type, key ID, and signature. Message kinds: `invitation`, `joinRequest`, `membershipGrant`, `workplace`, `attendance`, `receiptAck`, `attendanceDecision`, `correctionRequest`, `replacementRequest`, `authorityTransfer`, `transferAck`. Types belong to one versioned registry; unsupported kinds/versions are rejected before dispatch.

- [ ] Write byte-preservation and tamper tests:

```dart
expect(codec.encode(codec.decode(fixture, maxBytes: 65536)), orderedEquals(fixture));
await expectLater(verifier.verify(tampered, trust),
    throwsCheckError(CheckError.invalidSignature));
```

Add unknown version/type, wrong company, wrong domain/type signature, truncated/base64-invalid input, oversized input, unexpected fields/types, and signature-field-by-field mutation cases.
- [ ] Run `cd packages/raze_check_core && "$DART_BIN" test test/message_codec_test.dart test/message_verifier_test.dart`; expect failure.
- [ ] Define v1 encoding in the protocol document and implement it: UTF-8 JSON positional array `[1, kind, keyId, payloadBase64Url, signatureBase64Url]`; payload is a strictly typed positional array for each kind, no arbitrary objects/floats. Sign exact payload bytes with domain prefix `RAZE_CHECK_V1\n<kind>\n`; include company ID and message/event ID inside every signed payload. Decode validates exact field counts/types/ranges; redisplay reuses stored bytes. Trust comes from the enrolled root/issuer history, not an arbitrary embedded key.
- [ ] Turn the payload registry above into exact fixtures and encoder/decoder tests, including all authority-chain fields. There is no asserted verified location. Lengths: names at most 120 characters in records but compact invitation display label at most 40; reason at most 500; offset -840..840 minutes. QR over 1,500 bytes uses file export; no truncation of signed content. Unknown extra fields require a supported new version, never permissive parsing.
- [ ] Run tests and analyze; expect pass. Checked-in fixtures include maximum supported compact messages; later camera tests determine whether the QR cap needs a documented reduction before release.
- [ ] Commit: `git commit -m "feat: define signed versioned attendance messages"`.

## Task 6: Offline invitation, join approval, and membership return

**Files:** Create core `src/company/enrollment_service.dart`; local `test/enrollment_flow_test.dart`, `test/support/two_device_fixture.dart`; feature `src/enrollment/{invitation_screen,join_company_screen,join_review_screen,membership_status_screen}.dart`; feature `test/enrollment_flow_test.dart`.

**Interfaces:** `EnrollmentService.createInvitation(CommandContext) -> Future<SignedMessage>`; `requestJoin(SessionHandle, VerifiedMessage invitation, String operationId) -> Future<SignedMessage>`; `approveJoin(CommandContext, VerifiedMessage joinRequest) -> Future<CommandResult<SignedMessage>>`; `acceptGrant(SessionHandle, VerifiedMessage grant) -> Future<CommandResult<Membership>>`. `TwoDeviceFixture.create()` creates separate manager/staff vaults, repositories, sessions, and services with a fixed clock; `enrollStaff()` runs the complete message exchange and returns company/member handles for Tasks 7–11.

- [ ] Write the full offline enrollment test:

```dart
expect(await pair.staff.canIssueAttendance(companyId), isFalse);
final grant = await pair.approveSameJoinTwice();
expect(await pair.manager.employeeCount(companyId), 1);
await pair.staff.acceptGrantTwice(grant);
expect(await pair.staff.membershipCount(companyId), 1);
expect(await pair.staff.canIssueAttendance(companyId), isTrue);
```

The fixture wrappers invoke the interfaces above; also test forged grants, unapproved join, wrong invitation type, replayed request with altered contents, and a join QR attempting admin capabilities.
- [ ] Run local/feature enrollment tests; expect failure.
- [ ] Implement the three-message enrollment workflow. Invitation establishes an explicitly accepted root-key fingerprint; join is signed by the requesting installation; manager assigns company employee ID and returns a signed grant bound to that person's installation public key. Duplicate enrollment uses the join operation/request ID and authenticated origin, never name/email matching. Owner approval is required to merge a new request with an existing manual staff record.
- [ ] Wire invitation display, join confirmation, pending membership, manager approval, and grant receipt screens through injected message ports. At this task boundary tests exchange bytes through fake ports; Task 9 supplies camera/file adapters. Pending members cannot punch. Admin permissions are changed through Task 4, not the public invitation.
- [ ] Run enrollment tests and all core tests; expect pass across two isolated repositories with no network calls.
- [ ] Commit: `git commit -m "feat: complete offline staff enrollment and membership return"`.

## Task 7: Durable check-in/out and receipt outbox

**Files:** Create core `src/attendance/{attendance_models,capture_service,attendance_exceptions}.dart`; local `test/capture_service_test.dart`; feature `src/attendance/{capture_screen,receipt_screen,receipt_outbox_screen}.dart`; feature `test/capture_flow_test.dart`.

**Interfaces:** `CaptureService.createWorkplaceCode(CommandContext) -> Future<SignedMessage>`; `recordPunch(CommandContext, VerifiedMessage workplace, PunchKind kind) -> Future<CommandResult<AttendanceReceipt>>`; `getReceipt(SessionHandle, String companyId, String eventId) -> Future<AttendanceReceipt>`; `listOutbox(SessionHandle, String companyId) -> Future<List<AttendanceReceipt>>`. `PunchKind` is `checkIn`/`checkOut`; `AttendanceReceipt` retains event ID, immutable signed bytes, company/employee/installation/workplace IDs, claimed UTC/offset, and delivery status. IDs for retries come from a saved draft operation, not each button press.

- [ ] Write durability and re-export tests:

```dart
final saved = await pair.captureCheckIn();
await pair.restartStaff();
expect((await pair.exportReceipt(saved.eventId)).bytes, orderedEquals(saved.bytes));
expect(await pair.staff.eventCount(), 1);
expect(saved.delivery, DeliveryStatus.localOnly);
```

Add rapid double tap, disk failure before commit, process death after commit/before navigation, wrong-company workplace code, no membership, and checkout without a known check-in. Last case is retained with a missing-punch flag, not invented working time.
- [ ] Run local and feature capture tests; expect failure.
- [ ] Implement membership/workplace validation, atomic event+outbox commit, and exact-byte receipt retrieval. Display "Saved on this device" only after commit. Sharing/reopening never creates another punch. Check-out has a new event ID; clear the draft operation only after committed result is safely associated with its event.
- [ ] Flag same-kind punches within 2 minutes as possible duplicates, unexpected event order, and missing endpoints. Do not auto-delete events or compute salary. These are review flags, not proof of fraud. Preserve original time/offset; no substitution of receive time.
- [ ] Run capture tests plus repository durability tests; expect pass. Add an actual process-kill/relaunch scenario to Task 13; an in-memory mock does not prove durability.
- [ ] Commit: `git commit -m "feat: capture offline punches and persistent QR receipts"`.

## Task 8: Receipt review, auditable corrections, and return updates

**Files:** Create core `src/attendance/{receipt_import_service,review_service,correction_service,update_service}.dart`; local `test/{receipt_import_test,review_service_test,attendance_updates_test}.dart`; feature `src/attendance/{review_queue_screen,attendance_detail_screen,manual_entry_screen,correction_request_screen}.dart`; feature `test/review_flow_test.dart`.

**Interfaces:** `ReceiptImportService.importReceipt(CommandContext, VerifiedMessage receipt) -> Future<ImportOutcome>` where outcome is `received`, `alreadyReceived`, `needsReview`, or `rejected`, with event ID and optional return message. `ReviewService.decide(CommandContext, String eventId, ReviewDecision decision, String reason) -> Future<CommandResult<DecisionRecord>>`; `recordManual(CommandContext, ManualPunch draft) -> Future<CommandResult<AttendanceRecord>>`. `CorrectionService.request(SessionHandle, String companyId, String eventId, ProposedCorrection change, String operationId) -> Future<SignedMessage>` and `resolve(CommandContext, VerifiedMessage request, bool approve, String reason) -> Future<CommandResult<CorrectionRecord>>`. `UpdateService.accept(SessionHandle, VerifiedMessage update) -> Future<CommandResult<AttendanceRecord>>` applies signed acknowledgments/decisions monotonically.

- [ ] Write import/review invariants:

```dart
expect(await pair.importReceiptTwice(), [ImportStatus.received, ImportStatus.alreadyReceived]);
expect(await pair.manager.approvedCount(), 0);
await pair.approveReceiptTwice();
expect(await pair.manager.approvedCount(), 1);
expect(await pair.manager.decisionCount(), 1);
expect(await pair.manager.originalReceiptBytes(), orderedEquals(original));
```

Add same-ID/different-signed-contents conflict, stale expected revision, different-ID probable duplicate, and old received-only update arriving after approval. Authentic receipts from retired/revoked credentials enter a historical-review state without automatic approval; unknown keys cannot issue authorized records. Flag claimed times more than 5 minutes ahead of manager receipt time as a clock anomaly, retaining both times.
- [ ] Run the three local suites and feature review-flow test; expect failure.
- [ ] Apply the explicitly approved unreleased-v1 attendanceDecision amendment in the registry above, strict conditional validation, signed fixtures and protocol document together. Null correction ID requires null request/outcome and approved/rejected attendance. Direct manager correction has correction ID, null request and approved correction outcome; staff resolution has correction ID, original request message ID and independent approved/rejected correction outcome. Pending attendance is permitted only in a correction snapshot. Direct `CorrectionService.correct(CommandContext, eventId, ProposedCorrection, reason)` and request resolution preserve review status; later explicit reviews preserve current effective fields. Retain/correlate older resolutions without rolling back projection. `reviewAttendance` is the existing capability for these management operations.
- [ ] Manual attendance is immutable manager-local history with explicit employee, actor, reason and source, pending until reviewed; no manual staff transport is invented. Owner's explicit manual-employee enrollment link transfers that employee's personal export associations transactionally without altering originals. Receipt returns require an already-known authenticated staff receipt. Preserve owner capture and same-repository capture/import compatibility.
- [ ] Implement validation + idempotent import, decisions/corrections as new records, and permission-controlled review. Same receipt replay after approval preserves the decision. Manual entries include manager identity, reason, source `manual`, and pending review; approval is an explicit auditable action. Staff corrections are signed requests; they do not change approved records until resolved.
- [ ] Create signed delivery acknowledgments and decision messages for return QR/file exchange. Authenticate issuer, company, event hash/ID, and authority history. Receipt acknowledgment updates delivery only; a decision changes review status separately. Older updates cannot roll back later decisions; display unknown/new authority as review-required until its valid chain is accepted.
- [ ] Run receipt/review/update tests plus company-policy tests; expect pass. Test a direct unauthorized review call and a selected wrong company even if the UI hides the action.
- [ ] Commit: `git commit -m "feat: review receipts and preserve correction history"`.

## Task 9: Real camera, QR image import, and file sharing on both platforms

**Files:** Create core `src/contracts/transfer_port.dart`; local `src/platform/{mobile_qr_port,document_port,share_port}.dart`; feature `src/attendance/{scan_screen,message_import_sheet}.dart`; local `test/transfer_adapter_test.dart`; feature `test/transfer_context_test.dart`; `integration_test/qr_transfer_test.dart`; modify `android/app/src/main/AndroidManifest.xml`, `android/gradle.properties`, `ios/Runner/Info.plist`, and feature message-port wiring.

**Interfaces:** `TransferPort.scan({required Set<MessageKind> allowed}) -> Future<Uint8List?>`; `pickMessage() -> Future<Uint8List?>`; `decodePickedImage() -> Future<Uint8List?>`; `shareMessage(Uint8List bytes, String suggestedName) -> Future<ShareOutcome>`; `shareQrPng(Uint8List messageBytes) -> Future<ShareOutcome>`. Outcomes are `opened`, `dismissed`, `unavailable`, `failed`; none means delivered. Save the original authorized context with pending native operations and revalidate before dispatch.

- [ ] Write adapter/context tests: cancel returns no mutation; camera denied offers Files and manager-assisted fallback; multiple decoded QR messages require selection; unsupported/wrong-purpose messages explain the type. Assert:

```dart
await tester.startImportFor(companyA);
await tester.switchCompany(companyB);
await tester.completePickerWith(receiptForA);
expect(await manager.eventCount(companyB), 0);
expect(find.text('Return to the original company to continue'), findsOneWidget);
```

Define these helpers in the feature test around fake ports and real services. Add session expiry during the picker and repeated scanner callbacks producing one import.
- [ ] Run adapter and feature transfer-context tests; expect failure.
- [ ] Implement mobile_scanner QR-only live decode and `analyzeImage` for local PNG/JPEG; preserve bundled Android model (`useUnbundled` absent/false). Add only camera permission with a specific purpose string. Files picker uses MIME/UTI filters and bounded controlled staging. Reject cloud-backed files unavailable offline with a retry message. Handle malformed images without falling through to arbitrary file execution.
- [ ] Render original bytes with QR error correction M, quiet zone, readable screen size, and 1024-pixel PNG export. Over-limit messages export as a `.razecheck-message` file. Sharing uses `share_plus` with iPad anchor bounds; document-picker import accepts this extension. Share-sheet completion never acknowledges attendance. Delete expired temporary share files; retain the persistent event/archive source.
- [ ] Run tests, analysis, and Android/iOS builds. Run `qr_transfer_test.dart` on physical Android and iPhone in airplane mode for live scan and imported image. iOS Simulator image decoding is unsupported and cannot satisfy this gate. If an available device cannot run a test, record the unverified gate instead of claiming parity.
- [ ] Commit: `git commit -m "feat: add offline mobile QR and file transfer adapters"`.

## Task 10: Scoped encrypted backups and non-destructive staged restore

**Files:** Create core `src/recovery/{archive_models,backup_service,restore_service}.dart`; local `src/recovery/{archive_codec,restore_staging,backup_catalog}.dart`; local `test/{backup_archive_test,restore_staging_test}.dart`; feature `src/recovery/{backup_screen,restore_review_screen}.dart`; `docs/protocol/archive-v1.md`; add `archive` 4.5.2 to local dependencies.

**Interfaces:** `BackupService.create(SessionHandle, ExportScope, String passphrase) -> Future<ArchiveDescriptor>`; `RestoreService.inspect(SessionHandle, String selectedFile, String passphrase) -> Future<RestorePreview>`; `apply(RestorePreview, RestoreChoice) -> Future<RestoreResult>`. `ArchiveDescriptor` exposes an opaque artifact ID, creation time, scope, and counts; actual app-private paths remain adapter-owned. `RestorePreview` includes source manifest ID, company/person IDs, authority history, counts/hashes, file completeness, conflict list, and staging token. `RestoreChoice` permits `newInstallation` or `mergeNonConflicting`; existing active management authority is never replaced by this task alone.

- [x] Write archive/staging tests:

```dart
final before = await repo.snapshot(scope);
await expectLater(restore.inspect(session, tamperedArchive, secret),
    throwsCheckError(CheckError.invalidSignature));
expect(await repo.snapshot(scope), before);
```

Add wrong password, truncated header/ciphertext, unsupported version, excessive KDF count, ZIP traversal/symlinks, expansion limits, missing attachment/hash mismatch, missing recovery material, repeated restore, and staff scope attempting company export. Include an actual attachment fixture even though ID-upload UI is later scope.
- [x] Run archive/staging tests; expect failure.
- [x] Implement the Archive v1 layout above, including its exact header, manifest keys, safe entry paths, and limits, and write byte-level fixtures in `archive-v1.md`. Never ZIP-copy a live SQLite file or serialize an active session/device private signing identity. Authentication failure displays "Wrong passphrase or damaged backup" because those causes cannot be reliably distinguished from a failed authentication tag.
- [x] Inspect into isolated staging, authenticate before extraction, use manifest-listed safe paths only, and verify all counts/hashes/recovery dependencies before presenting confirmation. Apply data transactionally with a durable restore journal, including staged secure-key provisioning and attachment moves; failures between key-store and database writes resume/roll back without replacing existing keys or deleting the source. Add fault injection at each activation boundary. New installation credentials and authority activation are Task 11, so staged restored companies remain locked from management writes until authorized.
- [x] Keep the last successful encrypted archive in app-private persistent storage with an explicit save/share action. Display its location and distinguish "created in this app" from a user-confirmed external saved copy. An internal archive alone will not survive uninstall. No silent search of public storage. The backup passphrase is not stored alongside the archive.
- [x] Run archive/staging tests and analysis; expect pass. Test staff export contains only their identities, memberships, own received history, and unsent receipts, never company ownership recovery keys.
- [x] Commit: `git commit -m "feat: add encrypted scoped archives and staged restore"`.

## Task 11: Replacement credentials, authority handover, and recovery

**Files:** Create core `src/recovery/{authority_history,device_replacement_service,handover_service}.dart`; local `src/recovery/handover_journal.dart`; local `test/{device_replacement_test,handover_test,authority_fork_test}.dart`; feature `src/recovery/{replacement_request_screen,handover_screen,recovery_unlock_screen}.dart`; update `archive-v1.md` and enrollment trust handling.

**Interfaces:** `DeviceReplacementService.createRequest(SessionHandle, String companyId, String? employeeId) -> Future<SignedMessage>` (employee ID is null for an owner handover target); `authorize(CommandContext, VerifiedMessage request) -> Future<SignedMessage>`; `accept(SessionHandle, VerifiedMessage grant) -> Future<CommandResult<Membership>>`. `HandoverService.begin(CommandContext, VerifiedMessage targetRequest) -> Future<HandoverOffer>`; `activate(SessionHandle, RestorePreview, HandoverOffer) -> Future<SignedMessage>`; `finish(CommandContext, VerifiedMessage transferAck) -> Future<void>`; `recover(SessionHandle, RestorePreview, String recoverySecret) -> Future<RecoveryResult>`. Define generation records with random ID, parent ID, sequence, issuer public key, root authorization, and transfer/recovery reason.

- [ ] Write replacement/handover tests:

```dart
expect(restored.employeeId, original.employeeId);
expect(restored.installationId, isNot(original.installationId));
expect(restored.canIssueNewPunches, isFalse); // before returned membership grant
await pair.authorizeReplacement();
expect(await pair.verifyHistoricalReceipt(), isTrue);
```

Also assert source freezes management after handover preparation; interrupted export leaves recoverable source; target activation requires proof of target key; lost acknowledgment cannot cause both sides to resume management; old backup restoration cannot overwrite current generation; sibling generations from the same backup trigger an authority-fork conflict.
- [ ] Run the three recovery test suites; expect failure.
- [ ] Implement staff replacement preserving person/employee IDs and historical public keys, issuing a fresh installation key. Exported unsent receipts keep original signed bytes. New attendance requires the manager's returned replacement grant; a copied membership row is insufficient.
- [ ] Implement available-source handover as a journaled state machine: `active -> preparing -> offered -> retired`; target `staged -> activated`. Freeze source management before its final snapshot. Target verifies an offer bound to its fresh public key and activates a root-authorized child generation; return an acknowledgment to retire source. Before offer issuance, cancellation can unfreeze; after issuance, cancellation needs an authenticated target rollback or explicit recovery, never timeout-based unfreeze. Preserve source records until destination verification; retire authority, not historical data.
- [ ] Implement lost-source owner recovery using portable encrypted recovery credentials, with explicit checkpoint/missing-data confirmation and a new authorized generation. Do not restore an old installation signing key as the current identity. If a returning installation presents a stale/competing generation, retain its data for reconciliation and prevent automatic approval/profile/salary overwrite. Local offline revocation is not instantaneous.
- [ ] Run recovery, archive, receipt-history, and enrollment suites; expect pass. Screens explain unrecoverable unsynchronized records and unavailable recovery secrets accurately, and never imply ordinary login restores offline data.
- [ ] Commit: `git commit -m "feat: support verified device replacement and authority recovery"`.

## Task 12: Useful dashboards, reports, and embeddable feature entry

**Files:** Create core `src/attendance/attendance_queries.dart`; feature `src/host/{check_services,check_feature_host}.dart`, `src/raze_check_feature.dart`, `src/theme/check_theme.dart`, `src/dashboard/{staff_home_screen,manager_home_screen}.dart`, `src/reports/attendance_report_screen.dart`; feature `assets/fonts/{Manrope-Regular,Manrope-Medium,Manrope-SemiBold,Manrope-Bold}.ttf`, `assets/fonts/OFL.txt`; local `src/files/attendance_csv.dart`; feature `test/{dashboard_test,embedded_entry_test,accessibility_test}.dart`; local `test/attendance_csv_test.dart`; update root composition, feature pubspec font declarations, and feature public exports.

**Interfaces:** `AttendanceQueries.forStaff(SessionHandle, String companyId) -> Stream<StaffOverview>`; `forManager(CommandContext) -> Stream<ManagerOverview>`; `report(CommandContext, DateRange) -> Future<AttendanceReport>`. Define `CheckServices` as an injected bundle of Identity, Company, Enrollment, Capture, Import, Review, Correction, Update, Backup, Restore, Handover, Queries and Transfer interfaces. `RazeCheckFeature({required CheckServices services, required CheckFeatureHost host, String? initialCompanyId})` is a Flutter widget. Host supplies `onExit`, optional theme/icon builders, and navigation integration; it cannot inject unverified capabilities or a raw database.

- [ ] Write dashboard and embedded-entry tests:

```dart
expect(find.text('Saved on this device'), findsOneWidget);
expect(find.text('Awaiting review'), findsOneWidget);
expect(find.text('Absent'), findsNothing);
expect(find.text('Salary'), findsNothing); // later phase, no dead navigation
```

Fixture uses real service-derived state with one local-only receipt and one manager-received receipt. Also verify company/role always visible, no records leak after switch/lock, last-received time is accurate, unsupported initial-company access is rejected, and the feature mounts under an independent test host with no root app imports.
- [ ] Run feature dashboard/embedded/accessibility tests and CSV tests; expect failure.
- [ ] Build staff Home/Attendance/Profile and manager Overview/Attendance/Team/More navigation. Home surfaces next action, pending receipts, approved/pending counts, manual entry, invitation, backup age, and records-not-received wording qualified by available data. Keep requests/corrections inside attendance for this phase. Apply the approved modern neutral/teal light/dark direction, semantic status labels, at least 48 logical-pixel touch targets, and phone/tablet responsive layout. Bundle Manrope Regular/Medium/SemiBold/Bold with OFL license (the existing licensed assets in Raze Store may be copied into this package without modifying that repository); use host typography when supplied. No runtime font downloads.
- [ ] Implement report date filtering in company time zone, original/received time columns, employee ID/name within permission, source, delivery/review status, exception/correction fields, and report generated-at time. Escape CSV quotes/newlines and neutralize spreadsheet formula-leading cells (`=`, `+`, `-`, `@`, tab, CR) in user-entered text. Staff report is own records only; manager report requires `exportAttendance`.
- [ ] Run feature tests at widths 320/390/768 and text scaling 1.0/2.0; expect no overflow, readable statuses, semantics for icon controls, keyboard-safe forms, and accessible contrast. Run an embedded host test with a different theme/navigation callback. No Raze Store code, native cross-app service, replica status, or restore-from-companion button is introduced.
- [ ] Commit: `git commit -m "feat: deliver attendance dashboards reports and embeddable entry"`.

## Task 13: Device acceptance, reproducible verification, and release evidence

**Files:** Create `integration_test/{offline_attendance_test,recovery_test,secure_storage_test}.dart`; update `integration_test/qr_transfer_test.dart`; create `tool/verify.sh`, `docs/testing/{foundation-acceptance,device-matrix}.md`, and `README.md`; update protocol docs with verified limits only.

**Interfaces:** No new production interface. `tool/verify.sh` accepts optional `FLUTTER_BIN`/`DART_BIN`, runs each package's appropriate analysis/tests, checks formatting, and exits nonzero on failure. Device tests use fresh disposable app test data, never existing Raze Store data or a user's real company.

- [ ] Write integration assertions for a manager and staff logical store using real persistence/keys, full invitation/grant/receipt/ack/review, duplicate import, reopen, and scoped archive restoration. Add real process-kill checks through a documented device procedure: after visible save success, terminate/relaunch and verify event/operation IDs and signed bytes. These tests first expose incomplete platform wiring; record actual failures rather than manufacture a failing assertion.
- [ ] Run `tool/verify.sh`; expect any unresolved integration/wiring issues to fail. Fix only observed issues and rerun their owning tests before the full gate.
- [ ] Build `flutter build apk --debug` and `flutter build ios --simulator --debug`; then run each integration test with `flutter test integration_test/<file>.dart -d <selected-device-id>` on physical Android and iPhone. Re-read device inventory and confirm signing is available; do not alter developer-account settings or enroll devices without authorization. Missing physical/signing capability is recorded as an outstanding acceptance gate, not a pass.
- [ ] Execute the manual matrix on both platforms: fresh-install airplane-mode camera and image decode; rejected permissions; canceled share/file picker; unavailable cloud-backed document; maximum-size valid QR; too-large QR file fallback; overnight/offset event display; different company after picker; expired session; storage failure; duplicate receipt; approval/correction return; export/import wrong password; interrupted handover; uninstall/reinstall using an external backup. Last scenario uses disposable test installs only and never claims cache/companion recovery.
- [ ] Test oldest proposed platform floors (Android 24/iOS 16) with available emulator/simulator for supported features, plus physical camera/key/share tests on available devices. Record OS/device class, tested format limits, build revision, test date, and any unverified floor/device combination. Engineering performance fixture: 100 staff and 10,000 attendance events, reopening, paginated history, duplicate import, and backup within stated limits; this is not a marketed capacity guarantee.
- [ ] Run final `tool/verify.sh`, both builds, and relevant device suites after fixes. Review the branch for raw sensitive logs, unintended network use, Store dependencies, disabled future screens, and misleading "synced" or "backed up" claims. Record exact passing commands and outstanding limitations in acceptance docs. Independent whole-branch review is required before calling the foundation ready; release distribution remains out of scope.
- [ ] Commit: `git commit -m "test: verify offline foundation across Android and iOS"`.

## Verification commands and task order

All command examples assume the executor's checkout, not a hard-coded worktree. Use a shell with the SDK variables above. Root dependencies are resolved with `flutter pub get`; Dart workspace members share the root lockfile. `tool/verify.sh` must run:

```bash
"$DART_BIN" format --output=none --set-exit-if-changed lib packages integration_test
"$FLUTTER_BIN" analyze
(cd packages/raze_check_core && "$DART_BIN" test)
(cd packages/raze_check_local && "$FLUTTER_BIN" test)
(cd packages/raze_check_feature && "$FLUTTER_BIN" test)
```

Task order is 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13. Treat interfaces as sequential dependencies. A reviewer may inspect finished work in parallel, but implementations that mutate the same schema/contracts must not race. At each commit stage only that task's files and its required generated output, run `git diff --cached --check`, then commit with the stated message. Never stage unrelated work wholesale.

## Spec coverage and plan self-review

| Approved requirement | Owner in this plan / explicit later track |
| --- | --- |
| Local profiles, companies, roles, staff management | Tasks 2–4; custom fields/ID-upload UI later |
| Enrollment, key origin, device authorization | Tasks 5–6 and 11 |
| Offline punches, QR/image/file transfer, duplicate handling | Tasks 5 and 7–9 |
| Manual entry, staff correction, decision history | Task 8 |
| New-device backup/restore, identities, authority history | Tasks 10–11 |
| Helpful UI, permissions, freshness, accessibility, exports | Tasks 4, 9, 12–13 |
| Standalone operation and future host readiness | Tasks 1, 3, 5, 10, 12; no concrete Store bridge |
| Local Wi-Fi, schedules/grace, leave, OT, salary | Free workplace operations plans after foundation |
| Cloud migration, multiple remote managers, paid backups | Paid coordination plan |
| Two-app durable replicas and uninstall recovery | Held Raze Store integration plan |
| Biometric identification and strict presence | Separate optional equipment/policy design |

Self-review performed before handoff: scope maps to the approved first delivery phase; later subsystems remain named rather than dropped. Check public types and signatures against each task before execution; test-only fixture helpers live in the explicitly listed support/test files. Review Focus failures have owning tests. No application code or native feasibility is implied by the plan itself.

## Primary references and compatibility notes

- [Pinned Flutter Android defaults](https://github.com/flutter/flutter/blob/3.44.7/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt) and [Dart workspaces](https://dart.dev/tools/pub/workspaces).
- [Flutter package boundaries](https://docs.flutter.dev/packages-and-plugins/developing-packages).
- [Drift native platform setup](https://drift.simonbinder.eu/platforms/) and [encryption requirements](https://drift.simonbinder.eu/platforms/encryption/): ordinary SQLite does not supply encrypted records automatically.
- [mobile_scanner](https://pub.dev/packages/mobile_scanner/versions/7.4.2) and [image decoding API](https://pub.dev/documentation/mobile_scanner/latest/mobile_scanner/MobileScannerController/analyzeImage.html): bundled Android model and physical-iPhone image gate.
- [file_selector](https://pub.dev/packages/file_selector/versions/1.1.0), [compatible iOS implementation](https://pub.dev/packages/file_selector_ios/versions/0.5.3%2B6), and [share_plus](https://pub.dev/packages/share_plus/versions/13.3.1): native import/share differences.
- [Secure storage](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0), [cryptography](https://pub.dev/packages/cryptography/versions/2.9.0), and [Flutter crypto backend](https://pub.dev/packages/cryptography_flutter/versions/2.3.4).
- [Compatible build_runner](https://pub.dev/packages/build_runner/versions/2.16.2) and [Drift generator manifest](https://pub.dev/api/packages/drift_dev/versions/2.35.1).
- [Bundled time-zone database](https://pub.dev/packages/timezone/versions/0.11.0) and [archive codec](https://pub.dev/packages/archive/versions/4.5.2).

## Execution handoff

Review this plan before implementation and select an execution method. Recommended: **subagent-driven**, with one task implemented and independently reviewed at a time, plus a final whole-branch review. The identity, receipt, and recovery boundaries justify that scrutiny; tasks should remain sequential because their interfaces are tightly connected. **Native execution** is the lower-overhead alternative: one implementer follows all tasks and a fresh reviewer checks the whole branch at the end. Neither choice resumes the held Raze Store integration.
