# Raze Check guided onboarding and feature guides

Date: 2026-10-20

Status: Guided approach approved in chat; this written design awaits user review before implementation planning.

Starting point: `dev` at `9650a111f55d8fd53b09387ff2e4a98de27481bc`.

Related: [product design](2026-10-18-attendance-management-design.md), [embedding boundaries](2026-10-19-raze-check-integration-boundaries.md), and [implemented foundation](../../testing/foundation-acceptance.md).

## Purpose and agreed scope

Users should understand what to do next without having to discover every function themselves. The user approved a five-step first-open introduction, short guides that highlight relevant controls, Back/Next/Skip, saved progress, and replay through **Settings → Help & Guides**. Guides must respect the current user's permissions and never submit attendance, approve records, or restore data automatically.

Deliver ten guides with 46 authored step positions. Users see five welcome steps initially; they are not required to read all 46. Feature guides are offered where useful and remain available on demand. Audience and recovery-path variants replace the explanation within a step position rather than creating a longer compulsory tour.

This adds guidance to the existing offline foundation. It does not implement payroll, leave, overtime, grace rules, Wi-Fi transfer, cloud service, biometric identification, or Raze Store integration. Instructions must not advertise those as working features.

## Experience

### First open

The standalone app automatically presents the welcome guide before the profile chooser on its first launch with this feature. An existing installation without guide preferences receives the same introduction once.

Each page has a short heading, a familiar icon or existing Raze Check branding, one concrete explanation, a visible “Step 2 of 5” counter, and Back/Next/Skip controls. The final button is **Get started** and opens the existing profile chooser. It does not create a profile or assign a role.

Closing the app midway preserves the last step and resumes the introduction next launch. Skip dismisses the automatic introduction until the user explicitly replays it. Completing it also prevents automatic replay. A copy edit or application update does not force users through it again.

The five welcome topics are:

1. What Raze Check does: offline attendance for staff and management.
2. Your local profile and companies: one person can be staff in one company and owner in another.
3. Record attendance: save a separate check-in or check-out receipt on this device.
4. Exchange and review: saved, received, approved, and rejected mean different things.
5. Protect your records and get help: keep a verified external encrypted backup; reopen guides in Settings.

### Feature guides

The first eligible visit to a supported feature shows a small, dismissible **Show me how** invitation if that guide has not already been started, viewed, or dismissed. It does not open a blocking tour while the user is trying to record attendance. Starting a guide opens its saved position, with **Restart** available. Dismissing the invitation suppresses repeat automatic invitations for that guide on this installation. **Skip** closes an active feature guide while retaining its position for Continue; it does not mark the guide Viewed.

Guided steps highlight a real registered control when it is present on the current screen. A compact explanation panel is placed without covering the target. **Next** advances the explanation only; it never presses the highlighted control.

An explicit **Show me** action may open an existing app screen through its normal navigation callback and permission checks. Ordinary transient form initialization is allowed. It must not fill user inputs, persist a business draft or command, invoke a scanner or system picker, share files, confirm external backup custody, or execute a business operation. The user performs those actions using the normal controls.

If the next screen is not open or a prerequisite is missing, the step remains readable and explains how to reach it. It does not highlight a guessed position, navigate indefinitely, or require the other phone to respond before the guide can be read. For example, staff can learn that they must receive an approved membership even while waiting for their manager.

Finishing marks a guide **Viewed**, not “Company setup complete,” “Attendance saved,” or another business result. Tutorials do not infer success from Next, a share sheet, or a displayed QR.

### Settings and the guide library

Add a Settings entry to the profile chooser and unlocked app shell. Make it reachable from the manager's More area and the staff member's Profile area, including when no company is selected through the app-level Settings action.

**Settings → Help & Guides** contains:

- The welcome guide, with **Replay introduction**.
- Available feature guides with short descriptions and Not started / In progress / Viewed labels.
- **Continue** and **Restart** for a guide with saved progress.

Before unlock, only the welcome introduction and general safety explanations are available. After unlock, guide availability and actionable steps use the same current context and capability checks as their corresponding screens. A staff member does not receive actionable manager controls through the guide library. An unrestricted personal profile may still learn how to create its own company; a restricted company operator cannot use that route.

Settings initially contains the requested Help & Guides function. Do not add nonfunctional settings, analytics controls, or future-feature placeholders.

## Guide catalog: 46 step positions

The following is the content outline. Button labels in the implemented guide must match the actual screen, including the correct staff/manager variant.

