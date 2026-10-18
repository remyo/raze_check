# Attendance and staff management app — product design

Date: 2026-10-18

Status: Product scope for review before implementation planning. No application code has been created.

## 1. Purpose and agreed direction

Build a Flutter application for a business to manage staff records, attendance, leave, overtime, and salary summaries. Staff should be able to record attendance when the manager is away. A separate workplace tablet is optional.

The agreed product model is free offline use with manual/local transfer, and paid cloud coordination. Both versions support local storage. Payment enables automatic synchronization and remote access; it does not remove offline capability.

The user has agreed to an offline attendance receipt workflow: a staff member scans a workplace QR, saves an attendance event, and generates a receipt QR. The manager imports the receipt image, scans it, or receives the same event through local sharing. Repeated delivery must not create repeated attendance.

The operating rules below are proposed defaults that make this direction coherent. They are part of this review, not claims that every detail has already been approved. Technology vendors, subscription prices, hardware purchases, and implementation schedules are not selected by this document.

## 2. People and devices

| Role/device | Responsibilities |
| --- | --- |
| Owner | Creates the company, appoints admins, controls permissions, manages company settings and subscription. |
| Admin/manager | Performs only assigned tasks: staff records, attendance review, leave/OT approval, or salary management. Salary and identity-document access are separate permissions. |
| Staff | Maintains permitted personal details, records attendance, submits requests, and views their own received records and decisions. |
| Management phone/tablet | Holds the management app and, in free mode, the main company database. It can also provide an attendance station when needed. |
| Staff phone | Holds the staff member's local profile, company membership, attendance receipts, requests, and received company information. |
| Optional workplace tablet | Displays workplace attendance QR codes or runs a supervised attendance station. A tablet is not required for phone-based attendance receipts. |

Proposed free-mode boundary: one management database is authoritative for membership, approvals, and salary records. Owner and permitted admins can use management mode on that device. Independent management databases making concurrent changes are not included in the initial free design. Replacing the management device uses backup/restore rather than creating a second authority.

Paid mode supports multiple authorized management devices through the company cloud service. Employee devices receive only the information and operations their membership permits.

## 3. Free and paid feature boundary

| Capability | Free offline | Paid online |
| --- | --- | --- |
| Company setup | Local company creation; no cloud account required | Online owner account and company workspace |
| Staff profiles and custom fields | Stored in the management database | Synchronized to authorized devices |
| Staff enrollment | Invitation, join request, manager approval, return of membership via QR/local transfer | Invitation and approval through the online service |
| Check-in and check-out | Saved on staff device; receipt QR/image or local Wi-Fi transfer | Automatic cloud submission, with offline receipt/pending support |
| Optional attendance tablet | Local display/station with explicit transfer of its records | Connected display/station using the same company service |
| Attendance review, shifts, grace periods | Included | Included, available remotely |
| Leave, balances, overtime | Included; requests and decisions transferred manually/locally | Included with automatic delivery and remote approvals |
| Salary calculations and reports | Included using records received and approved by management | Included using synchronized and approved records |
| Owner/admin collaboration | Permissions within one management database | Multiple authorized management devices |
| Backup and export | Manual backup, restore, and export | Manual tools plus automatic cloud backup |
| Dashboard freshness | Reflects records received by that device | Live updates while connected; last synchronization shown otherwise |

Free local Wi-Fi transfer requires devices to be reachable and the app's sharing session to be available. Sharing on the same Wi-Fi is not automatic authorization to read company data. A manager who is away receives nothing until a receipt is delivered by some route.

Sending an image through a messaging app may use internet and that service's terms. The app itself does not require our cloud service to generate, display, save, or import the receipt.

## 4. Company creation and enrollment

1. The owner creates a company and configures its name, workplace, time zone, and initial attendance settings. Free mode creates this locally.
2. The owner protects management access and creates a company invitation QR.
3. The staff member creates a basic local profile, scans the invitation, sees the company name, and confirms a join request. Scanning does not grant membership or admin access.
4. In free mode, the join request reaches management by request QR or local transfer. In paid mode, the service delivers it.
5. The manager approves the request, assigns a stable employee identity, and completes the initial staff record. Repeated requests from the same enrollment must not create duplicate staff.
6. Free mode returns an approved membership credential to the staff phone through QR/local transfer. Paid mode delivers the approval through the service. The phone can then issue attendance receipts associated with that membership.

