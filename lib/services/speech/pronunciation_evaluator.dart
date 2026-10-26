import 'dart:math' as math;

import '../../core/curriculum/vocabulary.dart';
import '../audio/indonesian_text.dart';

enum SpeechBand { correct, almost, incorrect, noSpeech }

class PronunciationResult {
  const PronunciationResult({required this.band, required this.similarity, required this.heard, required this.strictMatch});

  final SpeechBand band;

  /// Kemiripan terbaik 0..1 (1 - jarak Levenshtein / panjang).
  final double similarity;

  /// Teks hasil speech-to-text yang paling mirip (apa adanya, untuk log).
  final String heard;

  /// `true` bila ucapan persis sama setelah normalisasi (dilaporkan terpisah
  /// agar penelitian dapat menyajikan akurasi ketat & toleran).
  final bool strictMatch;

  bool get isCorrect => band == SpeechBand.correct;
}

/// Menilai pelafalan kata sederhana (batasan masalah no. 3: evaluasi
/// pelafalan tanpa mengembangkan algoritma ASR).
///
/// Penilaian dibuat ramah anak usia 5–6 tahun:
/// - semua alternatif (n-best) dari speech-to-text dibandingkan;
/// - kata pengisi ("ini", "eh", "namanya") diabaikan;
/// - pelafalan khas anak dimaklumi (cadel r→l, f→p, z→j, sy→s, h di akhir);
/// - untuk materi huruf, nama huruf Indonesia diterima ("be", "ce", "ef").
class PronunciationEvaluator {
  PronunciationEvaluator._();

  static const double correctThreshold = 0.80;
  static const double almostThreshold = 0.55;

  static const _fillers = {'eh', 'em', 'emm', 'hmm', 'ehm', 'ini', 'itu', 'namanya', 'kata', 'adalah', 'yaitu', 'ya', 'dong', 'aku', 'saya', 'huruf'};

  static PronunciationResult evaluate(VocabItem target, List<String> alternates) {
    final heardList = alternates.map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
    if (heardList.isEmpty) {
      return const PronunciationResult(band: SpeechBand.noSpeech, similarity: 0, heard: '', strictMatch: false);
    }
    return target.isLetter ? _evaluateLetter(target.text, heardList) : _evaluateWord(target.text, heardList);
  }

  static PronunciationResult _evaluateWord(String target, List<String> heardList) {
    final t = clean(target);
    final tFold = fold(t);
    final tWords = t.split(' ').length;
    var best = 0.0;
    var bestHeard = heardList.first;
    var strict = false;
    var phonetic = false;

    for (final raw in heardList) {
      final words = clean(raw).split(' ').where((w) => w.isNotEmpty).toList();
      if (words.isEmpty) continue;
      for (final candidate in _windows(words, tWords)) {
        if (candidate == t) strict = true;
        final c = fold(candidate);
        if (c == tFold) phonetic = true;
        final s = math.max(similarity(candidate, t), similarity(c, tFold) * 0.97);
        if (s > best) {
          best = s;
          bestHeard = raw;
        }
      }
    }
    if (strict || phonetic) best = math.max(best, strict ? 1.0 : 0.95);

    final distance = (1 - best) * t.replaceAll(' ', '').length;
    final longWordOneSlip = t.replaceAll(' ', '').length >= 6 && distance <= 1.01;
    final band = (best >= correctThreshold || longWordOneSlip)
        ? SpeechBand.correct
        : best >= almostThreshold
        ? SpeechBand.almost
        : SpeechBand.incorrect;
    return PronunciationResult(band: band, similarity: _round(best), heard: bestHeard, strictMatch: strict);
  }

  static PronunciationResult _evaluateLetter(String letter, List<String> heardList) {
    final variants = {letter, ...?IndonesianText.letterSpokenVariants[letter], IndonesianText.letterNames[letter] ?? letter};
    final name = IndonesianText.letterNames[letter] ?? letter;
    var best = 0.0;
    var bestHeard = heardList.first;
    var strict = false;
    for (final raw in heardList) {
      final words = clean(raw, dropFillers: false).split(' ').where((w) => w.isNotEmpty).toList();
      for (final w in words) {
        if (variants.contains(w)) {
          strict = strict || w == name || w == letter;
          best = 1.0;
          bestHeard = raw;
        } else {
          final s = similarity(w, name);
          if (s > best) {
            best = s;
            bestHeard = raw;
          }
        }
      }
    }
    final band = best >= 1.0
        ? SpeechBand.correct
        : best >= 0.5
        ? SpeechBand.almost
        : SpeechBand.incorrect;
    return PronunciationResult(band: band, similarity: _round(best), heard: bestHeard, strictMatch: strict);
  }

  /// Potongan kata berurutan sepanjang [size] (untuk frasa "apel merah").
  static Iterable<String> _windows(List<String> words, int size) sync* {
    yield words.join(' ');
    if (words.length <= size) return;
    for (var i = 0; i + size <= words.length; i++) {
      yield words.sublist(i, i + size).join(' ');
    }
  }

  static final _bracketed = RegExp(r'\([^)]*\)|\[[^\]]*\]');
  static const _accents = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
  };

  /// Normalisasi: huruf kecil, tanpa aksen/tanda baca/tag, angka → kata,
  /// tanda hubung → spasi, kata pengisi dibuang.
  static String clean(String text, {bool dropFillers = true}) {
    var s = text.toLowerCase().replaceAll(_bracketed, ' ');
    s = s.split('').map((c) => _accents[c] ?? c).join();
    s = s.replaceAllMapped(RegExp(r'\d+'), (m) => IndonesianText.numberToWords(int.parse(m.group(0)!)));
    s = IndonesianText.normalize(s);
    if (!dropFillers) return s;
    final words = s.split(' ').where((w) => w.isNotEmpty && !_fillers.contains(w)).toList();
    return words.isEmpty ? s : words.join(' ');
  }

  /// Pelipatan fonetik untuk pelafalan khas anak.
  static String fold(String text) {
    var s = text
        .replaceAll('sy', 's')
        .replaceAll('kh', 'k')
        .replaceAll('ny', 'n')
        .replaceAll('r', 'l')
        .replaceAll(RegExp('[fv]'), 'p')
        .replaceAll('z', 'j')
        .replaceAll('q', 'k')
        .replaceAll('x', 'ks');
    s = s.replaceAllMapped(RegExp(r'h\b'), (_) => '');
    s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
    return s;
  }

  static double similarity(String a, String b) {
    if (a == b) return 1;
    final x = a.replaceAll(' ', '');
    final y = b.replaceAll(' ', '');
    final longest = math.max(x.length, y.length);
    if (longest == 0) return 1;
    return 1 - levenshtein(x, y) / longest;
  }

  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = math.min(math.min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[b.length];
  }

  static double _round(double v) => (v * 1000).round() / 1000;
}
