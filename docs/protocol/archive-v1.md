# Encrypted Archive v1

This unreleased v1 format is implemented by `LocalArchiveService`. `archive: 4.5.2` is pinned directly in the local package; the earlier 4.0.9 candidate conflicts with locked image 4.12.0. No dependency override or image downgrade is used.

## Outer bytes

All offsets are zero based. Integers are unsigned little endian.

| Offset | Length | Value |
| --- | --- | --- |
| 0 | 8 | ASCII `RZCKBK01` (`52 5a 43 4b 42 4b 30 31`) |
| 8 | 2 | version 1 (`01 00`) |
| 10 | 1 | AES-256-GCM, 1 |
| 11 | 1 | PBKDF2-HMAC-SHA256, 1 |
| 12 | 16 | fresh random salt |
| 28 | 12 | fresh random GCM nonce |
| 40 | 4 | 600000 (`c0 27 09 00`) |
| 44 | 8 | exact ciphertext length N |
| 52 | N | encrypted ZIP |
| 52+N | 16 | GCM authentication tag |

The exact 52 header bytes are AAD. PBKDF2 derives 32 bytes from UTF-8 passphrase bytes; creation requires at least 12 Unicode code points and UI confirmation. No normalization is applied. Readers accept only the listed version, algorithms and work factor. Total length must equal 68+N before key derivation. Bad authentication displays **Wrong passphrase or damaged backup**. There is no reliable password-versus-damage distinction.

A literal header-only parsing fixture with zero salt/nonce and N=3 is:

```text
525a434b424b3031 0100 01 01
00000000000000000000000000000000
000000000000000000000000
c0270900 0300000000000000
```

It requires exactly 3 ciphertext and 16 tag bytes; it is not an authenticated backup and its zero randomness must never be used by the writer. `backup_archive_test.dart` checks generated real encrypted attachment fixtures and corruption/truncation/KDF/version rejection.

## Limits and ZIP profile

Encrypted file (including header/tag), complete expanded file contents, and `records.json` each have a 67,108,864-byte ceiling. `records.json` shares the expanded total; every other entry is at most 8,388,608 bytes. At most 10,000 ZIP entries. Limits apply to declared metadata and actual output. No hidden sharding, nested compression, truncation, or partial-company export is performed.

ZIP is single disk, non-ZIP64, without archive/entry comments or extra fields. Only stored and raw-deflate methods are accepted. Flags are limited to UTF-8 and signed data-descriptor usage. Entries are ordinary files only: directories, symlinks and special Unix modes are rejected. Central/local names, flags, methods, CRCs, lengths, offsets, descriptors, central count and all byte ranges must agree. Local entries are contiguous in central-directory order, followed immediately by the directory and 22-byte EOCD. Duplicates are rejected before decoding, as are traversal/absolute/unexpected names. CRC is checked independently; package callback/`verify` flags are not security boundaries. Counted deflate output cannot exceed the declared size, and exact final size/CRC/file hash must match.

The exact membership is `manifest.json`, `records.json`, `recovery.json`, and `attachments/<64 lowercase SHA-256 hex digits>`. Whole-file GCM authentication finishes before ZIP parsing or decompression. Manifest membership must then equal decoded membership. No ZIP path is used as an arbitrary extraction destination.

## Manifest and passive identity

`manifest.json` has exactly these ten keys:

- `formatVersion`: integer 1; `archiveId`: identifier; `createdUtcMs`: integer UTC milliseconds.
- `scopeKind`: `company` or `personal`; `scopeId`: original company/person ID; `personId`: authorizing owner/person.
- `companyRootFingerprints`: company ID to lowercase SHA-256 of raw root public key.
- `authorityHeads`: company ID to original authority generation ID.
- `recordCountsByKind`: kind to exact count of current logical rows, including explicitly retired credentials.
- `files`: objects with exactly `path`, integer `byteLength`, and lowercase hex `sha256`, one per non-manifest entry.

`recovery.json` is exactly `{"version":1,"profiles":[...]}`. Each profile is exactly `{version:1,personId,displayName,installations:[[installationId,paddedBase64urlPublicKey],...]}`. There are no unlock verifiers, passwords, session handles, signing seeds, or private device-key references here. Personal scope includes only its profile. A company archive also requires its creation person's locally held passive profile, so completed creation-routing provenance can be rebuilt under a matching personal vault.

Company-only `companyRootRecovery` logical rows preserve their portable root seed, public key and root key ID. Seed-derived Ed25519 public key, company public key, fingerprint, current authority, complete parent lineage and root signatures must agree. Personal archives reject these rows. Owner-only backup authorization is unchanged; granting an operator backup capability does not permit company export. Restored profile metadata is stored separately from the active ProfileCatalog and cannot unlock a session. Task 11 creates fresh local credentials/installations while retaining person IDs.

