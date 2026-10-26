import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tanim/core/router/app_router.dart';
import 'package:tanim/core/theme/app_theme.dart';

class TanimApp extends StatefulWidget {
  const TanimApp({super.key, this.router});

  /// Tests pass their own router; the app builds the real one.
  final GoRouter? router;

  @override
  State<TanimApp> createState() => _TanimAppState();
}

class _TanimAppState extends State<TanimApp> {
  late final GoRouter _router = widget.router ?? buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Tanim',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: _router,
    );
  }
}
