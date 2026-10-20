import '../guide_models.dart';

final recoveryGuides = <GuideDefinition>[
  GuideDefinition(
    id: "backup",
    variantId: "personal",
    revision: 1,
    title: "Back up and restore records",
    description:
        "Keep a verified encrypted backup and inspect records before restoring.",
    steps: [
      GuideStep(
        id: "backup-scope",
        title: "Encrypted backup and passive restore",
        body:
            "Open Backup / recovery → Encrypted backup and passive restore. Select My personal records or an available company scope. Company backup requires the owner. Restricted company operators cannot use this screen.",
        targetId: "backup-scope",
        destination: GuideDestination.backup,
      ),
      GuideStep(
        id: "backup-create",
        title: "Create encrypted backup",
        body:
            "Enter and confirm a backup passphrase of at least 12 characters, then Create encrypted backup. Keep the passphrase separately.",
        targetId: "backup-create",
      ),
      GuideStep(
        id: "backup-external",
        title: "Save or share encrypted backup",
        body:
            "Retain a copy outside the app. Its own copy cannot be relied on after uninstall.",
        targetId: "backup-external",
      ),
      GuideStep(
        id: "backup-verify",
        title: "Verify external custody",
        body:
            "Independently verify the external copy before choosing I verified a saved copy outside this app. The guide cannot attest for you.",
        targetId: "backup-verify",
      ),
      GuideStep(
        id: "backup-restore",
        title: "Restore verified records",
        body:
            "Choose backup to inspect, enter its passphrase, and review records and conflicts before Restore verified records. New installation and Merge nonconflicting records appear only in their actual context. Passive restore grants no active membership or management authority.",
        targetId: "backup-restore",
      ),
    ],
  ),
  GuideDefinition(
    id: "backup",
    variantId: "owner",
    revision: 1,
    title: "Back up and restore records",
    description:
        "Keep a verified encrypted backup and inspect records before restoring.",
    steps: [
      GuideStep(
        id: "backup-scope",
        title: "Encrypted backup and passive restore",
        body:
            "Open Backup / recovery → Encrypted backup and passive restore. Select My personal records or an available company scope. Company backup requires the owner. Restricted company operators cannot use this screen.",
        targetId: "backup-scope",
        destination: GuideDestination.backup,
      ),
      GuideStep(
        id: "backup-create",
        title: "Create encrypted backup",
        body:
            "Enter and confirm a backup passphrase of at least 12 characters, then Create encrypted backup. Keep the passphrase separately.",
        targetId: "backup-create",
      ),
      GuideStep(
        id: "backup-external",
        title: "Save or share encrypted backup",
        body:
            "Retain a copy outside the app. Its own copy cannot be relied on after uninstall.",
        targetId: "backup-external",
      ),
      GuideStep(
        id: "backup-verify",
        title: "Verify external custody",
        body:
            "Independently verify the external copy before choosing I verified a saved copy outside this app. The guide cannot attest for you.",
        targetId: "backup-verify",
      ),
      GuideStep(
        id: "backup-restore",
        title: "Restore verified records",
        body:
            "Choose backup to inspect, enter its passphrase, and review records and conflicts before Restore verified records. New installation and Merge nonconflicting records appear only in their actual context. Passive restore grants no active membership or management authority.",
        targetId: "backup-restore",
      ),
    ],
  ),
  GuideDefinition(
    id: "new-device",
    variantId: "staff-replacement",
    revision: 1,
    title: "Move to a new device",
    description:
        "Follow the recovery or handover path available to your current role.",
    steps: [
      GuideStep(
        id: "new-device-path",
        title: "Recover staff identity on this device",
        body:
            "Choose Recover staff identity on this device. Required recovery material must be secured before deleting or replacing anything.",
        targetId: "new-device-path",
        destination: GuideDestination.recovery,
      ),
      GuideStep(
        id: "new-device-identity",
        title: "Verify original identity",
        body:
            "Verify original public identity IDs and the full company root fingerprint. Use Create fresh replacement request.",
        targetId: "new-device-identity",
      ),
      GuideStep(
        id: "new-device-request",
        title: "Share replacement request",
        body:
            "Send Share replacement request to authorized management. Recovery export requires both membership-management and attendance-export authority. Use actual Files-based messages.",
        targetId: "new-device-request",
      ),
      GuideStep(
        id: "new-device-archive",
        title: "Apply received-record archive",
        body:
            "Apply received-record archive before Receive replacement grant. Records never received by management or absent from the archive cannot be reconstructed.",
        targetId: "new-device-archive",
      ),
      GuideStep(
        id: "new-device-activate",
        title: "Receive replacement grant",
        body:
            "Receive replacement grant, follow actual lock/unlock instructions, and verify retained history. Deleted-app cache and unimplemented companion apps are not recovery sources.",
        targetId: "new-device-activate",
      ),
    ],
  ),
  GuideDefinition(
    id: "new-device",
    variantId: "owner-target",
    revision: 1,
    title: "Move to a new device",
    description:
        "Follow the recovery or handover path available to your current role.",
    steps: [
      GuideStep(
        id: "new-device-path",
        title: "Activate or recover owner on this device",
        body:
            "Owner-only recovery moves the same owner to another device; it does not transfer company ownership.",
        targetId: "new-device-path",
        destination: GuideDestination.recovery,
      ),
      GuideStep(
        id: "new-device-identity",
        title: "Verify original identity",
        body:
            "Verify original public identity IDs and full company root fingerprint. Prepare fresh owner installation on the target. Secure recovery material before replacing anything.",
        targetId: "new-device-identity",
      ),
      GuideStep(
        id: "new-device-request",
        title: "Secure the recovery path",
        body:
            "Share target request with source device. Source reads it and explicitly chooses Freeze source and prepare handover. Management freezes before snapshot; missing acknowledgment does not cancel an issued handover.",
        targetId: "new-device-request",
      ),
      GuideStep(
        id: "new-device-archive",
        title: "Inspect the matching archive",
        body:
            "Inspect the matching company recovery/handover archive and checkpoint. Source shares Share exact handover archive and Share signed handover offer. Missing records cannot be reconstructed. Use Files-based message controls.",
        targetId: "new-device-archive",
      ),
      GuideStep(
        id: "new-device-activate",
        title: "Verify and activate handover",
        body:
            "Target verifies and activates the signed handover and uses Share activation acknowledgment. Source uses Receive target acknowledgment. Follow actual lock/unlock instructions and verify retained history.",
        targetId: "new-device-activate",
      ),
    ],
  ),
  GuideDefinition(
    id: "new-device",
    variantId: "owner-source",
    revision: 1,
    title: "Move to a new device",
    description:
        "Follow the recovery or handover path available to your current role.",
    steps: [
      GuideStep(
        id: "new-device-path",
        title: "Move this owner device",
        body:
            "Owner-only recovery moves the same owner to another device; it does not transfer company ownership.",
        targetId: "new-device-path",
        destination: GuideDestination.recovery,
      ),
      GuideStep(
        id: "new-device-identity",
        title: "Verify original identity",
        body:
            "Verify original public identity IDs and full company root fingerprint. Prepare fresh owner installation on the target. Secure recovery material before replacing anything.",
        targetId: "new-device-identity",
      ),
      GuideStep(
        id: "new-device-request",
        title: "Secure the recovery path",
        body:
            "Share target request with source device. Source reads it and explicitly chooses Freeze source and prepare handover. Management freezes before snapshot; missing acknowledgment does not cancel an issued handover.",
        targetId: "new-device-request",
      ),
      GuideStep(
        id: "new-device-archive",
        title: "Inspect the matching archive",
        body:
            "Inspect the matching company recovery/handover archive and checkpoint. Source shares Share exact handover archive and Share signed handover offer. Missing records cannot be reconstructed. Use Files-based message controls.",
        targetId: "new-device-archive",
      ),
      GuideStep(
        id: "new-device-activate",
        title: "Verify and activate handover",
        body:
            "Target verifies and activates the signed handover and uses Share activation acknowledgment. Source uses Receive target acknowledgment. Follow actual lock/unlock instructions and verify retained history.",
        targetId: "new-device-activate",
      ),
    ],
  ),
  GuideDefinition(
    id: "new-device",
    variantId: "owner-recovery",
    revision: 1,
    title: "Move to a new device",
    description:
        "Follow the recovery or handover path available to your current role.",
    steps: [
      GuideStep(
        id: "new-device-path",
        title: "Activate or recover owner on this device",
        body:
            "Owner-only recovery moves the same owner to another device; it does not transfer company ownership.",
        targetId: "new-device-path",
        destination: GuideDestination.recovery,
      ),
      GuideStep(
        id: "new-device-identity",
        title: "Verify original identity",
        body:
            "Verify original public identity IDs and full company root fingerprint. Prepare fresh owner installation on the target. Secure recovery material before replacing anything.",
        targetId: "new-device-identity",
      ),
      GuideStep(
        id: "new-device-request",
        title: "Secure the recovery path",
        body: "Lost-source recovery requires a usable company backup.",
        targetId: "new-device-request",
      ),
      GuideStep(
        id: "new-device-archive",
        title: "Inspect the matching archive",
        body:
            "Inspect the available company recovery backup and its checkpoint, record counts, and conflicts. Records absent from that backup cannot be reconstructed. This lost-source path does not require a new response from the missing source device.",
        targetId: "new-device-archive",
      ),
      GuideStep(
        id: "new-device-activate",
        title: "Recover when source device is lost",
        body:
            "Use Recover when source device is lost with a usable company backup. Follow actual lock/unlock instructions and verify retained history; deleted-app cache is not a recovery source.",
        targetId: "new-device-activate",
      ),
    ],
  ),
];
