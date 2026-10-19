# Raze Check signed messages v1

This document fixes the standalone foundation wire registry. Camera, image, file,
and stored outbox readers use the same codec and verifier. Decoding validates
shape; verification checks signatures and supplied enrollment history. Neither
step grants permission for a new command, changes trust history, approves an
attendance event, or proves workplace presence.

## Transport and signatures

A message is UTF-8 JSON with exactly five positional elements:

```text
[1, kind, keyId, payloadBase64Url, signatureBase64Url]
```

`kind` is one of the eleven case-sensitive names in the registry below. Unknown
versions or kinds fail with `unsupportedVersion` before payload dispatch. Wrong
field counts/types, maps, floats, unknown enum values and malformed UTF-8/JSON
fail with `malformed`. JSON nesting deeper than four containers is rejected
before JSON decoding. Payload and certificate arrays have no extension slots.
A new field or kind requires an explicitly supported registry version.

The signature is Ed25519 (64 bytes), over the concatenation of UTF-8
`RAZE_CHECK_V1\n<kind>\n` and the **original decoded payload bytes**. There is
no trailing newline. Each `\n` in the domain denotes one LF byte. The signature
never uses a reconstructed payload. New builders use compact `jsonEncode`
arrays with direct Unicode and the standard JSON escaping of controls. Readers
also accept JSON whitespace and alternate valid escapes, retaining those exact
payload bytes. Decoded outer envelope bytes are also retained when redisplayed,
even by a different codec instance. Mutable input/output buffers cannot alter a
message's stored payload, signature or envelope. Persist original transport bytes
when exact outer formatting must survive storage or process restart.

Every field called base64url, including transport payload/signature, public keys,
SHA-256 hashes and certificate signatures, uses **canonical padded RFC 4648
base64url** (`-` and `_`; required `=` padding, no whitespace). Decode followed
by canonical base64url encode must equal the input. Public keys and hashes are
32 bytes; signatures are 64. The sole exception is the fingerprint in `keyId`:

```text
keyId = "ed25519:" + unpadded-base64url(SHA256(raw-32-byte-public-key))
```

This ID is exactly 51 ASCII bytes. Verification derives it from the actual
verification key and requires equality for every kind, including self-signed
requests. It is distinct from internal secure-store references such as
`signing:<uuid>`, `operator-signing:<uuid>` and `company-root:<uuid>`.
`Company.authoritySigningKeyId` remains local encrypted metadata. Use
`messageKeyId(publicKey)` for the wire ID and
`messageSigningBytes(kind, payloadBytes)` for `KeyService.sign`; pass the local
secure-store key reference only to `KeyService`, never into the envelope.

The final UTF-8 envelope is at most **1,500 bytes for QR** and **65,536 bytes for
message files**. Readers reject oversized transport before UTF-8/base64/JSON
work; caller `maxBytes` may lower but cannot increase the file limit.
`MessageCodec.fitsQr` applies the final envelope gate. Larger valid messages use
file export, with all bytes intact. No name/reason restriction or truncation is
introduced to make a message fit QR. Physical camera scan reliability remains a
separate release test; a passing byte-size test is not hardware evidence.

## Scalar types and bounds

All IDs, including company, message/event, person, employee, installation,
membership, request, workplace/code, decision/correction, snapshot and authority
generation IDs, are lowercase UUIDv4 strings with RFC 4122 variant bits. Optional
IDs use explicit JSON `null`, never an omitted field or empty string.

UTC instants are integers in `-8640000000000000..8640000000000000` milliseconds
(the Dart UTC instant range). Revisions and authority sequences are integers in
`1..9007199254740991` (the interoperable JSON safe-integer range). Offsets are
integer minutes in `-840..840`. Numbers encoded as JSON floating-point values,
even whole-valued floats, are rejected.

