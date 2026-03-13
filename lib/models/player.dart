import 'dart_throw.dart';

class Player {
  final String id;
  final String name;
  final List<List<DartThrow>> rounds; // Each round has up to 3 darts

  // ── X01 fields ──
  int scoreRemaining;
  int legsWon;
  int setsWon;

  // ── Cricket fields ──
  Map<int, int> cricketMarks; // segment -> mark count (0-3+)
  int cricketPoints;

  // ── Around the Clock ──
  int currentTarget;

  // ── Killer ──
  int killerSegment;   // The player's assigned double segment
  int killerLives;     // Lives (0 = eliminated)
  bool isKiller;       // Has become a killer

  // ── Shanghai ──
  int shanghaiScore;

  // ── Bob's 27 ──
  int bobs27Score;

  // ── High Score ──
  int highScoreTotal;

  // ── Double Training ──
  Map<int, bool> doublesHit; // segment -> hit (true/false)
  int doubleAttempts;
  int doubleHits;

  Player({
    required this.id,
    required this.name,
    this.scoreRemaining = 501,
    List<List<DartThrow>>? rounds,
    Map<int, int>? cricketMarks,
    this.cricketPoints = 0,
    this.currentTarget = 1,
    this.legsWon = 0,
    this.setsWon = 0,
    this.killerSegment = 0,
    this.killerLives = 3,
    this.isKiller = false,
    this.shanghaiScore = 0,
    this.bobs27Score = 27,
    this.highScoreTotal = 0,
    Map<int, bool>? doublesHit,
    this.doubleAttempts = 0,
    this.doubleHits = 0,
  })  : rounds = rounds ?? [],
        cricketMarks = cricketMarks ??
            {20: 0, 19: 0, 18: 0, 17: 0, 16: 0, 15: 0, 25: 0},
        doublesHit = doublesHit ??
            {for (int i = 1; i <= 20; i++) i: false, 25: false};

  // ── Computed stats ──
  List<DartThrow> get allThrows => rounds.expand((r) => r).toList();

  int get totalScore => allThrows.fold(0, (sum, t) => sum + t.score);

  double get average {
    if (rounds.isEmpty) return 0;
    final completedRounds = rounds.where((r) => r.length == 3).length;
    if (completedRounds == 0) return 0;
    final completedScore = rounds
        .where((r) => r.length == 3)
        .expand((r) => r)
        .fold(0, (int sum, t) => sum + t.score);
    return completedScore / completedRounds;
  }

  /// 3-dart-average (standard in darts)
  double get avg3dart => average;

  /// First 9 darts average
  double get first9Avg {
    final first9 = allThrows.take(9).toList();
    if (first9.length < 9) return 0;
    final score = first9.fold(0, (int sum, t) => sum + t.score);
    return score / 3; // Per round (3 darts)
  }

  int get dartsThrown => allThrows.length;

  List<DartThrow> get currentRound =>
      rounds.isNotEmpty ? rounds.last : [];

  int get currentRoundScore =>
      currentRound.fold(0, (sum, t) => sum + t.score);

  int get highestRound {
    if (rounds.isEmpty) return 0;
    return rounds
        .where((r) => r.isNotEmpty)
        .map((r) => r.fold(0, (int sum, t) => sum + t.score))
        .fold(0, (a, b) => a > b ? a : b);
  }

  int get ton80s => rounds.where((r) =>
      r.length == 3 &&
      r.fold(0, (int sum, t) => sum + t.score) == 180).length;

  int get ton40plus => rounds.where((r) =>
      r.length == 3 &&
      r.fold(0, (int sum, t) => sum + t.score) >= 140).length;

  int get ton00plus => rounds.where((r) =>
      r.length == 3 &&
      r.fold(0, (int sum, t) => sum + t.score) >= 100).length;

  int get doublesAttempted {
    // Count how many times player was in a checkout range and threw
    return allThrows.where((t) => t.isDouble).length;
  }

  double get doubleQuote {
    if (doubleAttempts == 0) return 0;
    return doubleHits / doubleAttempts * 100;
  }

  int get checkoutDarts => 0; // Tracked externally

  void resetForNewLeg(int startScore) {
    scoreRemaining = startScore;
    rounds.clear();
    cricketMarks = {20: 0, 19: 0, 18: 0, 17: 0, 16: 0, 15: 0, 25: 0};
    cricketPoints = 0;
    currentTarget = 1;
  }
}
