import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:raze_check_core/raze_check_core.dart';
import '../database/local_check_repository.dart';
import '../security/local_key_service.dart';
import '../security/secure_key_store.dart';

/// Query-only, kind-scoped reads. Never use this inside a transaction callback.
final class RepositoryReadView implements ReadView {
  RepositoryReadView(this.repository, this.companyId);
  final CheckRepository repository;
  final String companyId;
  @override
  Future<StoredRecord?> read(String id) => repository.read(companyId, id);
  @override
  Future<List<StoredRecord>> list(String kind) async {
    if (repository case final LocalCheckRepository local) {
      return local.listRecords(companyId, kind);
    }
    final s = await repository.snapshot(CompanyScope(companyId));
    return [
      ...s.records,
      ...s.events,
      ...s.outbox,
      ...s.authorityHistory,
    ].where((r) => r.kind == kind).toList();
  }
}

Future<List<AuthorityCertificate>> acceptedAuthorities(
  ReadView view,
  AuthorityCertificate fallback,
) async {
  final byId = <String, AuthorityCertificate>{};
  for (final r in await view.list('authority')) {
    final a = AuthorityCertificate(
      List<Object?>.from(jsonDecode(utf8.decode(r.payload)) as List),
    );
    byId[a.generationId] = a;
  }
  final existing = byId[fallback.generationId];
  if (existing != null &&
      jsonEncode(existing.values) != jsonEncode(fallback.values)) {
    throw const CheckException(CheckError.recoveryRequired);
  }
  byId[fallback.generationId] = fallback;
  return byId.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
}

Future<TrustContext> companyTrust(Company c, ReadView view) async =>
    TrustContext(
      companyId: c.id,
      rootPublicKey: base64Url.decode(c.rootPublicKey),
      authorities: await acceptedAuthorities(
        view,
        AuthorityCertificate(c.authority),
      ),
    );
Future<TrustContext> pinTrust(
  String company,
  Map<String, dynamic> pin,
  ReadView view,
) async => TrustContext(
  companyId: company,
  rootPublicKey: base64Url.decode(pin['rootPublicKey'] as String),
  authorities: await acceptedAuthorities(
    view,
    AuthorityCertificate(List<Object?>.from(pin['authority'] as List)),
  ),
);

