import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents a player's current rank and score on a Play Games leaderboard.
class PlayGamesRank {
  final int rank;
  final int rawScore;
  final String displayRank;

  const PlayGamesRank({
    required this.rank,
    required this.rawScore,
    required this.displayRank,
  });
}

/// Represents a summary of unlocked and total Play Games achievements.
class PlayGamesAchievementsSummary {
  final int unlocked;
  final int total;

  const PlayGamesAchievementsSummary({
    required this.unlocked,
    required this.total,
  });
}

/// Thin platform-channel wrapper around Android Google Play Games Services v2.
///
/// Safe no-op on non-Android platforms and in headless unit tests where the
/// native channel is absent.
class PlayGamesService {
  PlayGamesService._();

  static final PlayGamesService instance = PlayGamesService._();

  static const MethodChannel _channel = MethodChannel(
    'page.puzzak.fractals/play_games',
  );

  // Leaderboard IDs
  static const String leaderboardPotatoemeter = 'CgkItYGz7tcWEAIQAQ';
  static const String leaderboardDeepestZoom = 'CgkItYGz7tcWEAIQAg';
  static const String leaderboardTotalTime = 'CgkItYGz7tcWEAIQAw';

  // Achievement IDs
  static const String achFirstDive = 'CgkItYGz7tcWEAIQBA';
  static const String achBeyondFloat32 = 'CgkItYGz7tcWEAIQBQ';
  static const String achPerturbationPioneer = 'CgkItYGz7tcWEAIQBg';
  static const String achPlanckScaleTourist = 'CgkItYGz7tcWEAIQBw';
  static const String achGoogolExplorer = 'CgkItYGz7tcWEAIQCA';
  static const String achWeightedPotato = 'CgkItYGz7tcWEAIQCQ';
  static const String achTurboTater = 'CgkItYGz7tcWEAIQCg';
  static const String achQuantumYam = 'CgkItYGz7tcWEAIQCw';
  static const String achMultiverseHopper = 'CgkItYGz7tcWEAIQDA';
  static const String achCartographer = 'CgkItYGz7tcWEAIQDQ';
  static const String achShareTheInfinity = 'CgkItYGz7tcWEAIQDg';
  static const String achLostInTheSpiral = 'CgkItYGz7tcWEAIQDw';

  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Converts a [zoom] factor (>= 1.0) into a 3-decimal fixed-point integer
  /// representation of log10(zoom) * 1000 (e.g. 1e5 -> 5000, 1e100 -> 100000).
  static int zoomToLeaderboardScore(double zoom) {
    if (!zoom.isFinite || zoom <= 1.0) return 0;
    final int scaled = (math.log(zoom) / math.ln10 * 1000.0).round();
    return scaled < 0 ? 0 : scaled;
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    if (!isSupportedPlatform) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> isSignedIn() async {
    final bool? result = await _invoke<bool>('isSignedIn');
    return result ?? false;
  }

  Future<bool> signIn() async {
    final bool? result = await _invoke<bool>('signIn');
    return result ?? false;
  }

  Future<String?> getPlayerName() async {
    return await _invoke<String>('getPlayerName');
  }

  Future<void> submitScore(String leaderboardId, int score) async {
    await _invoke<void>('submitScore', <String, Object?>{
      'leaderboardId': leaderboardId,
      'score': score,
    });
  }

  Future<PlayGamesRank?> loadPlayerScore(String leaderboardId) async {
    final Map<dynamic, dynamic>? raw =
        await _invoke<Map<dynamic, dynamic>>('loadPlayerScore', <String, Object?>{
      'leaderboardId': leaderboardId,
    });
    if (raw == null) return null;
    final dynamic rank = raw['rank'];
    final dynamic rawScore = raw['rawScore'];
    final dynamic displayRank = raw['displayRank'];
    if (rank is! num || rawScore is! num) return null;
    return PlayGamesRank(
      rank: rank.toInt(),
      rawScore: rawScore.toInt(),
      displayRank: displayRank is String && displayRank.isNotEmpty
          ? displayRank
          : '#${rank.toInt()}',
    );
  }

  Future<void> unlockAchievement(String achievementId) async {
    await _invoke<void>('unlockAchievement', <String, Object?>{
      'achievementId': achievementId,
    });
  }

  Future<void> setAchievementSteps(String achievementId, int steps) async {
    await _invoke<void>('setAchievementSteps', <String, Object?>{
      'achievementId': achievementId,
      'steps': steps,
    });
  }

  Future<void> showAllLeaderboards() async {
    await _invoke<void>('showAllLeaderboards');
  }

  Future<void> showLeaderboard(String leaderboardId) async {
    await _invoke<void>('showLeaderboard', <String, Object?>{
      'leaderboardId': leaderboardId,
    });
  }

  Future<void> showAchievements() async {
    await _invoke<void>('showAchievements');
  }

  Future<PlayGamesAchievementsSummary?> loadAchievementsSummary() async {
    final Map<dynamic, dynamic>? raw =
        await _invoke<Map<dynamic, dynamic>>('loadAchievementsSummary');
    if (raw == null) return null;
    final dynamic unlocked = raw['unlocked'];
    final dynamic total = raw['total'];
    if (unlocked is! num || total is! num) return null;
    return PlayGamesAchievementsSummary(
      unlocked: unlocked.toInt(),
      total: total.toInt(),
    );
  }
}
