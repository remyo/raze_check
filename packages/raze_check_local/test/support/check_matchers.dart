import 'package:raze_check_core/raze_check_core.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher throwsCheckError(CheckError code) =>
    throwsA(isA<CheckException>().having((e) => e.code, 'code', code));
