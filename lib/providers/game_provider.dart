import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';
import '../models/dart_throw.dart';
import '../models/game_state.dart';
import '../models/game_history.dart';
import '../models/player.dart';
import '../services/score_calculator.dart';
import '../services/game_history_service.dart';

class GameProvider extends ChangeNotifier {
  GameState? _game;
  String? _lastMessage;

  GameState? get game => _game;
  String? get lastMessage => _lastMessage;

  bool get hasActiveGame =>
      _game != null && _game!.status == GameStatus.playing;

  // ─────────────── Start Game ───────────────

  void startGame({
    required String gameType,
    required List<String> playerNames,
    bool doubleIn = false,
    bool doubleOut = true,
    int legsToWin = 1,
    int setsToWin = 1,
    int legsPerSet = 3,
    int shanghaiRounds = 7,
    int highScoreRounds = 10,
  }) {
    const uuid = Uuid();

    int startScore = 0;
    if (gameType == AppConstants.game501) startScore = 501;
    if (gameType == AppConstants.game301) startScore = 301;
    if (gameType == AppConstants.game701) startScore = 701;

    final players = playerNames.map((name) {
      return Player(
        id: uuid.v4(),
        name: name,
        scoreRemaining: startScore,
        bobs27Score: 27,
      );
    }).toList();

    if (players.isNotEmpty) {
      players.first.rounds.add([]);
    }

    _game = GameState(
      gameType: gameType,
      players: players,
      status: GameStatus.playing,
      doubleIn: doubleIn,
      doubleOut: doubleOut,
      startScore: startScore,
      legsToWin: legsToWin,
      setsToWin: setsToWin,
      legsPerSet: legsPerSet,
      shanghaiMaxRounds: shanghaiRounds,
      highScoreMaxRounds: highScoreRounds,
    );

    _game!.addEvent('Spiel gestartet: $gameType');
    _lastMessage = null;
    notifyListeners();
  }

  // ─────────────── Add Throw ───────────────

  void addThrow(DartThrow dart) {
    if (_game == null || _game!.isGameOver) return;

    final player = _game!.currentPlayer;

    switch (_game!.gameType) {
      case AppConstants.game501:
      case AppConstants.game301:
      case AppConstants.game701:
        _processX01Throw(player, dart);
        break;
      case AppConstants.gameCricket:
        _processCricketThrow(player, dart, cutThroat: false);
        break;
      case AppConstants.gameCutThroat:
        _processCricketThrow(player, dart, cutThroat: true);
        break;
      case AppConstants.gameAroundTheClock:
        _processAroundTheClockThrow(player, dart);
        break;
      case AppConstants.gameShanghai:
        _processShanghaiThrow(player, dart);
        break;
      case AppConstants.gameKiller:
        _processKillerThrow(player, dart);
        break;
      case AppConstants.gameBobs27:
        _processBobs27Throw(player, dart);
        break;
      case AppConstants.gameHighScore:
        _processHighScoreThrow(player, dart);
        break;
      case AppConstants.gameDoubleTraining:
        _processDoubleTrainingThrow(player, dart);
        break;
    }

    notifyListeners();
  }

  // ─────────────── X01 ───────────────

  void _processX01Throw(Player player, DartThrow dart) {
    final result = ScoreCalculator.processX01Throw(player, dart, _game!);

    if (result.bust) {
      final roundScore = player.currentRoundScore;
      player.scoreRemaining += roundScore;
      player.rounds.last.clear();
      player.rounds.last.add(DartThrow.miss());
      _lastMessage = result.message;
      _game!.addEvent('${player.name}: BUST!');
      _nextPlayer();
      return;
    }

    if (result.noScore) {
      player.rounds.last.add(dart);
      _lastMessage = result.message;
    } else {
      player.scoreRemaining = result.scoreAfter;
      player.rounds.last.add(dart);
      _game!.addEvent(
          '${player.name}: ${dart.displayName} → Rest: ${result.scoreAfter}');
      _lastMessage = null;
    }

    if (result.won) {
      _handleX01LegWon(player);
      return;
    }

    if (player.rounds.last.length >= 3) {
      _nextPlayer();
    }
  }

