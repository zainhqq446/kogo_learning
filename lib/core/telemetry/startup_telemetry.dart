import 'package:flutter/foundation.dart';

/// Telemetri performa startup khusus mode development.
/// Mengukur execution milestone dari main hingga first frame dan secondary data.
/// Memastikan tidak ada data pribadi anak atau API key yang dicatat.
class StartupTelemetry {
  StartupTelemetry._();

  static final Stopwatch _stopwatch = Stopwatch();
  static bool _hasReportedFirstFrame = false;
  static bool _hasReportedSecondaryData = false;

  static void onMainStart() {
    if (kDebugMode && !_stopwatch.isRunning) {
      _stopwatch.start();
      debugPrint('[STARTUP] main start (+0 ms)');
    }
  }

  static void onAppStart() {
    if (kDebugMode) {
      debugPrint('[STARTUP] app start (+${_stopwatch.elapsedMilliseconds} ms)');
    }
  }

  static void onHomeInitStart() {
    if (kDebugMode) {
      debugPrint('[STARTUP] home init start (+${_stopwatch.elapsedMilliseconds} ms)');
    }
  }

  static void onHomeCriticalDataLoaded(int stageCount) {
    if (kDebugMode) {
      debugPrint(
        '[STARTUP] home critical data loaded ($stageCount stages) (+${_stopwatch.elapsedMilliseconds} ms)',
      );
    }
  }

  static void onFirstFrame() {
    if (kDebugMode && !_hasReportedFirstFrame) {
      _hasReportedFirstFrame = true;
      debugPrint(
        '[STARTUP] first frame rendered! Splash to HomePage UI: ${_stopwatch.elapsedMilliseconds} ms',
      );
    }
  }

  static void onSecondaryDataComplete() {
    if (kDebugMode && !_hasReportedSecondaryData) {
      _hasReportedSecondaryData = true;
      debugPrint(
        '[STARTUP] secondary data complete (Rewards & Profile ready): +${_stopwatch.elapsedMilliseconds} ms',
      );
    }
  }
}
