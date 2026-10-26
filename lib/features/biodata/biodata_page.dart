import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../../data/learner_repository.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/voice_lines.dart';
import '../../services/audio/voice_service.dart';
import '../../services/speech/speech_listener.dart';
import '../../services/sync/sync_service.dart';
import '../../services/system_settings.dart';
import '../shell/home_shell.dart';

/// Halaman Isi Biodata (proposal Gambar 3.4, 3.12, 3.22): Nama, Sekolah, Umur.
/// Mendukung beberapa anak pada satu perangkat (prosedur uji lapangan).
class BiodataPage extends StatefulWidget {
  const BiodataPage({super.key, this.editing, this.choose = false});

  /// Mengubah biodata anak yang sudah ada.
  final Learner? editing;

  /// Dibuka dari Profil untuk memilih/menambah anak.
  final bool choose;

  static Route<void> route({Learner? editing, bool choose = false}) => MaterialPageRoute(
    settings: const RouteSettings(name: 'biodata'),
    builder: (_) => BiodataPage(editing: editing, choose: choose),
  );

  @override
  State<BiodataPage> createState() => _BiodataPageState();
}

class _BiodataPageState extends State<BiodataPage> {
  static const avatars = ['🐻', '🐰', '🐱', '🐶', '🐼', '🦊'];

  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.editing?.name);
  late final _school = TextEditingController(text: widget.editing?.school);
  late int? _age = widget.editing?.age;
  late String _avatar = widget.editing?.avatar ?? avatars.first;
  String? _ageError;
  List<Learner> _existing = const [];
  bool _showForm = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadExisting());
    if (widget.editing == null) {
      final line = VoiceLines.welcomeNew();
      unawaited(VoiceService.instance.say(line.text, mood: line.mood));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    if (widget.editing != null) return;
    final all = await AppSession.instance.learners.all();
    if (!mounted) return;
    setState(() {
      _existing = all;
      _showForm = all.isEmpty;
    });
  }

  Future<void> _choose(Learner learner) async {
    AudioService.instance.play(Sfx.pop);
    await AppSession.instance.activate(learner);
    if (!mounted) return;
    _goHome();
  }

  void _goHome() {
    unawaited(VoiceService.instance.stop());
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        settings: const RouteSettings(name: HomeShell.routeName),
        builder: (_) => const HomeShell(),
      ),
      (_) => false,
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    final ageError = BiodataValidation.age(_age);
    setState(() => _ageError = ageError);
    final valid = _formKey.currentState!.validate() && ageError == null;
    if (!valid) {
      AudioService.instance.play(Sfx.wrong);
      return;
    }
    setState(() => _saving = true);
    final repo = AppSession.instance.learners;
    try {
      final editing = widget.editing;
      if (editing != null) {
        final updated = await repo.update(editing, name: _name.text, school: _school.text, age: _age!);
        AppSession.instance.updateLearner(updated);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Biodata tersimpan ✓')));
        Navigator.of(context).pop();
        return;
      }
      final learner = await repo.create(name: _name.text, school: _school.text, age: _age!, avatar: _avatar);
      await AppSession.instance.activate(learner);
      SyncService.instance.syncInBackground();
      AudioService.instance.play(Sfx.complete);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Halo, ${learner.firstName}! Biodata tersimpan ✓')));
      await _setupCheck();
      if (mounted) _goHome();
    } on ArgumentError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${e.message}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menyimpan. Coba lagi.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Meminta izin mikrofon dan memastikan suara Bahasa Indonesia tersedia.
  Future<void> _setupCheck() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Kogo ingin mendengar suaramu 🎤'),
        content: const Text(
          'Aplikasi memakai mikrofon untuk mendengar anak mengucapkan kata. '
          'Tekan "Izinkan" pada jendela berikutnya, ya.',
        ),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Lanjut'))],
      ),
    );
    if (ok != true) return;
    final error = await SpeechListeners.current.prepare();
    await VoiceService.instance.init();
    if (!mounted) return;
    final needsVoice = !VoiceService.instance.indonesianAvailable;
    if (error == null && !needsVoice) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Perlu sedikit pengaturan'),
        content: Text(
          [
            if (error == ListenError.permissionDenied) '• Izin mikrofon belum diberikan.',
            if (error == ListenError.notAvailable) '• Layanan pengenalan suara Google belum tersedia di perangkat ini.',
            if (needsVoice) '• Suara Bahasa Indonesia (Text-to-Speech) belum terpasang.',
            '\nAnda tetap dapat mengaturnya nanti dari Profil → Mode Peneliti.',
          ].join('\n'),
        ),
        actions: [
          if (needsVoice) TextButton(onPressed: () => unawaited(SystemSettings.openTtsSettings()), child: const Text('Pengaturan Suara')),
          if (error == ListenError.permissionDenied)
            TextButton(onPressed: () => unawaited(SystemSettings.openAppSettings()), child: const Text('Izin Aplikasi')),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Mengerti')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;
    return Scaffold(
      body: KogoBackground(
        colors: const [KogoColors.yellow100, KogoColors.orange50, KogoColors.pink50],
        decorations: const [
          FloatingDecoration('⭐', left: 24, top: 70, size: 30),
          FloatingDecoration('☁️', right: 20, top: 120, size: 42, opacity: 0.6, tilt: 0, duration: Duration(seconds: 4)),
        ],
        child: SafeArea(
          child: Column(
            children: [
              if (editing || widget.choose)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Kembali'),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  child: Column(
                    children: [
                      if (_existing.isNotEmpty) ...[_existingList(), const SizedBox(height: 16)],
                      if (_showForm) _form(editing) else _addButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _existingList() {
    return Entrance.slide(
      child: KogoCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Siapa yang mau belajar?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: KogoColors.gray800),
            ),
            const SizedBox(height: 12),
            for (final learner in _existing)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Pressable(
                  onTap: () => unawaited(_choose(learner)),
                  semanticLabel: 'Pilih ${learner.name}',
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: learner.id == AppSession.instance.learner?.id ? KogoColors.purple100 : KogoColors.gray100,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        GradientCircle(
                          colors: const [KogoColors.purple400, KogoColors.pink500],
                          child: Text(learner.avatar, style: const TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                learner.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${learner.school} · ${learner.age} tahun',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: KogoColors.gray500),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.play_circle_fill_rounded, color: KogoColors.purple500, size: 32),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addButton() {
    return GradientButton(
      label: 'Tambah Anak Baru',
      icon: Icons.person_add_alt_1_rounded,
      colors: const [KogoColors.purple400, KogoColors.pink500],
      onTap: () => setState(() => _showForm = true),
    );
  }

  Widget _form(bool editing) {
    return Entrance.slide(
      delay: const Duration(milliseconds: 100),
      child: KogoCard(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Text(
                'Kogo Belajar',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: KogoColors.gray800),
              ),
              const SizedBox(height: 12),
              Loop.bob(
                height: 8,
                child: GradientCircle(
                  colors: const [KogoColors.yellow300, KogoColors.orange400],
                  size: 104,
                  border: 4,
                  child: Text(_avatar, style: const TextStyle(fontSize: 54)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                editing ? 'Ubah biodata di bawah ini' : 'Selamat datang di Kogo Belajar!\nIsi kolom di bawah ini, ya.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: KogoColors.teal600),
              ),
              if (!editing) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final a in avatars)
                      Pressable(
                        onTap: () {
                          AudioService.instance.play(Sfx.pop);
                          setState(() => _avatar = a);
                        },
                        semanticLabel: 'Pilih gambar $a',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _avatar == a ? KogoColors.purple100 : KogoColors.gray100,
                            border: Border.all(color: _avatar == a ? KogoColors.purple500 : Colors.transparent, width: 3),
                          ),
                          child: Text(a, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: BiodataValidation.maxNameLength,
                decoration: const InputDecoration(labelText: 'Nama', prefixIcon: Icon(Icons.person_rounded), counterText: ''),
                validator: BiodataValidation.name,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _school,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                maxLength: BiodataValidation.maxSchoolLength,
                decoration: const InputDecoration(labelText: 'Sekolah', prefixIcon: Icon(Icons.school_rounded), counterText: ''),
                validator: BiodataValidation.school,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Umur',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _ageError == null ? KogoColors.gray600 : KogoColors.red600),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final age in const [BiodataValidation.minAge, BiodataValidation.maxAge]) ...[
                    if (age != BiodataValidation.minAge) const SizedBox(width: 12),
                    Expanded(
                      child: Pressable(
                        onTap: () {
                          AudioService.instance.play(Sfx.tap);
                          setState(() {
                            _age = age;
                            _ageError = null;
                          });
                        },
                        semanticLabel: '$age tahun',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: _age == age ? KogoColors.br(KogoColors.orange400, KogoColors.red400) : null,
                            color: _age == age ? null : KogoColors.gray100,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            '🎂 $age tahun',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _age == age ? KogoColors.white : KogoColors.gray700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (_ageError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _ageError!,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: KogoColors.red600),
                  ),
                ),
              const SizedBox(height: 22),
              GradientButton(
                label: _saving ? 'Menyimpan...' : 'Selesai',
                icon: Icons.check_rounded,
                expand: true,
                onTap: _saving ? null : () => unawaited(_submit()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
