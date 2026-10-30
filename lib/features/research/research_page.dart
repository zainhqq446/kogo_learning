import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../core/constants/backend_config.dart';
import '../../core/curriculum/curriculum.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../../data/app_settings.dart';
import '../../data/progress_repository.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/voice_lines.dart';
import '../../services/audio/voice_service.dart';
import '../../services/speech/speech_listener.dart';
import '../../services/sync/sync_service.dart';
import '../../services/system_settings.dart';

/// Mode Peneliti (khusus orang tua/guru/peneliti, dibuka lewat gerbang orang
/// tua): metrik pengujian lapangan sesuai proposal Tabel 3.1, sinkronisasi
/// data ke server, dan pemeriksaan perangkat (mikrofon & suara Indonesia).
class ResearchPage extends StatefulWidget {
  const ResearchPage({super.key});

  static Route<void> route() => MaterialPageRoute(
    settings: const RouteSettings(name: 'research'),
    builder: (_) => const ResearchPage(),
  );

  @override
  State<ResearchPage> createState() => _ResearchPageState();
}

class _ResearchPageState extends State<ResearchPage> {
  final _settings = AppSettings();
  final _urlController = TextEditingController();
  ResearchMetrics? _learnerMetrics;
  ResearchMetrics? _allMetrics;
  int _pending = 0;
  int _rejected = 0;
  DateTime? _lastSync;
  DeviceStatus? _device;
  bool _syncing = false;
  String? _syncMessage;
  bool _soundOn = AudioService.instance.soundOn;
  bool _musicOn = AudioService.instance.musicOn;
  ListenError? _micStatus;
  bool _micChecked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final progress = AppSession.instance.progress;
    final learner = AppSession.instance.learner;
    final learnerMetrics = learner == null ? null : await progress.metrics(learnerId: learner.id);
    final all = await progress.metrics();
    final pending = await SyncService.instance.pendingCount();
    final rejected = await SyncService.instance.rejectedCount();
    final last = await SyncService.instance.lastSyncAt();
    final url = await SyncService.instance.apiBaseUrl();
    final device = await SyncService.instance.deviceStatus();
    if (!mounted) return;
    setState(() {
      _learnerMetrics = learnerMetrics;
      _allMetrics = all;
      _pending = pending;
      _rejected = rejected;
      _lastSync = last;
      _device = device;
      _urlController.text = url;
    });
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (!BackendConfig.isValid(url)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alamat server tidak valid.')));
      return;
    }
    final normalized = BackendConfig.normalize(url);
    final messenger = ScaffoldMessenger.of(context);
    await SyncService.instance.switchServer(normalized == BackendConfig.normalize(BackendConfig.defaultApiBaseUrl) ? null : normalized);
    _urlController.text = normalized;
    messenger.showSnackBar(const SnackBar(content: Text('Alamat server disimpan.')));
    await _load();
  }

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });
    final report = await SyncService.instance.syncNow(refreshDevice: true);
    final pending = await SyncService.instance.pendingCount();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncMessage = report.ok
          ? (report.nothingToSend
                ? (pending == 0 ? 'Semua data sudah terkirim.' : '$pending data belum dapat dikirim. Coba lagi nanti.')
                : 'Terkirim: ${report.learners} anak, ${report.sessions} sesi, ${report.attempts} jawaban'
                      '${report.rejected > 0 ? ' (${report.rejected} ditolak)' : ''}.')
          : report.message;
    });
    await _load();
  }

  Future<void> _checkMic() async {
    final status = await SpeechListeners.current.prepare();
    if (mounted) {
      setState(() {
        _micStatus = status;
        _micChecked = true;
      });
    }
  }

  Future<void> _setSound(bool on) async {
    AudioService.instance.soundOn = on;
    await _settings.setBool(AppSettings.soundOnKey, on);
    setState(() => _soundOn = on);
  }

  Future<void> _setMusic(bool on) async {
    await AudioService.instance.setMusicOn(on);
    await _settings.setBool(AppSettings.musicOnKey, on);
    setState(() => _musicOn = on);
  }

  @override
  Widget build(BuildContext context) {
    final learner = AppSession.instance.learner;
    return Scaffold(
      backgroundColor: KogoColors.purple50,
      appBar: AppBar(title: const Text('Mode Peneliti'), backgroundColor: KogoColors.white, surfaceTintColor: Colors.transparent),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section(
              'Metrik Pengujian Lapangan (Tabel 3.1)',
              Icons.analytics_rounded,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (learner != null) ...[
                    Text('Anak aktif: ${learner.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _metricsTable(_learnerMetrics),
                    const Divider(height: 28),
                  ],
                  const Text('Semua anak di perangkat ini', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _metricsTable(_allMetrics),
                  const SizedBox(height: 8),
                  const Text(
                    'STT Accuracy = ucapan benar ÷ total percobaan suara (Dengar & Ulangi). '
                    'Response Time = akhir ucapan terakhir yang tertangkap hingga hasil tampil. '
                    'Error Rate = sesi yang mengalami galat suara (tidak terdengar/gangguan) ÷ total sesi.',
                    style: TextStyle(fontSize: 12, color: KogoColors.gray500),
                  ),
                ],
              ),
            ),
            _section(
              'Sinkronisasi Server',
              Icons.cloud_sync_rounded,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Alamat API',
                      suffixIcon: IconButton(icon: const Icon(Icons.save_rounded), onPressed: () => unawaited(_saveUrl())),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Perangkat: ${_deviceLabel(_device)}'),
                  Text('Belum terkirim: $_pending data${_rejected > 0 ? ' · ditolak server: $_rejected' : ''}'),
                  Text('Terakhir sinkron: ${_lastSync == null ? '-' : _formatTime(_lastSync!)}'),
                  if (_syncMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _syncMessage!,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: KogoColors.purple700),
                    ),
                  ],
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _syncing ? null : () => unawaited(_sync()),
                    icon: _syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded),
                    label: Text(_syncing ? 'Mengirim...' : 'Sinkronkan Sekarang'),
                  ),
                ],
              ),
            ),
            _section(
              'Cek Perangkat',
              Icons.phone_android_rounded,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      VoiceService.instance.clipCount > 0 ? Icons.check_circle_rounded : Icons.info_rounded,
                      color: VoiceService.instance.clipCount > 0 ? KogoColors.green500 : KogoColors.orange500,
                    ),
                    title: const Text('Rekaman Suara Kogo'),
                    subtitle: Text(
                      VoiceService.instance.clipCount > 0
                          ? '${VoiceService.instance.clipCount} rekaman; kalimat lain memakai TTS perangkat'
                          : 'Belum ada rekaman — memakai TTS perangkat',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      VoiceService.instance.indonesianAvailable ? Icons.check_circle_rounded : Icons.error_rounded,
                      color: VoiceService.instance.indonesianAvailable ? KogoColors.green500 : KogoColors.red500,
                    ),
                    title: const Text('Suara Bahasa Indonesia (TTS)'),
                    subtitle: Text(VoiceService.instance.indonesianAvailable ? 'Tersedia' : 'Belum terpasang — buka Pengaturan Suara'),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => unawaited(VoiceService.instance.say(VoiceLines.voiceCheck.text, mood: VoiceLines.voiceCheck.mood)),
                        child: const Text('Tes Suara'),
                      ),
                      OutlinedButton(onPressed: () => unawaited(SystemSettings.openTtsSettings()), child: const Text('Pengaturan Suara')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      !_micChecked
                          ? Icons.help_rounded
                          : _micStatus == null
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: !_micChecked
                          ? KogoColors.gray400
                          : _micStatus == null
                          ? KogoColors.green500
                          : KogoColors.red500,
                    ),
                    title: const Text('Mikrofon & Google Speech-to-Text'),
                    subtitle: Text(
                      !_micChecked
                          ? 'Belum diperiksa'
                          : switch (_micStatus) {
                              null => 'Siap digunakan',
                              ListenError.permissionDenied => 'Izin mikrofon ditolak',
                              _ => 'Layanan pengenalan suara tidak tersedia',
                            },
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(onPressed: () => unawaited(_checkMic()), child: const Text('Periksa')),
                      OutlinedButton(onPressed: () => unawaited(SystemSettings.openAppSettings()), child: const Text('Izin Aplikasi')),
                    ],
                  ),
                ],
              ),
            ),
            _section(
              'Suara Aplikasi',
              Icons.music_note_rounded,
              Column(
                children: [
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Efek suara'), value: _soundOn, onChanged: (v) => unawaited(_setSound(v))),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Musik latar'), value: _musicOn, onChanged: (v) => unawaited(_setMusic(v))),
                ],
              ),
            ),
            _section(
              'Tentang',
              Icons.info_rounded,
              Text(
                'Kogo Belajar v${SyncService.appVersion}\n'
                'Implementasi Voice Recognition pada Media Pembelajaran Interaktif Berbasis Android '
                'untuk Eksplorasi Kata Anak Usia Dini.\n'
                'Materi: ${Materi.values.map((m) => m.title).join(', ')} · ${Curriculum.totalNodes} permainan.',
                style: const TextStyle(color: KogoColors.gray600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: KogoCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: KogoColors.purple600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  static String _deviceLabel(DeviceStatus? d) {
    if (d == null) return '-';
    if (!d.registered) return 'belum terdaftar di server';
    final id = d.deviceId == null ? '' : ' (ID ${d.deviceId!.substring(0, d.deviceId!.length.clamp(0, 8))})';
    return d.approved ? 'disetujui peneliti$id' : 'menunggu persetujuan peneliti$id';
  }

  Widget _metricsTable(ResearchMetrics? m) {
    if (m == null) return const Text('Memuat...');
    String pct(double? v) => v == null ? '-' : '${v.toStringAsFixed(1)}%';
    return Column(
      children: [
        _metricRow('STT Accuracy Rate', pct(m.sttAccuracy), m.sttAccuracy == null ? null : m.sttAccuracy! >= 70, '≥ 70%'),
        _metricRow('Task Completion Rate', pct(m.taskCompletion), m.taskCompletion == null ? null : m.taskCompletion! >= 75, '≥ 75%'),
        _metricRow(
          'System Response Time',
          m.avgResponseMs == null ? '-' : '${(m.avgResponseMs! / 1000).toStringAsFixed(2)} s',
          m.avgResponseMs == null ? null : m.avgResponseMs! <= 3000,
          '≤ 3 s',
        ),
        _metricRow('System Error Rate', pct(m.errorRate), m.errorRate == null ? null : m.errorRate! <= 10, '≤ 10%'),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Percobaan suara: ${m.sttAttempts} (benar ${m.sttCorrect}, error ${m.sttErrors}) · '
            'Sesi: ${m.sessionsCompleted}/${m.sessionsStarted} selesai, ${m.sessionsWithErrors} dengan error',
            style: const TextStyle(fontSize: 12, color: KogoColors.gray500),
          ),
        ),
      ],
    );
  }

  Widget _metricRow(String label, String value, bool? pass, String target) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pass == null
                  ? KogoColors.gray200
                  : pass
                  ? KogoColors.green100
                  : KogoColors.red100,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              target,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: pass == null
                    ? KogoColors.gray600
                    : pass
                    ? KogoColors.green600
                    : KogoColors.red600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
