class AppConstants {
  // Dartboard segment order (clockwise from top)
  static const List<int> boardOrder = [
    20, 1, 18, 4, 13, 6, 10, 15, 2, 17,
    3, 19, 7, 16, 8, 11, 14, 9, 12, 5,
  ];

  // ──────────────── Game types ────────────────
  static const String game501 = '501';
  static const String game301 = '301';
  static const String game701 = '701';
  static const String gameCricket = 'Cricket';
  static const String gameCutThroat = 'Cut Throat Cricket';
  static const String gameAroundTheClock = 'Around the Clock';
  static const String gameShanghai = 'Shanghai';
  static const String gameKiller = 'Killer';
  static const String gameBobs27 = "Bob's 27";
  static const String gameHighScore = 'High Score';
  static const String gameDoubleTraining = 'Double Training';

  static const Map<String, List<String>> gameCategories = {
    'X01 (Klassisch)': [game301, game501, game701],
    'Cricket': [gameCricket, gameCutThroat],
    'Party & Spaß': [gameAroundTheClock, gameShanghai, gameKiller],
    'Training': [gameBobs27, gameHighScore, gameDoubleTraining],
  };

  static List<String> get allGameTypes =>
      gameCategories.values.expand((v) => v).toList();

  static const List<int> cricketNumbers = [20, 19, 18, 17, 16, 15];
  static const int maxPlayers = 8;
  static const int maxLegs = 11;
  static const int maxSets = 7;

  // ──────────────── Spielbeschreibungen ────────────────
  static const Map<String, String> gameDescriptions = {
    game301: 'Von 301 auf 0 – Double Out.',
    game501: 'Von 501 auf 0 – Double Out.',
    game701: 'Von 701 auf 0 – Double Out.',
    gameCricket: 'Schließe 15–20 & Bull, sammle Punkte.',
    gameCutThroat: 'Cricket – aber Punkte gehen an Gegner!',
    gameAroundTheClock: 'Triff 1 bis 20 der Reihe nach.',
    gameShanghai: 'Pro Runde ein Ziel (1–7). Shanghai = sofort gewonnen.',
    gameKiller: 'Triff dein Double um Killer zu werden, dann eliminiere andere.',
    gameBobs27: 'Training: Triff jedes Double für Punkte, oder verliere das Doppelte.',
    gameHighScore: '10 Runden: Wer hat den höchsten Gesamtscore?',
    gameDoubleTraining: 'Trainiere alle 20 Doubles + Bull. Treffquote zählt.',
  };

  static const Map<String, int> minPlayers = {
    game301: 1, game501: 1, game701: 1,
    gameCricket: 2, gameCutThroat: 3,
    gameAroundTheClock: 1, gameShanghai: 2, gameKiller: 3,
    gameBobs27: 1, gameHighScore: 1, gameDoubleTraining: 1,
  };
}

// ──────────────── RingType ────────────────
enum RingType {
  singleInner, singleOuter, double_, triple, outerBull, innerBull, miss;

  String get displayName {
    switch (this) {
      case RingType.singleInner:
      case RingType.singleOuter: return 'Single';
      case RingType.double_: return 'Double';
      case RingType.triple: return 'Triple';
      case RingType.outerBull: return 'Bull';
      case RingType.innerBull: return 'Bullseye';
      case RingType.miss: return 'Miss';
    }
  }

  static RingType fromString(String s) {
    // Unterstützt sowohl enum .name (camelCase) als auch Legacy-Format (snake_case)
    switch (s) {
      case 'double_':
      case 'double': return RingType.double_;
      case 'triple': return RingType.triple;
      case 'singleInner':
      case 'single_inner': return RingType.singleInner;
      case 'singleOuter':
      case 'single_outer': return RingType.singleOuter;
      case 'outerBull':
      case 'outer_bull': return RingType.outerBull;
      case 'innerBull':
      case 'inner_bull': return RingType.innerBull;
      case 'miss': return RingType.miss;
      default: return RingType.miss;
    }
  }
}



