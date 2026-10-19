import '../contracts/context.dart';
import '../contracts/capability.dart';
import '../contracts/result.dart';
import 'company_models.dart';

abstract interface class CompanyService {
  Future<List<OperatorChoice>> operatorChoices();
  Future<CommandResult<Company>> createCompany(
    SessionHandle session,
    CompanyDraft draft,
    String operationId,
  );
  Future<List<Company>> listCompanies(SessionHandle session);
  Future<Company?> readCompany(SessionHandle session, String companyId);
  Future<Membership?> membership(SessionHandle session, String companyId);
  Future<List<StaffRecord>> listStaff(SessionHandle session, String companyId);
  Future<List<Membership>> listMemberships(
    SessionHandle session,
    String companyId,
  );
  Future<CommandResult<StaffRecord>> createStaff(
    CommandContext context,
    StaffDraft draft,
  );
  Future<CommandResult<StaffRecord>> updateStaff(
    CommandContext context,
    StaffUpdate update,
  );
  Future<CommandResult<Membership>> grantCapabilities(
    CommandContext context,
    String membershipId,
    Set<Capability> capabilities,
  );
  Future<CommandResult<OperatorCredential>> activateOperator(
    CommandContext context,
    String membershipId,
    String passphrase,
  );
  Future<CommandResult<Membership>> deactivateStaff(
    CommandContext context,
    String employeeId,
    String reason,
  );
  Future<SessionHandle> unlockOperator(
    String companyId,
    String membershipId,
    String passphrase,
  );
}