Names/record labels contain 1..120 Unicode scalar values. Only the compact
invitation display label is limited to 1..40; membership-grant company labels
allow 120. Reasons contain 0..500 scalars. Scalars, rather than UTF-16 code units
or grapheme clusters, determine these limits; unpaired surrogates are rejected.
Valid Unicode controls are representable and JSON-escaped; there is no silent
normalization, trimming, truncation or control-character rewrite in signed data.
These are protocol record limits; a profile entry UI can impose its existing
separate product limit. Time-zone IDs contain 1..120 scalars and must appear in
the pinned bundled IANA database (`CompanyTimeZones.all`). Device locale does
not choose the company time zone.

## Payload registry

Every payload starts with `[companyId, messageId, issuedAtUtcMs]`. Every field
below follows that prefix, in the stated order. Everything is a string except
explicit integers, nullable IDs and fixed authority arrays. Hashes/keys are
base64url strings of the fixed byte lengths above. `kind`, `proposedKind` and
`effectiveKind` are `checkIn` or `checkOut`; outcome is `approved` or `rejected`;
evidence is exactly `staticQr`.

| Kind | Fields after common prefix |
| --- | --- |
| `invitation` | companyLabel, timeZoneId, workplaceId, rootPublicKeyBase64Url, authority |
| `joinRequest` | invitationId, personId, displayName, installationId, publicKeyBase64Url |
| `membershipGrant` | joinOrReplacementRequestId, membershipId, membershipRevision (integer), personId, employeeId, installationId, publicKeyBase64Url, companyLabel, timeZoneId, workplaceId, authority |
| `workplace` | workplaceId, codeId, authority |
| `attendance` | personId, employeeId, membershipId, membershipRevision (integer), installationId, kind, claimedUtcMs (integer), offsetMinutes (integer), workplaceId, codeId, membershipAuthorityGenerationId, evidence |
| `receiptAck` | eventId, eventPayloadSha256Base64Url, receivedUtcMs (integer), authority |
| `attendanceDecision` | eventId, eventPayloadSha256Base64Url, decisionId, decisionRevision (integer), outcome, reason, correctionIdOrNull, effectiveKind, effectiveUtcMs (integer), effectiveOffsetMinutes (integer), actorPersonId, authority |
| `correctionRequest` | employeeId, eventId, proposedKind, proposedUtcMs (integer), proposedOffsetMinutes (integer), reason |
| `replacementRequest` | personId, employeeIdOrNull, newInstallationId, newPublicKeyBase64Url |
| `authorityTransfer` | targetReplacementRequestId, snapshotManifestId, snapshotSha256Base64Url, nextAuthority, sourceAuthority |
| `transferAck` | transferMessageId, snapshotManifestId, snapshotSha256Base64Url, authority |

`messageId` is the event ID for attendance messages. Hashes identify the exact
original event payload or snapshot bytes, not a reserialized object.
`actorPersonId` attributes a decision but does not substitute an operator key
for the company issuer key. A decision with no correction repeats the original
effective fields. A resolved correction creates a new decision revision and
correction ID while retaining all prior history. Attendance/review services
must check those cross-record relationships, request references, revisions,
event hashes and permissions transactionally; the codec/verifier cannot infer
them from a single message. No v1 field asserts verified location.

## Authority and trust

Authority certificates use exactly the existing company v1 grammar:

```text
[generationId, parentGenerationIdOrNull, sequence, installationId,
 publicKeyBase64Url, issuedAtUtcMs, rootSignatureBase64Url]
```

The root signature covers UTF-8 `RAZE_CHECK_AUTHORITY_V1\n` plus compact JSON of
the first six elements. The root and company installation issuer are distinct
keys. A root certificate has a null parent and sequence 1. A successor names its
parent generation, increments sequence by exactly one, and cannot predate its
parent. IDs cannot name themselves as parents. Transfer next authority must
extend its signed source and use a different installation.

