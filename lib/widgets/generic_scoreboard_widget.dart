import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/game_state.dart';
import '../models/player.dart';

/// Generic scoreboard that adapts its display to the current game type.
/// Used for: Shanghai, Killer, Bob's 27, High Score, Double Training, Around the Clock
class GenericScoreboardWidget extends StatelessWidget {
  final GameState game;

  const GenericScoreboardWidget({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Game info bar
          _buildGameInfoBar(context),
          const SizedBox(height: 8),
          // Player cards
          Expanded(
            child: ListView.builder(
              itemCount: game.players.length,
              itemBuilder: (context, index) {
                final player = game.players[index];
                final isActive = index == game.currentPlayerIndex;
                return _buildPlayerCard(context, player, isActive, index);
              },
            ),
          ),
          const SizedBox(height: 8),
          // Current round bar
          if (!game.isGameOver) _buildCurrentRoundInfo(context),
        ],
      ),
    );
  }

  Widget _buildGameInfoBar(BuildContext context) {
    String info;
    switch (game.gameType) {
      case AppConstants.gameShanghai:
        info =
            'Runde ${game.shanghaiCurrentRound}/${game.shanghaiMaxRounds} – Ziel: ${game.shanghaiCurrentRound}';
        break;
      case AppConstants.gameBobs27:
        final target = game.bobs27CurrentDouble;
        info = 'Aktuelles Double: D${target == 25 ? "Bull" : "$target"}';
        break;
      case AppConstants.gameHighScore:
        info =
            'Runde ${game.highScoreCurrentRound}/${game.highScoreMaxRounds}';
        break;
      case AppConstants.gameDoubleTraining:
        final target = game.doubleTrainingCurrent;
        info = 'Aktuell: D${target == 25 ? "Bull" : "$target"}';
        break;
      case AppConstants.gameKiller:
        final alive = game.players.where((p) => p.killerLives > 0).length;
        info = '$alive Spieler übrig';
        break;
      default:
        info = game.gameType;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Text(
        info,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildPlayerCard(
      BuildContext context, Player player, bool isActive, int index) {
    final color = _playerColor(index);
    final eliminated = game.gameType == AppConstants.gameKiller &&
        player.killerLives <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? color.withValues(alpha: 0.06)
            : eliminated
                ? AppColors.accent.withValues(alpha: 0.04)
                : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? color
              : eliminated
                  ? AppColors.accent.withValues(alpha: 0.3)
                  : AppColors.border,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Active indicator
          if (isActive && !game.isGameOver)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          // Name
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: TextStyle(
                    color: eliminated
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    decoration:
                        eliminated ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getSubtitle(player),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          // Main value
          Text(
            _getMainValue(player),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: eliminated
                  ? AppColors.textMuted
                  : isActive
                      ? color
                      : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _getMainValue(Player player) {
    switch (game.gameType) {
      case AppConstants.gameAroundTheClock:
        return '${player.currentTarget}';
      case AppConstants.gameShanghai:
        return '${player.shanghaiScore}';
      case AppConstants.gameKiller:
        if (player.killerLives <= 0) return '☠️';
        return '${'❤️' * player.killerLives}';
      case AppConstants.gameBobs27:
        return '${player.bobs27Score}';
      case AppConstants.gameHighScore:
        return '${player.highScoreTotal}';
      case AppConstants.gameDoubleTraining:
        return '${player.doubleQuote.toStringAsFixed(0)}%';
      default:
        return '${player.totalScore}';
    }
  }

  String _getSubtitle(Player player) {
    switch (game.gameType) {
      case AppConstants.gameAroundTheClock:
        return 'Nächstes Ziel: ${player.currentTarget}';
      case AppConstants.gameShanghai:
        return '${player.dartsThrown} Darts';
      case AppConstants.gameKiller:
        if (player.killerSegment == 0) return 'Wählt Double...';
        if (!player.isKiller) return 'D${player.killerSegment} – wird Killer';
        return 'D${player.killerSegment} – KILLER ☠️';
      case AppConstants.gameBobs27:
        return '${player.dartsThrown} Darts';
      case AppConstants.gameHighScore:
        return 'Ø ${player.average.toStringAsFixed(1)}';
      case AppConstants.gameDoubleTraining:
        return '${player.doubleHits}/${player.doubleAttempts} getroffen';
      default:
        return '${player.dartsThrown} Darts';
    }
  }

  Widget _buildCurrentRoundInfo(BuildContext context) {
    final player = game.currentPlayer;
    final currentRound =
        player.rounds.isNotEmpty ? player.rounds.last : [];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(player.name,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const Spacer(),
          ...List.generate(3, (i) {
            if (i < currentRound.length) {
              return Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  currentRound[i].shortName,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              );
            }
            return Container(
              margin: const EdgeInsets.only(left: 6),
              width: 28,
              height: 24,
              decoration: BoxDecoration(
                border: Border.all(
                    color: AppColors.textMuted.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(6),
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _playerColor(int index) {
    const colors = [
      AppColors.primary, AppColors.accent, AppColors.accentOrange,
      AppColors.gold, Color(0xFF7C4DFF), Color(0xFF00BCD4),
      Color(0xFFFF6E40), Color(0xFF76FF03),
    ];
    return colors[index % colors.length];
  }
}
