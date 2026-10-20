# Guided Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a five-step first-open welcome and nine contextual feature guides, with offline progress, Settings replay, accessible artwork, and screenshots of the implemented screens.

**Architecture:** The reusable feature owns guide content, presentation, anchors, and ephemeral navigation context. A Dart-only core preference contract connects it to a bounded local JSON adapter through the optional host configuration. Existing screens retain all business commands and authorization checks.

**Tech Stack:** Existing Flutter 3.44.7 / Dart 3.12.2 workspace, Material 3, bundled Manrope and Material Icons, Dart file APIs, Flutter unit/widget tests. No new dependency.

**Spec:** [Approved guided onboarding design](../specs/2026-10-20-guided-onboarding-design.md). Read it before execution, including all 46 step positions and audience/recovery variants.

**Status:** Written spec approved 2026-10-20. Plan awaits user review. Preserve the user's selected **subagent-driven** execution method.

## Global Constraints

The following requirements are quoted from the approved spec:

- “Deliver ten guides with 46 authored step positions.”
- “Next advances the explanation only; it never presses the highlighted control.”
- “Finishing marks a guide Viewed” — never a business success.
- “Before unlock, only the welcome introduction and general safety explanations are available.”
- “Limit the file to 64 KiB and a bounded catalog-sized set of entries.”
- “No person/company identifiers, passphrases, receipt contents, or permission grants are stored in it.”
- “Automatic welcome is explicitly enabled by the standalone host and defaults off for an embedded host.”
- “Guide preferences are excluded from attendance recovery archives.”
- “Raze Store remains untouched.”
- “All steps must be scrollable when needed.”

Retain Android API 24 / iOS 16.0 floors and current dependency lockfile. Work in the existing managed checkout on the user's `dev` branch; `dev` is already the remote default. Do not switch or clean the separate primary checkout. Preserve ignored foundation evidence. No business schema/message/archive changes, new native plugin, payroll/leave/cloud claims, or regeneration of the approved launcher icon.

## Review Focus

These five conditions have specific tests assigned below:

1. Corrupt, oversized, future-version, or interrupted preference storage: app entry and attendance remain usable; original bytes and business files survive. Task 1.
2. A delayed guide navigation finishes after company, panel, permission, or session change: it never highlights or opens an action for the replacement context. Tasks 2 and 4–6.
3. Reading a tutorial would accidentally scan, approve, import, restore, attest backup custody, or prolong unlock: guide controls perform no such calls. Tasks 2 and 4–6.
4. A guide target unmounts, scrolls offscreen, becomes covered, or no longer fits at large text: explanation and exit remain usable without a misleading highlight. Task 3.
5. A host routes outside the feature navigator, omits persistence, or overrides branding: guides preserve host isolation and do not expose protected content after lock. Task 4.

---

## Repository and verification conventions

Paths are relative to `/Users/rem/.codex/worktrees/raze-check-foundation/raze_check`. The reviewed baseline is `6560c6a` plus this documentation commit; record the actual execution base before edits. Flutter is not currently on shell PATH. In each verification shell, set these task-specific tool variables before using the commands below:

```bash
FLUTTER_BIN=/Users/rem/fvm/versions/3.44.7/bin/flutter
DART_BIN=/Users/rem/fvm/versions/3.44.7/bin/dart
```

Run each task's failing check once, implement, and run its focused passing check. Broaden only for affected integration boundaries. The final task runs the relevant combined checks once. Do not repeat the 10,000-event capacity exercise, key recovery matrices, or destructive device tests for help UI.

Existing support:

- `packages/raze_check_feature/test/support/dashboard_fixture.dart`: `dashboardFixture()`, `featureServices(device)`, `unlockFeature(tester, name)`, and `settleFeature(tester, {until})`.
- `packages/raze_check_feature/test/full_entry_visual_test.dart`: real feature rendering, bundled font loading, and `RepaintBoundary` PNG capture.
- `packages/raze_check_local/test/support/temp_paths.dart`: isolated private paths.
- `test/check_app_test.dart`: real composition and idle-expiry coverage.

## File responsibilities and task sequence

