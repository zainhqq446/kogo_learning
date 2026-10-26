import 'package:flutter/foundation.dart';

import '../data/learner_repository.dart';
import '../data/progress_repository.dart';

/// Status aplikasi yang dibagikan antar-layar: anak yang sedang aktif dan
/// ringkasan progresnya (bintang, hadiah, beruntun).
class AppSession extends ChangeNotifier {
  AppSession({LearnerRepository? learners, ProgressRepository? progress})
    : learners = learners ?? LearnerRepository(),
      progress = progress ?? ProgressRepository();

  static AppSession instance = AppSession();

  final LearnerRepository learners;
  final ProgressRepository progress;

  Learner? _learner;
  LearnerStats _stats = LearnerStats.empty;

  Learner? get learner => _learner;
  LearnerStats get stats => _stats;

  /// Memuat profil aktif terakhir. `false` bila belum ada (tampilkan Biodata).
  Future<bool> restore() async {
    _learner = await learners.active();
    await refresh();
    return _learner != null;
  }

  Future<void> activate(Learner learner) async {
    await learners.setActive(learner.id);
    _learner = learner;
    await refresh();
  }

  Future<void> signOut() async {
    await learners.clearActive();
    _learner = null;
    _stats = LearnerStats.empty;
    notifyListeners();
  }

  Future<void> refresh() async {
    final current = _learner;
    _stats = current == null ? LearnerStats.empty : await progress.stats(current.id);
    notifyListeners();
  }

  Future<void> markRewardsSeen() async {
    final current = _learner;
    if (current == null || _stats.unseenRewards == 0) return;
    await progress.markRewardsSeen(current.id);
    await refresh();
  }

  void updateLearner(Learner learner) {
    _learner = learner;
    notifyListeners();
  }
}