Invitation QR, workplace attendance QR, attendance receipt QR, and approval/acknowledgment messages have distinct types. The app must reject a code used for the wrong purpose and explain what it is for.

Adding admins is an owner-controlled action; scanning a public invitation never appoints an admin. A replacement staff phone requires an authorized recovery/re-enrollment process. Historical records retain the original staff identity.

## 5. Daily attendance

### Staff flow

1. Open the joined company and select check-in or check-out.
2. Scan the workplace attendance QR. The app applies the configured checks and records which evidence was available. Personal-phone biometric authentication may authorize the action on supported devices.
3. Save one immutable attendance event locally before displaying success. The message is "Saved on this device" until delivery is acknowledged; saving locally is not manager approval.
4. Generate a receipt from the saved event. Redisplaying, saving, or sharing it preserves the same event ID.
5. Deliver through direct camera scan, image import, authenticated local sharing, or paid cloud synchronization. Check-out creates a separate event, with its own ID.
6. Receive management delivery and approval results when a return transfer or cloud connection is available. Sending a message alone does not prove that the manager received it.

Each receipt carries its message version, company ID, employee ID, event ID, check-in/out action, claimed event time with offset, originating device identity, and integrity information. Available workplace-check evidence can accompany it. Re-exporting uses the saved payload rather than creating a new punch.

A printed workplace QR permits attendance recording without an available display device. An optional tablet can display changing QR codes. Neither a static QR nor the name of a Wi-Fi network alone proves physical presence. A strict, verifiable workplace-presence mode needs a separate design before it can be promised.

Workplace Wi-Fi checking is a proposed attendance-policy feature, separate from using local Wi-Fi to transfer records. Its result, or the inability to perform a check, must be visible to management. The initial manual-review workflow records available evidence; platform feasibility and any stricter blocking policy must be established before implementation promises are made.

### Management flow

1. Scan a staff receipt, import an image, or receive a transfer.
2. Check the message format, company, staff membership, origin/integrity information, and event ID.
3. Store a valid new event once and acknowledge receipt. Invalid or conflicting input goes to a review/error state, not directly into attendance totals.
4. Review the recorded time, check-in/out sequence, relevant shift, and any exceptions. Approve, reject with a reason, or create an auditable correction.
5. Recalculate attendance summaries from approved records. Salary calculations consume approved attendance, leave, overtime, and adjustments.

Initial default: attendance submissions require manager approval before affecting salary. Managers can review and approve a batch. Automatic approval policies are a later, explicit product decision.

### Duplicate and conflict rules

| Incoming event | Result |
| --- | --- |
| New company/event ID with valid contents | Store once, awaiting review |
| Existing ID with identical immutable contents | Acknowledge "Already received"; preserve existing approval |
| Existing ID with different immutable contents | Flag conflict; do not overwrite |
| Different IDs suggesting the same punch | Flag a possible repeated punch for review |
| Duplicate delivery through QR, local sharing, and cloud | Apply the same rules regardless of transfer route |

Transport status and approval status are separate: saved locally / receipt acknowledged describes delivery; pending / approved / rejected describes management's decision. Later decisions and corrections have their own identities and reference the original event. They do not alter the original receipt.

### Offline evidence and recovery

An offline timestamp is claimed device time. Store the recorded time and offset separately from management/cloud receipt time. Receipt arrival must not replace the original claimed arrival time. Possible clock anomalies and out-of-order punches require review.

Proposed integrity mechanism: enroll a device key with the staff membership and sign receipt contents. A valid signature can establish origin and detect alteration; it cannot establish a correct clock or physical workplace presence. Membership approval, key replacement, and revocation are part of the enrollment/recovery design. Offline devices can retain stale permissions until they exchange updates, so imports must be checked against the management authority's membership and revocation history. A late-delivered receipt claimed to predate deactivation requires review; it must not silently authorize new activity or erase previously approved history.

If a camera fails, an available workplace station or manager-recorded attendance is the fallback. A future alternative using phone biometrics still needs the configured workplace checks. If the manager is away, staff retain their local receipts and deliver them later.

