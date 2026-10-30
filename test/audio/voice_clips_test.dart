import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';
import 'package:kogo_voice_learning/core/curriculum/vocabulary.dart';
import 'package:kogo_voice_learning/services/audio/voice_clips.dart';
import 'package:kogo_voice_learning/services/audio/voice_keys.dart';
import 'package:kogo_voice_learning/services/audio/voice_lines.dart';
import 'package:kogo_voice_learning/services/audio/voice_service.dart';

import '../helpers/fakes.dart';
import '../../tool/voice_catalog.dart';

void main() {
  late SilentSpeechEngine tts;
  late FakeClipPlayer player;
  late VoiceService voice;

  setUp(() {
    tts = SilentSpeechEngine();
    player = FakeClipPlayer();
    voice = VoiceService(tts);
  });

  test('keys are normalized and sentences split after . ! ?', () {
    expect(VoiceKeys.key('  Hebat!   Kamu  dapat 3 bintang! '), 'hebat! kamu dapat tiga bintang!');
    expect(VoiceKeys.sentences('Ini bola. Ayo ucapkan: bola!'), ['Ini bola.', 'Ayo ucapkan: bola!']);
    expect(VoiceKeys.sentences('Huruf apa, ya?'), ['Huruf apa, ya?']);
  });

  test('a fully recorded utterance plays clips in order instead of TTS', () async {
    voice.useClips(VoiceClips({'ini bola.': 'a.mp3', 'ayo ucapkan: bola!': 'b.mp3'}), player);
    await voice.say('Ini bola. Ayo ucapkan: bola!');
    expect(player.played, ['a.mp3', 'b.mp3']);
    expect(tts.spoken, isEmpty);
    expect(voice.missingClips, isEmpty);
  });

  test('one missing sentence uses the device voice for the whole utterance', () async {
    voice.useClips(VoiceClips({'ini bola.': 'a.mp3'}), player);
    await voice.say('Ini bola. Ayo ucapkan: bola!');
    expect(player.played, isEmpty, reason: 'never mix two voices in one utterance');
    expect(tts.spoken, isNotEmpty);
    expect(voice.missingClips, {'ayo ucapkan: bola!'});
  });

  test('words, letters and syllable spelling have their own clips', () async {
    final bola = vocabDuaSuku.firstWhere((v) => v.text == 'bola');
    final b = vocabHuruf.firstWhere((v) => v.text == 'b');
    voice.useClips(VoiceClips({VoiceKeys.word(bola): 'w.mp3', VoiceKeys.spell(bola): 's.mp3', VoiceKeys.letter('b'): 'l.mp3'}), player);
    await voice.sayWord(bola);
    await voice.spell(bola);
    await voice.sayWord(b);
    expect(player.played, ['w.mp3', 's.mp3', 'l.mp3']);
    expect(tts.spoken, isEmpty);
  });

  test('without recordings the app keeps using the device voice', () async {
    await voice.say('Halo!');
    expect(tts.spoken.single.text, 'Halo!');
  });

  test('bundled recordings cover the whole catalog and every file exists', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final clips = await VoiceClips.load(rootBundle);
    final catalog = buildVoiceCatalog();
    expect(clips.length, catalog.length);
    expect(clips.lookup(catalog.map((e) => e.key)), isNotNull);
    final manifest = jsonDecode(File('assets/voice/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    for (final file in (manifest['clips'] as Map<String, dynamic>).values) {
      expect(File('assets/voice/$file').lengthSync(), greaterThan(500), reason: file as String);
    }
  });

  test('catalog covers every line, word, letter and spelling the app can say', () {
    final keys = {for (final e in buildVoiceCatalog()) e.key};
    final items = [...vocabHuruf, ...vocabDuaSuku, ...vocabTigaSuku, ...vocabBeberapaKata];
    final lines = VoiceLines();
    final texts = [
      VoiceLines.greeting().text,
      VoiceLines.rewardsPage(0).text,
      VoiceLines.rewardsPage(42).text,
      for (final g in GameType.values) VoiceLines.gameIntro(g).text,
      for (final item in items) ...[VoiceLines.listenRepeatPrompt(item).text, VoiceLines.reveal(item).text],
      for (var i = 0; i < 20; i++) ...[lines.correct().text, lines.wrong().text, lines.almost().text, lines.noSpeech().text, lines.streak().text],
      VoiceLines.praiseWithWord(lines.correct(), 'kelinci'),
      VoiceLines.thatIs('apel merah', lines.wrong()),
    ];
    final missing = {
      for (final t in texts)
        for (final s in VoiceKeys.sentences(t))
          if (!keys.contains(VoiceKeys.key(s))) VoiceKeys.key(s),
    };
    expect(missing, isEmpty);
    for (final item in [...vocabDuaSuku, ...vocabTigaSuku, ...vocabBeberapaKata]) {
      expect(keys, containsAll([VoiceKeys.word(item), VoiceKeys.spell(item)]));
    }
    for (final l in vocabHuruf) {
      expect(keys, contains(VoiceKeys.letter(l.text)));
    }
  });
}
