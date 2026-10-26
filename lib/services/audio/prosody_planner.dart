import 'indonesian_text.dart';

/// Suasana suara Kogo. Menentukan nada dasar (pitch) dan kecepatan bicara.
enum SpeechMood {
  excited(1.22, 0.48),
  celebratory(1.26, 0.50),
  playful(1.18, 0.46),
  curious(1.12, 0.44),
  warm(1.10, 0.44),
  encouraging(1.12, 0.45),
  gentle(1.04, 0.41),
  patient(1.00, 0.40);

  const SpeechMood(this.pitch, this.rate);

  /// Pitch flutter_tts (1.0 = normal).
  final double pitch;

  /// Kecepatan flutter_tts Android (0.5 = normal).
  final double rate;
}

/// Potongan ucapan dengan intonasinya sendiri.
class SpeechChunk {
  const SpeechChunk(this.text, {required this.pitch, required this.rate, this.pauseAfterMs = 0});

  final String text;
  final double pitch;
  final double rate;
  final int pauseAfterMs;

  @override
  String toString() => 'SpeechChunk("$text", p=${pitch.toStringAsFixed(2)}, r=${rate.toStringAsFixed(2)}, +${pauseAfterMs}ms)';
}

/// Perencana prosodi untuk TTS bahasa Indonesia.
///
/// Mesin TTS Android tidak mendukung SSML secara konsisten, sehingga intonasi
/// dibentuk dengan memecah teks per kalimat lalu mengatur pitch, kecepatan,
/// dan jeda tiap potongan sesuai jenis kalimatnya:
/// - seruan/ajakan (`!`, "Ayo", "Yuk", "Wah", "Hore") → nada naik & lebih cepat;
/// - pertanyaan ya/tidak (`?`) → nada naik di akhir (tanda tanya dipertahankan);
/// - pertanyaan kata tanya (apa, mana, siapa, ...) → nada tinggi lalu turun;
/// - pernyataan (`.`) → nada dasar;
/// - ragu/elipsis (`...`, "Hmm") → nada turun & lebih lambat;
/// - kata target pelafalan → lambat dan jelas, diapit jeda.
class ProsodyPlanner {
  ProsodyPlanner._();

  static const double minPitch = 0.85;
  static const double maxPitch = 1.35;
  static const double minRate = 0.36;
  static const double maxRate = 0.52;

  static const targetPitch = 1.04;
  static const targetRate = 0.38;

  static const _whWords = {'apa', 'siapa', 'mana', 'berapa', 'kenapa', 'mengapa', 'bagaimana', 'kapan', 'manakah', 'apakah'};
  static const _exclaimStarters = {'ayo', 'yuk', 'wah', 'hore', 'hebat', 'wow', 'asyik', 'yey', 'yei'};

  static final _sentenceSplit = RegExp(r'(?<=[.!?])\s+');

  /// Menyusun potongan ucapan. [emphasize] (opsional) adalah kata target yang
  /// akan diucapkan terpisah, pelan, dan jelas sebagai contoh pelafalan.
  static List<SpeechChunk> plan(String text, {SpeechMood mood = SpeechMood.warm, String? emphasize}) {
    final clean = IndonesianText.forSpeech(text);
    if (clean.isEmpty) return const [];

    final chunks = <SpeechChunk>[];
    for (final sentence in clean.split(_sentenceSplit)) {
      final s = sentence.trim();
      if (s.isEmpty) continue;
      chunks.addAll(_planSentence(s, mood, emphasize));
    }
    return chunks;
  }

  /// Contoh pelafalan per suku kata: "ke … lin … ci … kelinci!".
  static List<SpeechChunk> syllables(List<String> syllables, String word) {
    return [
      for (final s in syllables) SpeechChunk(s, pitch: _clampPitch(targetPitch + 0.04), rate: minRate, pauseAfterMs: 320),
      SpeechChunk('$word!', pitch: _clampPitch(SpeechMood.playful.pitch), rate: targetRate + 0.04, pauseAfterMs: 300),
    ];
  }

