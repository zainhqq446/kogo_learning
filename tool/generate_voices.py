import asyncio
import os
import edge_tts

# Voice: id-ID-GadisNeural (Warm, enthusiastic, cheerful Indonesian female teacher/companion)
VOICE = "id-ID-GadisNeural"
# Pitch slightly cheerful (+5Hz / +8Hz), rate calm and clear (-4% for early childhood clarity)
RATE = "-4%"
PITCH = "+8Hz"

OUTPUT_DIR = "assets/audio"

AUDIO_FILES = {
    # 1. INSTRUKSI
    "instructions/instruction_01.mp3": "Yuk, dengarkan baik-baik ya!",
    "instructions/instruction_02.mp3": "Ayo kita coba bersama!",
    "instructions/instruction_03.mp3": "Sekarang giliran kamu yaa!",
    "instructions/instruction_04.mp3": "Dengarkan dulu, siap? Kita mulai!",
    "instructions/instruction_05.mp3": "Ayo kita belajar bersama dengan riang!",
    
    # 2. AJAKAN BERBICARA (Speech Invitation Prefix)
    "invitations/invite_01.mp3": "Sekarang, coba ucapkan",
    "invitations/invite_02.mp3": "Yuk, bilang kata ini",
    "invitations/invite_03.mp3": "Ayo ikuti Kakak, katakan",
    "invitations/invite_04.mp3": "Sekarang giliranmu, coba katakan",
    "invitations/invite_05.mp3": "Ayo, kamu pasti bisa bilang",

    # 3. JAWABAN BENAR (Correct Praise)
    "correct/correct_01.mp3": "Hebat!",
    "correct/correct_02.mp3": "Wah, benar!",
    "correct/correct_03.mp3": "Bagus sekali!",
    "correct/correct_04.mp3": "Keren!",
    "correct/correct_05.mp3": "Yeay, kamu berhasil!",
    "correct/correct_06.mp3": "Pintar sekali!",
    "correct/correct_07.mp3": "Mantap, jawabanmu tepat!",
    "correct/correct_08.mp3": "Luar biasa, kamu hebat!",

    # 4. HAMPIR BENAR (Almost Correct / Near Target)
    "almost_correct/almost_01.mp3": "Hampir benar! Coba lagi ya.",
    "almost_correct/almost_02.mp3": "Sudah dekat! Ayo coba sekali lagi.",
    "almost_correct/almost_03.mp3": "Bagus, sedikit lagi pasti pas!",
    "almost_correct/almost_04.mp3": "Hampir berhasil! Coba pelan-pelan yaa.",

    # 5. SALAH / BELUM TEPAT (Gentle encouragement, no shaming)
    "incorrect/retry_01.mp3": "Enggak apa-apa, yuk coba sekali lagi!",
    "incorrect/retry_02.mp3": "Kita coba lagi yaa, kamu pasti bisa!",
    "incorrect/retry_03.mp3": "Tenang saja, ayo kita ulangi bersama!",
    "incorrect/retry_04.mp3": "Tarik napas dulu, lalu coba lagi yaa!",

    # 6. TIDAK TERDETEKSI (No voice detected)
    "no_recognition/no_rec_01.mp3": "Suaramu belum terdengar jelas. Coba tekan mikrofon lagi ya!",
    "no_recognition/no_rec_02.mp3": "Belum terdengar nih. Yuk coba dekatkan suaramu!",
    "no_recognition/no_rec_03.mp3": "Suaranya masih malu-malu. Ayo katakan dengan jelas!",

    # 7. STREAK (3 or more correct in a row)
    "streak/streak_01.mp3": "Wah, hebat! Kamu keren sekali!",
    "streak/streak_02.mp3": "Wow, kamu makin pintar!",
    "streak/streak_03.mp3": "Luar biasa! Sudah berkali-kali benar!",
    "streak/streak_04.mp3": "Yeay! Tiga kali benar berturut-turut!",

    # 8. COMPLETION (Lesson completed)
    "completion/complete_01.mp3": "Yeay, kamu sudah selesai! Kamu hebat hari ini!",
    "completion/complete_02.mp3": "Hebat sekali! Kamu berhasil menyelesaikan semua tantangan!",
    "completion/complete_03.mp3": "Keren! Terima kasih sudah belajar bersama dengan ceria!",

    # 9. GAME INTROS & EXPLANATIONS (Voice Companion for each game)
    "games/find_object_intro_01.mp3": "Yuk, cari benda yang benar! Dengar baik-baik ya!",
    "games/find_object_intro_02.mp3": "Ayo kita cari gambar yang tepat bersama-sama!",
    "games/matching_intro_01.mp3": "Yuk, kita cocokkan! Cari gambar yang cocok dengan pasangannya ya!",
    "games/matching_intro_02.mp3": "Ayo pasangkan bagian-bagian kata ini sampai pas!",
    "games/listen_carefully_intro_01.mp3": "Sekarang dengarkan baik-baik ya, lalu pilih jawaban yang benar!",
    "games/listen_carefully_intro_02.mp3": "Yuk, dengarkan suaranya dengan teliti, siap?",
    "games/missing_letter_intro_01.mp3": "Wah, ada huruf yang hilang! Ayo bantu lengkapi kata ini ya!",
    "games/missing_letter_intro_02.mp3": "Ayo tebak huruf apa yang hilang dari kata ini!",
    "games/listen_repeat_intro_01.mp3": "Yuk, dengarkan dulu! Lalu ikuti ucapan Kakak ya!",

    # 10. GAME TRANSITIONS & ENCOURAGEMENTS
    "games/transition_next_01.mp3": "Bagus! Sekarang kita lanjut ke soal berikutnya ya!",
    "games/transition_next_02.mp3": "Mantap! Ayo kita lanjutkan ke pertanyaan berikutnya!",
    "games/encouragement_look_01.mp3": "Ayo lihat baik-baik, menurutmu yang mana ya?",
    "games/encouragement_look_02.mp3": "Tenang saja, perhatikan gambarnya pelan-pelan ya!",

    # 11. TARGET WORDS (Vocabulary used across lessons)
    "words/a.mp3": "A",
    "words/b.mp3": "B",
    "words/c.mp3": "C",
    "words/d.mp3": "D",
    "words/e.mp3": "E",
    "words/apel.mp3": "Apel",
    "words/bola.mp3": "Bola",
    "words/buku.mp3": "Buku",
    "words/meja.mp3": "Meja",
    "words/sapi.mp3": "Sapi",
    "words/kaki.mp3": "Kaki",
    "words/sepatu.mp3": "Sepatu",
    "words/kereta.mp3": "Kereta",
    "words/kelinci.mp3": "Kelinci",
    "words/kamera.mp3": "Kamera",
    "words/helikopter.mp3": "Helikopter",
    "words/matahari.mp3": "Matahari",
    "words/laboratorium.mp3": "Laboratorium",
}

async def generate_audio(relative_path: str, text: str):
    full_path = os.path.join(OUTPUT_DIR, relative_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    communicate = edge_tts.Communicate(text, VOICE, rate=RATE, pitch=PITCH)
    await communicate.save(full_path)
    print(f"Generated: {relative_path} -> '{text}'")

async def main():
    print(f"Starting voice generation using {VOICE}...")
    for rel_path, text in AUDIO_FILES.items():
        await generate_audio(rel_path, text)
    print(f"Successfully generated all {len(AUDIO_FILES)} voice files!")

if __name__ == "__main__":
    asyncio.run(main())
