import 'dart:typed_data';
import '../messaging/message_types.dart';

/// A share result is transport UI feedback, never proof of delivery or backup.
enum ShareOutcome { opened, dismissed, unavailable, failed }

final class TransferException implements Exception {
  const TransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef TransferGuard = Future<void> Function();

abstract interface class TransferPort {
  Future<Uint8List?> scan({required Set<MessageKind> allowed});
  Future<Uint8List?> pickMessage();
  Future<Uint8List?> decodePickedImage();
  Future<ShareOutcome> shareMessage(Uint8List bytes, String suggestedName);
  Future<ShareOutcome> shareQrPng(Uint8List messageBytes);
}

/// Real native ports require the original authorization/visible-context guard.
/// Legacy byte ports remain usable by hosts without native transport.
abstract interface class ContextualMessagePort {
  Future<Uint8List?> receiveFor(Set<MessageKind> allowed, TransferGuard guard);
  Future<void> sendFor(Uint8List bytes, TransferGuard guard);
}
