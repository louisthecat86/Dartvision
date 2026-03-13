import 'dart:convert';

class GameHistoryEntry {
  final String id;
  final String gameType;
  final DateTime playedAt;
  final int durationMinutes;
  final String winnerName;
  final List<GameHistoryPlayer> players;

  GameHistoryEntry({
    required this.id,
    required this.gameType,
    required this.playedAt,
    required this.durationMinutes,
    required this.winnerName,
    required this.players,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameType': gameType,
        'playedAt': playedAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        'winnerName': winnerName,
        'players': players.map((p) => p.toJson()).toList(),
      };

  factory GameHistoryEntry.fromJson(Map<String, dynamic> json) {
    return GameHistoryEntry(
      id: json['id'] as String,
      gameType: json['gameType'] as String,
      playedAt: DateTime.parse(json['playedAt'] as String),
      durationMinutes: json['durationMinutes'] as int,
      winnerName: json['winnerName'] as String,
      players: (json['players'] as List)
          .map((p) => GameHistoryPlayer.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

class GameHistoryPlayer {
  final String name;
  final bool isWinner;
  final double average;
  final int dartsThrown;
  final int highestRound;
  final int ton80s;
  final int ton40plus;
  final int finalScore; // remaining or points, depending on game

  GameHistoryPlayer({
    required this.name,
    required this.isWinner,
    required this.average,
    required this.dartsThrown,
    required this.highestRound,
    required this.ton80s,
    required this.ton40plus,
    required this.finalScore,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'isWinner': isWinner,
        'average': average,
        'dartsThrown': dartsThrown,
        'highestRound': highestRound,
        'ton80s': ton80s,
        'ton40plus': ton40plus,
        'finalScore': finalScore,
      };

  factory GameHistoryPlayer.fromJson(Map<String, dynamic> json) {
    return GameHistoryPlayer(
      name: json['name'] as String,
      isWinner: json['isWinner'] as bool,
      average: (json['average'] as num).toDouble(),
      dartsThrown: json['dartsThrown'] as int,
      highestRound: json['highestRound'] as int,
      ton80s: json['ton80s'] as int,
      ton40plus: json['ton40plus'] as int,
      finalScore: json['finalScore'] as int,
    );
  }
}
