import 'player.dart';

enum GameStatus { setup, playing, finished }

class GameState {
  final String gameType;
  final List<Player> players;
  int currentPlayerIndex;
  int currentDartInRound; // 0, 1, or 2
  GameStatus status;
  String? winnerId;
  final DateTime startedAt;

  // ── X01 options ──
  final bool doubleIn;
  final bool doubleOut;
  final int startScore;      // 301, 501, 701
  int legsToWin;             // e.g. first to 3 legs
  int setsToWin;             // e.g. first to 3 sets (each set = X legs)
  int legsPerSet;            // legs needed to win a set
  int currentLeg;
  int currentSet;

  // ── Shanghai ──
  int shanghaiCurrentRound;  // 1-7 (or 1-20)
  int shanghaiMaxRounds;

  // ── Killer ──
  // killer state stored in Player objects

  // ── Bob's 27 ──
  int bobs27CurrentDouble;   // 1-20 then 25

  // ── High Score ──
  int highScoreMaxRounds;
  int highScoreCurrentRound;

  // ── Double Training ──
  int doubleTrainingCurrent; // 1-20 then 25

  // ── General ──
  final List<String> eventLog;

  GameState({
    required this.gameType,
    required this.players,
    this.currentPlayerIndex = 0,
    this.currentDartInRound = 0,
    this.status = GameStatus.setup,
    this.winnerId,
    DateTime? startedAt,
    this.doubleIn = false,
    this.doubleOut = true,
    this.startScore = 501,
    this.legsToWin = 1,
    this.setsToWin = 1,
    this.legsPerSet = 3,
    this.currentLeg = 1,
    this.currentSet = 1,
    this.shanghaiCurrentRound = 1,
    this.shanghaiMaxRounds = 7,
    this.bobs27CurrentDouble = 1,
    this.highScoreMaxRounds = 10,
    this.highScoreCurrentRound = 1,
    this.doubleTrainingCurrent = 1,
    List<String>? eventLog,
  })  : startedAt = startedAt ?? DateTime.now(),
        eventLog = eventLog ?? [];

  Player get currentPlayer => players[currentPlayerIndex];

  bool get isGameOver => status == GameStatus.finished;

  int get roundNumber {
    if (players.isEmpty) return 0;
    return players.first.rounds.length;
  }

  Player? get winner =>
      winnerId != null
          ? players.firstWhere((p) => p.id == winnerId)
          : null;

  void addEvent(String event) {
    eventLog.insert(0, event);
    if (eventLog.length > 200) eventLog.removeLast();
  }
}



