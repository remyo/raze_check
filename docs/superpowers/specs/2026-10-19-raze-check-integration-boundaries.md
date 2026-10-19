# Raze Check standalone and future Raze Store integration

Date: 2026-10-19

Status: Design for review. No Flutter packages, native bridge, replication engine, or Raze Store integration have been implemented.

Parent: [Attendance and staff management product design](2026-10-18-attendance-management-design.md).

## 1. User direction and scope

Build standalone Raze Check first. Staff use it without Raze Store. Owners can also use its management screens. Later, authorized managers can open the same attendance features as a miniapp inside Raze Store, which is already a Flutter application.

Keep the Raze Store feature on hold: no host navigation entry, dependency installation, production bridge, or attendance-data change in that repository during this phase. Prepare the reusable boundaries in Raze Check's standalone implementation. This document is the integration contract's design basis, not a completed API or compatibility certification.

The future local integration is free. Paid service adds cloud coordination across devices. Two local copies on one phone do not protect against loss of that phone and are not a substitute for external backups.

## 2. Boundaries to establish in the standalone build

| Boundary | Responsibility |
| --- | --- |
| Domain and application services | Company membership, permissions, attendance rules, requests, salary calculations, commands, and audit history. No dependency on Raze Store application code. |
| Reusable Flutter feature | Staff and management screens entered with a selected company and authenticated session. Host navigation and presentation preferences are supplied through a small interface. |
| Standalone host | App startup, onboarding, routing, platform lifecycle, and the initial local service implementations. It remains independently usable. |
| Persistence and transport adapters | Local durable storage, QR exchange, encrypted archives, and later local/cloud transports. All imports and mutations use common validation and duplicate handling. |
| Recovery service | Validated exports, restore staging, identity preservation, replacement device authorization, and authority handover. |

The implementation plan should select a modest package layout that lets Raze Store depend on the reusable feature without importing the standalone application's root widget, global router, or global database instance. Avoid a generic miniapp marketplace or dynamically downloaded code system. Host embedding initially ships through normal app releases.

Company selection and host-supplied identity are inputs, not permission grants. Raze Check verifies the actor's company membership and operation rights. A store name, shared email, or installed companion app is not sufficient authorization. Staff-only sessions must not receive management replicas or employer-wide backups.

Raze Store currently has Tools navigation, Riverpod, Drift, and local transfer code. Those are integration candidates, not a requirement to share its retail tables or catalog-transfer payload. Its theme, icon, and interaction conventions can be supplied by the host without coupling attendance rules to the store application.

## 3. Versioned connection contract

Prepare service interfaces and serialization boundaries in the standalone implementation for these capabilities. The native implementation and final wire schema belong to the held integration track.

- **Compatibility and authorized linking:** identify the application/installation, supported protocol and archive versions, and permitted capabilities; authenticate both applications and the selected company session before disclosing protected company data.
- **Queries and commands:** return company-scoped records with versions. Mutations include an operation ID, authenticated actor, company ID, expected record version, and current authority generation. Retry of the same operation is idempotent; conflicting contents for that ID are rejected.
- **Committed changes:** retain stable entity IDs, immutable attendance events, versioned decisions/corrections, and deletion/deactivation markers where applicable. Use an ordered revision/checkpoint for replication; wall-clock timestamps alone must not select a winning edit.
- **Recovery snapshots:** export a consistent logical snapshot plus attachment manifest, integrity checks, compatible format version, and authorized recovery information. Do not copy an open database file without a consistent snapshot mechanism.
- **Replication acknowledgments:** acknowledge only durably applied and verified changes. Track the checkpoint, attachment completeness, and ability to decrypt/recover independently. Sending bytes is not acknowledgment.
- **Explicit outcomes:** distinguish committed, pending authority, duplicate, version conflict, unauthorized, incompatible version, unavailable peer, and incomplete recovery copy. Local UI must not turn a timeout into a successful operation.

Attendance receipt delivery and replica replication are separate operations: receiving a receipt does not approve attendance, and receiving an approval replica does not appoint another independent management authority. Transport-level authentication also does not bypass company-level permissions.

No raw database paths or unrestricted database handles cross the host boundary. Native adapters must validate the caller and enforce the versioned contract. A signed related app still needs an authorized company session.

## 4. Future durable copies in both apps

After explicit company linking, each app stores a persistent encrypted recovery copy of the authorized company scope. Cache directories are excluded: they may be cleared independently and the removed application's private files do not survive its uninstall.

For the proposed free local design, one authority per company commits management decisions. Either UI can submit commands to it while it is reachable. The other app applies verified committed changes to its local copy. A missing authority does not silently turn the peer into an independent writer: management actions remain uncommitted/pending or unavailable until an authorized handover or recovery. Staff attendance capture can still create local pending receipts under the existing attendance rules.

Paid companies retain the cloud authority defined by the product design. Restoring a local replica does not override current server membership or finalized decisions; pending offline work still needs reconciliation.

Local synchronization should run after changes when the peer is reachable, on app opening/resuming, and on an explicit retry. Do not promise uninterrupted background execution. The platform adapter must handle missing, force-stopped, locked, incompatible, or storage-full applications and interrupted transfers. The exact Android and iOS mechanisms need device tests; a shared container alone is not evidence of two independent recovery copies.

