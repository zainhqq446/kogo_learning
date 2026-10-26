/// Kosakata resmi Kogo Belajar.
///
/// Sesuai batasan masalah penelitian (BAB I 1.4 butir 5), kosakata dibatasi
/// pada kata benda sederhana di lingkungan sekitar anak usia 5–6 tahun:
/// buah dan makanan, hewan, serta benda sehari-hari. Kata kerja, kata sifat,
/// dan kata benda abstrak dari dataset lama sengaja tidak dipakai.
///
/// Setiap kata menyimpan suku katanya secara eksplisit (bukan hasil tebakan
/// algoritma) agar pelafalan TTS per suku kata dan pengelompokan materi
/// selalu tepat.
library;

enum WordCategory { buah, makanan, hewan, benda, kendaraan, alam, tubuh }

class VocabItem {
  const VocabItem({required this.text, required this.syllables, required this.category, this.imageAsset, this.emoji, this.letter});

  /// Teks yang ditampilkan dan diucapkan (huruf kecil), contoh `kupu-kupu`
  /// atau frasa `apel merah`. Untuk materi huruf, berisi huruf kecil `a`.
  final String text;

  /// Suku kata eksplisit, contoh `['ke', 'lin', 'ci']`.
  final List<String> syllables;
  final WordCategory category;

  /// Path gambar dataset (gambar memuat tulisan kata di bagian bawah; widget
  /// `WordPicture` memotong area tulisan agar jawaban tidak terlihat).
  final String? imageAsset;

  /// Cadangan bila gambar dataset tidak tersedia (contoh ikan untuk huruf I).
  final String? emoji;

  /// Khusus materi huruf: kata contoh yang diawali huruf tersebut.
  final VocabItem? letter;

  String get display => text.toUpperCase();
  String get firstLetter => text.isEmpty ? '' : text[0].toUpperCase();

  /// Untuk item huruf, gambar & kata contoh berasal dari [letter].
  String? get pictureAsset => letter?.imageAsset ?? imageAsset;
  String? get pictureEmoji => letter?.emoji ?? emoji;
  bool get isLetter => letter != null;

  @override
  String toString() => 'VocabItem($text)';
}

const _d1 = 'assets/dataset_gambar/1_dua_suku_kata/kata_benda';
const _d2 = 'assets/dataset_gambar/2_tiga_suku_kata/kata_benda';
const _d3 = 'assets/dataset_gambar/3_lebih_dari_tiga_suku_kata/kata_benda';

VocabItem _w(String text, String syl, WordCategory c, String dir, {String? file}) =>
    VocabItem(text: text, syllables: syl.split('-'), category: c, imageAsset: '$dir/${file ?? text}.png');