## Indexed exact-byte records grammar

`records.json` is a UTF-8 JSON array with a strict incremental line profile. It starts with the literal `[[1]\n`; each subsequent item is a single line `,<JSON array>\n`; the final byte is `]`. No other whitespace/line layout is accepted. JSON strings use ordinary escaping, so payload text cannot create extra lines. Four implicit zero-based tables (strings, payloads, row descriptors, logical entries) are filled in encounter order. Definitions precede references. Every definition must be used. Duplicates, invalid indexes/types/arity, duplicate logical IDs, duplicate journal revision/operation identities and invalid ownership are rejected.

| Tag | Exact item | Meaning |
| --- | --- | --- |
| `s` | `["s",text]` | Define unique nonempty string, at most 1024 UTF-8 bytes. IDs, kinds, categories and attachment hashes use this table. |
| `p` | `["p",sha256Base64url,exactBytesBase64url]` | Define payload, at most 8 MiB raw. Both encodings are canonical padded base64url. Hash must match. Writer interns only hash plus byte-equal content. |
| `r` | `["r",idS,companyS,kindS,revision,payloadP]` | Define unique complete record descriptor. Revision is positive. Original bytes are never parsed/reformatted for interning. |
| `e` | `["e",categoryS,rowR]` | Current logical row. Category is `entity`, `event`, `outbox`, `authority`, or `recovery`. Original company/record ID is unique across categories. |
| `o` | `["o",companyS,operationS,authorityS,digestP,expectedRevisionOrNull,revisionOrNull,resultROrNull,[ownerS,...]]` | Original operation, SHA-256 request digest, saved exact result (including earlier mutable revisions), optional nonnegative expected revision, explicit personal owners. Pending operations have null revision/result; completed ones have both. |
| `t` | Same positions as `o`, but digest position is `null` | Explicit retired local-credential operation; saved result is safe `retiredLocalCredential`, never the old secret-containing result. |
| `j` | `["j",companyS,revision,operationS]` | Original committed revision journal association, positive revision. |
| `l` | `["l",companyS,recordS,personS]` | Explicit personal inclusion sidecar. |
| `a` | `["a",companyS,recordS,sha256S,byteLength]` | Original attachment descriptor; byte length is nonnegative and at most 8 MiB. |
| `v` | `["v",companyS,revision]` | Original nonnegative checkpoint. Personal checkpoint is exactly the maximum included safe operation revision. |

The sum of raw referenced payload lengths, counting each `e` reference and every operation's digest and saved result separately, is at most 64 MiB. Retired operations charge an internal 32-byte sentinel for conservative accounting, but their wire digest is absent. Logical rows, operations, owners, journals, associations, attachments and checkpoints together are at most 524288 items. Definitions, strings, line size, source row size and encoded bytes have separate bounds. These guards prevent reference amplification. They do not raise the pre-existing materialized LogicalSnapshot budget.

Literal small records fixture (one row with bytes `01 02 03`; this is an inner-format fixture, not a complete domain archive):

```json
[[1]
,["s","row"]
,["s","company"]
,["s","kind"]
,["p","A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E=","AQID"]
,["r",0,1,2,1,0]
,["s","entity"]
,["e",3,0]
,["v",1,0]
]
```

Personal inclusion is never inferred from membership. Every current row, attachment link and saved result requires its own explicit association; operation owners must be exactly the selected person. Original company IDs, journal IDs and revision values remain intact. Required derived membership indexes are rebuilt on a new passive installation without changing archived rows/history. A conflicting existing index fails the transaction.

### Explicit local operator redaction

`operatorCredential` is the one authorized non-lossless credential exception. Portable `retiredLocalCredential` bytes are a versioned object with exactly `version:1`, `reason:"freshLocalSetupRequired"`, `id`, `companyId`, `membershipId`, `personId`, `installationId`, `publicKey`. Salt, verifier, private-key reference/seed and password-derived activation request digest are excluded. Current rows and old activation results use this safe representation; original operation ID, expected/committed revision, authority, owners and journal stay intact through tag `t`. The local adapter persists an explicit `StoredOperation.retiredLocalCredential` marker. Its old-operation replay returns `recoveryRequired` before normal digest/result replay, even after a later activation removes the company gate. New authorized operator setup requires a new operation ID and fresh secret/key. Portable tombstones conflict with existing live credentials; they never downgrade them. All other bytes and history are lossless.

## Consistent traversal, resources and capacity

