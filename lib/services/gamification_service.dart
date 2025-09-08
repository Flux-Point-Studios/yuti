import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GamificationState {
  final int totalXp;
  final int level; // current level (min 1)
  final int xpIntoLevel; // xp accumulated within current level
  final int xpForNextLevel; // xp needed to reach next level from current level start
  final Set<String> completedTasks;

  GamificationState({
    required this.totalXp,
    required this.level,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
    required this.completedTasks,
  });
}

class GamificationService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _xpKey = 'gami_total_xp';
  static const String _tasksKey = 'gami_tasks_completed';

  // Singleton
  static final GamificationService _instance = GamificationService._internal();
  factory GamificationService() => _instance;
  GamificationService._internal();

  // Base XP increment per level (level L → L+1 requires L * baseXp)
  static const int _baseXpPerLevel = 50; // 50, 100, 150, ...

  static const Map<String, String> taskIdToLabel = {
    'task_add_wallet': 'Add a wallet',
    'task_first_swap': 'Create your first swap',
    'task_first_send': 'Send an asset',
  };

  Future<int> _getTotalXp() async {
    final v = await _storage.read(key: _xpKey);
    return int.tryParse(v ?? '0') ?? 0;
  }

  Future<Set<String>> _getCompletedTasks() async {
    final v = await _storage.read(key: _tasksKey);
    if (v == null || v.isEmpty) return <String>{};
    try {
      final list = (json.decode(v) as List).cast<String>();
      return list.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _setTotalXp(int xp) async {
    await _storage.write(key: _xpKey, value: xp.toString());
  }

  Future<void> _setCompletedTasks(Set<String> tasks) async {
    await _storage.write(key: _tasksKey, value: json.encode(tasks.toList()));
  }

  // Compute current level and progress given total XP
  // Level 1 start at 0 XP, need 50 XP to reach level 2, then +100, +150...
  GamificationState computeStateFromTotalXp(int totalXp, Set<String> completed) {
    int level = 1;
    int xpRemaining = totalXp;
    int neededForNext = _baseXpPerLevel; // for level 1→2

    while (xpRemaining >= neededForNext) {
      xpRemaining -= neededForNext;
      level += 1;
      neededForNext = level * _baseXpPerLevel; // next step increases by baseXp each level
    }

    return GamificationState(
      totalXp: totalXp,
      level: level,
      xpIntoLevel: xpRemaining,
      xpForNextLevel: neededForNext,
      completedTasks: completed,
    );
  }

  Future<GamificationState> getState() async {
    final totalXp = await _getTotalXp();
    final tasks = await _getCompletedTasks();
    return computeStateFromTotalXp(totalXp, tasks);
  }

  Future<GamificationState> addXp(int amount) async {
    final current = await _getTotalXp();
    final updated = current + amount;
    await _setTotalXp(updated);
    final tasks = await _getCompletedTasks();
    return computeStateFromTotalXp(updated, tasks);
  }

  // Award 10 XP for a task if not already completed
  Future<GamificationState> awardTask(String taskId) async {
    final tasks = await _getCompletedTasks();
    if (tasks.contains(taskId)) {
      return getState();
    }
    tasks.add(taskId);
    await _setCompletedTasks(tasks);
    return addXp(10);
  }

  bool isKnownTask(String taskId) => taskIdToLabel.containsKey(taskId);
} 