// Exports the app curriculum (lib/core/curriculum) to JSON for the backend seed.
//
// Usage (repository root): dart run tool/export_vocabulary.dart
// Output: backend/src/data/vocabulary.json
import 'dart:convert';
import 'dart:io';

import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';

void main() {
  final data = {
    'materi': [
      for (final m in Materi.values)
        {
          'code': m.code,
          'title': m.title,
          'order': m.index + 1,
          'nodeCount': Curriculum.nodesOf(m).length,
          'words': [
            for (final (i, w) in m.items.indexed)
              {
                'order': i + 1,
                'text': w.text,
                'syllables': w.syllables,
                'category': w.category.name,
                'example': w.letter?.text,
                'image': w.pictureAsset,
              },
          ],
        },
    ],
    'gameTypes': [for (final g in GameType.values) {'code': g.code, 'title': g.title}],
    'rewardTiers': [for (final t in RewardTier.values) {'code': t.name, 'title': t.title, 'minStars': t.minStars}],
  };
  final file = File('backend/src/data/vocabulary.json');
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  stdout.writeln('Wrote ${file.path}');
}