`LocalCheckRepository.visitArchive` holds one exclusive connection and a `BEGIN DEFERRED` WAL read snapshot. Keyset pages carry at most 32 routing entries; encrypted body length is prechecked and one body of at most 12 MiB is loaded/decrypted at a time. Awaited callbacks provide backpressure. Cancellation/liveness and a five-minute transaction duration bound are checked between items; callbacks must not recursively call that repository. The company checkpoint comes from the same read snapshot. Another SQLite connection may write without mixing its revision into the export. Long reads can retain WAL pages.

Indexed serialization uses a persistent worker isolate; parsing and validation also run in workers with one awaited logical item at a time. Bounded tables still retain distinct payload bytes and routing metadata, and the encoded records/ZIP/AES bodies are whole bounded buffers. Installed cryptography 2.9.0 stream-shaped methods buffer messages: this implementation makes **no bounded streaming AES or fixed peak-memory claim**. The archive codec's KDF/AES/ZIP work runs off the UI isolate. Task 13 must measure full-store size, peak memory, duration and cancellation on devices for the complete manager store with 100 staff and 10000 external receipt imports, including its actual operations/history. Staff stores are separate. Same-store capture+import and all-reviewed 10000-event cases are not guaranteed to fit. Overflow is explicit and preserves the previous encrypted backup and source.

## Inspection, acceptance and persistence

Selected bytes are actually counted up to 64 MiB and never deleted by the service. The native host separately owns/disposes its selected staging copy. Authentication, ZIP checks, all hashes/counts/scope/lineage/recovery checks complete before preview. Inspection files are re-encrypted under a unique restore vault; no plaintext employee or recovery files are staged on disk. Preview objects are identity-bound, tied to the original live session, and expire after five minutes. They do not grant authority.

Schema 3 adds `restore_jobs`, `restore_commits`, `restored_profiles` and `passive_scopes`; schema 1/2 upgrade without rewriting data. Restore jobs are installation-local I/O intents and are excluded from archives. Their encrypted bodies contain staging entries, planned key allocations and attachment move evidence, under a separate OS-keystore staging vault. SQLite FULL commits precede side effects. Errors before logical acceptance roll back DB/profile/gate changes and unrelated proven-owned recovery allocations; startup resolves interrupted jobs. Public discard uses the same apply/recovery coordinator and awaits any active operation before inspection cleanup; route-finally navigation cleanup cannot erase an applying journal. Completely published immutable attachments are always retained because another valid writer may already reference them. Once written, every newly allocated shared scope vault is retained on rollback, even without restore-owned move evidence: a normal writer may already have used it for a reused or independently published object/record. Retry authenticates and hash-validates identical content before reuse. This may leave encrypted orphan storage and unused shared scope keys; future GC requires leases/reference coordination. Retention does not activate an identity/authority or establish a successful backup. A key write interrupted before its durable ownership acknowledgment is conservatively left untouched rather than guessed to be disposable. After logical acceptance, the durable matching archive-ID/whole-manifest-SHA256 receipt (binding every file hash including recovery metadata) makes cleanup retain committed resources. A different archive reusing an ID cannot masquerade as accepted.

All logical rows, saved operation results, journals, associations, attachment references, passive profiles, creation reservations, revision maps and passive gates are inserted in one DB transaction. Existing exact identities may replay; incompatible record/revision/operation/root/authority provenance is a conflict, never renumbered or overwritten. `newInstallation` rejects an already existing company unless this exact archive has already committed. Both choices leave newly restored scopes passive. Central repository `commit` and `prepare` reject every writer for a passive scope, covering management, enrollment, capture and attendance. Task 10 provides no activation bypass.

File contents use OS flush before publication. Directory rename/create durability is explicitly synchronized through POSIX `open(O_RDONLY)`, `fsync`, `close` (Android `libc.so`; iOS/macOS/Linux process libc). This is exercised on the development macOS host; Android/iOS runtime symbols, actual provider/storage/power-loss behavior and physical recovery remain Task 13 gates. Unsupported OS fails before lazy libc initialization. Null malloc, failed open or nonzero fsync is a storage failure; missing symbols/libraries are mapped to storage failure by the service. close runs in finally (its return is ignored), free always runs, and there is no errno retry or durability fallback. Ordinary rename or archive-package flush alone is not claimed durable.

The encrypted private backup catalog is updated only after the new file is complete. Previous successful archive files are retained on failure. The UI shows the private location, **Created in this app**, and a separate user-confirmed external saved-copy state. Opening a share sheet is not external persistence. The archive passphrase is never saved. Internal archives do not survive uninstall.
