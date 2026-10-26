import 'package:go_router/go_router.dart';
import 'package:tanim/features/about/about_screen.dart';
import 'package:tanim/features/collect/presentation/collection_screen.dart';
import 'package:tanim/features/collect/presentation/label_screen.dart';
import 'package:tanim/features/scan/presentation/result_screen.dart';
import 'package:tanim/features/scan/presentation/scan_screen.dart';

abstract final class Routes {
  static const scan = '/';
  static const result = '/result';
  static const about = '/about';
  static const collection = '/collection';
  static const collect = '/collect';
  static const label = '/label';
}

GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(path: Routes.scan, builder: (_, _) => const ScanScreen()),
    GoRoute(
      path: Routes.result,
      builder: (_, state) => ResultScreen(photoPath: state.extra! as String),
    ),
    GoRoute(path: Routes.about, builder: (_, _) => const AboutScreen()),
    GoRoute(path: Routes.collection, builder: (_, _) => const CollectionScreen()),
    GoRoute(path: Routes.collect, builder: (_, _) => const ScanScreen(collect: true)),
    GoRoute(
      path: Routes.label,
      builder: (_, state) => LabelScreen(args: state.extra! as LabelArgs),
    ),
  ],
);