/// Kata dua suku kata, diurutkan dari pola suku terbuka (KV-KV) yang paling
/// mudah diucapkan ke pola tertutup/gugus konsonan (ng, ny, nc).
final List<VocabItem> vocabDuaSuku = [
  _w('bola', 'bo-la', WordCategory.benda, _d1),
  _w('buku', 'bu-ku', WordCategory.benda, _d1),
  _w('susu', 'su-su', WordCategory.makanan, _d1),
  _w('kuda', 'ku-da', WordCategory.hewan, _d1),
  _w('topi', 'to-pi', WordCategory.benda, _d1),
  _w('roti', 'ro-ti', WordCategory.makanan, _d1),
  _w('baju', 'ba-ju', WordCategory.benda, _d1),
  _w('keju', 'ke-ju', WordCategory.makanan, _d1),
  _w('apel', 'a-pel', WordCategory.buah, _d1),
  _w('ayam', 'a-yam', WordCategory.hewan, _d1),
  _w('ular', 'u-lar', WordCategory.hewan, _d1),
  _w('awan', 'a-wan', WordCategory.alam, _d1),
  _w('mobil', 'mo-bil', WordCategory.kendaraan, _d1),
  _w('gajah', 'ga-jah', WordCategory.hewan, _d1),
  _w('tikus', 'ti-kus', WordCategory.hewan, _d1),
  _w('kodok', 'ko-dok', WordCategory.hewan, _d1),
  _w('nanas', 'na-nas', WordCategory.buah, _d1),
  _w('telur', 'te-lur', WordCategory.makanan, _d1),
  _w('tomat', 'to-mat', WordCategory.buah, _d1),
  _w('jeruk', 'je-ruk', WordCategory.buah, _d1),
  _w('melon', 'me-lon', WordCategory.buah, _d1),
  _w('balon', 'ba-lon', WordCategory.benda, _d1),
  _w('bebek', 'be-bek', WordCategory.hewan, _d1),
  _w('kapal', 'ka-pal', WordCategory.kendaraan, _d1),
  _w('bulan', 'bu-lan', WordCategory.alam, _d1),
  _w('gitar', 'gi-tar', WordCategory.benda, _d1),
  _w('pohon', 'po-hon', WordCategory.alam, _d1),
  _w('rumah', 'ru-mah', WordCategory.benda, _d1),
  _w('lebah', 'le-bah', WordCategory.hewan, _d1),
  _w('pintu', 'pin-tu', WordCategory.benda, _d1),
  _w('lampu', 'lam-pu', WordCategory.benda, _d1),
  _w('kunci', 'kun-ci', WordCategory.benda, _d1),
  _w('tangan', 'ta-ngan', WordCategory.tubuh, _d1),
  _w('hidung', 'hi-dung', WordCategory.tubuh, _d1),
  _w('jagung', 'ja-gung', WordCategory.makanan, _d1),
  _w('gunung', 'gu-nung', WordCategory.alam, _d1),
  _w('kucing', 'ku-cing', WordCategory.hewan, _d1),
  _w('anjing', 'an-jing', WordCategory.hewan, _d1),
  _w('singa', 'si-nga', WordCategory.hewan, _d1),
  _w('bunga', 'bu-nga', WordCategory.alam, _d1),
  _w('monyet', 'mo-nyet', WordCategory.hewan, _d1),
  _w('pisang', 'pi-sang', WordCategory.buah, _d1),
  _w('mangga', 'mang-ga', WordCategory.buah, _d1),
  _w('anggur', 'ang-gur', WordCategory.buah, _d1),
  _w('bintang', 'bin-tang', WordCategory.alam, _d1),
  _w('kentang', 'ken-tang', WordCategory.makanan, _d1),
  _w('wortel', 'wor-tel', WordCategory.makanan, _d1),
  // "kambing" berada di folder tiga suku kata pada dataset lama, padahal
  // jumlah suku katanya dua (kam-bing).
  _w('kambing', 'kam-bing', WordCategory.hewan, _d2),
];

