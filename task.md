# Kogo Voice Learning — Final Product Fix & End-to-End Integration Plan

## Status: COMPLETED

### Prioritas 1: Hilangkan Ketergantungan Tombol Sinkronisasi Manual
- [x] 1.1 Hapus tombol manual sync dari antarmuka utama/profil anak; jadikan sinkronisasi 100% otomatis di latar belakang.
- [x] 1.2 Tambahkan badge/indikator status koneksi & sinkronisasi non-intrusif (Online / Offline / Sinkronisasi Berjalan) di UI.
- [x] 1.3 Perkuat trigger auto-sync saat pembukaan aplikasi (app startup / resume) dan pasca penyimpanan jawaban/progres/pencapaian.
- [x] 1.4 Verifikasi idempotensi dan pencegahan race-condition concurrent sync.

### Prioritas 2: Login, Register, dan Isolasi Data Antarakun
- [x] 2.1 Perbaiki profil home page: pastikan nama anak yang ditampilkan berasal dari akun yang sedang login (bukan fallback hardcoded 'Sarah').
- [x] 2.2 Pastikan register anak/peneliti menyimpan identitas ke SQLite dan terhubung dengan backend / PostgreSQL.
- [x] 2.3 Pastikan pemuatan progres, pencapaian, dan jawaban difilter secara ketat berdasarkan `child_id` akun aktif.
- [x] 2.4 Uji dan buktikan isolasi data: Akun A (misal: "Bintang") dan Akun B (misal: "Awan") memiliki riwayat, skor, dan sesi terisolasi.

### Prioritas 3: PostgreSQL dan Sinkronisasi Data Penelitian
- [x] 3.1 Audit relasi Foreign Key SQLite vs PostgreSQL untuk sesi, jawaban, evaluasi, dan pencapaian.
- [x] 3.2 Pastikan format data sinkronisasi batch mencakup seluruh metrik penelitian (skor kemiripan, durasi, status evaluasi, retry).
- [x] 3.3 Verifikasi data benar-benar tersimpan di PostgreSQL `kogo_research` via read-only query.

### Prioritas 4: ElevenLabs TTS & Feedback Suara
- [x] 4.1 Pastikan fallback cerdas jika audio aset lokal tidak tersedia -> panggil proxy TTS backend `/api/voice/tts`.
- [x] 4.2 Sediakan indikator visual loading audio & pencegahan error jika audio gagal diputar.
- [x] 4.3 Verifikasi lifecycle pemutaran audio (stop audio saat ganti soal/layar, bebas memory leak).

### Prioritas 5: Speech Recognition & Skor Kemiripan
- [x] 5.1 Pastikan izin mikrofon diperiksa dan ditangani dengan ramah anak.
- [x] 5.2 Evaluasi kemiripan pengucapan menggunakan Levenshtein normalized secara konsisten.
- [x] 5.3 Berikan kesempatan mencoba kembali tanpa menghapus log percobaan sebelumnya.

### Prioritas 6: Mini-Game Icebreaking Anak
- [x] 6.1 Pastikan 3 varian mini-game (Surprise Star, Color Balloons, Catch Stars) interaktif, responsif, dan menyenangkan.
- [x] 6.2 Pastikan counter 5 soal tidak ter-reset atau memicu pop-up berulang saat rotasi/rebuild widget.
- [x] 6.3 Pastikan setelah selesai mini-game, navigasi kembali melanjutkan soal pembelajaran secara mulus.

### Prioritas 7: Efek Suara dan Musik Latar Anak
- [x] 7.1 Integrasikan efek suara ceria untuk jawaban benar (`assets/audio/correct/`), suara dorongan semangat untuk jawaban salah (`assets/audio/incorrect/`), dan efek mikrofon.
- [x] 7.2 Implementasikan BGM (Background Music) instrumental lembut dengan kontrol toggle Play/Pause/Mute dan pengaturan volume di Settings.
- [x] 7.3 Hentikan/rendahkan (duck) BGM saat anak sedang merekam suara ke mikrofon.

### Prioritas 8: Perbaikan UX & Responsive Layout
- [x] 8.1 Sediakan dialog/halaman Settings untuk pengaturan volume suara & musik.
- [x] 8.2 Tampilkan avatar & nama anak yang aktif di Home & AppBar.
- [x] 8.3 Pastikan tata letak responsif pada berbagai ukuran layar tablet dan smartphone.

### Prioritas 9: Pengujian Menyeluruh & Bukti
- [x] 9.1 Jalankan `flutter analyze` dan pastikan zero error (No issues found).
- [x] 9.2 Jalankan unit & widget tests untuk isolasi akun, auto-sync, dan mini-games (16/16 lulus).
- [x] 9.3 Jalankan query verifikasi data di database PostgreSQL `kogo_research`.