  void _handleX01LegWon(Player player) {
    player.legsWon++;
    _game!.addEvent('🎯 ${player.name} gewinnt Leg ${_game!.currentLeg}!');

    // Check if set won
    if (player.legsWon >= _game!.legsPerSet && _game!.setsToWin > 1) {
      player.setsWon++;
      // Reset legs for all players
      for (final p in _game!.players) {
        p.legsWon = 0;
      }
      _game!.addEvent('📦 ${player.name} gewinnt Set ${_game!.currentSet}!');
      _game!.currentSet++;

      if (player.setsWon >= _game!.setsToWin) {
        _finishGame(player);
        return;
      }
    } else if (_game!.setsToWin <= 1 && player.legsWon >= _game!.legsToWin) {
      _finishGame(player);
      return;
    }

    // Start new leg
    _game!.currentLeg++;
    for (final p in _game!.players) {
      p.resetForNewLeg(_game!.startScore);
    }
    _game!.currentPlayerIndex = 0;
    _game!.players.first.rounds.add([]);
    _lastMessage = '🎯 Neues Leg (#${_game!.currentLeg})';
  }

  // ─────────────── Cricket / Cut Throat ───────────────

  void _processCricketThrow(Player player, DartThrow dart,
      {required bool cutThroat}) {
    final result = ScoreCalculator.processCricketThrow(
      player, dart, _game!.players,
    );

    player.rounds.last.add(dart);

    if (result.segment != null && result.newMarkCount != null) {
      player.cricketMarks[result.segment!] = result.newMarkCount!;
    }

    if (cutThroat && result.pointsAdded > 0 && result.segment != null) {
      // In Cut Throat, points go to OTHER players
      for (final p in _game!.players) {
        if (p.id != player.id &&
            (p.cricketMarks[result.segment!] ?? 0) < 3) {
          p.cricketPoints += result.pointsAdded;
        }
      }
    } else {
      player.cricketPoints += result.pointsAdded;
    }

    _game!.addEvent(
        '${player.name}: ${dart.displayName} (+${result.marksAdded} marks)');
    if (result.message != null) _lastMessage = result.message;

    // Check win
    final allClosed = player.cricketMarks.values.every((m) => m >= 3);
    if (allClosed) {
      bool wins;
      if (cutThroat) {
        // Cut throat: all closed AND LOWEST points wins
        wins = _game!.players.every(
            (p) => p.id == player.id || player.cricketPoints <= p.cricketPoints);
      } else {
        wins = _game!.players.every(
            (p) => p.id == player.id || player.cricketPoints >= p.cricketPoints);
      }
      if (wins) {
        _finishGame(player);
        return;
      }
    }

    if (player.rounds.last.length >= 3) _nextPlayer();
  }

  // ─────────────── Around the Clock ───────────────

  void _processAroundTheClockThrow(Player player, DartThrow dart) {
    final result = ScoreCalculator.processAroundTheClockThrow(player, dart);

    player.rounds.last.add(dart);
    player.currentTarget = result.newTarget;

    _lastMessage = result.message;
    _game!.addEvent('${player.name}: ${dart.displayName} → ${result.message}');

    if (result.won) {
      _finishGame(player);
      return;
    }
    if (player.rounds.last.length >= 3) _nextPlayer();
  }

  // ─────────────── Shanghai ───────────────

