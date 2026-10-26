import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget section(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: text.bodyMedium),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('About Tanim')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          section(
            'What it does',
            'Tanim ("to plant") looks at a photo of one rice leaf and says whether it shows bacterial leaf blight, '
                'blast, brown spot or tungro, or looks healthy. Everything runs on your phone, so it works without signal.',
          ),
          section(
            'How it works',
            'A small neural network (MobileNetV3, 3.4 MB) was trained on about 2,300 labelled leaf photos. '
                'The heatmap shows which parts of the photo shaped its answer.',
          ),
          section(
            'What it gets wrong',
            'The training photos come from India and Bangladesh, not the Philippines. Tested on photos from a '
                'source it had never seen, it was right only 32–61% of the time, partly because it learned to use '
                'backgrounds as a clue. Photos from Filipino farms are needed to fix this.',
          ),
          section(
            'Photo credits',
            'Sethy et al. (2020), Rice Leaf Disease Image Samples; RiceLeafBD; RiceLeafDisease-BD5. '
                'All from Mendeley Data under CC BY 4.0.',
          ),
          section(
            'Not a diagnosis',
            'Before spraying or pulling plants, check with your Municipal Agriculture Office.',
          ),
        ],
      ),
    );
  }
}
