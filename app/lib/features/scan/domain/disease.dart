/// The five classes, in the same order as the model's output
/// (assets/model/labels.json; checked when the model loads).
enum Disease {
  bacterialLeafBlight(
    label: 'bacterial_leaf_blight',
    name: 'Bacterial leaf blight',
    cause: 'Bacteria (Xanthomonas oryzae pv. oryzae)',
    signs: 'Yellow to straw-coloured streaks that start at the leaf tip or edges and spread down, often with wavy margins.',
    steps: [
      'There is no spray that cures it, so save your money on fungicides.',
      'Go easy on nitrogen (urea) and use balanced fertilizer; heavy nitrogen makes it worse.',
      'Drain the field for a few days where you can, and avoid moving water from sick plots to healthy ones.',
      'Plough under or remove infected stubble and weeds after harvest.',
      'Next season, ask for a resistant variety.',
    ],
  ),
  blast(
    label: 'blast',
    name: 'Rice blast',
    cause: 'Fungus (Magnaporthe oryzae)',
    signs: 'Diamond or spindle-shaped spots with grey or whitish centres and brown borders.',
    steps: [
      'Split nitrogen into smaller doses instead of one heavy application.',
      'Keep the field flooded if you can; dry, stressed rice is hit harder.',
      'Ask your agriculturist whether a fungicide is worth it at this stage, and which one.',
      'Next season, use clean seed of a resistant variety.',
    ],
  ),
  brownSpot(
    label: 'brown_spot',
    name: 'Brown spot',
    cause: 'Fungus (Bipolaris oryzae)',
    signs: 'Small round to oval brown spots, often with a yellow halo and a grey centre.',
    steps: [
      'Brown spot usually means the soil is short on nutrients. Ask for a soil test.',
      'Apply balanced fertilizer, especially potassium.',
      'Next season, use certified seed.',
    ],
  ),
  tungro(
    label: 'tungro',
    name: 'Tungro',
    cause: 'Virus, spread by green leafhoppers',
    signs: 'Leaves turn yellow to orange from the tip down; plants are stunted with fewer tillers.',
    steps: [
      'There is no cure. Pull out and bury infected plants early so leafhoppers can’t spread it.',
      'Tell your Municipal Agriculture Office: tungro spreads between farms.',
      'Plant at the same time as your neighbours next season, and use a tungro-resistant variety.',
    ],
  ),
  healthy(
    label: 'healthy',
    name: 'Looks healthy',
    cause: null,
    signs: 'No disease signs found on this leaf.',
    steps: [
      'Keep checking a few leaves across the field every week.',
      'Scan again if you see spots, streaks or yellowing.',
    ],
  );

  Disease({required this.label, required this.name, required this.cause, required this.signs, required this.steps});

  final String label;
  final String name;
  final String? cause;
  final String signs;
  final List<String> steps;

  static Disease fromLabel(String label) =>
      values.firstWhere((d) => d.label == label, orElse: () => throw ArgumentError('Unknown class $label'));
}
