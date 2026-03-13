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

  // ──────────────── Gemini Modell ────────────────
  // gemini-1.5-flash-8b: 1.500 kostenlose Anfragen/Tag, ideal für Bildanalyse
   static const String geminiModel = 'gemini-2.0-flash-lite';

  // ──────────────── Standard-Erkennungsprompt (ohne Kalibrierung) ────────────────
  static const String detectionPrompt = '''
You are analyzing a dartboard image taken from an angle (not necessarily straight on).
The camera may be positioned to the side or below the board — this is normal and expected.

Your task: Identify ALL darts currently stuck in the dartboard.

IMPORTANT PERSPECTIVE NOTE:
- The board may appear elliptical or skewed due to camera angle
- Use the number markings visible around the board edge to determine segment positions
- Focus on where the DART TIP/POINT enters the board, not the shaft direction
- A dart viewed from the side will show the shaft at an angle — still identify the tip location

For each dart found, determine:
1. NUMBER segment (1-20, or 25 for bull area)
2. RING type:
   - "inner_bull" = red center circle (50 points)
   - "outer_bull" = green ring around center (25 points)  
   - "triple" = narrow inner ring (worth 3x)
   - "double" = narrow outer ring at board edge (worth 2x)
   - "single_inner" = large area between triple and bull
   - "single_outer" = large area between triple and double

Board number order clockwise from top: 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5

Respond ONLY with valid JSON, no other text:
{
  "darts": [
    {"segment": <1-20 or 25>, "ring": "<ring_type>", "confidence": <0.0-1.0>}
  ],
  "board_detected": true/false,
  "total_darts": <number>
}
''';

  // ──────────────── Kalibrierter Prompt (mit Referenzbild) ────────────────
  static const String calibrationPromptPrefix = '''
I will show you TWO images of a dartboard:
IMAGE 1 (below) is the REFERENCE — the EMPTY board with NO darts, taken from your camera position.
Use this reference to understand the board's exact orientation, perspective, segment layout, and lighting from this specific angle.
''';

  static const String calibrationPromptSuffix = '''
IMAGE 2 (below) is the CURRENT state — the SAME board with darts thrown.
Using the reference image to understand the board geometry and perspective, identify ALL darts in IMAGE 2.

The camera angle is fixed (same position as reference). Use the reference to precisely map segment boundaries.

For each dart, determine:
1. NUMBER segment (1-20, or 25 for bull area) — compare with reference board layout
2. RING type: "inner_bull", "outer_bull", "triple", "double", "single_inner", "single_outer"

Board numbers clockwise from top: 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5

Respond ONLY with valid JSON, no other text:
{
  "darts": [
    {"segment": <1-20 or 25>, "ring": "<ring_type>", "confidence": <0.0-1.0>}
  ],
  "board_detected": true/false,
  "total_darts": <number>
}
''';

  // ──────────────── Kalibrierungsprüfung ────────────────
  static const String boardCheckPrompt = '''
Look at this image. Is a dartboard clearly visible?
Answer ONLY with JSON: {"board_visible": true/false, "quality": "good"|"dark"|"blurry"|"partial"}
''';

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

// ──────────────── RingType (unverändert) ────────────────
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
    switch (s.toLowerCase()) {
      case 'double': return RingType.double_;
      case 'triple': return RingType.triple;
      case 'single_inner': return RingType.singleInner;
      case 'single_outer': return RingType.singleOuter;
      case 'outer_bull': return RingType.outerBull;
      case 'inner_bull': return RingType.innerBull;
      default: return RingType.miss;
    }
  }
}