## 6. Staff management features

### Staff profiles

- Default fields: name, employee number, contact details, birthday, department, position, joining date, employment status, and applicable pay settings. Age is calculated from birthday.
- Manager-managed identity-document attachments and additional profile details.
- Custom field definitions: text, number, date, selection, and attachment, with required/optional and view/edit permissions.
- Staff edit permitted personal details; verified details, permissions, and pay settings require authorized management.
- Staff deactivation stops new authorized activity while preserving historical attendance and salary records.

The attendance QR contains only the compact attendance message. It does not contain identity-document images or salary information. Larger files and bulk records use authenticated local transfer/export or paid cloud file storage, not a single QR.

### Attendance and schedules

- Check-in/check-out history, working days, shifts, rest days, breaks, late arrival, early departure, and missing punches.
- Shifts that cross midnight and company/workplace time-zone handling.
- Grace-period settings, kept separate from payable-time or deduction rules. Being labeled late does not automatically authorize a salary deduction.
- Manager-entered attendance and staff correction requests with reason, original record, author, and decision history.
- Daily and monthly summaries, including "not yet received" or incomplete information. Missing receipt delivery must not silently become confirmed absence.

### Leave

- Staff requests, manager approval/rejection, leave categories, paid/unpaid designation, balances, and usage history.
- Initial balances and manual adjustments by authorized management; automatic accrual policies can be added after their rules are specified.
- Free-mode requests and decision/balance updates use the same QR/local exchange approach for compact messages. Staff see the balance as of the last received update.
- A request alone does not change the approved leave balance.

### Overtime

- Staff requests or manager-entered OT linked to a work date/shift.
- Manager approves eligible duration before it affects salary.
- Extra time between punches is visible for review and is not automatically approved overtime.

### Salary summaries

- Configurable hourly or monthly base pay, approved OT, allowances, and explicit approved adjustments.
- Hourly totals use approved payable hours. Monthly base pay does not automatically change because of a late mark or missing receipt; any proration/deduction rule must be configured and approved.
- Effective-dated pay settings preserve historical calculations.
- Explainable pay-period breakdowns, review, finalization, and export. Finalized periods retain their calculation snapshot; later changes require a recorded adjustment or explicit reopening.
- Initial scope is salary calculation and recordkeeping. Statutory tax calculations, legal compliance automation, bank payments, and government filings are separate future scope. No jurisdiction-specific rates or deduction formulas are assumed.

### Reports and notifications

- Staff list, attendance/late/missing-punch reports, leave balances, OT totals, and salary summaries.
- CSV export and manual backup/restore in free mode.
- In-app reminders and pending-action indicators; paid connected notifications can deliver updates remotely. Freshness and last-received/synchronized time remain visible.
- Staff views are limited to their own relevant records. Owner/admin views respect assigned permissions.

## 7. Paid operation, upgrades, and backups

Paid mode adds authenticated cloud services and private attachment storage. It accepts the same attendance events as QR/local transfer and applies the same identity, duplicate, and approval rules. Online delivery does not grant a new permission or make an invalid receipt valid.

While disconnected, already-enrolled users work from locally available data and queue allowed actions. First-time cloud enrollment and actions requiring current server authorization may require connection. Reconnecting can produce a rejection or conflict if membership or permissions changed; local pending state is not a promise of acceptance.

The cloud becomes the shared authority for a paid company's management state. Conflicting approval or profile changes require version checks and review; they must not silently replace finalized salary data.

An upgrade uploads the existing company, stable identities, receipts, decisions, and permitted files without re-creating staff or duplicating attendance. The migration must be verified before cloud coordination is enabled. Exact provider, billing, and migration implementation are deferred to their own plan.

Manual backups must include the company data, attachments, and the recovery material needed to restore its authority, with protection for sensitive information. Show backup time and provide a tested restore route. Cloud synchronization and cloud backup are distinct: paid backup needs a defined recoverable history and retention policy before launch.

Proposed subscription-expiry behavior: keep downloaded records readable/exportable and allow local capture; automatic cloud coordination follows the subscription policy. Returning to a free company requires choosing/restoring one main management database and resolving outstanding records. Do not silently turn several former cloud clients into independent management authorities. Pricing, retention duration, and downgrade timing are commercial decisions for the paid release.

