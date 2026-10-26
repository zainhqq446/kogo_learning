// Renders every screen with real fonts to PNG files for visual review against
// the Figma design. Skipped unless KOGO_SCREENSHOTS=<output dir> is set:
//   KOGO_SCREENSHOTS=/tmp/shots flutter test test/screenshots/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/app/app_session.dart';
import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';
import 'package:kogo_voice_learning/core/theme/kogo_theme.dart';
import 'package:kogo_voice_learning/features/biodata/biodata_page.dart';
import 'package:kogo_voice_learning/features/games/game_page.dart';
import 'package:kogo_voice_learning/features/games/reward_dialog.dart';
import 'package:kogo_voice_learning/features/map/stage_map_page.dart';
import 'package:kogo_voice_learning/features/research/research_page.dart';
import 'package:kogo_voice_learning/features/shell/home_shell.dart';
import 'package:kogo_voice_learning/features/splash/splash_page.dart';
import 'package:kogo_voice_learning/services/speech/speech_listener.dart';

import '../helpers/fakes.dart';
import '../helpers/test_database.dart';

final _outDir = Platform.environment['KOGO_SCREENSHOTS'];

Future<void> _loadFonts() async {
  const material = '/opt/sdk/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$material/Roboto-$w.ttf').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('$material/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
  final emoji = FontLoader('NotoColorEmoji')
    ..addFont(Future.value(ByteData.sublistView(File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf').readAsBytesSync())));
  await emoji.load();
}

final _root = GlobalKey();

Widget _app(Widget home) {
  final theme = KogoTheme.light;
  return RepaintBoundary(
    key: _root,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: const ['NotoColorEmoji']),
      ),
      builder: (context, child) => DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Roboto', fontFamilyFallback: ['NotoColorEmoji']),
        child: child!,
      ),
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(() async {
    final boundary = _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    if (_outDir == null) return;
    Directory(_outDir!).createSync(recursive: true);
    await _loadFonts();
  });

  setUp(() async {
    await useFreshTestDatabase();
    AppSession.instance = AppSession();
    SpeechListeners.current = FakeSpeechListener();
  });

  Future<void> seedLearner({int completedNodes = 0, Materi materi = Materi.duaSuku}) async {
    final session = AppSession.instance;
    final kid = await session.learners.create(name: 'Sarah Putri', school: 'TK Pertiwi', age: 6, avatar: '🐰');
    await session.activate(kid);
    final nodes = Curriculum.nodesOf(materi);
    for (var i = 0; i < completedNodes; i++) {
      final s = await session.progress.startSession(learnerId: kid.id, node: nodes[i]);
      await session.progress.completeSession(sessionId: s, learnerId: kid.id, node: nodes[i], totalItems: 4, firstTryCorrect: i.isEven ? 4 : 2);
    }
    await session.refresh();
  }

  testWidgets('screenshots', (tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const SplashPage(minDuration: Duration(hours: 1))));
    await tester.pump();
    await _shot(tester, '01_splash');

    await tester.pumpWidget(_app(const BiodataPage()));
    await tester.pumpAndSettle();
    await _shot(tester, '02_biodata');

    await tester.runAsync(() => seedLearner(completedNodes: 7));
    await tester.pumpWidget(_app(const HomeShell()));
    await tester.pumpAndSettle();
    await _shot(tester, '03_beranda');

    await tester.tap(find.text('Hadiah'));
    await tester.pumpAndSettle();
    await _shot(tester, '04_hadiah');

    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    await _shot(tester, '05_profil');

    await tester.pumpWidget(_app(const StageMapPage(materi: Materi.duaSuku)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await _shot(tester, '06_peta');

    final nodes = Curriculum.nodesOf(Materi.duaSuku);
    final names = {
      GameType.listenRepeat: '07_dengar_ulangi',
      GameType.findObject: '08_cari_objek',
      GameType.missingLetter: '09_huruf_hilang',
      GameType.matching: '10_cocokkan',
      GameType.listening: '11_dengar_pilih',
    };
    for (final entry in names.entries) {
      final node = nodes.firstWhere((n) => n.game == entry.key);
      await tester.pumpWidget(_app(GamePage(key: ValueKey(entry.value), node: node)));
      await tester.pumpAndSettle();
      await _shot(tester, entry.value);
    }
    final fill = nodes.firstWhere((n) => n.game == GameType.fillBlank);
    await tester.pumpWidget(_app(GamePage(key: const ValueKey('fill'), node: fill)));
    await tester.pumpAndSettle();
    await _shot(tester, '12_isi_huruf_kosong');

    final letters = Curriculum.nodesOf(Materi.huruf);
    await tester.pumpWidget(_app(GamePage(key: const ValueKey('huruf'), node: letters.first)));
    await tester.pumpAndSettle();
    await _shot(tester, '13_huruf_dengar_ulangi');

    await tester.pumpWidget(_app(const RewardDialog(stars: 3, newTiers: [RewardTier.perunggu], hasNext: true)));
    await tester.pump(const Duration(seconds: 2)); // bintang muncul satu per satu
    await tester.pumpAndSettle();
    await _shot(tester, '14_hadiah_dialog');

    await tester.pumpWidget(_app(const ResearchPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await _shot(tester, '15_mode_peneliti');

    // Habiskan timer yang tertunda (splash dibekukan 1 jam, suara, sinkronisasi).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(hours: 2));
  }, skip: _outDir == null);
}