| Task | Responsibility | Main new files |
| --- | --- | --- |
| 1 | Preference contract and durable standalone adapter | Core `src/guides/guide_progress.dart`; local `src/guides/local_guide_progress_store.dart` |
| 2 | Catalog, variants, and guide state transitions | Feature `src/guides/guide_models.dart`, `guide_catalog.dart`, `guide_controller.dart`, and `content/*.dart` |
| 3 | Anchors, responsive panel, invitation, and artwork | Feature `src/guides/guide_scope.dart`, `guide_scene.dart`, `guide_anchor_registry.dart`, `guide_target.dart`, `guide_layer.dart`, `guide_panel.dart`, `guide_invitation.dart`, `guide_artwork.dart` |
| 4 | First open, host composition, Settings and replay | Feature `src/guides/welcome_screen.dart`, `guide_library_screen.dart`, `src/settings/settings_screen.dart`; existing entry/host/composition |
| 5 | Company, attendance, team, and report integration | Existing workflow screens; `src/guides/company_guide_bindings.dart` |
| 6 | Backup and device-recovery integration | Existing recovery screens; `src/guides/recovery_guide_bindings.dart` |
| 7 | Combined verification and visual evidence | Feature `test/guide_visual_test.dart`; `docs/testing/guided-onboarding.md` and `screenshots/guides/` |

Execute in that order. Share the interfaces below with each implementer. Tasks 5 and 6 are separated by independently reviewable workflow boundaries, but integration in the shared feature entry remains sequential. Use targeted subagents for independent research and fresh reviews without concurrent edits to the same files.

### Task 1: Persist tutorial preferences without touching business storage

**Files**

- Create: `packages/raze_check_core/lib/src/guides/guide_progress.dart`
- Modify: `packages/raze_check_core/lib/raze_check_core.dart`
- Create: `packages/raze_check_local/lib/src/guides/local_guide_progress_store.dart`
- Modify: `packages/raze_check_local/lib/raze_check_local.dart`
- Test: `packages/raze_check_core/test/guide_progress_test.dart`
- Test: `packages/raze_check_local/test/guide_progress_store_test.dart`

**Interfaces**

- `GuideProgress({required String guideId, required String variantId, required int contentRevision, String? stepId, bool viewed = false, bool invitationDismissed = false})`: immutable values. A null step means not started.
- `GuideProgressSnapshot({bool welcomeDismissed = false, List<GuideProgress> entries = const []})`: immutable defensive copy, unique `(guideId, variantId)` entries.
- `abstract interface class GuideProgressStore`: `Future<GuideProgressSnapshot> read()`, `Future<void> write(GuideProgressSnapshot snapshot)`, `Future<void> flush()`.
- `LocalGuideProgressStore({required AppPaths paths}) implements GuideProgressStore`.
- Adapter file: `${paths.root.path}/guide-progress.v1.json`; temporary file: `guide-progress.v1.json.tmp`. Schema version `1`, maximum encoded size **65,536 bytes**, maximum **64 entries**. ID strings use `[a-z0-9][a-z0-9-]{0,63}`; content revisions are positive integers. No timestamp, identity, or authority fields.

- [ ] **Step 1: Write contract/storage tests.** Cover defensive copying, duplicate keys, fresh/round-trip state, concurrent ordered writes, a leftover interrupted temporary file, corrupt JSON, future version, oversized input/output, and unavailable storage. Use `tempPaths()` and known sentinel files for the database/catalog; compare their bytes before/after. Representative assertions:

  ```dart
  expect((await reopened.read()).welcomeDismissed, isTrue);
  expect((await reopened.read()).entries.single.stepId, 'choose-punch');
  expect(await originalFile.readAsBytes(), originalBytes);
  expect(await databaseSentinel.readAsBytes(), databaseBytes);
  expect(encoded.length, lessThanOrEqualTo(65536));
  ```

  The malformed/future-version cases must reject subsequent writes on that adapter instance without replacing the source. An orphan temporary file never overrides a valid main file.

- [ ] **Step 2: Confirm the new tests fail.** From each package run `"$DART_BIN" test test/guide_progress_test.dart` (core) and `"$FLUTTER_BIN" test --no-pub test/guide_progress_store_test.dart` (local). Expected initial failure: missing guide contract/adapter.
- [ ] **Step 3: Implement the interfaces and adapter.** Bound the file read to at most 65,537 bytes before JSON decoding, validate types/limits, and ignore extra unrecognized JSON fields without retaining them. Serialize writes; flush the temporary file then replace the main file in the same directory. Missing file means empty progress. Malformed/oversized/unsupported files disable persistence for that instance and remain untouched. I/O failures surface to the guide controller only. `flush()` waits for already queued writes; no database or key APIs are referenced.
- [ ] **Step 4: Run both focused tests to PASS.** Inspect failures rather than weakening the byte-preservation and bound assertions.
- [ ] **Step 5: Commit the six listed files** with `feat: persist bounded local guide preferences`.

