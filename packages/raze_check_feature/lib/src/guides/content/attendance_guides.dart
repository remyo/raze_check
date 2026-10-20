import '../guide_models.dart';

final attendanceGuides = <GuideDefinition>[
  GuideDefinition(
    id: "capture",
    variantId: "staff",
    revision: 1,
    title: "Check in and check out",
    description: "Understand workplace codes and separate attendance receipts.",
    steps: [
      GuideStep(
        id: "capture-open",
        title: "Record attendance",
        body: "Select the correct company and open Record attendance.",
        targetId: "capture-open",
        destination: GuideDestination.capture,
      ),
      GuideStep(
        id: "capture-kind",
        title: "Check in or Check out",
        body:
            "Choose Check in or Check out. Reading a valid workplace code saves that punch immediately.",
        targetId: "capture-kind",
      ),
      GuideStep(
        id: "capture-read",
        title: "Read the workplace code",
        body:
            "Choose Scan QR, QR image from Files, or Message from Files yourself. The guide never starts scanning.",
        targetId: "capture-read",
      ),
      GuideStep(
        id: "capture-saved",
        title: "Saved on this device",
        body:
            "Look for Saved on this device and Share receipt. An error is not a completed punch. Retry saved punch exists only for a real pending draft. Check-out is another event; saving is separate from approval.",
        targetId: "capture-saved",
      ),
    ],
  ),
  GuideDefinition(
    id: "capture",
    variantId: "owner",
    revision: 1,
    title: "Check in and check out",
    description: "Understand workplace codes and separate attendance receipts.",
    steps: [
      GuideStep(
        id: "capture-open",
        title: "Workplace QR",
        body:
            "Open Workplace QR → Display workplace code. Displaying the code is your explicit action; this guide never creates it.",
        targetId: "capture-open",
        destination: GuideDestination.capture,
      ),
      GuideStep(
        id: "capture-kind",
        title: "Check in or Check out",
        body:
            "On the staff phone, choose Check in or Check out. Reading a valid workplace code saves that punch immediately.",
        targetId: null,
      ),
      GuideStep(
        id: "capture-read",
        title: "Read the workplace code",
        body:
            "Staff chooses Scan QR, QR image from Files, or Message from Files on their own phone. The guide never starts scanning.",
        targetId: null,
      ),
      GuideStep(
        id: "capture-saved",
        title: "Saved on this device",
        body:
            "Look for Saved on this device and Share receipt. An error is not a completed punch. Retry saved punch exists only for a real pending draft. Check-out is another event; saving is separate from approval.",
        targetId: null,
      ),
    ],
  ),
  GuideDefinition(
    id: "exchange",
    variantId: "staff",
    revision: 1,
    title: "Send receipts and receive updates",
    description: "Share saved receipts and distinguish delivery from approval.",
    steps: [
      GuideStep(
        id: "exchange-outbox",
        title: "Receipt outbox",
        body: "Open Receipt outbox and select the actual saved punch to send.",
        targetId: "exchange-outbox",
        destination: GuideDestination.capture,
      ),
      GuideStep(
        id: "exchange-share",
        title: "Share receipt",
        body:
            "Use Share receipt, then Share QR image or Share message file. Use an intact message file if QR is too large. Opening sharing does not confirm delivery.",
        targetId: "exchange-share",
      ),
      GuideStep(
        id: "exchange-import",
        title: "Management receives receipts",
        body:
            "Management uses Import receipt or correction, then View attendance.",
        targetId: "exchange-import",
      ),
      GuideStep(
        id: "exchange-return",
        title: "Management returns updates",
        body:
            "After real import or review, management uses Show receipt acknowledgment, Show decision <revision>, and Share selected return.",
        targetId: "exchange-return",
      ),
      GuideStep(
        id: "exchange-receive",
        title: "Receive attendance update",
        body:
            "Use Receive attendance update. Read delivery separately from approval: acknowledgment is not approval.",
        targetId: "exchange-receive",
      ),
    ],
  ),
];