final List<VocabItem> vocabTigaSuku = [
  _w('kelapa', 'ke-la-pa', WordCategory.buah, _d2),
  _w('sepatu', 'se-pa-tu', WordCategory.benda, _d2),
  _w('sepeda', 'se-pe-da', WordCategory.kendaraan, _d2),
  _w('kelinci', 'ke-lin-ci', WordCategory.hewan, _d2),
  _w('kamera', 'ka-me-ra', WordCategory.benda, _d2),
  _w('celana', 'ce-la-na', WordCategory.benda, _d2),
  _w('kemeja', 'ke-me-ja', WordCategory.benda, _d2),
  _w('radio', 'ra-di-o', WordCategory.benda, _d2),
  _w('buaya', 'bu-a-ya', WordCategory.hewan, _d2),
  _w('gorila', 'go-ri-la', WordCategory.hewan, _d2),
  _w('koala', 'ko-a-la', WordCategory.hewan, _d2),
  _w('jendela', 'jen-de-la', WordCategory.benda, _d2),
  _w('harimau', 'ha-ri-mau', WordCategory.hewan, _d2),
  _w('jerapah', 'je-ra-pah', WordCategory.hewan, _d2),
  _w('pesawat', 'pe-sa-wat', WordCategory.kendaraan, _d2),
  _w('telepon', 'te-le-pon', WordCategory.benda, _d2),
  _w('selimut', 'se-li-mut', WordCategory.benda, _d2),
  _w('bendera', 'ben-de-ra', WordCategory.benda, _d2),
  _w('cokelat', 'co-ke-lat', WordCategory.makanan, _d2),
  _w('mentega', 'men-te-ga', WordCategory.makanan, _d2),
  _w('merpati', 'mer-pa-ti', WordCategory.hewan, _d2),
  _w('kanguru', 'ka-ngu-ru', WordCategory.hewan, _d2),
  _w('pelangi', 'pe-la-ngi', WordCategory.alam, _d2),
  _w('pinguin', 'pi-ngu-in', WordCategory.hewan, _d2),
  _w('beruang', 'be-ru-ang', WordCategory.hewan, _d2),
  _w('belalang', 'be-la-lang', WordCategory.hewan, _d2),
  _w('kepiting', 'ke-pi-ting', WordCategory.hewan, _d2),
  _w('semangka', 'se-mang-ka', WordCategory.buah, _d2),
  _w('stroberi', 'stro-be-ri', WordCategory.buah, _d2),
  _w('komputer', 'kom-pu-ter', WordCategory.benda, _d2),
  _w('sekolah', 'se-ko-lah', WordCategory.benda, _d2),
  _w('lukisan', 'lu-ki-san', WordCategory.benda, _d2),
  _w('mahkota', 'mah-ko-ta', WordCategory.benda, _d2),
  _w('hadiah', 'ha-di-ah', WordCategory.benda, _d2),
  _w('mikrofon', 'mi-kro-fon', WordCategory.benda, _d2),
  _w('jembatan', 'jem-ba-tan', WordCategory.benda, _d2),
  _w('hamburger', 'ham-bur-ger', WordCategory.makanan, _d2),
  _w('penggaris', 'peng-ga-ris', WordCategory.benda, _d2),
  // "flamingo" berada di folder lebih dari tiga suku kata pada dataset lama,
  // padahal suku katanya tiga (fla-mi-ngo).
  _w('flamingo', 'fla-mi-ngo', WordCategory.hewan, _d3),
];

/// "Beberapa Kata": frasa dua kata sederhana (benda + warna) seperti contoh
/// "APEL MERAH" pada desain Figma. Warna dipilih yang benar-benar terlihat
/// pada gambarnya sehingga anak dapat menghubungkan kata dengan gambar.
final List<VocabItem> vocabBeberapaKata = [
  _phrase('apel merah', 'a-pel me-rah', WordCategory.buah, '$_d1/apel.png'),
  _phrase('pisang kuning', 'pi-sang ku-ning', WordCategory.buah, '$_d1/pisang.png'),
  _phrase('anggur ungu', 'ang-gur u-ngu', WordCategory.buah, '$_d1/anggur.png'),
  _phrase('kodok hijau', 'ko-dok hi-jau', WordCategory.hewan, '$_d1/kodok.png'),
  _phrase('awan putih', 'a-wan pu-tih', WordCategory.alam, '$_d1/awan.png'),
  _phrase('jeruk oranye', 'je-ruk o-ra-nye', WordCategory.buah, '$_d1/jeruk.png'),
  _phrase('sepatu biru', 'se-pa-tu bi-ru', WordCategory.benda, '$_d2/sepatu.png'),
  _phrase('topi hitam', 'to-pi hi-tam', WordCategory.benda, '$_d1/topi.png'),
  _phrase('mobil merah', 'mo-bil me-rah', WordCategory.kendaraan, '$_d1/mobil.png'),
  _phrase('bintang kuning', 'bin-tang ku-ning', WordCategory.alam, '$_d1/bintang.png'),
  _phrase('pohon hijau', 'po-hon hi-jau', WordCategory.alam, '$_d1/pohon.png'),
  _phrase('susu putih', 'su-su pu-tih', WordCategory.makanan, '$_d1/susu.png'),
  _phrase('balon merah', 'ba-lon me-rah', WordCategory.benda, '$_d1/balon.png'),
  _phrase('wortel oranye', 'wor-tel o-ra-nye', WordCategory.makanan, '$_d1/wortel.png'),
  _phrase('lumba-lumba biru', 'lum-ba-lum-ba bi-ru', WordCategory.hewan, '$_d3/lumba-lumba.png'),
  _phrase('bulan kuning', 'bu-lan ku-ning', WordCategory.alam, '$_d1/bulan.png'),
  _phrase('tomat merah', 'to-mat me-rah', WordCategory.buah, '$_d1/tomat.png'),
  _phrase('kura-kura hijau', 'ku-ra-ku-ra hi-jau', WordCategory.hewan, '$_d3/kura-kura.png'),
  _phrase('kupu-kupu oranye', 'ku-pu-ku-pu o-ra-nye', WordCategory.hewan, '$_d3/kupu-kupu.png'),
  _phrase('jagung kuning', 'ja-gung ku-ning', WordCategory.makanan, '$_d1/jagung.png'),
];

