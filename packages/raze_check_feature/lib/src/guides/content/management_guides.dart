import '../guide_models.dart';

final managementGuides = <GuideDefinition>[
  GuideDefinition(
    id: "review",
    variantId: "staff",
    revision: 1,
    title: "Review attendance and corrections",
    description: "Read attendance decisions, corrections, and signed history.",
    steps: [
      GuideStep(
        id: "review-details",
        title: "View attendance",
        body:
            "Inspect original and effective punch details in View attendance.",
        targetId: "review-details",
        destination: GuideDestination.attendance,
      ),
      GuideStep(
        id: "review-hints",
        title: "Read status and hints",
        body:
            "Read source, current status, and review hints. Hints do not establish working time or misconduct. Offline records may still be missing. Manual entries retain manager identity, reason, and explicit manual source.",
        targetId: "review-hints",
      ),
      GuideStep(
        id: "review-decision",
        title: "Read the decision",
        body: "Receive the decision and return update from management.",
        targetId: "review-decision",
      ),
      GuideStep(
        id: "review-correction",
        title: "Request correction",
        body:
            "Use Request correction, enter corrected time, offset, and reason, then Save signed request.",
        targetId: "review-correction",
      ),
      GuideStep(
        id: "review-history",
        title: "Decision and correction history",
        body:
            "Use Share correction request and read Decision and correction history. Corrections do not automatically change approval; original signed receipt bytes remain unchanged.",
        targetId: "review-history",
      ),
    ],
  ),
  GuideDefinition(
    id: "review",
    variantId: "owner",
    revision: 1,
    title: "Review attendance and corrections",
    description: "Read attendance decisions, corrections, and signed history.",
    steps: [
      GuideStep(
        id: "review-details",
        title: "View attendance",
        body:
            "Inspect original and effective punch details in View attendance.",
        targetId: "review-details",
        destination: GuideDestination.attendance,
      ),
      GuideStep(
        id: "review-hints",
        title: "Read status and hints",
        body:
            "Read source, current status, and review hints. Hints do not establish working time or misconduct. Offline records may still be missing. Manual entries retain manager identity, reason, and explicit manual source.",
        targetId: "review-hints",
      ),
      GuideStep(
        id: "review-decision",
        title: "Review attendance",
        body:
            "Enter Review reason, then explicitly choose Approve attendance or Reject attendance. Next never records a decision.",
        targetId: "review-decision",
      ),
      GuideStep(
        id: "review-correction",
        title: "Correct attendance",
        body:
            "Use Correct attendance, enter corrected time, offset, and reason, then Save manager correction.",
        targetId: "review-correction",
      ),
      GuideStep(
        id: "review-history",
        title: "Resolve correction requests",
        body:
            "For incoming requests use Resolution reason and Approve correction or Reject correction. Share selected return and read Decision and correction history. Correction does not automatically change approval; original signed receipt bytes remain unchanged.",
        targetId: "review-history",
      ),
    ],
  ),
  GuideDefinition(
    id: "review",
    variantId: "operator",
    revision: 1,
    title: "Review attendance and corrections",
    description: "Read attendance decisions, corrections, and signed history.",
    steps: [
      GuideStep(
        id: "review-details",
        title: "View attendance",
        body:
            "Inspect original and effective punch details in View attendance.",
        targetId: "review-details",
        destination: GuideDestination.attendance,
      ),
      GuideStep(
        id: "review-hints",
        title: "Read status and hints",
        body:
            "Read source, current status, and review hints. Hints do not establish working time or misconduct. Offline records may still be missing. Manual entries retain manager identity, reason, and explicit manual source.",
        targetId: "review-hints",
      ),
      GuideStep(
        id: "review-decision",
        title: "Review attendance",
        body:
            "Enter Review reason, then explicitly choose Approve attendance or Reject attendance. Next never records a decision.",
        targetId: "review-decision",
      ),
      GuideStep(
        id: "review-correction",
        title: "Correct attendance",
        body:
            "Use Correct attendance, enter corrected time, offset, and reason, then Save manager correction.",
        targetId: "review-correction",
      ),
      GuideStep(
        id: "review-history",
        title: "Resolve correction requests",
        body:
            "For incoming requests use Resolution reason and Approve correction or Reject correction. Share selected return and read Decision and correction history. Correction does not automatically change approval; original signed receipt bytes remain unchanged.",
        targetId: "review-history",
      ),
    ],
  ),
  GuideDefinition(
    id: "team",
    variantId: "owner",
    revision: 1,
    title: "Manage staff and operator access",
    description:
        "Understand staff records and company-scoped operator capabilities.",
    steps: [
      GuideStep(
        id: "team-open",
        title: "Team",
        body: "Open Team, then select a real record or Add staff.",
        targetId: "team-open",
        destination: GuideDestination.team,
      ),
      GuideStep(
        id: "team-details",
        title: "Save staff",
        body:
            "Edit Name and permitted optional details, then Save staff. A staff record does not enroll a phone.",
        targetId: "team-details",
      ),
      GuideStep(
        id: "team-capabilities",
        title: "Operator capabilities",
        body:
            "Only the owner can use Manage operator access and Save capabilities for an eligible active non-owner member. Capabilities limit staff management, membership management, attendance review, and attendance export to their granted scopes.",
        targetId: "team-capabilities",
      ),
      GuideStep(
        id: "team-credential",
        title: "Company operator credential",
        body:
            "Activate operator credential requires a passphrase and confirmation of at least 12 characters. Unlock company operator uses this local company-scoped credential. Role labels and guides grant no authority. Where available, deactivation removes the corresponding access.",
        targetId: "team-credential",
      ),
    ],
  ),
  GuideDefinition(
    id: "team",
    variantId: "operator",
    revision: 1,
    title: "Manage staff and operator access",
    description:
        "Understand staff records and company-scoped operator capabilities.",
    steps: [
      GuideStep(
        id: "team-open",
        title: "Team",
        body: "Open Team, then select a real record or Add staff.",
        targetId: "team-open",
        destination: GuideDestination.team,
      ),
      GuideStep(
        id: "team-details",
        title: "Save staff",
        body:
            "Edit Name and permitted optional details, then Save staff. A staff record does not enroll a phone.",
        targetId: "team-details",
      ),
      GuideStep(
        id: "team-capabilities",
        title: "Operator capabilities",
        body:
            "Only the owner can use Manage operator access and Save capabilities for an eligible active non-owner member. Capabilities limit staff management, membership management, attendance review, and attendance export to their granted scopes.",
        targetId: null,
      ),
      GuideStep(
        id: "team-credential",
        title: "Company operator credential",
        body:
            "Activate operator credential requires a passphrase and confirmation of at least 12 characters. Unlock company operator uses this local company-scoped credential. Role labels and guides grant no authority. Where available, deactivation removes the corresponding access.",
        targetId: null,
      ),
    ],
  ),
  GuideDefinition(
    id: "reports",
    variantId: "personal",
    revision: 1,
    title: "Read and export attendance reports",
    description: "Choose a report scope, date range, and permitted CSV export.",
    steps: [
      GuideStep(
        id: "reports-scope",
        title: "Attendance report",
        body:
            "Open Attendance report. Where Report scope is available choose My attendance or Company attendance. Owners initially see personal scope; restricted operators see only authorized company scope.",
        targetId: "reports-scope",
        destination: GuideDestination.reports,
      ),
      GuideStep(
        id: "reports-dates",
        title: "Generate report",
        body:
            "Enter Start date (YYYY-MM-DD) and End date (YYYY-MM-DD), then Generate report. Both dates are included using company time zone and effective punch date.",
        targetId: "reports-dates",
      ),
      GuideStep(
        id: "reports-csv",
        title: "Share CSV",
        body:
            "Use Share CSV where permitted. Preview shows the first 25 rows; export includes all selected rows. Regenerate after changes. Reports show records and decisions, not salary or payable hours.",
        targetId: "reports-csv",
      ),
    ],
  ),
  GuideDefinition(
    id: "reports",
    variantId: "owner",
    revision: 1,
    title: "Read and export attendance reports",
    description: "Choose a report scope, date range, and permitted CSV export.",
    steps: [
      GuideStep(
        id: "reports-scope",
        title: "Attendance report",
        body:
            "Open Attendance report. Where Report scope is available choose My attendance or Company attendance. Owners initially see personal scope; restricted operators see only authorized company scope.",
        targetId: "reports-scope",
        destination: GuideDestination.reports,
      ),
      GuideStep(
        id: "reports-dates",
        title: "Generate report",
        body:
            "Enter Start date (YYYY-MM-DD) and End date (YYYY-MM-DD), then Generate report. Both dates are included using company time zone and effective punch date.",
        targetId: "reports-dates",
      ),
      GuideStep(
        id: "reports-csv",
        title: "Share CSV",
        body:
            "Use Share CSV where permitted. Preview shows the first 25 rows; export includes all selected rows. Regenerate after changes. Reports show records and decisions, not salary or payable hours.",
        targetId: "reports-csv",
      ),
    ],
  ),
  GuideDefinition(
    id: "reports",
    variantId: "operator",
    revision: 1,
    title: "Read and export attendance reports",
    description: "Choose a report scope, date range, and permitted CSV export.",
    steps: [
      GuideStep(
        id: "reports-scope",
        title: "Attendance report",
        body:
            "Open Attendance report. Where Report scope is available choose My attendance or Company attendance. Owners initially see personal scope; restricted operators see only authorized company scope.",
        targetId: "reports-scope",
        destination: GuideDestination.reports,
      ),
      GuideStep(
        id: "reports-dates",
        title: "Generate report",
        body:
            "Enter Start date (YYYY-MM-DD) and End date (YYYY-MM-DD), then Generate report. Both dates are included using company time zone and effective punch date.",
        targetId: "reports-dates",
      ),
      GuideStep(
        id: "reports-csv",
        title: "Share CSV",
        body:
            "Use Share CSV where permitted. Preview shows the first 25 rows; export includes all selected rows. Regenerate after changes. Reports show records and decisions, not salary or payable hours.",
        targetId: "reports-csv",
      ),
    ],
  ),
];
