/// Protective v1 transport limits, applied to the final UTF-8 envelope.
abstract final class MessageLimits {
  static const qrBytes = 1500;
  static const fileBytes = 65536;
  static const nameCharacters = 120;
  static const invitationLabelCharacters = 40;
  static const reasonCharacters = 500;
  static const maxInteger = 9007199254740991;
  static const maxUtcMs = 8640000000000000;
}