### Task 2: Define all guide content and non-mutating state transitions

**Files**

- Create under `packages/raze_check_feature/lib/src/guides/`: `guide_models.dart`, `guide_catalog.dart`, `guide_controller.dart`
- Create under that directory's `content/`: `welcome_company_guides.dart`, `attendance_guides.dart`, `management_guides.dart`, `recovery_guides.dart`
- Create: `packages/raze_check_feature/test/support/guide_fixture.dart`
- Test: `packages/raze_check_feature/test/guide_catalog_test.dart`, `guide_controller_test.dart`

**Interfaces**

- `GuidePresentationConfig({bool automaticWelcome = false})`.
- `GuideDestination` enum: `createCompany`, `joinCompany`, `capture`, `attendance`, `team`, `reports`, `backup`, `recovery`. These denote screens, never actions such as check-in or approval.
- `GuideStep({required String id, required String title, required String body, String? targetId, GuideDestination? destination})`.
- `GuideDefinition({required String id, required String variantId, required int revision, required String title, required String description, required List<GuideStep> steps})`.
- `GuideAudience({required Map<String, String> variants})`: immutable map of permitted guide ID to content variant. Presentation eligibility only; never an authorization grant and never supplied through the host.
- `GuideContext({required Object token, required Object authorityToken, required GuideAudience audience, required Future<void> Function() validateCurrent, GuideDestination? destination, Map<GuideDestination, Future<void> Function()> navigation = const {}})`: ephemeral scene binding. The scene token changes on panel/route changes; the authority token changes on session, company, or permission changes. Neither grants authority. Validation closures capture and check the real session/company and current scene; none is serialized.
- `GuideCatalog()`: `GuideDefinition resolve(String guideId, String variantId)` and `List<GuideDefinition> available(GuideAudience audience)`. Unsupported IDs/variants cannot be started.
- `GuideRun`: read-only current `GuideDefinition definition`, `int stepIndex`, and `Object contextToken`.
- `GuideController({GuideProgressStore? store, required GuideCatalog catalog}) extends ChangeNotifier`: `Future<void> initialize()`, `Future<void> bind(GuideContext context)`, `void invalidateScene(Object token)`, `void invalidateAuthority(Object authorityToken)`, `void start(String guideId, {bool restart = false})`, `void next()`, `void back()`, `void skip()`, `void dismissInvitation(String guideId)`, `Future<void> showDestination()`, `void setPaused(bool paused)`, `Future<void> flush()`.
- Controller getters: `GuideRun? active`, `GuideAudience audience`, `GuideProgressSnapshot progress`, `String? notice`, `bool ready`, `bool persistenceFailed`, `bool sessionOnly`, `bool paused`, `bool canShowDestination`; `bool shouldInvite(String guideId)`. `catalog` is a final public field for library lookup.
- Test support: `MemoryGuideProgressStore implements GuideProgressStore` with `GuideProgressSnapshot snapshot`, `int writes`, and optional read/write failures; `testGuideContext({Object? token, Object? authorityToken, GuideDestination? destination, Map<String,String> variants = const {'welcome':'public'}, Future<void> Function()? validateCurrent, Map<GuideDestination, Future<void> Function()> navigation = const {}})`.

- [ ] **Step 1: Write catalog/controller tests.** Define unique semantic step IDs for the spec's numbered positions, starting all revisions at `1`. Count authored positions once, not per variant. Assert the guide lengths `[5,4,6,4,5,5,4,3,5,5]`, unknown-entry filtering, resume by step ID, removed-step restart with explanation, and preserved first-open dismissal across content revisions. Test Skip retains the current position, completion says Viewed, invitation suppression, missing-store session progress, and storage errors falling back to memory. A delayed navigation completer must never restore an invalidated context:

  ```dart
  expect(catalog.available(publicAudience).map((g) => g.id), ['welcome']);
  expect(controller.progress.welcomeDismissed, isTrue);
  expect(controller.active, isNull); // after invalidation and late navigation
  expect(navigationCalls, 0); // Next/Back/Skip never call Show me
  ```

  Also test the positive Show me handshake: a matching destination with the same validated authority token resumes the same guide/step, while another destination or authority token does not.

