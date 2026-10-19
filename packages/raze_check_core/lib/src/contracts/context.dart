/// Opaque, in-memory capability issued by the active identity service.
///
/// Implementations expose no credentials or serialized representation. The
/// issuing service must validate the exact handle object against its live
/// session registry on every authorized action. Implementing this interface,
/// reconstructing JSON, or retaining an expired handle never grants access.
abstract interface class SessionHandle {}

/// Company and concurrency scope captured when a command starts.
///
/// Actor identity and permissions are resolved from [session], never supplied
/// as a caller-selected role. Async completions must recheck this original
/// context rather than substituting the currently selected company.
final class CommandContext {
  const CommandContext({
    required this.companyId,
    required this.session,
    required this.operationId,
    required this.authorityGenerationId,
    this.expectedRevision,
  });

  final String companyId;
  final SessionHandle session;
  final String operationId;
  final String authorityGenerationId;
  final int? expectedRevision;
}