| ID | Guide | Steps | Intended context |
| --- | --- | ---: | --- |
| `welcome` | Welcome to Raze Check | 5 | Everyone; automatically shown in standalone first-open flow |
| `companies` | Set up and switch companies | 4 | Unrestricted personal profile; switching only among accessible companies |
| `membership` | Invite staff or join a company | 6 | Separate invitation-management and staff-join explanations |
| `capture` | Check in and check out | 4 | Eligible personal attendance context |
| `exchange` | Send receipts and receive updates | 5 | Staff receipt/outbox and return-update context |
| `review` | Review attendance and corrections | 5 | Permission-limited management or personal correction variant |
| `team` | Manage staff and operator access | 4 | Only the staff/membership/operator actions the current actor can perform |
| `reports` | Read and export attendance reports | 3 | Personal report or authorized company report/export |
| `backup` | Back up and restore records | 5 | Authorized personal/company scope |
| `new-device` | Move to a new device | 5 | Staff replacement or owner handover/recovery path |
| | **Total** | **46** | |

### Companies — 4 steps

1. Choose **Create company** to manage a new company, or **Join company** when invited by another company. This guide starts after profile unlock; the welcome explains local profile creation.
2. Enter **Company name**, using a name the team will recognize.
3. Use **Select IANA time zone**, then **Create company** when the details are ready.
4. Use **Switch company** and confirm the current company and available actions. Explain **Keep editing / Discard draft** when switching with an open draft; permissions belong to each company membership.

### Invitations and joining — 6 steps

1. Management opens its invitation workflow; staff opens its joining workflow.
2. An authorized manager creates and sends the invitation.
3. Staff reads the invitation and checks the company security fingerprint with the manager.
4. Staff confirms and sends a join request; creating a request does not yet grant membership.
5. Management reads the join request and explicitly approves and returns membership.
6. Staff receives membership and verifies the company is available.

The inactive phone's steps are explanatory. The guide never simulates that phone's approval or marks a request as delivered.

### Check-in/check-out — 4 steps

1. Select the correct company and open **Record attendance**. The owner counterpart explains **Workplace QR → Display workplace code**.
2. Choose **Check in** or **Check out**. Explain before scanning that reading a valid workplace code saves that punch immediately.
3. Read the code through **Scan QR**, **QR image from Files**, or **Message from Files**. The guide never starts those actions itself.
4. Look for the actual **Saved on this device** result and **Share receipt**. An error is not a completed punch; **Retry saved punch** is explained only when a real pending draft exists. Check-out is another event, and local saving is separate from management approval.

### Receipts and updates — 5 steps

1. Open **Receipt outbox** and select the saved punch to send.
2. Use **Share receipt**, then **Share QR image** or **Share message file**. Use an intact message file if the app says QR is too large; opening sharing does not confirm delivery.
3. Explain management's **Import receipt or correction → View attendance** workflow.
4. Explain management's **Show receipt acknowledgment**, **Show decision <revision>**, and **Share selected return** controls. These targets exist only after actual receipt import or review.
5. On the staff phone, use **Receive attendance update** and read delivery status separately from approval status. Receipt acknowledgment is not approval.

### Review and corrections — 5 steps

1. Open **View attendance** and inspect the original and effective punch details.
2. Read the source, current status, and review hints. Hints do not establish working time or misconduct, and offline records may still be missing.
3. Management enters **Review reason** and explicitly chooses **Approve attendance / Reject attendance**. Staff receives an explanation of the decision and return update.
4. Management uses **Correct attendance → Save manager correction**; staff uses **Request correction → Save signed request**, with the corrected time, offset, and reason.
5. Explain **Share correction request / Share selected return** and **Decision and correction history**. The manager variant includes **Resolution reason / Approve correction / Reject correction** for an incoming request. A correction does not automatically change approval, and original signed receipt bytes remain unchanged.

Use audience-specific text and targets. A manual attendance entry must retain its manager identity, reason, and explicit manual source; it is never described as a staff-scanned receipt.

### Staff and operator permissions — 4 steps

1. Open **Team**, then select a record or **Add staff**.
2. Edit **Name** and permitted optional details, then **Save staff**. Creating a staff record does not enroll a phone.
3. The owner can use **Manage operator access → Save capabilities** for an eligible active non-owner member. Explain the existing capability labels in plain language while matching their actual controls. Other audiences receive explanatory text only.
4. Explain **Activate operator credential**, its passphrase and confirmation of at least 12 characters, and **Unlock company operator**. This credential is local and company-scoped; role labels or guide choices never grant authority. Explain deactivation effects only where that action is available.