- [ ] **Step 2: Run from the feature package:** `"$FLUTTER_BIN" test --no-pub test/guide_catalog_test.dart test/guide_controller_test.dart`. Expected initial failure: missing catalog/controller.
- [ ] **Step 3: Implement content and state.** Copy the approved spec's actual UI vocabulary and distinctions into concise step text. Use variants `public`, `personal`, `staff`, `owner`, `operator`, `staff-replacement`, `owner-target`, `owner-source`, and `owner-recovery` only where applicable; each variant retains its guide's slot count. The welcome always uses `public`. Unknown stored entries are omitted from the active catalog. Starting resolves the permitted variant afresh; never restore a previous profile's actionable variant.
- [ ] **Step 4: Implement safe navigation and progress effects.** The controller contains no services, database, transfer ports, command contexts, or business callbacks. `showDestination()` is user-triggered only; capture tokens and validate before navigation. Retain one pending guide-position/destination intent. A destination scene can resume it only after validation, with the same authority token and matching destination; `bind()` checks its generation again after awaiting validation. This handshake occurs when the destination mounts, not when a pushed route eventually returns. Authority invalidation clears active and pending guidance; unrelated navigation, failed/canceled requests, or stale completions cannot revive it. Catch preference failures once into nonblocking state. Await initialization before the first write to avoid overwriting loaded progress. Serialize snapshots in user-interaction order. `next()` on the last welcome page dismisses automatic welcome; feature completion marks Viewed; Skip preserves a resumable position and suppresses further automatic invitations. Invitation suppression applies across variants of that guide on this installation.
- [ ] **Step 5: Run the focused tests to PASS**, then commit the listed guide/controller/content/test files with `feat: define role-aware tutorial catalog and progress`.

### Task 3: Render accessible guides around real controls

**Files**

- Create under `packages/raze_check_feature/lib/src/guides/`: `guide_scope.dart`, `guide_scene.dart`, `guide_anchor_registry.dart`, `guide_target.dart`, `guide_layer.dart`, `guide_panel.dart`, `guide_invitation.dart`, `guide_artwork.dart`
- Test: `packages/raze_check_feature/test/guide_presentation_test.dart`

**Interfaces**

- `GuideScope({required GuideController controller, required Widget child})`; `static GuideController? maybeOf(BuildContext context)` and `static GuideAnchorRegistry? registryOf(BuildContext context)`. The scope owns one registry for the feature. Screens mounted without guides remain functional.
- `GuideAnchorRegistry extends ChangeNotifier`: `void register(Object sceneToken, String id, GlobalKey key)`, `void unregister(Object sceneToken, String id, GlobalKey key)`, `Rect? bounds(Object sceneToken, String id, RenderBox layer)`. Unregister must match the key so an old widget cannot remove its replacement. Bounds are absent for detached, hidden, clipped-offscreen, or invalid targets.
- `GuideScene({required GuideContext context, required Widget child})`: owns its entries in that registry, binds only while visible/current, and invalidates its scene token on disposal/context change.
- `GuideTarget({required String id, required Widget child})`: attaches/detaches its render target to the nearest scene; without a scene it returns its child.
- `GuideLayer({required Widget child})`: presents the active panel and decoration above the feature UI, within the protected visibility boundary.
- `GuidePanel({required GuideRun run, required VoidCallback onBack, required VoidCallback onNext, required VoidCallback onSkip, VoidCallback? onShowDestination})`.
- `GuideInvitation({required String guideId})`: compact Show me how and dismiss controls; absent if `shouldInvite` is false or the guide is unavailable.
- `GuideArtwork({required String guideId, required int stepIndex, WidgetBuilder? brandBuilder})`.

- [ ] **Step 1: Write presentation tests.** Mount a scene with real buttons, an overflowing scroll area, and an active guide. Test target removal/replacement, duplicate IDs in separate routes/scenes, offscreen fallback, a covered route/modal, panel controls, and unchanged application callbacks. Verify scroll/rotation remeasures actual bounds. Assert:

  ```dart
  expect(applicationCommandCalls, 0); // after all guide navigation controls
  expect(panelRect.overlaps(targetRect), isFalse); // when spotlight is shown
  expect(find.text('Skip'), findsOneWidget); // including missing-target fallback
  expect(tester.takeException(), isNull); // 320px width, 2x text and landscape
  ```

  Include semantics, focus order, Android/iOS tap-target guidance, reduced-motion rendering, and Back disabled on step one. Underlying highlighted controls remain user-operated; guide decorations must not intercept their taps.