| Visible state | Meaning |
| --- | --- |
| Saved in this app | Durable local save; its business status may still be pending. |
| Waiting for company confirmation | A proposed management command has not been committed by the current authority. |
| Copy pending in Raze Store / Raze Check | Latest committed changes or required attachments have not been acknowledged there. |
| Copy verified in both apps through [checkpoint time] | Both have a consistent, readable recovery checkpoint with required files and recovery access. Later pending changes are shown separately. |

Uninstall survival applies through the surviving app's last verified checkpoint. If the deleted app held newer unmirrored changes, those changes cannot be reconstructed from the older copy. If complete protection of a new change is required, the UI cannot claim that protection until the peer acknowledges it. Availability of the first local save and redundancy of the save are separate facts.

Recovery data must be usable after removal of either installation. Do not encrypt the only peer copy with a key accessible only to the app being removed, and do not assume hardware-backed device keys can be copied. Provision each authorized recovery participant with usable recovery access and a replacement-credential path. Include attachments and finalized calculation snapshots; a list of employees alone is not a company backup.

Mirroring current state also propagates legitimate changes and deletions. Historical rollback requires separate versioned backups and a defined retention policy. Unlinking, clearing app data, and deleting company data are distinct actions with distinct effects; deleting a company must not silently become recoverable through an unreviewed old replica or resurrect it on reconnection.

## 5. Uninstall, reinstall, and recovery experience

The source for a restore is a surviving authorized copy, a user-selected encrypted external backup, or paid cloud recovery. No flow assumes a final sync can run while the operating system uninstalls an app.

1. On first launch or through Restore, locate an available companion using supported platform mechanisms, or let the user select a backup. App discovery alone reveals no protected employee data.
2. Authenticate the company owner or an explicitly authorized recovery administrator using the surviving peer or recovery material. A matching company ID is not authorization.
3. Offer: "Restore existing company data?" Show the source, company, checkpoint time, record counts, attachment completeness, and known missing changes. Ask for explicit restoration; do not silently overwrite existing newer data.
4. Import into staging and validate before activation. Preserve company, employee, event, decision, and operation IDs. Register replacement installation credentials through the authorized recovery process.
5. If the active management authority still exists, reconnect as a peer. If replacing an unavailable authority, use explicit recovery to establish a new authority generation and record that decision. A temporary timeout alone must not trigger automatic promotion.
6. On return of an old installation or backup, compare authority history, detect competing generations, and stop automatic management writes until reconciled. Old unmirrored events may be imported for review; old approvals or salary snapshots must not overwrite current records. Offline revocation cannot be instantaneous.

If Raze Store is removed, Raze Check can retain its verified copy; if Raze Check is removed, Raze Store can retain its verified copy. Continued management from a surviving non-authoritative replica requires the authorized recovery step. A reinstalled app receives a new installation identity even while preserving the person's and company's identities.

If both apps are removed, app-private copies are not a recovery plan. Offer recovery only from a usable external archive or synchronized cloud copy. Exported backups must be user-selected, encrypted documents outside the app's private/cache directory, with usable recovery material. Do not silently scan public storage or promise operating-system backup behavior.

## 6. Delivery and acceptance

### Standalone foundation

Build and verify the reusable service/screen boundaries, stable IDs, versioned operations and archives, permissions, idempotent imports, encrypted backup/restore, and independent app operation. Tests should exercise these actual boundaries and failure behavior rather than scaffolding future native bridges. The Raze Store bridge remains documented future work, without an implementation; no launch claim says records survive uninstall through a companion copy.

### Held Raze Store integration

Resume only when requested, with its own implementation plan. Before release verify:

1. Both entry points use the same business rules and authorized company scope; a staff session cannot obtain a management replica.
2. Either app can submit a management change, retry it without duplication, and observe the same committed result in both copies. Stale concurrent edits require conflict handling.
3. Uninstall either app after a verified checkpoint and recover readable records, required attachments, finalized summaries, and authorized management access from the other.
4. Interrupt replication or fill peer storage before completion. Preserve the last complete checkpoint and show incomplete protection; do not claim missing records or files were saved in both.
5. Reinstall the removed app and restore with explicit authorization while preserving entity IDs. Test missing passwords, inaccessible keys, and unauthorized discovery.
6. Recover authority from the peer, then return an old backup or formerly unavailable installation. Detect and reconcile stale/competing authority without silent overwrites.
7. Upgrade one app before the other, reject incompatible protocol/schema operations safely, and preserve readable recovery data during interrupted migrations.
8. Distinguish uninstall, temporary peer unavailability, unlinking, clearing data, and deliberate company deletion. No automatic failover or resurrection on reconnect.
9. Remove both apps and accurately offer external/cloud recovery only when a usable source exists.

## 7. Platform evidence

- [Flutter reusable packages](https://docs.flutter.dev/packages-and-plugins/developing-packages)
- [Android app-specific persistent storage, cache eviction, and uninstall removal](https://developer.android.com/training/data-storage/app-specific)
- [Android protected inter-app data access](https://developer.android.com/guide/topics/providers/content-provider-basics)
- [Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple group-container lifecycle](https://developer.apple.com/documentation/Foundation/FileManager/containerURL(forSecurityApplicationGroupIdentifier:))

These sources establish platform capabilities and limitations. The proposed replication and recovery protocol still requires implementation and real-device verification.
