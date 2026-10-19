import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../contracts/context.dart';
import '../contracts/result.dart';
import '../identity/key_service.dart';
import '../messaging/message_types.dart';
import '../messaging/message_verifier.dart';

/// Public certificates only. A routing fingerprint is never a trust anchor.
final class AuthorityHistoryFile {
  AuthorityHistoryFile._(
    this.companyId,
    this.rootFingerprint,
    this.certificates,
  );
  final String companyId, rootFingerprint;
  final List<AuthorityCertificate> certificates;
  static const maxBytes = 65536, maxCertificates = 128;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final _hex = RegExp(r'^[0-9a-f]{64}$');

  static AuthorityHistoryFile decode(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const CheckException(CheckError.limitExceeded);
    }
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      // Check nesting before recursive JSON decoding. The exact grammar needs
      // only top-level, certificate-list and certificate arrays.
      var depth = 0, quoted = false, escaped = false;
      for (final c in text.codeUnits) {
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (c == 92) {
            escaped = true;
          } else if (c == 34) {
            quoted = false;
          }
        } else if (c == 34) {
          quoted = true;
        } else if (c == 91 || c == 123) {
          if (++depth > 3) throw const CheckException(CheckError.malformed);
        } else if (c == 93 || c == 125) {
          if (--depth < 0) throw const CheckException(CheckError.malformed);
        }
      }
      final j = jsonDecode(text);
      if (j is! List ||
          j.length != 5 ||
          j[0] != 'RAZE_CHECK_AUTHORITY_HISTORY' ||
          j[1] is! int ||
          j[1] != 1 ||
          j[2] is! String ||
          !_uuid.hasMatch(j[2] as String) ||
          j[3] is! String ||
          !_hex.hasMatch(j[3] as String) ||
          j[4] is! List) {
        throw const CheckException(CheckError.malformed);
      }
      final list = j[4] as List;
      if (list.isEmpty || list.length > maxCertificates) {
        throw const CheckException(CheckError.limitExceeded);
      }
      return AuthorityHistoryFile._(
        j[2] as String,
        j[3] as String,
        List.unmodifiable(
          list.map((c) => AuthorityCertificate(List<Object?>.from(c as List))),
        ),
      );
    } on CheckException {
      rethrow;
    } catch (_) {
      throw const CheckException(CheckError.malformed);
    }
  }

  /// Returns a new linear history without changing any caller state. Callers
  /// persist this atomically, or quarantine authenticated competing evidence.
  Future<List<AuthorityCertificate>> verify(
    KeyService keys,
    TrustContext pinned,
  ) async {
    if (companyId != pinned.companyId) {
      throw const CheckException(CheckError.wrongCompany);
    }
    final actual = (await Sha256().hash(
      pinned.rootPublicKey,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (actual != rootFingerprint) {
      throw const CheckException(CheckError.invalidSignature);
    }
    final accepted = <String, AuthorityCertificate>{};
    final children = <String?, String>{};
    Future<void> add(AuthorityCertificate a) async {
      if (!await keys.verify(
        a.signingBytes,
        a.signature,
        pinned.rootPublicKey,
      )) {
        throw const CheckException(CheckError.invalidSignature);
      }
      final old = accepted[a.generationId];
      if (old != null) {
        if (jsonEncode(old.values) != jsonEncode(a.values)) {
          throw const CheckException(CheckError.recoveryRequired);
        }
        return;
      }
      final parent = a.parentGenerationId;
      if (parent != null) {
        final previous = accepted[parent];
        if (previous == null) {
          throw const CheckException(CheckError.unknownIssuer);
        }
        if (a.sequence != previous.sequence + 1 ||
            a.issuedAtUtcMs < previous.issuedAtUtcMs) {
          throw const CheckException(CheckError.invalidTransition);
        }
      }
      if (children.containsKey(parent)) {
        throw const CheckException(CheckError.recoveryRequired);
      }
      children[parent] = a.generationId;
      accepted[a.generationId] = a;
    }

    final known = [...pinned.authorities]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final a in known) {
      await add(a);
    }
    for (final a in certificates) {
      await add(a);
    }
    return List.unmodifiable(accepted.values);
  }

  static List<Uint8List> batches(
    String companyId,
    String fingerprint,
    List<AuthorityCertificate> ordered,
  ) {
    final output = <Uint8List>[];
    for (var start = 0; start < ordered.length;) {
      var end = (start + maxCertificates).clamp(0, ordered.length);
      late Uint8List bytes;
      while (true) {
        bytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode([
              'RAZE_CHECK_AUTHORITY_HISTORY',
              1,
              companyId,
              fingerprint,
              ordered.sublist(start, end).map((a) => a.values).toList(),
            ]),
          ),
        );
        if (bytes.length <= maxBytes) break;
        if (--end == start) {
          throw const CheckException(CheckError.limitExceeded);
        }
      }
      decode(bytes);
      output.add(bytes);
      start = end;
    }
    return List.unmodifiable(output);
  }
}

abstract interface class AuthorityHistoryService {
  Future<List<Uint8List>> exportHistory(
    SessionHandle session,
    String companyId,
  );
  Future<void> importHistory(
    SessionHandle session,
    String companyId,
    Uint8List bytes,
  );
}

/// Opaque, live consent; never serializable or recoverable after restart.
abstract interface class InvitationCandidate {}

abstract interface class InvitationHistoryService {
  Future<VerifiedMessage> verifyInvitationCandidate(
    SessionHandle session,
    InvitationCandidate candidate,
  );
  Future<InvitationCandidate> beginInvitation(
    SessionHandle session,
    Uint8List bytes, {
    required String acceptedRootFingerprint,
  });
  Future<void> stageHistory(
    SessionHandle session,
    InvitationCandidate candidate,
    Uint8List bytes,
  );
  Future<VerifiedMessage> finishInvitation(
    SessionHandle session,
    InvitationCandidate candidate,
  );
  void cancelInvitation(InvitationCandidate candidate);
}
