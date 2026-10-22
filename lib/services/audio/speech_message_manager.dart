import 'dart:math';

/// Tipe kategori pesan suara dalam Kogo Voice Learning.
enum SpeechCategory {
  instruction,
  speechInvitation,
  correct,
  almostCorrect,
  incorrect,
  noRecognition,
  retry,
  streak,
  completion,
}

/// Konteks status anak dan aktivitas pembelajaran saat pesan suara dihasilkan.
/// Memastikan pesan selalu kontekstual tanpa menyebut istilah teknis kepada anak.
class SpeechMessageContext {
  final String? stageTitle;
  final String? lessonType;
  final String targetWord;
  final int attemptNumber;
  final bool? isCorrect;
  final double similarityPercent;
  final int streak;
  final bool isCompleted;
  final bool isEmptyRecognition;

  const SpeechMessageContext({
    this.stageTitle,
    this.lessonType,
    required this.targetWord,
    this.attemptNumber = 1,
    this.isCorrect,
    this.similarityPercent = 0.0,
    this.streak = 0,
    this.isCompleted = false,
    this.isEmptyRecognition = false,
  });
}

/// Manager pesan suara dinamis Kogo Voice Learning.
/// Bertanggung jawab memilih kalimat yang ramah anak, hangat, bervariasi,
/// dan mencegah pengulangan kalimat yang sama dua kali berturut-turut.
class SpeechMessageManager {
  SpeechMessageManager._internal();
  static final SpeechMessageManager instance = SpeechMessageManager._internal();

  final Random _random = Random();
  String? _lastSpokenMessage;

  // A. INSTRUKSI (Sebelum aktivitas dimulai)
  final List<String> instructionMessages = [
    'Yuk, dengarkan baik-baik!',
    'Ayo kita coba bersama!',
    'Sekarang giliran kamu!',
    'Dengarkan dulu, ya!',
    'Siap? Kita mulai!',
    'Ayo kita belajar bersama!',
  ];

  // B. AJAKAN BERBICARA (Saat anak harus mengucapkan kata)
  final List<String> speechInvitationTemplates = [
    'Sekarang, coba ucapkan {word}.',
    'Yuk, bilang {word}!',
    'Ayo ikuti Kakak, katakan {word}.',
    'Sekarang giliran kamu mengucapkan {word}.',
    'Coba katakan {word}, kamu pasti bisa!',
    'Ayo bilang {word} dengan riang!',
  ];

  // C. JAWABAN BENAR (Recognition / Evaluasi tepat)
  final List<String> correctMessages = [
    'Hebat!',
    'Bagus sekali!',
    'Pintar!',
    'Wah, benar!',
    'Yeay, kamu berhasil!',
    'Keren!',
    'Mantap!',
    'Aku suka jawabanmu!',
    'Hebat, kamu bisa!',
    'Luar biasa!',
  ];

  // D. HAMPIR BENAR (Mendekati target, similarity >= 65%)
  final List<String> almostCorrectMessages = [
    'Hampir benar! Coba lagi, ya.',
    'Sudah dekat! Ayo coba sekali lagi.',
    'Bagus, sedikit lagi!',
    'Hampir berhasil!',
    'Coba pelan-pelan lagi yaa.',
    'Yuk, kita coba sekali lagi!',
  ];

  // E. SALAH / BELUM TERDETEKSI (Lembut dan tidak menyalahkan anak)
  final List<String> incorrectMessages = [
    'Yuk, coba sekali lagi.',
    'Tidak apa-apa, kita coba bersama lagi yaa.',
    'Coba ucapkan lebih jelas, kamu pasti bisa!',
    'Ayo, kamu bisa!',
    'Kita coba sekali lagi, ya!',
  ];

