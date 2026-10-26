import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tanim/core/router/app_router.dart';
import 'package:tanim/features/scan/application/scan_providers.dart';

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cameras = ref.watch(camerasProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (cameras) {
        AsyncData(:final value) when value.isNotEmpty => _CameraView(camera: _backCamera(value)),
        AsyncData() || AsyncError() => const _NoCameraView(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  static CameraDescription _backCamera(List<CameraDescription> cameras) =>
      cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
}

Future<void> _pickFromGallery(BuildContext context) async {
  final photo = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);
  if (photo != null && context.mounted) {
    await context.push(Routes.result, extra: photo.path);
  }
}

class _CameraView extends StatefulWidget {
  const _CameraView({required this.camera});
  final CameraDescription camera;

  @override
  State<_CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<_CameraView> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera in the background so other apps can use it.
    if (state == AppLifecycleState.inactive) {
      final old = _controller;
      setState(() => _controller = null);
      unawaited(old?.dispose());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    final controller = CameraController(widget.camera, ResolutionPreset.high, enableAudio: false);
    try {
      await controller.initialize();
      if (!mounted) return unawaited(controller.dispose());
      setState(() {
        _controller = controller;
        _error = null;
      });
    } on CameraException catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _error = e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt'
            ? 'Tanim needs the camera to scan leaves. Allow it in Settings, or pick a photo instead.'
            : 'The camera could not start. You can still pick a photo.';
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) await context.push(Routes.result, extra: photo.path);
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not take the photo. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (controller != null && controller.value.isInitialized)
          Center(child: CameraPreview(controller))
        else if (_error != null)
          _Message(text: _error!)
        else
          const Center(child: CircularProgressIndicator()),
        const _LeafGuide(),
        Align(
          alignment: Alignment.bottomCenter,
          child: _ControlBar(onShutter: controller == null || _busy ? null : _capture, busy: _busy),
        ),
      ],
    );
  }
}

/// The model looks at the centre square of the photo. In portrait that square
/// is as wide as the (centred, full-width) preview, so it sits in the middle of
/// the screen. Everything outside it is dimmed.
class _LeafGuide extends StatelessWidget {
  const _LeafGuide();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth;
        final top = (box.maxHeight - side) / 2;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _DimOutside(side: side)),
            ),
            const SafeArea(
              child: Padding(padding: EdgeInsets.only(top: 16), child: _TopBar()),
            ),
            Positioned(
              left: 24,
              right: 24,
              top: top + side + 16,
              child: const Text(
                'Fill the square with one leaf.\nDaylight works best.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, height: 1.4, shadows: [Shadow(blurRadius: 8)]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DimOutside extends CustomPainter {
  _DimOutside({required this.side});
  final double side;

  @override
  void paint(Canvas canvas, Size size) {
    final square = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: side - 4, height: side - 4),
      const Radius.circular(20),
    );
    canvas
      ..drawPath(
        Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(square)),
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      )
      ..drawRRect(
        square,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.9),
      );
  }

  @override
  bool shouldRepaint(_DimOutside old) => old.side != side;
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.eco, color: Colors.white),
          const SizedBox(width: 8),
          const Text(
            'Tanim',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'About Tanim',
            color: Colors.white,
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.push(Routes.about),
          ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.onShutter, required this.busy});
  final VoidCallback? onShutter;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              tooltip: 'Pick a photo',
              iconSize: 28,
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: () => _pickFromGallery(context),
            ),
            Semantics(
              button: true,
              label: 'Take photo',
              child: GestureDetector(
                onTap: onShutter,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: busy
                      ? const CircularProgressIndicator(color: Colors.white)
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: onShutter == null ? Colors.white38 : Colors.white,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 56),
          ],
        ),
      ),
    );
  }
}

class _NoCameraView extends StatelessWidget {
  const _NoCameraView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 16),
          const _TopBar(),
          const Spacer(),
          const _Message(text: 'No camera found on this device.\nPick a photo of a rice leaf instead.'),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: FilledButton.icon(
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Pick a photo'),
              onPressed: () => _pickFromGallery(context),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
        ),
      ),
    );
  }
}