  void _processShanghaiThrow(Player player, DartThrow dart) {
    final targetNum = _game!.shanghaiCurrentRound;
    player.rounds.last.add(dart);

    // Only darts hitting the target number count
    if (dart.segment == targetNum) {
      player.shanghaiScore += dart.score;
      _game!.addEvent(
          '${player.name}: ${dart.displayName} → +${dart.score}');

      // Check Shanghai: Single + Double + Triple of same number in one round
      final thisRound = player.rounds.last;
      final hasSingle = thisRound.any((d) =>
          d.segment == targetNum &&
          (d.ring == RingType.singleInner || d.ring == RingType.singleOuter));
      final hasDouble = thisRound.any(
          (d) => d.segment == targetNum && d.ring == RingType.double_);
      final hasTriple = thisRound.any(
          (d) => d.segment == targetNum && d.ring == RingType.triple);

      if (hasSingle && hasDouble && hasTriple) {
        _lastMessage = '🀄 SHANGHAI! ${player.name} gewinnt sofort!';
        _finishGame(player);
        return;
      }
    } else {
      _game!.addEvent('${player.name}: ${dart.displayName} → Daneben');
    }

    _lastMessage = null;

    if (player.rounds.last.length >= 3) {
      // Check if this was the last player in the round
      final isLastPlayer =
          _game!.currentPlayerIndex == _game!.players.length - 1;
      _nextPlayer();

      if (isLastPlayer) {
        _game!.shanghaiCurrentRound++;

        if (_game!.shanghaiCurrentRound > _game!.shanghaiMaxRounds) {
          // Game over – highest score wins
          Player best = _game!.players.first;
          for (final p in _game!.players) {
            if (p.shanghaiScore > best.shanghaiScore) best = p;
          }
          _finishGame(best);
        }
      }
    }
  }

  // ─────────────── Killer ───────────────

  void _processKillerThrow(Player player, DartThrow dart) {
    player.rounds.last.add(dart);

    // Phase 1: Assign doubles (throw any double to claim it)
    if (player.killerSegment == 0) {
      if (dart.ring == RingType.double_) {
        player.killerSegment = dart.segment;
        _lastMessage = '${player.name} hat D${dart.segment} als Ziel!';
        _game!.addEvent('${player.name}: D${dart.segment} gewählt');
      } else {
        _lastMessage = 'Treffe ein Double um dein Ziel zu wählen!';
      }
    }
    // Phase 2: Become killer (hit your own double)
    else if (!player.isKiller) {
      if (dart.ring == RingType.double_ &&
          dart.segment == player.killerSegment) {
        player.isKiller = true;
        _lastMessage = '☠️ ${player.name} ist jetzt KILLER!';
        _game!.addEvent('☠️ ${player.name} ist Killer!');
      }
    }
    // Phase 3: Kill others (hit their doubles)
    else {
      if (dart.ring == RingType.double_) {
        for (final p in _game!.players) {
          if (p.id != player.id &&
              p.killerSegment == dart.segment &&
              p.killerLives > 0) {
            p.killerLives--;
            _game!.addEvent(
                '💀 ${player.name} trifft ${p.name}! (${p.killerLives} Leben)');
            _lastMessage =
                '💀 ${p.name} getroffen! ${p.killerLives} Leben übrig.';
            if (p.killerLives == 0) {
              _game!.addEvent('☠️ ${p.name} ist eliminiert!');
            }
          }
        }

        // Hit own double = lose a life
        if (dart.segment == player.killerSegment) {
          player.killerLives--;
          _lastMessage =
              '🤦 Eigenes Double getroffen! ${player.killerLives} Leben.';
          _game!.addEvent(
              '🤦 ${player.name} eigenes Double! (${player.killerLives} Leben)');
        }

        // Check if only one player alive
        final alive =
            _game!.players.where((p) => p.killerLives > 0).toList();
        if (alive.length == 1) {
          _finishGame(alive.first);
          return;
        }
        if (player.killerLives <= 0) {
          // Skip to next alive player
          _nextPlayer(skipDead: true);
          return;
        }
      }
    }

    if (player.rounds.last.length >= 3) {
      _nextPlayer(skipDead: true);
    }
  }

  // ─────────────── Bob's 27 ───────────────

