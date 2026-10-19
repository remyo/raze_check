import 'dart:convert';
import 'dart:typed_data';
import '../contracts/result.dart';
import '../identity/key_service.dart';
import 'message_types.dart';

/// An enrolled or historical staff credential, obtained from verified grants.
/// Retirement is reported without destroying authentic historical signatures.
final class TrustedCredential {
  TrustedCredential({
    required this.companyId,
    required this.personId,
    required this.employeeId,
    required this.installationId,
    required this.membershipId,
    required this.membershipRevision,
    required this.authorityGenerationId,
    required Uint8List publicKey,
    this.retired = false,
  }) : _publicKey = Uint8List.fromList(publicKey);
  final String companyId, personId, employeeId, installationId, membershipId;
  final String authorityGenerationId;
  final int membershipRevision;
  final bool retired;
  final Uint8List _publicKey;
  Uint8List get publicKey => Uint8List.fromList(_publicKey);
}

/// Supplied by enrollment/storage, never populated from an arbitrary incoming
/// key. First use requires the caller's explicit root fingerprint acceptance.
final class TrustContext {
  TrustContext({
    required this.companyId,
    required Uint8List rootPublicKey,
    required List<AuthorityCertificate> authorities,
    List<TrustedCredential> credentials = const [],
  }) : _rootPublicKey = Uint8List.fromList(rootPublicKey),
       authorities = List.unmodifiable(authorities),
       credentials = List.unmodifiable(credentials);
  final String companyId;
  final Uint8List _rootPublicKey;
  Uint8List get rootPublicKey => Uint8List.fromList(_rootPublicKey);
  final List<AuthorityCertificate> authorities;
  final List<TrustedCredential> credentials;
}

final class VerifiedMessage {
  const VerifiedMessage._(
    this.message, {
    this.proofOfPossessionOnly = false,
    this.historicalCredential = false,
  });
  final SignedMessage message;
  final bool proofOfPossessionOnly;

  /// A valid signature is not permission to perform new activity.
  final bool historicalCredential;
}

final class MessageVerifier {
  MessageVerifier(this.keys);
  final KeyService keys;

  Future<VerifiedMessage> verify(
    SignedMessage message,
    TrustContext trust,
  ) async {
    final p = message.payload;
    if (p.companyId != trust.companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    if (message.kind == MessageKind.joinRequest ||
        message.kind == MessageKind.replacementRequest) {
      final field = message.kind == MessageKind.joinRequest
          ? 'publicKeyBase64Url'
          : 'newPublicKeyBase64Url';
      final public = decodeMessageBase64(
        p.field<String>(field),
        byteLength: 32,
      );
      await _signature(message, public);
      return VerifiedMessage._(message, proofOfPossessionOnly: true);
    }

    final history = await _history(trust);
    if (message.kind == MessageKind.attendance ||
        message.kind == MessageKind.correctionRequest) {
      final candidates = <TrustedCredential>[];
      for (final candidate in trust.credentials) {
        if (candidate.companyId == trust.companyId &&
            await messageKeyId(candidate.publicKey) == message.keyId) {
          candidates.add(candidate);
        }
      }
      if (candidates.isEmpty) {
        throw const CheckException(CheckError.unknownIssuer);
      }
      await _signature(message, candidates.first.publicKey);
      final matching = candidates
          .where(
            (c) =>
                p.field<String>('employeeId') == c.employeeId &&
                (message.kind == MessageKind.correctionRequest ||
                    (p.field<String>('personId') == c.personId &&
                        p.field<String>('installationId') == c.installationId &&
                        p.field<String>('membershipId') == c.membershipId &&
                        p.field<int>('membershipRevision') ==
                            c.membershipRevision &&
                        p.field<String>('membershipAuthorityGenerationId') ==
                            c.authorityGenerationId)),
          )
          .toList();
      if (matching.isEmpty) throw const CheckException(CheckError.unauthorized);
      if (!matching.any((c) => history.containsKey(c.authorityGenerationId))) {
        throw const CheckException(CheckError.unknownIssuer);
      }
      return VerifiedMessage._(
        message,
        historicalCredential: matching.every((c) => c.retired),
      );
    }

    final field = message.kind == MessageKind.authorityTransfer
        ? 'sourceAuthority'
        : 'authority';
    final authority = AuthorityCertificate(p.field<List<Object?>>(field));
    await _certificate(authority, trust, history);
    await _signature(message, authority.publicKey);
    if (p.issuedAtUtcMs < authority.issuedAtUtcMs) {
      throw const CheckException(CheckError.invalidTransition);
    }
    if (message.kind == MessageKind.invitation &&
        !_equal(
          decodeMessageBase64(
            p.field<String>('rootPublicKeyBase64Url'),
            byteLength: 32,
          ),
          trust.rootPublicKey,
        )) {
      throw const CheckException(CheckError.invalidSignature);
    }
    if (message.kind == MessageKind.authorityTransfer) {
      final next = AuthorityCertificate(
        p.field<List<Object?>>('nextAuthority'),
      );
      if (next.parentGenerationId != authority.generationId ||
          next.sequence != authority.sequence + 1 ||
          next.installationId == authority.installationId) {
        throw const CheckException(CheckError.invalidTransition);
      }
      await _certificate(next, trust, {
        ...history,
        authority.generationId: authority,
      });
    }
    return VerifiedMessage._(message);
  }

  Future<void> _signature(SignedMessage message, Uint8List public) async {
    if (await messageKeyId(public) != message.keyId ||
        !await keys.verify(message.signingBytes, message.signature, public)) {
      throw const CheckException(CheckError.invalidSignature);
    }
  }

  Future<Map<String, AuthorityCertificate>> _history(TrustContext trust) async {
    final history = <String, AuthorityCertificate>{};
    for (final authority in trust.authorities) {
      final prior = history[authority.generationId];
      if (prior != null &&
          jsonEncode(prior.values) != jsonEncode(authority.values)) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      history[authority.generationId] = authority;
    }
    for (final authority in history.values) {
      await _certificate(authority, trust, history);
      // Following parent pointers must terminate at a verified root; the
      // sequence decrement plus positive bound precludes cycles.
    }
    return history;
  }

  Future<void> _certificate(
    AuthorityCertificate authority,
    TrustContext trust,
    Map<String, AuthorityCertificate> history,
  ) async {
    if (!await keys.verify(
      authority.signingBytes,
      authority.signature,
      trust.rootPublicKey,
    )) {
      throw const CheckException(CheckError.invalidSignature);
    }
    final known = history[authority.generationId];
    if (known != null &&
        jsonEncode(known.values) != jsonEncode(authority.values)) {
      throw const CheckException(CheckError.recoveryRequired);
    }
    final parentId = authority.parentGenerationId;
    if (parentId == null) {
      if (history.values.any(
        (a) =>
            a.parentGenerationId == null &&
            a.generationId != authority.generationId,
      )) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      return;
    }
    final parent = history[parentId];
    if (parent == null) throw const CheckException(CheckError.unknownIssuer);
    if (authority.sequence != parent.sequence + 1 ||
        authority.issuedAtUtcMs < parent.issuedAtUtcMs) {
      throw const CheckException(CheckError.invalidTransition);
    }
    if (history.values.any(
      (a) =>
          a.parentGenerationId == parentId &&
          a.generationId != authority.generationId,
    )) {
      throw const CheckException(CheckError.recoveryRequired);
    }
  }
}

bool _equal(List<int> a, List<int> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
