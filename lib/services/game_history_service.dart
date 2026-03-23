import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_history.dart';

class GameHistoryService {
  static const String _key = 'game_history';
  static const int _maxEntries = 100;

  static Future<List<GameHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];

    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => GameHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveEntry(GameHistoryEntry entry) async {
    final history = await loadHistory();
    history.insert(0, entry);
    if (history.length > _maxEntries) {
      history.removeRange(_maxEntries, history.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(history.map((e) => e.toJson()).toList()));
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Global stats across all games
  static Future<Map<String, dynamic>> globalStats() async {
    final history = await loadHistory();
    if (history.isEmpty) {
      return {
        'totalGames': 0,
        'totalDarts': 0,
        'bestAverage': 0.0,
        'most180s': 0,
        'bestHighRound': 0,
        'favoriteGame': '-',
      };
    }

    int totalDarts = 0;
    double bestAvg = 0;
    int most180s = 0;
    int bestHigh = 0;
    final gameCount = <String, int>{};

    for (final game in history) {
      gameCount[game.gameType] = (gameCount[game.gameType] ?? 0) + 1;
      for (final p in game.players) {
        totalDarts += p.dartsThrown;
        if (p.average > bestAvg) bestAvg = p.average;
        most180s += p.ton80s;
        if (p.highestRound > bestHigh) bestHigh = p.highestRound;
      }
    }

    String favorite = '-';
    int maxCount = 0;
    gameCount.forEach((k, v) {
      if (v > maxCount) {
        maxCount = v;
        favorite = k;
      }
    });

    return {
      'totalGames': history.length,
      'totalDarts': totalDarts,
      'bestAverage': bestAvg,
      'most180s': most180s,
      'bestHighRound': bestHigh,
      'favoriteGame': favorite,
    };
  }
}



