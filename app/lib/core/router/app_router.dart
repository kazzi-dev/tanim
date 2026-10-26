import 'package:go_router/go_router.dart';
import 'package:tanim/features/about/about_screen.dart';
import 'package:tanim/features/scan/presentation/result_screen.dart';
import 'package:tanim/features/scan/presentation/scan_screen.dart';

abstract final class Routes {
  static const scan = '/';
  static const result = '/result';
  static const about = '/about';
}

GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(path: Routes.scan, builder: (_, _) => const ScanScreen()),
    GoRoute(
      path: Routes.result,
      builder: (_, state) => ResultScreen(photoPath: state.extra! as String),
    ),
    GoRoute(path: Routes.about, builder: (_, _) => const AboutScreen()),
  ],
);
