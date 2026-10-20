import '../guide_models.dart';

final welcomeCompanyGuides = <GuideDefinition>[
  GuideDefinition(
    id: "welcome",
    variantId: "public",
    revision: 1,
    title: "Welcome to Raze Check",
    description: "Learn welcome to raze check.",
    steps: [
      GuideStep(
        id: "welcome-offline",
        title: "Offline attendance",
        body:
            "Raze Check keeps attendance on this device for staff and management.",
        targetId: null,
      ),
      GuideStep(
        id: "welcome-profiles",
        title: "Profiles and companies",
        body:
            "Your local profile can be staff in one company and owner in another. Get started opens the profile chooser; it assigns no role.",
        targetId: null,
      ),
      GuideStep(
        id: "welcome-receipts",
        title: "Record attendance",
        body: "Save a separate check-in or check-out receipt on this device.",
        targetId: null,
      ),
      GuideStep(
        id: "welcome-statuses",
        title: "Exchange and review",
        body:
            "Saved, received, approved, and rejected describe different stages.",
        targetId: null,
      ),
      GuideStep(
        id: "welcome-help",
        title: "Protect your records",
        body:
            "Keep a verified external encrypted backup- Reopen these guides in Settings → Help & Guides.",
        targetId: null,
      ),
    ],
  ),
  GuideDefinition(
    id: "companies",
    variantId: "personal",
    revision: 1,
    title: "Set up and switch companies",
    description: "Learn set up and switch companies-",
    steps: [
      GuideStep(
        id: "companies-choose",
        title: "Choose your company",
        body:
            "Choose Create company to manage a new company, or Join company when invited.",
        targetId: "companies-choose",
        destination: GuideDestination.createCompany,
      ),
      GuideStep(
        id: "companies-name",
        title: "Company name",
        body: "Enter a Company name the team will recognize.",
        targetId: "companies-name",
      ),
      GuideStep(
        id: "companies-zone",
        title: "Select IANA time zone",
        body: "Choose the company time zone, then Create company when ready.",
        targetId: "companies-zone",
      ),
      GuideStep(
        id: "companies-switch",
        title: "Switch company",
        body:
            "Confirm the current company and available actions. With an open draft choose Keep editing or Discard draft. Permissions belong to each membership-",
        targetId: "companies-switch",
      ),
    ],
  ),
  GuideDefinition(
    id: "membership",
    variantId: "staff",
    revision: 1,
    title: "Invite staff or join a company",
    description: "Learn invite staff or join a company.",
    steps: [
      GuideStep(
        id: "membership-open",
        title: "Open the joining workflow",
        body:
            "Open Join company to read your invitation. Management opens its invitation workflow.",
        targetId: "membership-open",
        destination: GuideDestination.joinCompany,
      ),
      GuideStep(
        id: "membership-invite",
        title: "Create and send an invitation",
        body:
            "An authorized manager chooses Create invitation and sends it. This explanation does not act on the other phone.",
        targetId: null,
      ),
      GuideStep(
        id: "membership-trust",
        title: "Check the invitation",
        body:
            "Read invitation and compare the full company security fingerprint with the manager.",
        targetId: "membership-trust",
      ),
      GuideStep(
        id: "membership-request",
        title: "Send a join request",
        body:
            "Confirm the invitation and send your join request. A request does not grant membership or confirm delivery.",
        targetId: "membership-request",
      ),
      GuideStep(
        id: "membership-approve",
        title: "Receive approval",
        body:
            "Management reads the join request, explicitly approves it, and returns membership-",
        targetId: null,
      ),
      GuideStep(
        id: "membership-receive",
        title: "Receive membership",
        body:
            "Use Receive membership and verify the company is available. Awaiting manager approval is different from Membership active.",
        targetId: "membership-receive",
      ),
    ],
  ),
  GuideDefinition(
    id: "membership",
    variantId: "owner",
    revision: 1,
    title: "Invite staff or join a company",
    description: "Learn invite staff or join a company.",
    steps: [
      GuideStep(
        id: "membership-open",
        title: "Manage invitations",
        body:
            "Open the invitation workflow with current membership-management authority. Staff actions on the other phone are informational.",
        targetId: "membership-open",
        destination: GuideDestination.joinCompany,
      ),
      GuideStep(
        id: "membership-invite",
        title: "Create and send an invitation",
        body:
            "An authorized manager chooses Create invitation and sends it. This explanation does not act on the other phone.",
        targetId: "membership-invite",
      ),
      GuideStep(
        id: "membership-trust",
        title: "Check the invitation",
        body:
            "Read invitation and compare the full company security fingerprint with the manager.",
        targetId: null,
      ),
      GuideStep(
        id: "membership-request",
        title: "Send a join request",
        body:
            "Confirm the invitation and send your join request. A request does not grant membership or confirm delivery.",
        targetId: null,
      ),
      GuideStep(
        id: "membership-approve",
        title: "Receive approval",
        body:
            "Management reads the join request, explicitly approves it, and returns membership-",
        targetId: "membership-approve",
      ),
      GuideStep(
        id: "membership-receive",
        title: "Receive membership",
        body:
            "Use Receive membership and verify the company is available. Awaiting manager approval is different from Membership active.",
        targetId: null,
      ),
    ],
  ),
  GuideDefinition(
    id: "membership",
    variantId: "operator",
    revision: 1,
    title: "Invite staff or join a company",
    description: "Learn invite staff or join a company.",
    steps: [
      GuideStep(
        id: "membership-open",
        title: "Manage invitations",
        body:
            "Open the invitation workflow with current membership-management authority. Staff actions on the other phone are informational.",
        targetId: "membership-open",
        destination: GuideDestination.joinCompany,
      ),
      GuideStep(
        id: "membership-invite",
        title: "Create and send an invitation",
        body:
            "An authorized manager chooses Create invitation and sends it. This explanation does not act on the other phone.",
        targetId: "membership-invite",
      ),
      GuideStep(
        id: "membership-trust",
        title: "Check the invitation",
        body:
            "Read invitation and compare the full company security fingerprint with the manager.",
        targetId: null,
      ),
      GuideStep(
        id: "membership-request",
        title: "Send a join request",
        body:
            "Confirm the invitation and send your join request. A request does not grant membership or confirm delivery.",
        targetId: null,
      ),
      GuideStep(
        id: "membership-approve",
        title: "Receive approval",
        body:
            "Management reads the join request, explicitly approves it, and returns membership-",
        targetId: "membership-approve",
      ),
      GuideStep(
        id: "membership-receive",
        title: "Receive membership",
        body:
            "Use Receive membership and verify the company is available. Awaiting manager approval is different from Membership active.",
        targetId: null,
      ),
    ],
  ),
];