  void _processBobs27Throw(Player player, DartThrow dart) {
    player.rounds.last.add(dart);
    final targetDouble = _game!.bobs27CurrentDouble;

    // Check if the dart hit the target double
    final hitTarget = dart.ring == RingType.double_ &&
        dart.segment == targetDouble;
    // Or bullseye for target 25
    final hitBull = targetDouble == 25 &&
        (dart.ring == RingType.innerBull || dart.ring == RingType.outerBull);

    if (hitTarget || hitBull) {
      player.bobs27Score += dart.score;
      _game!.addEvent(
          '${player.name}: ${dart.displayName} → +${dart.score}');
    }

    if (player.rounds.last.length >= 3) {
      // Did player hit target double at all this round?
      final anyHit = player.rounds.last.any((d) {
        if (targetDouble == 25) {
          return d.ring == RingType.innerBull || d.ring == RingType.outerBull;
        }
        return d.ring == RingType.double_ && d.segment == targetDouble;
      });

      if (!anyHit) {
        // Lose double the target's value
        final penalty = targetDouble == 25 ? 50 : targetDouble * 2;
        player.bobs27Score -= penalty;
        _game!.addEvent(
            '${player.name}: Kein Treffer auf D$targetDouble → -$penalty');
      }

      _lastMessage =
          '${player.name}: ${player.bobs27Score} Punkte (D$targetDouble)';

      // Eliminated?
      if (player.bobs27Score < 0) {
        _game!.addEvent('${player.name}: Eliminiert! (Score < 0)');
      }

      final isLastPlayer =
          _game!.currentPlayerIndex == _game!.players.length - 1;
      _nextPlayer();

      if (isLastPlayer) {
        if (_game!.bobs27CurrentDouble < 20) {
          _game!.bobs27CurrentDouble++;
        } else if (_game!.bobs27CurrentDouble == 20) {
          _game!.bobs27CurrentDouble = 25;
        } else {
          // Game over – highest score wins (exclude negatives)
          Player? best;
          for (final p in _game!.players) {
            if (best == null || p.bobs27Score > best.bobs27Score) best = p;
          }
          if (best != null) _finishGame(best);
        }
      }
    }
  }

  // ─────────────── High Score ───────────────

  void _processHighScoreThrow(Player player, DartThrow dart) {
    player.rounds.last.add(dart);
    player.highScoreTotal += dart.score;

    _game!.addEvent('${player.name}: ${dart.displayName} (+${dart.score})');

    if (player.rounds.last.length >= 3) {
      _lastMessage =
          '${player.name}: ${player.highScoreTotal} Punkte (Runde ${_game!.highScoreCurrentRound}/${_game!.highScoreMaxRounds})';

      final isLastPlayer =
          _game!.currentPlayerIndex == _game!.players.length - 1;
      _nextPlayer();

      if (isLastPlayer) {
        _game!.highScoreCurrentRound++;
        if (_game!.highScoreCurrentRound > _game!.highScoreMaxRounds) {
          Player best = _game!.players.first;
          for (final p in _game!.players) {
            if (p.highScoreTotal > best.highScoreTotal) best = p;
          }
          _finishGame(best);
        }
      }
    }
  }

  // ─────────────── Double Training ───────────────

  void _processDoubleTrainingThrow(Player player, DartThrow dart) {
    player.rounds.last.add(dart);
    player.doubleAttempts++;

    final target = _game!.doubleTrainingCurrent;
    bool hit = false;

    if (target == 25) {
      hit = dart.ring == RingType.innerBull;
    } else {
      hit = dart.ring == RingType.double_ && dart.segment == target;
    }

    if (hit) {
      player.doubleHits++;
      player.doublesHit[target] = true;
      _game!.addEvent('${player.name}: D$target GETROFFEN! ✓');
      _lastMessage = '✓ D$target getroffen!';
    } else {
      _game!.addEvent('${player.name}: ${dart.displayName} → Daneben');
    }

    if (player.rounds.last.length >= 3) {
      final isLastPlayer =
          _game!.currentPlayerIndex == _game!.players.length - 1;
      _nextPlayer();

      if (isLastPlayer) {
        if (_game!.doubleTrainingCurrent < 20) {
          _game!.doubleTrainingCurrent++;
        } else if (_game!.doubleTrainingCurrent == 20) {
          _game!.doubleTrainingCurrent = 25;
        } else {
          // Done - best hit rate wins
          Player best = _game!.players.first;
          for (final p in _game!.players) {
            if (p.doubleQuote > best.doubleQuote) best = p;
          }
          _finishGame(best);
        }
      }
    }
  }

  // ─────────────── Navigation ───────────────

