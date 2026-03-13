import 'package:flutter_test/flutter_test.dart';
import 'package:dart_scorer/models/dart_throw.dart';
import 'package:dart_scorer/models/player.dart';
import 'package:dart_scorer/models/game_state.dart';
import 'package:dart_scorer/services/score_calculator.dart';
import 'package:dart_scorer/config/constants.dart';

void main() {
  group('DartThrow', () {
    test('single 20 scores 20', () {
      final dart = DartThrow.manual(20, RingType.singleOuter);
      expect(dart.score, 20);
    });

    test('double 20 scores 40', () {
      final dart = DartThrow.manual(20, RingType.double_);
      expect(dart.score, 40);
    });

    test('triple 20 scores 60', () {
      final dart = DartThrow.manual(20, RingType.triple);
      expect(dart.score, 60);
    });

    test('inner bull scores 50', () {
      final dart = DartThrow.manual(25, RingType.innerBull);
      expect(dart.score, 50);
    });

    test('outer bull scores 25', () {
      final dart = DartThrow.manual(25, RingType.outerBull);
      expect(dart.score, 25);
    });

    test('miss scores 0', () {
      final dart = DartThrow.miss();
      expect(dart.score, 0);
    });

    test('isDouble works correctly', () {
      expect(DartThrow.manual(20, RingType.double_).isDouble, true);
      expect(DartThrow.manual(25, RingType.innerBull).isDouble, true);
      expect(DartThrow.manual(20, RingType.triple).isDouble, false);
      expect(DartThrow.manual(20, RingType.singleOuter).isDouble, false);
    });

    test('displayName formatting', () {
      expect(DartThrow.manual(20, RingType.triple).displayName, 'T20 (60)');
      expect(DartThrow.manual(20, RingType.double_).displayName, 'D20 (40)');
      expect(DartThrow.manual(25, RingType.innerBull).displayName, 'Bullseye (50)');
      expect(DartThrow.miss().displayName, 'Miss');
    });

    test('shortName formatting', () {
      expect(DartThrow.manual(20, RingType.triple).shortName, 'T20');
      expect(DartThrow.manual(20, RingType.double_).shortName, 'D20');
      expect(DartThrow.manual(20, RingType.singleOuter).shortName, '20');
      expect(DartThrow.manual(25, RingType.innerBull).shortName, 'DB');
      expect(DartThrow.manual(25, RingType.outerBull).shortName, 'SB');
      expect(DartThrow.miss().shortName, 'M');
    });
  });

  group('ScoreCalculator - X01', () {
    GameState _makeGame({
      int startScore = 501,
      bool doubleOut = true,
      bool doubleIn = false,
    }) {
      final player = Player(id: '1', name: 'Test', scoreRemaining: startScore);
      player.rounds.add([]);
      return GameState(
        gameType: startScore == 301 ? '301' : '501',
        players: [player],
        status: GameStatus.playing,
        doubleOut: doubleOut,
        doubleIn: doubleIn,
        startScore: startScore,
      );
    }

    test('normal throw reduces score', () {
      final game = _makeGame();
      final player = game.players.first;
      final dart = DartThrow.manual(20, RingType.triple);
      final result = ScoreCalculator.processX01Throw(player, dart, game);

      expect(result.bust, false);
      expect(result.scoreAfter, 441);
    });

    test('bust when score goes below 0', () {
      final game = _makeGame(startScore: 10);
      final player = game.players.first;
      player.scoreRemaining = 10;
      final dart = DartThrow.manual(20, RingType.singleOuter);
      final result = ScoreCalculator.processX01Throw(player, dart, game);

      expect(result.bust, true);
    });

    test('bust when finishing without double (double out)', () {
      final game = _makeGame();
      final player = game.players.first;
      player.scoreRemaining = 20;
      final dart = DartThrow.manual(20, RingType.singleOuter);
      final result = ScoreCalculator.processX01Throw(player, dart, game);

      expect(result.bust, true);
    });

    test('win with double out', () {
      final game = _makeGame();
      final player = game.players.first;
      player.scoreRemaining = 40;
      final dart = DartThrow.manual(20, RingType.double_);
      final result = ScoreCalculator.processX01Throw(player, dart, game);

      expect(result.won, true);
      expect(result.scoreAfter, 0);
    });

    test('win with bullseye (double out)', () {
      final game = _makeGame();
      final player = game.players.first;
      player.scoreRemaining = 50;
      final dart = DartThrow.manual(25, RingType.innerBull);
      final result = ScoreCalculator.processX01Throw(player, dart, game);

      expect(result.won, true);
      expect(result.scoreAfter, 0);
    });

    test('bust on score remaining 1 with double out', () {
      final game = _makeGame();
      final player = game.players.first;
      player.scoreRemaining = 2;
      final dart = DartThrow.manual(1, RingType.singleOuter);
      final result = ScoreCalculator.processX01Throw(player, dart, game);

      expect(result.bust, true);
    });

    test('no double out allows single finish', () {
      final game = _makeGame(doubleOut: false);
      final player = game.players.first;
      player.scoreRemaining = 20;
      final dart = DartThrow.manual(20, RingType.singleOuter);
      final result = ScoreCalculator.processX01Throw(player, dart, game);

      expect(result.won, true);
      expect(result.bust, false);
    });

    test('double in blocks first non-double throw', () {
      final game = _makeGame(doubleIn: true);
      final player = game.players.first;
      // Player has no score yet (totalScore == 0 based on allThrows)
      final dart = DartThrow.manual(20, RingType.singleOuter);
      final result = ScoreCalculator.processX01Throw(player, dart, game);

      expect(result.noScore, true);
      expect(result.scoreAfter, 501); // Unchanged
    });
  });

  group('ScoreCalculator - Checkout suggestions', () {
    test('170 checkout exists', () {
      expect(ScoreCalculator.suggestCheckout(170), isNotNull);
      expect(ScoreCalculator.suggestCheckout(170), 'T20 T20 Bull');
    });

    test('returns null for impossible checkouts', () {
      expect(ScoreCalculator.suggestCheckout(171), isNull);
      expect(ScoreCalculator.suggestCheckout(1), isNull);
    });

    test('common checkouts are correct', () {
      expect(ScoreCalculator.suggestCheckout(40), 'D20');
      expect(ScoreCalculator.suggestCheckout(50), 'Bull');
      expect(ScoreCalculator.suggestCheckout(100), 'T20 D20');
      expect(ScoreCalculator.suggestCheckout(32), 'D16');
      expect(ScoreCalculator.suggestCheckout(2), 'D1');
    });
  });

  group('ScoreCalculator - Around the Clock', () {
    test('hitting target advances', () {
      final player = Player(id: '1', name: 'Test', currentTarget: 5);
      final dart = DartThrow.manual(5, RingType.singleOuter);
      final result = ScoreCalculator.processAroundTheClockThrow(player, dart);

      expect(result.hit, true);
      expect(result.newTarget, 6);
    });

    test('missing target stays', () {
      final player = Player(id: '1', name: 'Test', currentTarget: 5);
      final dart = DartThrow.manual(10, RingType.singleOuter);
      final result = ScoreCalculator.processAroundTheClockThrow(player, dart);

      expect(result.hit, false);
      expect(result.newTarget, 5);
    });

    test('hitting 20 wins', () {
      final player = Player(id: '1', name: 'Test', currentTarget: 20);
      final dart = DartThrow.manual(20, RingType.singleOuter);
      final result = ScoreCalculator.processAroundTheClockThrow(player, dart);

      expect(result.won, true);
    });

    test('doubles and triples also count', () {
      final player = Player(id: '1', name: 'Test', currentTarget: 7);
      final dart = DartThrow.manual(7, RingType.triple);
      final result = ScoreCalculator.processAroundTheClockThrow(player, dart);

      expect(result.hit, true);
      expect(result.newTarget, 8);
    });
  });

  group('Player', () {
    test('average calculation with complete rounds', () {
      final player = Player(id: '1', name: 'Test');
      player.rounds.add([
        DartThrow.manual(20, RingType.triple),
        DartThrow.manual(20, RingType.triple),
        DartThrow.manual(20, RingType.triple),
      ]);
      expect(player.average, 180.0);
    });

    test('empty player has 0 average', () {
      final player = Player(id: '1', name: 'Test');
      expect(player.average, 0.0);
    });

    test('highestRound tracks correctly', () {
      final player = Player(id: '1', name: 'Test');
      player.rounds.add([
        DartThrow.manual(20, RingType.triple),
        DartThrow.manual(19, RingType.triple),
        DartThrow.manual(18, RingType.triple),
      ]);
      player.rounds.add([
        DartThrow.manual(1, RingType.singleOuter),
        DartThrow.manual(1, RingType.singleOuter),
        DartThrow.manual(1, RingType.singleOuter),
      ]);
      expect(player.highestRound, 174); // T20+T19+T18
    });

    test('ton80s counts correctly', () {
      final player = Player(id: '1', name: 'Test');
      player.rounds.add([
        DartThrow.manual(20, RingType.triple),
        DartThrow.manual(20, RingType.triple),
        DartThrow.manual(20, RingType.triple),
      ]);
      player.rounds.add([
        DartThrow.manual(20, RingType.triple),
        DartThrow.manual(20, RingType.triple),
        DartThrow.manual(19, RingType.triple),
      ]);
      expect(player.ton80s, 1);
    });

    test('resetForNewLeg resets correctly', () {
      final player = Player(id: '1', name: 'Test', scoreRemaining: 100);
      player.rounds.add([DartThrow.manual(20, RingType.triple)]);
      player.resetForNewLeg(501);

      expect(player.scoreRemaining, 501);
      expect(player.rounds, isEmpty);
    });

    test('double training quote calculation', () {
      final player = Player(id: '1', name: 'Test');
      player.doubleAttempts = 10;
      player.doubleHits = 3;
      expect(player.doubleQuote, 30.0);
    });

    test('bobs27 initial score is 27', () {
      final player = Player(id: '1', name: 'Test');
      expect(player.bobs27Score, 27);
    });
  });

  group('RingType', () {
    test('fromString parses correctly', () {
      expect(RingType.fromString('double'), RingType.double_);
      expect(RingType.fromString('triple'), RingType.triple);
      expect(RingType.fromString('single_inner'), RingType.singleInner);
      expect(RingType.fromString('single_outer'), RingType.singleOuter);
      expect(RingType.fromString('outer_bull'), RingType.outerBull);
      expect(RingType.fromString('inner_bull'), RingType.innerBull);
      expect(RingType.fromString('unknown'), RingType.miss);
    });

    test('displayName is correct', () {
      expect(RingType.double_.displayName, 'Double');
      expect(RingType.triple.displayName, 'Triple');
      expect(RingType.singleInner.displayName, 'Single');
      expect(RingType.outerBull.displayName, 'Bull');
      expect(RingType.innerBull.displayName, 'Bullseye');
      expect(RingType.miss.displayName, 'Miss');
    });
  });

  group('AppConstants', () {
    test('board order has 20 segments', () {
      expect(AppConstants.boardOrder.length, 20);
    });

    test('all game types have descriptions', () {
      for (final type in AppConstants.allGameTypes) {
        expect(AppConstants.gameDescriptions.containsKey(type), true,
            reason: '$type missing description');
      }
    });

    test('all game types have min players', () {
      for (final type in AppConstants.allGameTypes) {
        expect(AppConstants.minPlayers.containsKey(type), true,
            reason: '$type missing minPlayers');
      }
    });

    test('game categories contain all game types', () {
      final allFromCategories = AppConstants.allGameTypes;
      expect(allFromCategories.length, 11);
    });
  });
}
