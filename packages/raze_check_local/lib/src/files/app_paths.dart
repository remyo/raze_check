import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:raze_check_core/raze_check_core.dart';

/// Private persistent files; never cache, user documents, or raw host DB handles.
final class AppPaths {
  AppPaths(this.root);
  final Directory root;
  File get database => File('${root.path}/checks.sqlite');
  File get catalog => File('${root.path}/profiles.v1.enc');
  static Future<AppPaths> persistent() async {
    try {
      final support = await getApplicationSupportDirectory();
      final root = await Directory(
        '${support.path}/raze_check',
      ).create(recursive: true);
      if (Platform.isIOS) {
        await const MethodChannel(
          'com.remyo.razecheck/private_storage',
        ).invokeMethod<void>('excludeFromBackup', root.path);
      }
      return AppPaths(root);
    } catch (_) {
      throw const CheckException(CheckError.storageFailure);
    }
  }
}
