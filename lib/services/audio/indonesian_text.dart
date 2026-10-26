/// Utilitas teks bahasa Indonesia untuk TTS dan pencocokan ucapan.
class IndonesianText {
  IndonesianText._();

  /// Cara membaca nama huruf dalam bahasa Indonesia.
  static const Map<String, String> letterNames = {
    'a': 'a',
    'b': 'be',
    'c': 'ce',
    'd': 'de',
    'e': 'e',
    'f': 'ef',
    'g': 'ge',
    'h': 'ha',
    'i': 'i',
    'j': 'je',
    'k': 'ka',
    'l': 'el',
    'm': 'em',
    'n': 'en',
    'o': 'o',
    'p': 'pe',
    'q': 'ki',
    'r': 'er',
    's': 'es',
    't': 'te',
    'u': 'u',
    'v': 've',
    'w': 'we',
    'x': 'eks',
    'y': 'ye',
    'z': 'zet',
  };

  /// Variasi hasil speech-to-text yang wajar ketika anak menyebut nama huruf.
  static const Map<String, List<String>> letterSpokenVariants = {
    'a': ['a', 'ah', 'aa', 'ha'],
    'b': ['be', 'b', 'beh', 'bee'],
    'c': ['ce', 'c', 'che', 'cek', 'se'],
    'd': ['de', 'd', 'deh', 'dee'],
    'e': ['e', 'eh', 'ee'],
    'f': ['ef', 'f', 'eff', 'ep'],
    'g': ['ge', 'g', 'geh', 'gue'],
    'h': ['ha', 'h', 'hah'],
    'i': ['i', 'ih', 'ii', 'e'],
    'j': ['je', 'j', 'jeh', 'jay'],
    'k': ['ka', 'k', 'kah', 'kak'],
    'l': ['el', 'l', 'ell', 'elle'],
    'm': ['em', 'm', 'emm'],
    'n': ['en', 'n', 'enn'],
    'o': ['o', 'oh', 'oo'],
    'p': ['pe', 'p', 'peh'],
    'r': ['er', 'r', 'err', 'air'],
    's': ['es', 's', 'ess'],
    't': ['te', 't', 'teh'],
    'u': ['u', 'uh', 'uu', 'oo'],
    'w': ['we', 'w', 'weh'],
    'z': ['zet', 'z', 'set', 'zed'],
  };

  static const _ones = ['nol', 'satu', 'dua', 'tiga', 'empat', 'lima', 'enam', 'tujuh', 'delapan', 'sembilan'];

  /// Angka 0–999 menjadi kata, contoh 12 → "dua belas", 105 → "seratus lima".
  static String numberToWords(int n) {
    if (n < 0 || n > 999) return '$n';
    if (n < 10) return _ones[n];
    if (n == 10) return 'sepuluh';
    if (n == 11) return 'sebelas';
    if (n < 20) return '${_ones[n - 10]} belas';
    if (n < 100) {
      final tens = n ~/ 10;
      final rest = n % 10;
      return '${_ones[tens]} puluh${rest == 0 ? '' : ' ${_ones[rest]}'}';
    }
    final hundreds = n ~/ 100;
    final rest = n % 100;
    final head = hundreds == 1 ? 'seratus' : '${_ones[hundreds]} ratus';
    return rest == 0 ? head : '$head ${numberToWords(rest)}';
  }

  static final _emoji = RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]', unicode: true);
  static final _tags = RegExp(r'\[[^\]]*\]');
  static final _digits = RegExp(r'\d+');
  static final _spaces = RegExp(r'\s+');

  /// Membersihkan teks sebelum diucapkan TTS: emoji & tag dibuang, angka
  /// ditulis sebagai kata, tanda hubung kata ulang (kupu-kupu) dipertahankan.
  static String forSpeech(String text) {
    var out = text.replaceAll(_tags, ' ').replaceAll(_emoji, ' ');
    out = out.replaceAllMapped(_digits, (m) => numberToWords(int.parse(m.group(0)!)));
    out = out.replaceAll(RegExp(r'\s+-\s+'), ' ');
    out = out.replaceAll('…', '...');
    return out.replaceAll(_spaces, ' ').trim();
  }

  /// Normalisasi untuk membandingkan hasil speech-to-text dengan target:
  /// huruf kecil, tanpa tanda baca, tanda hubung kata ulang diganti spasi.
  static String normalize(String text) {
    return text.toLowerCase().replaceAll('-', ' ').replaceAll(RegExp(r"[^a-z0-9\s]"), ' ').replaceAll(_spaces, ' ').trim();
  }
}