VocabItem _phrase(String text, String syl, WordCategory c, String asset) =>
    VocabItem(text: text, syllables: syl.replaceAll(' ', '-').split('-'), category: c, imageAsset: asset);

VocabItem _letter(String letter, VocabItem example) => VocabItem(text: letter, syllables: [letter], category: example.category, letter: example);

/// Latihan huruf: setiap huruf dipasangkan dengan benda yang diawali huruf
/// tersebut. Huruf Q, V, X, dan Y dilewati karena tidak memiliki kata benda
/// sederhana yang dikenal anak usia 5–6 tahun.
final List<VocabItem> vocabHuruf = [
  _letter('a', _w('apel', 'a-pel', WordCategory.buah, _d1)),
  _letter('b', _w('bola', 'bo-la', WordCategory.benda, _d1)),
  _letter('c', _w('cokelat', 'co-ke-lat', WordCategory.makanan, _d2)),
  _letter('d', _w('dinosaurus', 'di-no-sau-rus', WordCategory.hewan, _d3)),
  _letter('e', _w('eskalator', 'es-ka-la-tor', WordCategory.benda, _d3)),
  _letter('f', _w('flamingo', 'fla-mi-ngo', WordCategory.hewan, _d3)),
  _letter('g', _w('gajah', 'ga-jah', WordCategory.hewan, _d1)),
  _letter('h', _w('harimau', 'ha-ri-mau', WordCategory.hewan, _d2)),
  _letter('i', const VocabItem(text: 'ikan', syllables: ['i', 'kan'], category: WordCategory.hewan, emoji: '🐟')),
  _letter('j', _w('jeruk', 'je-ruk', WordCategory.buah, _d1)),
  _letter('k', _w('kucing', 'ku-cing', WordCategory.hewan, _d1)),
  _letter('l', _w('lebah', 'le-bah', WordCategory.hewan, _d1)),
  _letter('m', _w('mobil', 'mo-bil', WordCategory.kendaraan, _d1)),
  _letter('n', _w('nanas', 'na-nas', WordCategory.buah, _d1)),
  _letter('o', _w('orangutan', 'o-rang-u-tan', WordCategory.hewan, _d3)),
  _letter('p', _w('pisang', 'pi-sang', WordCategory.buah, _d1)),
  _letter('r', _w('rumah', 'ru-mah', WordCategory.benda, _d1)),
  _letter('s', _w('sepatu', 'se-pa-tu', WordCategory.benda, _d2)),
  _letter('t', _w('topi', 'to-pi', WordCategory.benda, _d1)),
  _letter('u', _w('ular', 'u-lar', WordCategory.hewan, _d1)),
  _letter('w', _w('wortel', 'wor-tel', WordCategory.makanan, _d1)),
  _letter('z', const VocabItem(text: 'zebra', syllables: ['ze', 'bra'], category: WordCategory.hewan, emoji: '🦓')),
];