  void _nextPlayer({bool skipDead = false}) {
    if (_game == null) return;

    int next = (_game!.currentPlayerIndex + 1) % _game!.players.length;

    if (skipDead) {
      int attempts = 0;
      while (_game!.players[next].killerLives <= 0 &&
          attempts < _game!.players.length) {
        next = (next + 1) % _game!.players.length;
        attempts++;
      }
    }

    _game!.currentPlayerIndex = next;
    _game!.currentDartInRound = 0;
    _game!.currentPlayer.rounds.add([]);
  }

  void _finishGame(Player winner) {
    _game!.status = GameStatus.finished;
    _game!.winnerId = winner.id;
    _lastMessage = '🏆 ${winner.name} gewinnt!';
    _game!.addEvent('🏆 ${winner.name} gewinnt das Spiel!');

    // Save to history
    _saveHistory(winner);
  }

  void _saveHistory(Player winner) {
    final duration =
        DateTime.now().difference(_game!.startedAt).inMinutes;

    final entry = GameHistoryEntry(
      id: const Uuid().v4(),
      gameType: _game!.gameType,
      playedAt: _game!.startedAt,
      durationMinutes: duration,
      winnerName: winner.name,
      players: _game!.players.map((p) {
        int finalScore;
        switch (_game!.gameType) {
          case AppConstants.game501:
          case AppConstants.game301:
          case AppConstants.game701:
            finalScore = p.scoreRemaining;
            break;
          case AppConstants.gameCricket:
          case AppConstants.gameCutThroat:
            finalScore = p.cricketPoints;
            break;
          case AppConstants.gameShanghai:
            finalScore = p.shanghaiScore;
            break;
          case AppConstants.gameBobs27:
            finalScore = p.bobs27Score;
            break;
          case AppConstants.gameHighScore:
            finalScore = p.highScoreTotal;
            break;
          default:
            finalScore = p.totalScore;
        }

        return GameHistoryPlayer(
          name: p.name,
          isWinner: p.id == winner.id,
          average: p.average,
          dartsThrown: p.dartsThrown,
          highestRound: p.highestRound,
          ton80s: p.ton80s,
          ton40plus: p.ton40plus,
          finalScore: finalScore,
        );
      }).toList(),
    );

    GameHistoryService.saveEntry(entry);
  }

  // ─────────────── Actions ───────────────

  void undoLastThrow() {
    if (_game == null || _game!.isGameOver) return;

    final player = _game!.currentPlayer;
    if (player.rounds.isEmpty) return;

    final currentRound = player.rounds.last;
    if (currentRound.isEmpty) {
      if (player.rounds.length <= 1 && _game!.currentPlayerIndex == 0) return;

      player.rounds.removeLast();
      final prevIndex = _game!.currentPlayerIndex == 0
          ? _game!.players.length - 1
          : _game!.currentPlayerIndex - 1;
      _game!.currentPlayerIndex = prevIndex;

      final prevPlayer = _game!.currentPlayer;
      if (prevPlayer.rounds.isNotEmpty && prevPlayer.rounds.last.isNotEmpty) {
        final lastThrow = prevPlayer.rounds.last.removeLast();
        _reverseThrowScore(prevPlayer, lastThrow);
      }
    } else {
      final lastThrow = currentRound.removeLast();
      _reverseThrowScore(player, lastThrow);
    }

    _lastMessage = 'Letzter Wurf rückgängig';
    _game!.addEvent('Undo');
    notifyListeners();
  }

  /// Kehrt die Auswirkung eines einzelnen Wurfs auf den Spieler-Score um.
  void _reverseThrowScore(Player player, DartThrow dart) {
    switch (_game!.gameType) {
      case AppConstants.game501:
      case AppConstants.game301:
      case AppConstants.game701:
        player.scoreRemaining += dart.score;
        break;
      case AppConstants.gameCricket:
      case AppConstants.gameCutThroat:
        _reverseCricketThrow(player, dart);
        break;
      case AppConstants.gameShanghai:
        // Nur Treffer auf das Rundenziel zählen
        if (dart.segment == _game!.shanghaiCurrentRound) {
          player.shanghaiScore -= dart.score;
        }
        break;
      case AppConstants.gameHighScore:
        player.highScoreTotal -= dart.score;
        break;
      case AppConstants.gameDoubleTraining:
        player.doubleAttempts--;
        final target = _game!.doubleTrainingCurrent;
        final hit = (target == 25)
            ? dart.ring == RingType.innerBull
            : (dart.ring == RingType.double_ && dart.segment == target);
        if (hit) {
          player.doubleHits--;
          player.doublesHit[target] = false;
        }
        break;
      // AroundTheClock, Killer, Bob's27 sind schwer rückgängig zu machen
      // (Zustandsübergänge), daher nur Dart-Entfernung ohne Score-Korrektur
      default:
        break;
    }
  }