  static List<SpeechChunk> _planSentence(String sentence, SpeechMood mood, String? emphasize) {
    final kind = _classify(sentence);
    var pitch = mood.pitch;
    var rate = mood.rate;
    var pause = 350;
    switch (kind) {
      case _Kind.exclamation:
        pitch += 0.08;
        rate += 0.02;
        pause = 280;
      case _Kind.yesNoQuestion:
        pitch += 0.10;
        rate -= 0.02;
        pause = 500;
      case _Kind.whQuestion:
        pitch += 0.04;
        rate -= 0.01;
        pause = 500;
      case _Kind.hesitation:
        pitch -= 0.05;
        rate -= 0.05;
        pause = 450;
      case _Kind.statement:
        break;
    }

    final parts = _splitAroundTarget(sentence, emphasize);
    final result = <SpeechChunk>[];
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;
      if (part.isTarget) {
        if (result.isNotEmpty) {
          final prev = result.removeLast();
          result.add(SpeechChunk(prev.text, pitch: prev.pitch, rate: prev.rate, pauseAfterMs: 250));
        }
        result.add(SpeechChunk(part.text, pitch: _clampPitch(targetPitch), rate: _clampRate(targetRate), pauseAfterMs: isLast ? 500 : 300));
        continue;
      }
      for (final piece in _splitLong(part.text)) {
        result.add(SpeechChunk(piece.text, pitch: _clampPitch(pitch), rate: _clampRate(rate), pauseAfterMs: piece.isComma ? 180 : 0));
      }
      if (isLast && result.isNotEmpty) {
        final last = result.removeLast();
        result.add(SpeechChunk(last.text, pitch: last.pitch, rate: last.rate, pauseAfterMs: pause));
      }
    }
    return result;
  }

  static _Kind _classify(String sentence) {
    final lower = sentence.toLowerCase();
    final firstWord = lower.split(RegExp(r'[\s,]+')).first.replaceAll(RegExp(r'[^a-z]'), '');
    if (lower.startsWith('hmm') || lower.endsWith('...')) return _Kind.hesitation;
    if (lower.endsWith('?')) {
      final words = lower.replaceAll(RegExp(r'[^a-z\s]'), ' ').split(RegExp(r'\s+'));
      return words.any(_whWords.contains) ? _Kind.whQuestion : _Kind.yesNoQuestion;
    }
    if (lower.endsWith('!') || _exclaimStarters.contains(firstWord)) return _Kind.exclamation;
    return _Kind.statement;
  }

  static List<_Part> _splitAroundTarget(String sentence, String? target) {
    if (target == null || target.trim().isEmpty) return [_Part(sentence, false)];
    final cleanTarget = IndonesianText.forSpeech(target);
    final index = sentence.toLowerCase().indexOf(cleanTarget.toLowerCase());
    if (index < 0) return [_Part(sentence, false)];
    final before = sentence.substring(0, index).trim();
    final word = sentence.substring(index, index + cleanTarget.length);
    var after = sentence.substring(index + cleanTarget.length).trim();
    final trailing = RegExp(r'^[.!?,]+').stringMatch(after) ?? '';
    after = after.substring(trailing.length).trim();
    return [if (before.isNotEmpty) _Part(before, false), _Part('$word${trailing.isEmpty ? '.' : trailing}', true), if (after.isNotEmpty) _Part(after, false)];
  }

  /// Kalimat panjang (> 7 kata) dipecah di koma agar napas terdengar alami.
  static List<({String text, bool isComma})> _splitLong(String text) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= 7 || !text.contains(',')) return [(text: text, isComma: false)];
    final pieces = text.split(RegExp(r'(?<=,)\s+'));
    return [for (var i = 0; i < pieces.length; i++) (text: pieces[i], isComma: i < pieces.length - 1)];
  }

  static double _clampPitch(double v) => v.clamp(minPitch, maxPitch);
  static double _clampRate(double v) => v.clamp(minRate, maxRate);
}

enum _Kind { statement, exclamation, yesNoQuestion, whQuestion, hesitation }

class _Part {
  const _Part(this.text, this.isTarget);
  final String text;
  final bool isTarget;
}