- [ ] **Step 2: Run:** `"$FLUTTER_BIN" test --no-pub test/guide_presentation_test.dart` from the feature package. Expected initial failure: missing presentation widgets.
- [ ] **Step 3: Implement layout and target lifetime.** Use widget/render registration, not text lookup or coordinates baked into the catalog. Measure into the guide layer's coordinate space after layout; respond to scrolling, size/text-scale changes, and route visibility. Only the current scene's mounted, visible targets qualify. Avoid continuous timers. Use an `IgnorePointer` highlight decoration and an independently interactive panel. If safe spacing cannot fit, use a scrollable bottom/full-page explanation and omit the spotlight. Keep Skip/Close and a semantic step counter reachable.
- [ ] **Step 4: Implement artwork and invitations.** Preserve the approved mascot; use existing Material Icons (`person_outline`, `add_business`, `qr_code_scanner`, `fact_check_outlined`, `people_outline`, `file_download_outlined`, `settings_backup_restore`) in themed rounded compositions. Inherit Manrope, Material 3, current host palette, 48×48 controls, and radius-22 card vocabulary. No text baked into images, icon-font replacement, new SVG/raster dependency, or launcher-icon regeneration. Honor `brandBuilder` for the welcome.
- [ ] **Step 5: Run presentation tests to PASS** and commit with `feat: add accessible guided control highlights`.

### Task 4: Connect welcome, Settings, progress, and host lifecycle

**Files**

- Create: `packages/raze_check_feature/lib/src/guides/welcome_screen.dart`, `guide_library_screen.dart`
- Create: `packages/raze_check_feature/lib/src/settings/settings_screen.dart`
- Modify: `packages/raze_check_feature/lib/src/host/check_feature_host.dart`
- Modify: `packages/raze_check_feature/lib/src/raze_check_feature.dart`
- Modify: `packages/raze_check_feature/lib/src/profile/profile_gate.dart`
- Modify: `packages/raze_check_feature/lib/raze_check_feature.dart`
- Modify: `packages/raze_check_feature/lib/src/company/company_switcher.dart` (Settings callback/entry only in this task)
- Modify: `lib/app/local_composition.dart`, `lib/app/check_app.dart`
- Test: `packages/raze_check_feature/test/guide_entry_test.dart`, `guide_library_test.dart`, `guide_navigation_test.dart`, `embedded_entry_test.dart`
- Test: `test/check_app_test.dart`, `test/local_composition_test.dart`

**Interfaces**

- Extend `CheckFeatureHost` with optional `GuideProgressStore? guideProgress` and `GuidePresentationConfig guides = const GuidePresentationConfig()`; existing constructors stay valid. Export only the configuration with existing feature API; internal guide contexts/eligibility are not a host permission interface.
- Add `final LocalGuideProgressStore guideProgress` to `LocalComposition`, initialized once with the same private `AppPaths`; flush best-effort on close without suppressing repository/identity cleanup.
- `WelcomeScreen({WidgetBuilder? brandBuilder, required VoidCallback onFinished})` uses the current scoped controller.
- `SettingsScreen({required VoidCallback onOpenGuides})`.
- `GuideLibraryScreen()` reads the currently permitted catalog and progress from scope.
- Add optional `VoidCallback? onSettings` to `CompanyWorkspace`; existing clients continue to work.
- Settings route name `settings`, library route name `help-guides`; use `CheckFeatureHost.open` or its existing local fallback.

- [ ] **Step 1: Write real-entry tests.** Cover first-open five steps, quit/reopen at step three, Skip suppression, completed suppression, replay/restart, pre-unlock public-only library, shared-installation progress disclosure, and no-company Settings. Advance an existing fake clock during Next/Back/animations and verify the same five-minute lock deadline. Keep the profile gate the navigator's first route. Representative assertions:

  ```dart
  expect(find.text('Step 3 of 5'), findsOneWidget);
  expect(find.text('Create local profile'), findsOneWidget); // after Get started
  expect(find.text('Help & Guides'), findsOneWidget); // Settings
  expect(controller.active, isNull); // lock or host exit
  expect(identityActivityCalls, 0); // tutorial-only interaction
  ```

  Extend embedded coverage with no adapter/automaticWelcome off, host typeface/brand override, and a host `navigate` that uses an outer navigator. A protected guide moved there must hide/close on lock even if the profile gate cannot pop that outer route. Verify normal guide navigation does not discard an existing form draft.

