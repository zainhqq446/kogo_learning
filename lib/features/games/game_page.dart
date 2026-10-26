import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../core/curriculum/curriculum.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/voice_service.dart';
import '../../services/speech/speech_listener.dart';
import '../../services/sync/sync_service.dart';
import 'fill_blank_game.dart';
import 'find_object_game.dart';
import 'game_controller.dart';
import 'game_scaffold.dart';
import 'listen_repeat_game.dart';
import 'listening_game.dart';
import 'matching_game.dart';
import 'missing_letter_game.dart';
import 'reward_dialog.dart';

/// Parameter bersama untuk setiap permainan.
class GameProps {
  const GameProps({required this.node, required this.controller, required this.onProgress, required this.onComplete});

  final LearningNode node;
  final GameController controller;

  /// Melaporkan jumlah soal yang sudah selesai (untuk indikator kemajuan).
  final void Function(int done) onProgress;
  final Future<void> Function() onComplete;
}

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.node});

  final LearningNode node;

  static Route<void> route(LearningNode node) => PageRouteBuilder<void>(
    settings: RouteSettings(name: 'game/${node.materi.code}/${node.index}'),
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, _, _) => GamePage(node: node),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(animation), child: child),
    ),
  );

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final GameController _controller;
  int _done = 0;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    final learner = AppSession.instance.learner;
    _controller = GameController(node: widget.node, learnerId: learner?.id ?? -1);
    if (learner != null) unawaited(_controller.start());
    unawaited(AudioService.instance.startMusic());
  }

  @override
  void dispose() {
    unawaited(VoiceService.instance.stop());
    unawaited(SpeechListeners.current.cancel());
    unawaited(AudioService.instance.setListening(false));
    super.dispose();
  }

  Future<bool> _onExit() async {
    final ok = await confirmExitGame(context);
    if (ok) {
      await VoiceService.instance.stop();
      await _controller.abandon();
    }
    return ok;
  }

  Future<void> _onComplete() async {
    if (_completing) return;
    _completing = true;
    setState(() => _done = _controller.totalItems);
    final result = await _controller.finish();
    await AppSession.instance.refresh();
    SyncService.instance.syncInBackground();
    if (!mounted) return;
    final nodes = Curriculum.nodesOf(widget.node.materi);
    final hasNext = widget.node.index + 1 < nodes.length;
    final action = await RewardDialog.show(
      context,
      result: result,
      fallbackStars: Curriculum.starsFor(firstTryCorrect: _controller.firstTryCorrect, total: _controller.totalItems),
      hasNext: hasNext,
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    switch (action) {
      case RewardAction.next:
        navigator.pushReplacement(GamePage.route(nodes[widget.node.index + 1]));
      case RewardAction.replay:
        navigator.pushReplacement(GamePage.route(widget.node));
      case RewardAction.home:
        navigator.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final props = GameProps(
      node: widget.node,
      controller: _controller,
      onProgress: (done) {
        if (mounted && done != _done) setState(() => _done = done);
      },
      onComplete: _onComplete,
    );
    return GameScaffold(
      game: widget.node.game,
      progress: _done,
      total: _controller.totalItems,
      onExit: _onExit,
      child: switch (widget.node.game) {
        GameType.listenRepeat => ListenRepeatGame(props: props, listener: SpeechListeners.current),
        GameType.findObject => FindObjectGame(props: props),
        GameType.missingLetter => MissingLetterGame(props: props),
        GameType.matching => MatchingGame(props: props),
        GameType.listening => ListeningGame(props: props),
        GameType.fillBlank => FillBlankGame(props: props),
      },
    );
  }
}
