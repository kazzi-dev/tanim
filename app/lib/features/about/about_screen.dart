import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tanim/core/theme/app_theme.dart';
import 'package:tanim/core/theme/theme_mode_controller.dart';
import 'package:tanim/core/widgets/ios.dart';

/// Settings and About, as an iOS-style grouped list.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    Widget text(String body) => Padding(
      padding: const EdgeInsets.all(16),
      child: Text(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.label)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          GroupedSection(
            header: 'Appearance',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: CupertinoSlidingSegmentedControl<ThemeMode>(
                  groupValue: mode,
                  onValueChanged: (m) => ref.read(themeModeProvider.notifier).set(m ?? ThemeMode.system),
                  children: const {
                    ThemeMode.system: Text('System'),
                    ThemeMode.light: Text('Light'),
                    ThemeMode.dark: Text('Dark'),
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          GroupedSection(
            header: 'What it does',
            children: [
              text(
                'Tanim ("to plant") looks at a photo of one rice leaf and says whether it shows bacterial leaf '
                'blight, blast, brown spot or tungro, or looks healthy. Everything runs on your phone, so it '
                'works without signal.',
              ),
            ],
          ),
          const SizedBox(height: 28),
          const GroupedSection(
            header: 'How well it works',
            footer: 'Photos from Filipino farms are needed to close the gap.',
            children: [
              GroupedRow(title: 'Test photos', trailing: _Value('97.6%')),
              GroupedRow(title: 'Photos from a new source', trailing: _Value('32–61%')),
              GroupedRow(title: 'Model size', trailing: _Value('3.4 MB')),
            ],
          ),
          const SizedBox(height: 28),
          GroupedSection(
            header: 'Help improve Tanim',
            children: [
              text(
                'Tap the bookmark on the camera screen, then Collect. Photograph rice leaves in the field and say '
                'what is on them; an agriculturist’s label is best. Photos stay on your phone until you export them.',
              ),
            ],
          ),
          const SizedBox(height: 28),
          const GroupedSection(
            header: 'About',
            footer: 'Not a diagnosis. Before spraying or pulling plants, check with your Municipal Agriculture Office.',
            children: [
              GroupedRow(title: 'Made by', trailing: _Value('Kazzi (Mark Nelson Gemina)')),
              GroupedRow(title: 'GitHub', trailing: _Value('github.com/kazzi-dev')),
              GroupedRow(
                title: 'Photo credits',
                subtitle: 'Sethy et al. (2020), RiceLeafBD, RiceLeafDisease-BD5. Mendeley Data, CC BY 4.0.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.value);
  final String value;

  @override
  Widget build(BuildContext context) =>
      Text(value, style: TextStyle(fontSize: 17, color: context.colors.secondaryLabel, letterSpacing: -0.3));
}
