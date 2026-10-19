import 'dart:io';
import 'package:raze_check_local/raze_check_local.dart';

Future<AppPaths> tempPaths() async =>
    AppPaths(await Directory.systemTemp.createTemp('raze-security-'));
