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

  // Categories for display
  static const Map<String, List<String>> gameCategories = {
    'X01 (Klassisch)': [game301, game501, game701],
    'Cricket': [gameCricket, gameCutThroat],
    'Party & Spaß': [gameAroundTheClock, gameShanghai, gameKiller],
    'Training': [gameBobs27, gameHighScore, gameDoubleTraining],
  };

  static List<String> get allGameTypes =>
      gameCategories.values.expand((v) => v).toList();

  // Cricket numbers
  static const List<int> cricketNumbers = [20, 19, 18, 17, 16, 15];

  // Max players
  static const int maxPlayers = 8;

  // Max legs/sets
  static const int maxLegs = 11;
  static const int maxSets = 7;

  // Gemini API
  static const String geminiModel = 'gemini-2.0-flash';

  // Detection prompt for Gemini
  static const String detectionPrompt = '''
Analyze this dartboard image carefully. Identify ALL darts visible on the board.

For each dart, determine:
1. The NUMBER segment (1-20) where the dart tip is located
2. The RING type: "double" (outer narrow ring), "triple" (inner narrow ring), "single_outer" (large area between triple and double), "single_inner" (large area between triple and bull), "outer_bull" (green ring around bullseye), "inner_bull" (red center bullseye)

IMPORTANT RULES:
- Look at where the DART TIP touches the board, not the shaft
- The board numbers clockwise from top: 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5
- If no darts are visible, return an empty array
- Be precise about double vs triple rings - doubles are on the OUTER edge, triples are the INNER narrow ring

Respond ONLY with valid JSON in this exact format, no other text:
{
  "darts": [
    {"segment": <number 1-20 or 25 for bull/bullseye>, "ring": "<ring_type>", "confidence": <0.0-1.0>}
  ],
  "board_detected": true/false,
  "total_darts": <number>
}
''';

  // Game descriptions
  static const Map<String, String> gameDescriptions = {
    game301: 'Von 301 auf 0 – Double Out.',
    game501: 'Von 501 auf 0 – Double Out.',
    game701: 'Von 701 auf 0 – Double Out.',
    gameCricket: 'Schließe 15–20 & Bull, sammle Punkte.',
    gameCutThroat: 'Cricket – aber Punkte gehen an Gegner!',
    gameAroundTheClock: 'Treffe 1 bis 20 der Reihe nach.',
    gameShanghai: 'Pro Runde ein Ziel (1–7). Shanghai = sofort gewonnen.',
    gameKiller: 'Triff dein Double um Killer zu werden, dann eliminiere andere.',
    gameBobs27: 'Training: Triff jedes Double für Punkte, oder verliere das Doppelte.',
    gameHighScore: '10 Runden: Wer hat den höchsten Gesamtscore?',
    gameDoubleTraining: 'Trainiere alle 20 Doubles + Bull. Treffquote zählt.',
  };

  // Min players per game
  static const Map<String, int> minPlayers = {
    game301: 1,
    game501: 1,
    game701: 1,
    gameCricket: 2,
    gameCutThroat: 3,
    gameAroundTheClock: 1,
    gameShanghai: 2,
    gameKiller: 3,
    gameBobs27: 1,
    gameHighScore: 1,
    gameDoubleTraining: 1,
  };
}

enum RingType {
  singleInner,
  singleOuter,
  double_,
  triple,
  outerBull,
  innerBull,
  miss;

  String get displayName {
    switch (this) {
      case RingType.singleInner:
      case RingType.singleOuter:
        return 'Single';
      case RingType.double_:
        return 'Double';
      case RingType.triple:
        return 'Triple';
      case RingType.outerBull:
        return 'Bull';
      case RingType.innerBull:
        return 'Bullseye';
      case RingType.miss:
        return 'Miss';
    }
  }

  static RingType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'double':
        return RingType.double_;
      case 'triple':
        return RingType.triple;
      case 'single_inner':
        return RingType.singleInner;
      case 'single_outer':
        return RingType.singleOuter;
      case 'outer_bull':
        return RingType.outerBull;
      case 'inner_bull':
        return RingType.innerBull;
      default:
        return RingType.miss;
    }
  }
}