## 8. Biometrics and optional equipment

Personal-phone fingerprint or supported face authentication can unlock or authorize use of the employee's existing account. It establishes device authentication, not an independent employee identity or workplace-presence proof.

A shared tablet's ordinary built-in biometric APIs do not tell the application which employee matched. Shared fingerprint attendance needs compatible identification hardware/software and enrollment; shared face recognition needs a separate recognition and anti-spoofing design. Neither is included as a promised first-release capability.

For initial attendance-station use, offer manager-assisted recording or an explicitly designed employee credential/PIN flow. Treat any future shared biometrics as an additional method feeding the same attendance-event system, not a separate attendance database.

## 9. Architecture boundaries and phased delivery

One Flutter product can expose staff, management, and optional station modes. Keep these responsibilities separate:

- Membership and permissions: company identities, enrollment, authorized devices, and roles.
- Staff records: default/custom fields, attachments, and visibility.
- Attendance: immutable punches, schedules, grace rules, and approved corrections.
- Transport: QR encode/decode, image import, local exchange, and optional cloud synchronization.
- Requests: leave, overtime, and correction decisions.
- Salary: versioned pay settings and calculation snapshots from approved inputs.
- Recovery: export, backup, restore, and device replacement.

All incoming transfer routes use the same validation and duplicate-handling logic. Transport adapters do not independently edit approved attendance or salary.

This is a product-level design, not one large implementation task. Proposed delivery order:

1. Free attendance foundation: company setup, staff enrollment, permissions, local storage, separate QR types, attendance receipt capture/import, approval, duplicate handling, manual correction, basic export, and backup/restore.
2. Complete free workplace workflows: authenticated local sharing, schedules/grace rules, custom fields/attachments, leave, OT, and salary summaries. Each module gets its detailed rules and acceptance criteria before its implementation plan.
3. Paid collaboration: cloud accounts and sync, multiple management devices, remote approvals, attachment sync, recovery backups, company migration, and subscription behavior.
4. Optional extensions: shared biometric hardware/recognition, advanced multi-branch management, and jurisdiction-specific payroll integrations after separate design review.

Local Wi-Fi sharing remains in the intended free feature set even if QR transfer ships first. The optional equipment and advanced features are not prerequisites for the core product.

## 10. Acceptance scenarios

Before any release claims, verify the relevant scenarios on the selected target platforms:

1. Create a free company and complete staff enrollment without a cloud account, including the manager approval returned to the staff phone.
2. Capture and retain a staff punch while the manager is away; preserve it across app restart.
3. Import the same receipt image twice and later receive it through local/cloud transfer; maintain one attendance event and its original approval state.
4. Reject tampered/wrong-company/unapproved-membership messages and flag conflicting contents for the same event ID.
5. Flag different-ID repeated punches, missing check-outs, out-of-order events, and clock anomalies without silently inventing approved working time.
6. Transfer a leave/OT request and return a decision; distinguish delivery from approval and show last-known balances.
7. Restrict staff, attendance admins, and salary admins to their permitted records and operations.
8. Preserve history through corrections, staff deactivation, pay-rate changes, and finalized salary-period adjustments.
9. Restore a manual backup, including required attachments and membership continuity, without duplicating staff or receipts.
10. Upgrade a company to paid mode without duplicate records; reconcile offline submissions, denied permissions, and conflicting edits on reconnection.
11. Verify receipt QR size/readability on real devices. Use file/local transfer for payloads exceeding the tested compact-message limit.

## 11. References checked during brainstorming

- [Flutter offline-first architecture](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- [Google barcode scanning: on-device operation](https://developers.google.com/ml-kit/vision/barcode-scanning)
- [Flutter local authentication capabilities](https://pub.dev/packages/local_auth)
- [Android biometric authentication result](https://developer.android.com/reference/kotlin/android/hardware/biometrics/BiometricPrompt.AuthenticationResult)
- [Apple Face ID behavior and API privacy boundary](https://support.apple.com/en-us/102381)

Next artifact: a detailed implementation plan for the first delivery phase after this product design is reviewed. Launch platforms and implementation technology choices belong in that planning discussion; this document does not implicitly select a backend vendor, database package, or biometric device.
