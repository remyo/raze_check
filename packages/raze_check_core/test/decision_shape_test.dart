import 'package:raze_check_core/raze_check_core.dart';
import 'package:test/test.dart';
import 'support/message_vectors.dart';

void main() {
  test(
    'decision independently encodes correction and review with exact conditional shape',
    () async {
      final v = await MessageVectors.create();
      final old = v.payload(MessageKind.attendanceDecision);
      final p = List<Object?>.of(old);
      expect(
        () => MessagePayload(MessageKind.attendanceDecision, p),
        returnsNormally,
      );
      p[7] = 'pending';
      expect(
        () => MessagePayload(MessageKind.attendanceDecision, p),
        throwsA(isA<CheckException>()),
      );
      p[9] = old[5];
      p[11] = 'approved';
      expect(
        () => MessagePayload(MessageKind.attendanceDecision, p),
        returnsNormally,
      );
      p[11] = 'rejected';
      expect(
        () => MessagePayload(MessageKind.attendanceDecision, p),
        throwsA(isA<CheckException>()),
      );
      p[10] = old[3];
      expect(
        () => MessagePayload(MessageKind.attendanceDecision, p),
        returnsNormally,
      );
    },
  );
}
