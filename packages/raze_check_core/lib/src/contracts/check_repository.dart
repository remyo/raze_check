import 'dart:typed_data';
import 'context.dart';
import 'result.dart';

/// Opaque logical bytes. Payloads and collections are defensively immutable.
final class StoredRecord {
  StoredRecord(
    this.id,
    this.companyId,
    this.kind,
    this.revision,
    Uint8List payload,
  ) : payload = Uint8List.fromList(payload).asUnmodifiableView();
  final String id;
  final String companyId;
  final String kind;
  final int revision;
  final Uint8List payload;
}

/// Explicit service-authorized inclusion in a person's export, never inferred
/// from a company membership. The transaction supplies the original company ID.
final class PersonalRecordAssociation {
  const PersonalRecordAssociation(
    this.personId,
    this.recordId, {
    this.companyId,
  });
  final String personId;
  final String recordId;

  /// Populated in snapshots; mutation associations use the transaction company.
  final String? companyId;
}

/// Reference to immutable encrypted content addressed by the plaintext SHA-256.
/// The linked logical record controls personal-export inclusion.
final class AttachmentManifestEntry {
  const AttachmentManifestEntry({
    required this.companyId,
    required this.recordId,
    required this.sha256,
    required this.byteLength,
  });
  final String companyId;
  final String recordId;
  final String sha256;
  final int byteLength;
}

final class Mutation {
  Mutation(
    List<StoredRecord> records,
    List<StoredRecord> events,
    List<StoredRecord> outbox,
    this.result, {
    List<StoredRecord> authorityHistory = const [],
    List<StoredRecord> recovery = const [],
    List<AttachmentManifestEntry> attachments = const [],
    List<PersonalRecordAssociation> personalRecords = const [],
    Set<String> personalOperationOwners = const {},
  }) : records = List.unmodifiable(records),
       events = List.unmodifiable(events),
       outbox = List.unmodifiable(outbox),
       authorityHistory = List.unmodifiable(authorityHistory),
       recovery = List.unmodifiable(recovery),
       attachments = List.unmodifiable(attachments),
       personalRecords = List.unmodifiable(personalRecords),
       personalOperationOwners = Set.unmodifiable(personalOperationOwners);
  final List<StoredRecord> records;
  final List<StoredRecord> events;
  final List<StoredRecord> outbox;
  final StoredRecord result;
  final List<StoredRecord> authorityHistory;
  final List<StoredRecord> recovery;
  final List<AttachmentManifestEntry> attachments;
  final List<PersonalRecordAssociation> personalRecords;
  final Set<String> personalOperationOwners;
}

abstract interface class ReadView {
  Future<StoredRecord?> read(String id);
  Future<List<StoredRecord>> list(String kind);
}

sealed class ExportScope {
  const ExportScope();
}

final class PersonalScope extends ExportScope {
  const PersonalScope(this.personId);
  final String personId;
}

final class CompanyScope extends ExportScope {
  const CompanyScope(this.companyId);
  final String companyId;
}

/// A durable intent or completed result. No session credentials are persisted.
final class StoredOperation {
  StoredOperation({
    required this.companyId,
    required this.operationId,
    required this.authorityGenerationId,
    required Uint8List requestDigest,
    required this.expectedRevision,
    required this.revision,
    required this.result,
    Set<String> personalOwners = const {},
  }) : personalOwners = Set.unmodifiable(personalOwners),
       requestDigest = Uint8List.fromList(requestDigest).asUnmodifiableView();
  final String companyId;
  final String operationId;
  final String authorityGenerationId;
  final Uint8List requestDigest;
  final Set<String> personalOwners;
  final int? expectedRevision;
  final int? revision;
  final StoredRecord? result;
}

final class RevisionEntry {
  const RevisionEntry(this.companyId, this.revision, this.operationId);
  final String companyId;
  final int revision;
  final String operationId;
}

final class LogicalSnapshot {
  LogicalSnapshot({
    required this.scope,
    required Map<String, int> revisions,
    required List<StoredRecord> records,
    required List<StoredRecord> events,
    required List<StoredOperation> operations,
    required List<RevisionEntry> journal,
    required List<StoredRecord> outbox,
    required List<StoredRecord> authorityHistory,
    required List<StoredRecord> recovery,
    required List<AttachmentManifestEntry> attachments,
    List<PersonalRecordAssociation> personalRecords = const [],
  }) : personalRecords = List.unmodifiable(personalRecords),
       revisions = Map.unmodifiable(revisions),
       records = List.unmodifiable(records),
       events = List.unmodifiable(events),
       operations = List.unmodifiable(operations),
       journal = List.unmodifiable(journal),
       outbox = List.unmodifiable(outbox),
       authorityHistory = List.unmodifiable(authorityHistory),
       recovery = List.unmodifiable(recovery),
       attachments = List.unmodifiable(attachments);
  final ExportScope scope;
  final List<PersonalRecordAssociation> personalRecords;
  final Map<String, int> revisions;
  final List<StoredRecord> records;
  final List<StoredRecord> events;
  final List<StoredOperation> operations;
  final List<RevisionEntry> journal;
  final List<StoredRecord> outbox;
  final List<StoredRecord> authorityHistory;
  final List<StoredRecord> recovery;
  final List<AttachmentManifestEntry> attachments;
}

/// Storage is not an authorization boundary: services must validate the live
/// session, company permission and original async context before calling it.
abstract interface class CheckRepository {
  /// Digest is SHA-256 of normalized caller intent, excluding regenerated IDs,
  /// timestamps and signatures. A retry never executes [build] again.
  Future<CommandResult<StoredRecord>> commit(
    CommandContext context, {
    required Uint8List requestDigest,
    required Future<Mutation> Function(ReadView) build,
  });

  /// Persist an operation ID before queuing UI work. Builders must still be
  /// re-authorized on resume. Does not advance the committed revision.
  Future<void> prepare(
    CommandContext context, {
    required Uint8List requestDigest,
    Set<String> personalOwners = const {},
  });
  Future<List<StoredOperation>> pendingOperations(
    String companyId, {
    String? personId,
  });
  Future<StoredRecord?> read(String companyId, String recordId);
  Stream<int> watchRevision(String companyId);

  /// Protected format limits, not subscription limits. Scope objects do not
  /// confer permission. Services authorize before asking for a snapshot.
  Future<LogicalSnapshot> snapshot(
    ExportScope scope, {
    int maxBytes = 64 * 1024 * 1024,
    int maxEntries = 10000,
  });
}
