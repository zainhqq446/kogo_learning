// Daftar semua ucapan Kogo yang direkam dengan ElevenLabs.
//
//   dart run tool/voice_catalog.dart > build/voice_catalog.json
//
// Daftar dibangun dari fungsi kalimat yang sama dengan yang dipakai aplikasi,
// sehingga setiap kalimat yang diucapkan pasti memiliki rekaman.
import 'dart:convert';
import 'dart:io';

import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';
import 'package:kogo_voice_learning/core/curriculum/vocabulary.dart';
import 'package:kogo_voice_learning/features/games/game_content.dart';
import 'package:kogo_voice_learning/services/audio/indonesian_text.dart';
import 'package:kogo_voice_learning/services/audio/prosody_planner.dart';
import 'package:kogo_voice_learning/services/audio/voice_keys.dart';
import 'package:kogo_voice_learning/services/audio/voice_lines.dart';

/// Satu klip: [key] dicari aplikasi, [text] dikirim ke ElevenLabs.
class VoiceEntry {
  const VoiceEntry(this.key, this.text, this.kind);

  final String key;
  final String text;

  /// `line` (kalimat), `word` (kata contoh, lebih lambat), `letter`, `spell`.
  final String kind;

  Map<String, String> toJson() => {'key': key, 'text': text, 'kind': kind};
}

List<VoiceEntry> buildVoiceCatalog() {
  final entries = <String, VoiceEntry>{};
  void line(String utterance) {
    for (final s in VoiceKeys.sentences(utterance)) {
      entries.putIfAbsent(VoiceKeys.key(s), () => VoiceEntry(VoiceKeys.key(s), s, 'line'));
    }
  }

  final letters = vocabHuruf;
  final words = [...vocabDuaSuku, ...vocabTigaSuku, ...vocabBeberapaKata];
  final letterExamples = [for (final l in letters) l.letter!];
  final allItems = [...letters, ...words];
  // Kata yang dapat disebut pada permainan (termasuk contoh kata huruf).
  final spokenWords = {
    for (final w in [...words, ...letterExamples]) w.text,
  };

  // Kalimat tetap.
  VoiceLines.pooledTexts.forEach(line);
  line(VoiceLines.greeting().text);
  line(VoiceLines.welcomeNew().text);
  line(VoiceLines.locked().text);
  line(VoiceLines.allMatched.text);
  line(VoiceLines.voiceCheck.text);
  line(VoiceLines.rewardsPage(0).text);
  line(VoiceLines.rewardsPage(1).text);
  for (final m in Materi.values) {
    line(VoiceLines.materiIntro(m).text);
  }
  for (final g in GameType.values) {
    line(VoiceLines.gameIntro(g).text);
  }
  for (var stars = 1; stars <= 3; stars++) {
    line(VoiceLines.completion(stars).text);
  }
  for (final tier in RewardTier.values) {
    line(VoiceLines.newReward(tier).text);
  }

  // Kalimat per kata dan per huruf.
  for (final item in allItems) {
    line(VoiceLines.listenRepeatPrompt(item).text);
    line(VoiceLines.reveal(item).text);
  }
  final findLetters = {
    for (final m in Materi.values)
      for (final node in Curriculum.nodesOf(m).where((n) => n.game == GameType.findObject))
        for (final round in GameContent.findObject(node)) round.letter,
  };
  for (final letter in findLetters) {
    line(VoiceLines.findObjectPrompt(letter).text);
  }
  const anyLine = VoiceLine('Hebat!', SpeechMood.warm);
  for (final w in spokenWords) {
    line(VoiceLines.wordThenLine(w, anyLine));
    line(VoiceLines.thatIs(w, anyLine));
    line(VoiceLines.praiseWithWord(anyLine, w));
  }

  // Contoh pelafalan kata, nama huruf, dan ejaan suku kata.
  for (final item in [...words, ...letterExamples]) {
    entries.putIfAbsent(VoiceKeys.word(item), () => VoiceEntry(VoiceKeys.word(item), '${item.text}.', 'word'));
    final spell = [...item.syllables, item.text].join(' ... ');
    entries.putIfAbsent(VoiceKeys.spell(item), () => VoiceEntry(VoiceKeys.spell(item), '$spell!', 'spell'));
  }
  for (final l in letters) {
    final name = IndonesianText.letterNames[l.text] ?? l.text;
    entries.putIfAbsent(VoiceKeys.letter(l.text), () => VoiceEntry(VoiceKeys.letter(l.text), name, 'letter'));
  }
  return entries.values.toList();
}

void main() {
  final catalog = buildVoiceCatalog();
  stdout.writeln(const JsonEncoder.withIndent('  ').convert([for (final e in catalog) e.toJson()]));
}
