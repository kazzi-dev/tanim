import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tanim/core/router/app_router.dart';
import 'package:tanim/core/theme/app_theme.dart';
import 'package:tanim/core/theme/theme_mode_controller.dart';

class TanimApp extends ConsumerStatefulWidget {
  const TanimApp({super.key, this.router, this.themeMode});

  /// Tests pass their own router; the app builds the real one.
  final GoRouter? router;

  /// Tests and screenshots can force a mode; otherwise the saved setting wins.
  final ThemeMode? themeMode;

  @override
  ConsumerState<TanimApp> createState() => _TanimAppState();
}

class _TanimAppState extends ConsumerState<TanimApp> {
  late final GoRouter _router = widget.router ?? buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tanim',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: widget.themeMode ?? ref.watch(themeModeProvider),
      routerConfig: _router,
    );
  }
}
