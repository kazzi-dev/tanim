// Writes the app's disease advice as a review sheet for an agriculturist, so
// the sheet always matches what the app shows.
//
//   dart run tool/advice_sheet.dart > ../docs/ADVICE_REVIEW.md
import 'dart:io';

import 'package:tanim/features/scan/domain/disease.dart';

void main() {
  final out = StringBuffer()
    ..writeln('# Tanim advice: review sheet')
    ..writeln()
    ..writeln('Tanim is a phone app that guesses which rice leaf disease is in a photo. After the guess it shows the')
    ..writeln(
      'text below. **Please check it before farmers rely on it.** Mark each line OK, or write what it should say.',
    )
    ..writeln('The app always adds: *"Tanim is a study project, not a diagnosis. Before spraying or pulling plants,')
    ..writeln('check with your Municipal Agriculture Office."*')
    ..writeln()
    ..writeln('Reviewer: ______________________ Office: ______________________ Date: __________')
    ..writeln();
  for (final d in Disease.values) {
    out
      ..writeln('## ${d.name}')
      ..writeln()
      ..writeln('| | Text in the app | OK? | Correction |')
      ..writeln('|---|---|---|---|');
    if (d.cause != null) out.writeln('| Cause | ${d.cause} | ☐ | |');
    out.writeln('| What it looks like | ${d.signs} | ☐ | |');
    for (final (i, step) in d.steps.indexed) {
      out.writeln('| Step ${i + 1} | $step | ☐ | |');
    }
    out
      ..writeln()
      ..writeln('Anything missing or dangerous to leave out? ____________________________________________')
      ..writeln();
  }
  out
    ..writeln('## Translations')
    ..writeln()
    ..writeln('Once the English is right, the same text is needed in **Tagalog** and **Bisaya (Cebuano)**, written or')
    ..writeln('checked by a native speaker who knows farm words. Machine translation is not good enough here.');
  stdout.write(out);
}