- [ ] **Step 2: Run new entry/library/navigation tests to confirm initial failure**, then the root composition test focused on persistence after reopen. Do not treat old tests failing because welcome was enabled as authorization to disable it in production; configure those fixtures explicitly where they test another behavior.
- [ ] **Step 3: Implement root composition and entry.** Create one controller per feature instance, initialize once, and place guide scope/layer inside the existing protected `Visibility`. Standalone passes `automaticWelcome: true` plus its adapter. Gate the initial profile chooser in place so welcome never becomes a permanent route under it. Missing adapter means session-only progress; failed persistence shows a nonblocking message. The first-run UI must not hold app entry hostage to a thrown storage error.
- [ ] **Step 4: Implement Settings/library and lifecycle binding.** Show Not started / In progress / Viewed, Continue/Restart, Replay introduction, and “Guide progress is shared on this device.” Before unlock bind only the welcome/public safety context. Derive unlocked eligibility from current live screen checks. Add app-bar Settings plus More/Profile entry. Wrap pages passed to custom host routing with captured guide scope and lifecycle/session visibility guards. Invalidate authority before lock, replacement unlock, exit, and disposal; pause for background/covering routes. Give Settings/library the originating validated audience so they do not erase company eligibility, and discard it on authority change. Never call `recordActivity` or `onAuthorizedActivity` from tutorial controls.
- [ ] **Step 5: Run affected checks to PASS.** Feature: `"$FLUTTER_BIN" test --no-pub test/guide_entry_test.dart test/guide_library_test.dart test/guide_navigation_test.dart test/embedded_entry_test.dart`. Root: `"$FLUTTER_BIN" test --no-pub test/check_app_test.dart test/local_composition_test.dart`.
- [ ] **Step 6: Commit only Task 4 files** with `feat: add first-open welcome and settings guide library`.

### Task 5: Attach company, attendance, team, and report guides

**Files**

- Create: `packages/raze_check_feature/lib/src/guides/company_guide_bindings.dart`
- Modify under `packages/raze_check_feature/lib/src/`: `company/company_switcher.dart`, `company/company_setup_screen.dart`, `dashboard/staff_home_screen.dart`, `dashboard/manager_home_screen.dart`
- Modify: `enrollment/membership_status_screen.dart`, `invitation_screen.dart`, `join_company_screen.dart`, `join_review_screen.dart`
- Modify: `attendance/capture_screen.dart`, `receipt_screen.dart`, `receipt_outbox_screen.dart`, `review_queue_screen.dart`, `attendance_detail_screen.dart`, `correction_request_screen.dart`, `message_import_sheet.dart`
- Modify: `team/staff_list_screen.dart`, `staff_detail_screen.dart`, `operator_access_screen.dart`, `reports/attendance_report_screen.dart`
- Test: `packages/raze_check_feature/test/guide_workflows_test.dart`; extend `guide_navigation_test.dart`

**Interfaces**

- `GuideAudience companyGuideAudience({required bool unlocked, required bool canCreateCompany, required bool owner, required bool operatorSession, required bool activeMembership, required bool canInvite, required bool canManageStaff, required bool canReview, required bool canExport})`.
- The caller supplies already-derived presentation eligibility from its existing checks; this helper only maps to guide variants. No host-supplied role or capability is accepted.
- Company workspace owns a separate guide scene token for each panel/tab identity and a guide authority token for the live session/company/permissions. Preserve the existing business `_generation` and its semantics.
- Use safe existing screen callbacks for destinations. Do not navigate away from a live draft without the screen's existing explicit discard decision.

- [ ] **Step 1: Write workflow and stale-context tests.** With real synthetic staff/owner data and a restricted operator fixture, open/replay the seven relevant guides (`companies` through `reports`). Assert eligible actions match existing UI, including ordinary personal staff who possess stored capabilities but are not in management mode. Test missing membership, no receipt, no staff selection, company switch, panel switch within the same route, permission reload, and late Show me completion. Snapshot repository rows and command counters before and after Next/Back/Skip:

  ```dart
  expect(afterRecords, beforeRecords);
  expect(scanCalls, 0);
  expect(importCalls, 0);
  expect(reviewCalls, 0);
  expect(find.text('Membership active'), findsNothing); // waiting for grant
  ```