### Reports — 3 steps

1. Open **Attendance report** and, where **Report scope** is available, choose **My attendance / Company attendance**. An owner's initial report scope is personal; a restricted operator has only its authorized company scope.
2. Enter **Start date (YYYY-MM-DD)** and **End date (YYYY-MM-DD)**, then **Generate report**. Both dates are included using the company time zone and effective punch date.
3. Use **Share CSV** where permitted. The preview shows the first 25 rows; the export includes all selected rows. Regenerate to include later changes. This foundation reports attendance records and decisions, not calculated salary or payable hours.

### Backup and restore — 5 steps

1. Open **Backup / recovery → Encrypted backup and passive restore** and select **My personal records** or an available company scope. Company backup requires the owner; this general backup screen is unavailable to restricted company operators.
2. Enter and confirm a backup passphrase of at least 12 characters, then use **Create encrypted backup**. Keep the passphrase separately.
3. Use **Save or share encrypted backup** to retain a copy outside the app; the app's own copy cannot be relied on after uninstall.
4. Independently verify the external copy before choosing **I verified a saved copy outside this app**. The guide never performs this attestation.
5. Use **Choose backup to inspect**, enter its passphrase, and review records and conflicts before choosing **Restore verified records**. Explain **New installation / Merge nonconflicting records** only in their actual context. Passive restored data is not automatically an active membership or management authority.

### New device — 5 steps

This is a five-stage orientation with staff, source-owner, replacement-owner, and lost-source variants. Each stage can explain multiple controls; it is not a claim that every recovery path takes only five clicks.

1. Choose **Recover staff identity on this device**, **Activate or recover owner on this device**, or **Move this owner device** on the source. Owner handover moves the same owner to another device; it does not transfer company ownership.
2. Verify the original public identity IDs and full company root fingerprint. Explain **Create fresh replacement request** for staff or **Prepare fresh owner installation** for an owner. Secure required recovery material before replacing or deleting anything.
3. Staff sends **Share replacement request** to authorized management. For owner handover, **Share target request with source device**, then the source reads it and explicitly chooses **Freeze source and prepare handover**. Explain the freeze before this action; an issued handover is not automatically canceled by a missing acknowledgment. Lost-source recovery instead requires a usable company backup.
4. Staff must **Apply received-record archive** before **Receive replacement grant**. Owners inspect the matching company recovery/handover archive and checkpoint; the source shares the exact archive and signed offer. Records never received by management or absent from the available archive cannot be reconstructed.
5. Staff receives its replacement grant. The owner target verifies and activates the signed handover and shares the activation acknowledgment; the source uses **Receive target acknowledgment**. The lost-source variant explains **Recover when source device is lost**. Follow the actual lock/unlock instructions and verify retained history. Deleted-app cache or an unimplemented companion app is not a recovery source.

Recovery instructions follow the actual Files-based message controls rather than promising a generic QR transport. Staff recovery export requires both membership-management and attendance-export authority; owner recovery remains owner-only. Counterpart actions are informational when the current actor cannot perform them.

## Architecture and boundaries

Keep presentation and the guide catalog inside `raze_check_feature`. A small guide controller owns the active guide, current step, audience variant, and transient navigation context. A reusable step panel and anchor wrapper avoid one separate overlay implementation per feature.

Use stable semantic guide/step/anchor IDs. Register anchors from the actual widgets, scoped to the active feature navigator, route, and screen/panel generation. Company workflows often switch stateful panels within one route, so route identity alone is insufficient. Reuse existing guarded navigation callbacks rather than inventing deep links to those panels. Do not locate controls by translated text, screen coordinates, or global widget-tree searches. Unmounting a target unregisters it. Recalculate positions after layout, scrolling, rotation, or text scaling.

Introduce a small Dart-only `GuideProgressStore` contract and progress value types in `raze_check_core`. It stores tutorial preferences only; it provides no role, company, database, attendance, or authentication access.

Implement the standalone adapter in `raze_check_local`, using a versioned private JSON preference file under `AppPaths.root`. It contains only guide IDs, content revisions, audience-variant IDs, step IDs, and presentation/progress flags. No person/company identifiers, passphrases, receipt contents, or permission grants are stored in it. Limit the file to 64 KiB and a bounded catalog-sized set of entries. Serialize writes and replace the file through a same-directory temporary file so an interrupted write does not publish a partial document.