  // Belum terdengar / Audio kosong
  final List<String> noRecognitionMessages = [
    'Suaramu belum terdengar jelas. Coba tekan mikrofon lagi, ya!',
    'Belum terdengar. Yuk, coba dekatkan suaramu!',
    'Suaranya masih malu-malu nih. Ayo bicara lagi yaa!',
    'Yuk coba lagi, tekan mikrofon dan katakan dengan jelas!',
  ];

  // Percobaan kedua / Retry
  final List<String> retryMessages = [
    'Ayo coba lagi, pelan-pelan saja yaa.',
    'Tarik napas dulu, lalu coba lagi!',
    'Kakak yakin kamu pasti bisa, yuk coba lagi!',
    'Sekali lagi yaa, semangat!',
  ];

  // F. KEBERHASILAN BERUNTUN (Streak >= 3)
  final List<String> streakMessages = [
    'Wah, hebat! Kamu keren sekali!',
    'Wow, kamu makin pintar!',
    'Hebat! Sudah berkali-kali benar!',
    'Luar biasa! Teruskan yaa!',
    'Yeay! Kamu sangat hebat hari ini!',
  ];

  // G. SELESAI LESSON
  final List<String> completionMessages = [
    'Yeay, kamu sudah selesai!',
    'Hebat! Kamu berhasil menyelesaikan latihan ini!',
    'Keren! Sampai jumpa di petualangan berikutnya yaa!',
    'Hari ini kamu hebat sekali!',
    'Terima kasih sudah belajar bersama dengan ceria!',
  ];

  /// Menghasilkan pesan suara yang sesuai dengan konteks tanpa pengulangan kalimat yang sama.
  String generateMessage(SpeechMessageContext context) {
    List<String> pool;

    if (context.isCompleted) {
      pool = completionMessages;
    } else if (context.streak >= 3 && context.isCorrect == true && context.streak % 3 == 0) {
      pool = streakMessages;
    } else if (context.isCorrect == true) {
      pool = correctMessages;
    } else if (context.isEmptyRecognition) {
      pool = noRecognitionMessages;
    } else if (context.isCorrect == false) {
      if (context.similarityPercent >= 65.0) {
        pool = almostCorrectMessages;
      } else if (context.attemptNumber > 1) {
        pool = retryMessages;
      } else {
        pool = incorrectMessages;
      }
    } else {
      // Default: Ajakan berbicara kontekstual dengan kata target
      if (context.targetWord.isNotEmpty) {
        final template = _selectRandomNonRepeating(speechInvitationTemplates);
        final populated = template.replaceAll('{word}', context.targetWord);
        _lastSpokenMessage = populated;
        return populated;
      }
      pool = instructionMessages;
    }

    final message = _selectRandomNonRepeating(pool);
    _lastSpokenMessage = message;
    return message;
  }

  /// Memilih instruksi awal ramah anak untuk memulai aktivitas
  String getInstructionMessage() {
    final msg = _selectRandomNonRepeating(instructionMessages);
    _lastSpokenMessage = msg;
    return msg;
  }

  /// Memilih ajakan berbicara dengan kata target
  String getSpeechInvitation(String targetWord) {
    final template = _selectRandomNonRepeating(speechInvitationTemplates);
    final populated = template.replaceAll('{word}', targetWord);
    _lastSpokenMessage = populated;
    return populated;
  }

  /// Memilih pesan selebrasi selesai aktivitas
  String getCompletionMessage() {
    final msg = _selectRandomNonRepeating(completionMessages);
    _lastSpokenMessage = msg;
    return msg;
  }

  String _selectRandomNonRepeating(List<String> options) {
    if (options.isEmpty) return '';
    if (options.length == 1) return options.first;

    // Filter pesan yang baru saja diucapkan agar tidak berulang
    final candidates = options.where((m) => m != _lastSpokenMessage).toList();
    final list = candidates.isNotEmpty ? candidates : options;
    return list[_random.nextInt(list.length)];
  }

  /// Reset history pesan (berguna untuk testing atau pergantian sesi)
  void resetHistory() {
    _lastSpokenMessage = null;
  }
}