- [ ] **Step 2: Run:** `"$FLUTTER_BIN" test --no-pub test/guide_workflows_test.dart test/guide_navigation_test.dart`. Expected initial failure: missing invitations/targets/integration.
- [ ] **Step 3: Add scene binding and the normal-screen navigation map.** Reuse `_capture`, `_attendance`, `_report`, enrollment and company-setup callbacks only when their current context and draft state allow navigation. Their original authorization checks remain in place. Scene tokens change on panel/tab identity; authority tokens change on session/company/permission context, independently of command generations. Validation checks the captured opaque session with `identical`, the original selected company, and scene liveness before/after asynchronous validation. Destination scenes identify the matching `GuideDestination` so a valid explicit Show me can resume its explanatory position.
- [ ] **Step 4: Add stable targets and invitations for every catalog position.** Use IDs named after actual controls, e.g. `company-create`, `company-time-zone`, `membership-read-invitation`, `capture-check-in`, `receipt-share`, `review-reason`, `team-operator-access`, `report-scope`. `GuideStep.targetId` must match these IDs. Add wrappers only; don't replace normal business callbacks with guide-aware commands. Counterpart/missing-prerequisite steps remain informational. Modal transfer choices can register targets, but Show me must never open a scanner, picker, share sheet, or import. Rebinding after a return resolves real targets afresh.
- [ ] **Step 5: Run integration tests to PASS**, plus existing `company_context_test.dart`, `transfer_context_test.dart`, `capture_flow_test.dart`, `enrollment_flow_test.dart`, `review_flow_test.dart`, and `report_screen_test.dart`. Commit listed files with `feat: guide company setup and attendance workflows`.

### Task 6: Attach backup and device-transfer guides

**Files**

- Create: `packages/raze_check_feature/lib/src/guides/recovery_guide_bindings.dart`
- Modify under `packages/raze_check_feature/lib/src/recovery/`: `recovery_workspace.dart`, `backup_screen.dart`, `restore_review_screen.dart`, `replacement_request_screen.dart`, `handover_screen.dart`, `recovery_unlock_screen.dart`
- Test: `packages/raze_check_feature/test/guide_recovery_test.dart`

**Interfaces**

- `GuideAudience recoveryGuideAudience({required bool restrictedOperator, required bool owner, required bool canExportStaffRecovery, required String recoveryVariant})`; accepted path variants are the four recovery variants from Task 2.
- Derive `canExportStaffRecovery` from the existing combination of membership-management and attendance-export checks. The recovery workspace's own selected company/member determines source/export context; never substitute the dashboard's company.
- Reuse Task 3 scenes/targets and Task 2 `backup`/`recovery` screen destinations. There is no guide activation, archive apply, source freeze, or external-copy confirmation callback.

- [ ] **Step 1: Write recovery-guide tests.** Exercise ordinary personal backup, owner company backup, restricted operator denial, staff replacement, owner target/source, and lost-source text. Require ordered staff instructions (archive before grant), source freeze consequences, and passive-restore/activation distinction. Starting from a screen with real form input, Next/Skip must preserve it. Capture counters for file pick/share, archive create/apply, replacement authorize/accept, handover freeze/activate, and backup attestation:

  ```dart
  expect(businessAndTransferCalls, isEmpty);
  expect(backupConfirmed, isFalse);
  expect(sourceFrozen, isFalse);
  expect(find.textContaining('before'), findsWidgets); // archive-before-grant copy
  expect(controller.active, isNull); // recovery company changed mid-navigation
  ```

- [ ] **Step 2: Run:** `"$FLUTTER_BIN" test --no-pub test/guide_recovery_test.dart`. Expected initial failure: missing recovery guide bindings.
- [ ] **Step 3: Add scoped scene bindings, targets, and invitations.** Include backup scope/passphrase/create/share/verify/inspect and restore review targets. Add recovery path/request/archive/offer/activation/acknowledgment targets only where the actual controls exist. Before-unlock help describes protection generally and never enables protected recovery actions. Recovery file messages retain their current Files-based UI. Inactive counterpart steps explain the exchange; missing data produces an explanation rather than a demo archive.
- [ ] **Step 4: Run new tests to PASS**, plus existing `backup_screen_test.dart`, `recovery_screen_test.dart`, `replacement_operator_test.dart`, and `backup_dashboard_refresh_test.dart`. Commit listed files with `feat: guide backup and device recovery safely`.

### Task 7: Capture screens, verify builds, and document delivery

**Files**

- Create: `packages/raze_check_feature/test/guide_visual_test.dart`
- Create: `docs/testing/guided-onboarding.md`
- Create: `docs/testing/screenshots/guides/` with eight PNGs and `metadata.json`
- Modify: `README.md` (link to Help & Guides behavior/evidence)
- Update this plan's checkboxes and approved spec's implementation status only after evidence supports them.

**Interfaces**

- Screenshot export uses the existing `RAZE_VISUAL_DIR` environment convention and `RepaintBoundary` at the full-feature layer, above the nested navigator and guide presentation.
- Metadata per image: source commit, capture type, synthetic fixture description, viewport, device-pixel ratio, text scale, theme, guide/step, and SHA-256. No personal device IDs or signing details in tracked evidence.
- Runtime screenshot baseline already captured at `build/artifacts/guided-onboarding/baseline/android-current.png`; it shows the existing app before tutorials and remains private/untracked.