The standalone composition supplies one adapter instance. `CheckFeatureHost` receives optional guide-presentation configuration and this progress contract. Automatic welcome is explicitly enabled by the standalone host and defaults off for an embedded host. Without a supplied persistent adapter, manual guides remain usable with session-only progress; the feature does not discover a host database or storage path.

No new native plugin, cloud service, analytics, downloaded tutorial content, business schema migration, signed-message change, or archive-format change is required. Guide preferences are excluded from attendance recovery archives. A fresh installation starts with fresh guide progress, even after attendance restoration. Raze Store remains untouched.

## Progress and lifecycle rules

Progress belongs to this app installation, not an employment record. The guide library states this where progress is shown. Sharing the device can therefore share tutorial progress; it never shares business access.

Store stable step IDs with the content revision. On compatible edits, resume the same step. If a saved step no longer exists, restart that guide with a short explanation. Unknown entries are ignored within the file bounds. Revising copy does not reset the first-open dismissal or silently reopen previously dismissed feature invitations.

The controller binds actionable highlights to the original session, selected company, route/panel generation, and audience context. Lock, session replacement, company switching, permission loss, route disposal, or exit from the feature dismisses the actionable overlay. Save only the explanatory step position; reopening resolves current permissions and prerequisites again. An intentional **Show me** navigation may retain that explanatory position, but attaches new highlights only after the destination registers fresh targets and the original session/company context is revalidated.

Backgrounding hides the guide with the existing protected feature view. Camera, picker, and share transitions pause the guide and retain the app's existing guarded completion behavior. Resume only after the ordinary screen has returned and the original context is still valid. Tutorial timers, animations, persistence, and automatic navigation must not reset the five-minute idle timeout or bypass the existing lock flow. Genuine user interaction follows the app's existing activity policy.

## Failures, layout, and accessibility

A guide-preference read/write failure must not prevent profile unlock or attendance use. Keep in-memory progress for the session and show a nonblocking message that guide progress could not be saved. Malformed, oversized, or unsupported-version preferences remain untouched, with persistent writes disabled for that session; subsequent launches may retry reading. Do not reset the attendance database, keys, catalog, or existing business records.

Missing or offscreen anchors produce a readable instruction panel with Continue/Close or an available guarded navigation action. They must not leave a dimmed screen with no working exit. Pause or close must preserve any underlying form draft according to that form's existing navigation behavior.

Match the approved Raze Check typography, colors, branding, and light/dark themes. Use concise plain English and the existing UI labels. Support narrow phones, tablets, landscape, large text, screen readers, and reduced-motion preferences. All steps must be scrollable when needed. Provide semantic headings, step counts, labeled controls, sensible focus order, and a non-gesture way to leave a guide. Prefer a bottom sheet or full-page explanation when a floating bubble cannot fit safely.

## Acceptance checks for the implementation plan

1. First-open introduction appears with five steps, resumes after interruption, and stays dismissed after Skip or Get started.
2. Settings opens the guide library before and after unlock with the permitted content; replay and restart work without resetting business data.
3. All ten guides use the 46 defined step positions and actual feature labels/anchors. Audience/path variants never surface an unauthorized executable action.
4. Missing prerequisites and absent anchors remain readable and dismissible. Company switch, lock/expiry, permission change, and stale asynchronous navigation cannot attach a guide action to another company.
5. Next, Skip, replay, and completion create no attendance, approval, correction, enrollment, external-copy confirmation, or restore mutation.
6. Preferences persist offline across restart; malformed, oversized, interrupted, and unavailable preference storage cannot block the app. Only tutorial preference data is written.
7. Representative welcome, capture, management, and backup guides fit phone/tablet, light/dark, large-text and screen-reader layouts. Validate real anchor positioning after scroll and rotation.
8. Embedded-host tests retain navigation/theme isolation, optional guide persistence, and automatic-welcome-off behavior. No Raze Store dependency is added.
9. Run focused guide/controller/preferences/widget and affected host tests plus analysis and relevant normal builds. Existing cryptographic, 10,000-event capacity, destructive lifecycle, and unchanged recovery matrices do not need repetition merely for explanatory UI.
10. Record automated versus hands-on device evidence honestly. The unresolved Israel-team Xcode account/profile issue remains a separate iPhone installation prerequisite.

## Next approval boundary

The user has approved the guided approach. Review and approval of this written design permits preparation of the implementation plan. Product code and new tutorial dependencies have not been added at this stage.