`TrustContext` supplies the company ID, already pinned root public key, known
root/issuer certificate history and enrolled/historical staff credentials. An
invitation's embedded root must equal that pinned key. First-use callers must
show the company label and root fingerprint and obtain explicit acceptance
before constructing this pinned context; an empty certificate history is valid
for that explicit initial root enrollment. Never automatically trust an incoming
root or staff key. Company messages verify using their root-certified issuer
key, and staff attendance/corrections use a supplied `TrustedCredential` obtained
from a verified membership grant. Staff signature verification also binds the
employee, person, installation, membership/revision and authority generation
where those fields are present.

Every supplied history certificate is root-verified and checked for parent
availability, sequence and time ordering. An incoming certificate can extend a
known parent; no trust history is mutated by verification. Conflicting generation
contents, competing initial roots or sibling successors fail with
`recoveryRequired`; missing ancestors/credentials fail with `unknownIssuer`.
Root/signature/fingerprint mismatch fails with `invalidSignature`; mismatched
company fails with `wrongCompany`; a valid staff signature borrowing another
enrollment fails with `unauthorized`. Invalid lineage ordering/transfer links
fail with `invalidTransition`. Fork recovery is a separate explicit workflow.

`joinRequest` and `replacementRequest` verify only possession of the embedded
new key, including its derived wire ID; `VerifiedMessage.proofOfPossessionOnly`
is true. Claimed person/employee IDs do not authenticate the claimant or grant
membership, operator rights or replacement authority. Company enrollment and
recovery approval remain required. `membershipGrant` grants attendance access
only; management permissions remain in local capability history.

Keep retired device keys and past membership revisions. An authentic receipt
from a retired credential returns `historicalCredential: true` instead of
losing historical signature validity. Consumers flag authorization uncertainty
and enforce current activity permissions independently. Verified signatures
alone never authorize new activity or overwrite company authority history.

## Test vectors

`packages/raze_check_core/test/fixtures/messages/` contains 33 checked-in exact
UTF-8 envelopes. Deterministic **public test-only** Ed25519 seeds are 32 bytes
filled with 1 (root), 2 (issuer), 3 (staff) and 4 (next issuer). IDs are
`00000000-0000-4000-8000-<12-digit lowercase hex counter>`. Company is counter 1;
initial generation 2, issuer installation 3, next generation 4 and installation
5; staff person/employee/installation/membership are 6/7/8/9. Representative
message UTC is `1792368000000`, initial authority UTC is 1,000 ms earlier,
company label is `Raze Check`, zone `Asia/Tokyo`, staff name `Alex Tanaka`,
reason `Correct missed check-in`, and claimed offset 540. Each representative
filename is `<kind>.json` and is verified against the fixture enrollment history.

The independent SHA-256 issuer wire ID is
`ed25519:ajgD1fBZkCocba-8m6RykhL3yqwIY0zDrnaydSnwOCc`; staff is
`ed25519:ti6Gf6LzOv5i1daxZC4WIdVDMHhGsqV7iX5xCRm3Zwk`.

`<kind>.max.json` exercises maximum text/scalar, numeric and populated optional
fields where available, with NUL control scalars to exercise six-byte JSON
escaping; authority generation chains retain their concrete initial/next
sequences rather than inventing unbounded history. `<kind>.compact.json` keeps
those boundary choices, choosing shorter label/reason content before signing
where necessary and filling remaining base64 capacity with ASCII. These are
maximum compact examples for that fixed vector family, not a claim that every
combination of allowed fields fits QR or authenticates against the representative
staff revision. Fixtures intentionally stress the wire grammar, not UI labels.

Regenerate from the core package with
`dart run test/support/generate_message_fixtures.dart`; its outer-array and
payload construction are explicit and do not call `MessageCodec.encode`.
Codec tests retain every fixture byte, reject every payload field with an
unexpected type/extra field, and cover Unicode/number/base64/depth boundaries.
Verifier tests use real Ed25519, mutate signed payload/certificate fields and
all signature bytes, and reject wrong domains/types/company/root/issuer and
borrowed staff identity. Tests also cover exact 1,500/1,501 and 65,536/65,537
transport boundaries and complete file fallback. These fixtures and their
computed sizes are not physical QR scan evidence.