- [ ] **Step 1: Add visual assertions and capture cases.** Reuse `dashboardFixture`, font loading and capture patterns from `full_entry_visual_test.dart`. Test both themes, 320/390/768 widths, 1×/2× text, landscape, visible/missing targets, and reduced motion. Assert no overflow, 48-pixel interactive controls, labeled semantics, real anchor alignment, and no overlap when highlighted. Export these eight actual Flutter renders:

  | File | State | Viewport / scale |
  | --- | --- | --- |
  | `welcome-light.png` | First welcome page, light | 390×844 / 1 |
  | `welcome-dark.png` | First welcome page, dark | 390×844 / 1 |
  | `staff-guides.png` | Staff Help & Guides library | 390×844 / 1 |
  | `capture-highlight.png` | Capture guide, actual Check in target | 390×844 / 1 |
  | `management-review.png` | Management review guide, dark | 390×844 / 1 |
  | `backup-tablet.png` | Owner backup guide | 768×1024 / 1 |
  | `welcome-large-text.png` | Welcome with large text | 320×900 / 2 |
  | `capture-landscape.png` | Capture guide after rotation | 844×390 / 1 |

- [ ] **Step 2: Run the visual test, inspect every PNG, and fix demonstrated defects.** From the feature package:

  ```bash
  RAZE_VISUAL_DIR=/Users/rem/.codex/worktrees/raze-check-foundation/raze_check/docs/testing/screenshots/guides "$FLUTTER_BIN" test --no-pub --concurrency=1 test/guide_visual_test.dart
  ```

  Use `view_image` on each exported image. Distinguish widget rendering from physical-device evidence; image generation is never a substitute for app screenshots. The existing logo/icons are sufficient. If a new raster illustration becomes necessary, use the image-generation skill/tool with the approved mascot reference, keep text in Flutter, and inspect the returned asset before inclusion.

- [ ] **Step 3: Run final affected checks once.** From root: `"$DART_BIN" format --output=none --set-exit-if-changed lib packages test`, `"$FLUTTER_BIN" analyze --no-pub`, and `"$FLUTTER_BIN" test --no-pub test --concurrency=2`. From feature: `"$FLUTTER_BIN" test --no-pub --concurrency=2`. From core/local run the new preference tests from Task 1. Existing business algorithms are unchanged; broaden local service testing only for an actual related change or failure.
- [ ] **Step 4: Build normal Android and iOS simulator apps.** Root commands: `"$FLUTTER_BIN" build apk --debug --no-pub` and `"$FLUTTER_BIN" build ios --simulator --debug --no-pub`. Record source revision, commands, exits and artifact hashes. Preserve the prior foundation artifacts. These builds must use `lib/main.dart`; no acceptance harness entry or test fixture data in normal builds.
- [ ] **Step 5: Record available device evidence.** Recheck connected devices; when the same authorized Android phone is available, install the normal update without uninstall/data clearing and capture the new welcome/guide view. Do not manufacture a reset by clearing app storage. Keep device chrome/raw captures in ignored evidence. Current iPhone999 installation remains blocked by Xcode's missing Israel Eusebio team account/profile; do not repeat signing attempts until the user reports that access is ready. An iOS simulator build or widget screenshot does not resolve that physical-device gap.
- [ ] **Step 6: Write the evidence summary and request the final branch review.** Report implemented guides, storage/permission/lifecycle test results, eight image links, Android/iOS build status, and outstanding physical-device checks. Use the preserved subagent workflow's final review; fix actionable findings and repeat only affected checks. Commit the evidence/README/plan status with `test: verify guided onboarding and capture screens`. Do not claim completion from screenshots alone.

## Plan self-review and handoff

Coverage: Task 1 owns bounded preferences and failure isolation; Task 2 all 46 positions, variants and progress transitions; Task 3 real anchors/artwork/accessibility; Task 4 first open/replay/embedding/session boundaries; Tasks 5–6 every feature guide and guarded navigation; Task 7 screenshot inspection, normal builds, and explicit device limits. All five Review Focus conditions have owning tests.

No tutorial implementation, new asset generation, dependency installation, or rebuild was performed while writing this plan. The user-authorized baseline Android screenshot is read-only evidence of the existing app. The next step after plan review is the previously selected subagent-driven implementation.