  /// Cricket-Undo: Marks und ggf. Punkte zurücknehmen.
  void _reverseCricketThrow(Player player, DartThrow dart) {
    final targetSegments = [...AppConstants.cricketNumbers, 25];
    final segment = dart.segment;
    if (!targetSegments.contains(segment)) return;

    int marksToRemove = 1;
    if (dart.ring == RingType.double_ || dart.ring == RingType.innerBull) {
      marksToRemove = 2;
    } else if (dart.ring == RingType.triple) {
      marksToRemove = 3;
    }

    final currentMarks = player.cricketMarks[segment] ?? 0;
    final previousMarks = (currentMarks - marksToRemove).clamp(0, 99);
    player.cricketMarks[segment] = previousMarks;

    // Punkte rückrechnen: nur Excess-Marks über 3 brachten Punkte
    if (currentMarks > 3) {
      final excessNow = currentMarks - 3;
      final excessBefore = previousMarks > 3 ? previousMarks - 3 : 0;
      final pointsToRemove = (excessNow - excessBefore) *
          (segment == 25 ? 25 : segment);

      if (_game!.gameType == AppConstants.gameCutThroat) {
        for (final p in _game!.players) {
          if (p.id != player.id &&
              (p.cricketMarks[segment] ?? 0) < 3) {
            p.cricketPoints -= pointsToRemove;
          }
        }
      } else {
        player.cricketPoints -= pointsToRemove;
      }
    }
  }

  void endGame() {
    if (_game != null) {
      _game!.status = GameStatus.finished;
      _lastMessage = 'Spiel beendet';
    }
    notifyListeners();
  }

  String? get checkoutSuggestion {
    if (_game == null) return null;
    final gt = _game!.gameType;
    if (gt != AppConstants.game501 &&
        gt != AppConstants.game301 &&
        gt != AppConstants.game701) {
      return null;
    }

    final remaining = _game!.currentPlayer.scoreRemaining;
    if (remaining > 170 || remaining < 2) return null;
    return ScoreCalculator.suggestCheckout(remaining);
  }

  // ─────────────── Live-Preview für Kamera ───────────────

  /// Simuliert eine Runde (bis zu 3 Darts) ohne den Spielstand zu ändern.
  /// Gibt für jeden Dart ein Vorschau-Ergebnis zurück.
  List<ThrowPreview> previewRound(List<DartThrow> darts) {
    if (_game == null) return [];
    final gt = _game!.gameType;
    final player = _game!.currentPlayer;
    final results = <ThrowPreview>[];

    // Für X01: simuliere Score-Verlauf
    if (gt == AppConstants.game501 ||
        gt == AppConstants.game301 ||
        gt == AppConstants.game701) {
      int simRemaining = player.scoreRemaining;
      // Score der bisherigen (noch nicht bestätigten) Würfe in der Runde abziehen
      final existingRoundScore = player.currentRoundScore;
      bool busted = false;

      for (final dart in darts) {
        if (busted) {
          results.add(ThrowPreview(
            score: 0,
            remaining: simRemaining + existingRoundScore,
            message: '(Bust – zählt nicht)',
            isBust: true,
          ));
          continue;
        }

        // Double-In Prüfung
        if (_game!.doubleIn &&
            player.totalScore == 0 &&
            results.every((r) => r.isNoScore) &&
            !dart.isDouble) {
          results.add(ThrowPreview(
            score: 0,
            remaining: simRemaining,
            message: 'Double-In erforderlich!',
            isNoScore: true,
          ));
          continue;
        }

        final newScore = simRemaining - dart.score;

        if (newScore < 0 ||
            (newScore == 1 && _game!.doubleOut) ||
            (newScore == 0 && _game!.doubleOut && !dart.isDouble)) {
          busted = true;
          results.add(ThrowPreview(
            score: dart.score,
            remaining: player.scoreRemaining, // Reset bei Bust
            message: newScore == 0
                ? 'Bust! Double-Out erforderlich.'
                : newScore == 1
                    ? 'Bust! Kann nicht mit 1 beenden.'
                    : 'Bust! Über 0 hinaus.',
            isBust: true,
          ));
          continue;
        }

        simRemaining = newScore;
        results.add(ThrowPreview(
          score: dart.score,
          remaining: simRemaining,
          message: newScore == 0 ? 'Checkout! 🎯' : null,
          isWon: newScore == 0,
        ));
      }
    } else {
      // Nicht-X01: Einfache Score-Anzeige
      for (final dart in darts) {
        results.add(ThrowPreview(
          score: dart.score,
          remaining: 0,
          message: null,
        ));
      }
    }

    return results;
  }