final class LocalAuthorityHistoryService implements AuthorityHistoryService {
  LocalAuthorityHistoryService({
    required this.repository,
    required this.identity,
    required SecureKeyStore keys,
    required this.ids,
  }) : signing = LocalKeyService(keys);
  final CheckRepository repository;
  final IdentityService identity;
  final KeyService signing;
  final IdGenerator ids;
  Future<TrustContext> trust(
    SessionHandle session,
    String company,
    ReadView view,
  ) async {
    final a = identity.requireActor(session);
    a.requireCompany(company);
    if (a.restrictedCompanyId != null && a.restrictedCompanyId != company) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final pin = await view.read('enrollment-trust:${a.personId}');
    if (pin != null) {
      return pinTrust(
        company,
        Map<String, dynamic>.from(jsonDecode(utf8.decode(pin.payload)) as Map),
        view,
      );
    }
    final index = await view.read('member-index:${a.personId}');
    final member = index == null
        ? null
        : await view.read(
            (jsonDecode(utf8.decode(index.payload)) as Map)['membershipId']
                as String,
          );
    if (member == null) throw const CheckException(CheckError.unknownIssuer);
    AccessPolicy(identity).requireMembership(
      a,
      Membership.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(utf8.decode(member.payload)) as Map,
        ),
      ),
    );
    final row = await view.read(company);
    if (row == null) throw const CheckException(CheckError.unknownIssuer);
    return companyTrust(
      Company.fromJson(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(row.payload)) as Map),
      ),
      view,
    );
  }

  @override
  Future<List<Uint8List>> exportHistory(
    SessionHandle session,
    String companyId,
  ) async {
    final t = await trust(
      session,
      companyId,
      RepositoryReadView(repository, companyId),
    );
    final hash = (await Sha256().hash(
      t.rootPublicKey,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final batches = AuthorityHistoryFile.batches(
      companyId,
      hash,
      t.authorities,
    );
    var checked = <AuthorityCertificate>[];
    for (final bytes in batches) {
      checked = await AuthorityHistoryFile.decode(bytes).verify(
        signing,
        TrustContext(
          companyId: companyId,
          rootPublicKey: t.rootPublicKey,
          authorities: checked,
        ),
      );
    }
    identity.requireActor(session);
    return batches;
  }

  @override
  Future<void> importHistory(
    SessionHandle session,
    String companyId,
    Uint8List bytes,
  ) async {
    final a = identity.requireActor(session),
        file = AuthorityHistoryFile.decode(bytes);
    if (file.companyId != companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final initial = await trust(
      session,
      companyId,
      RepositoryReadView(repository, companyId),
    );
    final digest = Uint8List.fromList((await Sha256().hash(bytes)).bytes);
    var conflict = false;
    final result = await repository.commit(
      CommandContext(
        companyId: companyId,
        session: session,
        operationId: 'history:${base64UrlEncode(digest)}:${a.personId}',
        authorityGenerationId: initial.authorities.first.generationId,
      ),
      requestDigest: digest,
      authorize: (view) async {
        await trust(session, companyId, view);
      },
      beforeCommit: () => identity.requireActor(session),
      build: (view) async {
        final t = await trust(session, companyId, view);
        List<AuthorityCertificate> chain;
        try {
          chain = await file.verify(signing, t);
        } on CheckException catch (e) {
          if (e.code != CheckError.recoveryRequired) rethrow;
          // Retain only genuinely root-authenticated branch evidence. A forged
          // certificate anywhere in the batch cannot plant a conflict gate.
          for (final c in file.certificates) {
            if (!await signing.verify(
              c.signingBytes,
              c.signature,
              t.rootPublicKey,
            )) {
              throw const CheckException(CheckError.invalidSignature);
            }
          }
          conflict = true;
          final row = StoredRecord(
            'authority-conflict:${base64UrlEncode(digest)}',
            companyId,
            'authorityConflict',
            1,
            bytes,
          );
          return Mutation(
            [],
            [row],
            [],
            row,
            personalRecords: [PersonalRecordAssociation(a.personId, row.id)],
          );
        }
        final rows = <StoredRecord>[];
        for (final c in chain) {
          if (await view.read(c.generationId) == null) {
            rows.add(
              StoredRecord(
                c.generationId,
                companyId,
                'authority',
                1,
                Uint8List.fromList(utf8.encode(jsonEncode(c.values))),
              ),
            );
          }
        }
        final receipt = StoredRecord(
          'history-import:${base64UrlEncode(digest)}',
          companyId,
          'authorityHistoryImport',
          1,
          Uint8List.fromList(utf8.encode(jsonEncode({'accepted': true}))),
        );
        return Mutation(
          [],
          [],
          [],
          receipt,
          authorityHistory: rows,
          personalRecords: [
            for (final c in chain)
              PersonalRecordAssociation(a.personId, c.generationId),
          ],
        );
      },
    );
    if (result case Rejected<StoredRecord>(:final error)) {
      throw CheckException(error);
    }
    if (result is! Committed<StoredRecord>) {
      throw const CheckException(CheckError.invalidTransition);
    }
    if (conflict || result.value.kind == 'authorityConflict') {
      throw const CheckException(CheckError.recoveryRequired);
    }
  }
}

/// A validated business transition can reveal that this installation's local
/// manager generation is stale. Public history alone never chooses a head.
Future<void> requireCurrentManagement(Company company, ReadView view) async {
  final current = AuthorityCertificate(company.authority);
  for (final row in await view.list('remoteAuthority')) {
    final data = jsonDecode(utf8.decode(row.payload)) as Map;
    final known = AuthorityCertificate(
      List<Object?>.from(data['authority'] as List),
    );
    if (known.sequence > current.sequence ||
        (known.sequence == current.sequence &&
            known.generationId != current.generationId)) {
      throw const CheckException(CheckError.recoveryRequired);
    }
  }
}

/// Called only after a verified ordinary business transition, in its write
/// transaction. Historical returns may be accepted but never lower knowledge.
Future<StoredRecord?> observeBusinessAuthority(
  String companyId,
  String personId,
  AuthorityCertificate authority,
  ReadView view, {
  List<AuthorityCertificate> staged = const [],
}) async {
  final known = await view.read(authority.generationId);
  if ((known == null ||
          known.kind != 'authority' ||
          utf8.decode(known.payload) != jsonEncode(authority.values)) &&
      !staged.any(
        (a) => jsonEncode(a.values) == jsonEncode(authority.values),
      )) {
    throw const CheckException(CheckError.unknownIssuer);
  }
  final id = 'remote-authority:$personId',
      prior = await view.read('remote-authority:$personId');
  if (prior != null) {
    final previous = AuthorityCertificate(
      List<Object?>.from(
        (jsonDecode(utf8.decode(prior.payload)) as Map)['authority'] as List,
      ),
    );
    if (previous.sequence > authority.sequence) return null;
    if (previous.sequence == authority.sequence) {
      if (jsonEncode(previous.values) != jsonEncode(authority.values)) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      return null;
    }
  }
  return StoredRecord(
    id,
    companyId,
    'remoteAuthority',
    (prior?.revision ?? 0) + 1,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({'personId': personId, 'authority': authority.values}),
      ),
    ),
  );
}
