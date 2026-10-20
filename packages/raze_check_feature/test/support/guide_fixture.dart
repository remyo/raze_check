import 'package:raze_check_core/raze_check_core.dart';
import 'package:raze_check_feature/src/guides/guide_models.dart';

class MemoryGuideProgressStore implements GuideProgressStore {
  MemoryGuideProgressStore({
    GuideProgressSnapshot? snapshot,
    this.failRead = false,
    this.failWrite = false,
  }) : snapshot = snapshot ?? GuideProgressSnapshot();
  GuideProgressSnapshot snapshot;
  int writes = 0;
  bool failRead, failWrite;
  @override
  Future<GuideProgressSnapshot> read() async {
    if (failRead) throw StateError('read');
    return snapshot;
  }

  @override
  Future<void> write(GuideProgressSnapshot value) async {
    if (failWrite) throw StateError('write');
    snapshot = value;
    writes++;
  }

  @override
  Future<void> flush() async {}
}

GuideContext testGuideContext({
  Object? token,
  Object? authorityToken,
  GuideDestination? destination,
  Map<String, String> variants = const {'welcome': 'public'},
  Future<void> Function()? validateCurrent,
  Map<GuideDestination, Future<void> Function()> navigation = const {},
}) => GuideContext(
  token: token ?? Object(),
  authorityToken: authorityToken ?? Object(),
  audience: GuideAudience(variants: variants),
  validateCurrent: validateCurrent ?? () async {},
  destination: destination,
  navigation: navigation,
);