  /// Übergibt eine bestätigte Runde an den Spielstand.
  /// Gibt eine Zusammenfassung zurück (z.B. Bust, Spieler gewechselt, etc.).
  RoundResult submitRound(List<DartThrow> darts) {
    if (_game == null || _game!.isGameOver) {
      return const RoundResult(playerBefore: '', scoreBefore: 0, scoreAfter: 0);
    }

    final playerBefore = _game!.currentPlayer.name;
    final scoreBefore = _game!.currentPlayer.scoreRemaining;
    final indexBefore = _game!.currentPlayerIndex;

    for (final dart in darts) {
      if (_game!.isGameOver) break;
      // Bust in X01 führt dazu dass addThrow intern _nextPlayer aufruft
      // und restliche Darts der Runde ignoriert werden.
      if (_game!.currentPlayerIndex != indexBefore) break;
      addThrow(dart);
    }

    // Falls addThrow nicht alle verarbeitet hat (Bust nach Dart 1/2),
    // sicherstellen dass Spieler gewechselt ist
    final autoAdvanced = _game!.currentPlayerIndex != indexBefore;

    // Falls alle 3 Darts verarbeitet und kein auto-advance: manuell weiter
    if (!autoAdvanced && !_game!.isGameOver) {
      // addThrow ruft _nextPlayer intern auf bei 3 Darts.
      // Hier nichts extra tun.
    }

    return RoundResult(
      playerBefore: playerBefore,
      scoreBefore: scoreBefore,
      scoreAfter: _game!.isGameOver
          ? 0
          : _game!.players
              .firstWhere((p) => p.name == playerBefore)
              .scoreRemaining,
      message: _lastMessage,
      gameOver: _game!.isGameOver,
      winnerName: _game!.winner?.name,
    );
  }

  /// Aktueller Spieler-Info für Kamera-HUD.
  String get currentPlayerName =>
      _game?.currentPlayer.name ?? '';

  int get currentPlayerScore =>
      _game?.currentPlayer.scoreRemaining ?? 0;

  int get currentPlayerDartsInRound =>
      _game?.currentPlayer.currentRound.length ?? 0;

  String get gameTypeDisplay =>
      _game?.gameType ?? '';
}

/// Vorschau eines einzelnen Wurfs (ohne Commit).
class ThrowPreview {
  final int score;
  final int remaining;
  final String? message;
  final bool isBust;
  final bool isNoScore;
  final bool isWon;

  const ThrowPreview({
    required this.score,
    required this.remaining,
    this.message,
    this.isBust = false,
    this.isNoScore = false,
    this.isWon = false,
  });
}

/// Ergebnis einer bestätigten Runde.
class RoundResult {
  final String playerBefore;
  final int scoreBefore;
  final int scoreAfter;
  final String? message;
  final bool gameOver;
  final String? winnerName;

  const RoundResult({
    required this.playerBefore,
    required this.scoreBefore,
    required this.scoreAfter,
    this.message,
    this.gameOver = false,
    this.winnerName,
  });
}