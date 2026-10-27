import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tanim/app.dart';
import 'package:tanim/core/theme/theme_mode_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } on Exception {
    prefs = null; // the app still works; the appearance choice just isn't saved
  }
  runApp(ProviderScope(overrides: [preferencesProvider.overrideWithValue(prefs)], child: const TanimApp()));
}
