import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as time_zones;

import 'app/check_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  time_zones.initializeTimeZones();
  runApp(const ProviderScope(child: CheckApp()));
}
