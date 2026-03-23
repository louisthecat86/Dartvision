import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/game_state.dart';
import '../models/player.dart';

class ScoreboardWidget extends StatelessWidget {
  final GameState game;

  const ScoreboardWidget({super.key, required this.game});

  bool get _hasLegsOrSets => game.legsToWin > 1 || game.setsToWin > 1;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Player cards
          Expanded(
            child: game.players.length <= 2
                ? Row(
                    children: game.players.asMap().entries.map((e) {
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: e.key == 0 ? 4 : 0,
                              left: e.key == 1 ? 4 : 0),
                          child: _buildPlayerCard(
                            context,
                            e.value,
                            e.key == game.currentPlayerIndex,
                            e.key,
                          ),
                        ),
                      );
                    }).toList(),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: game.players.length,
                    itemBuilder: (context, index) {
                      final width =
                          (MediaQuery.of(context).size.width - 36) /
                              2.5;
                      return SizedBox(
                        width: width,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildPlayerCard(
                            context,
                            game.players[index],
                            index == game.currentPlayerIndex,
                            index,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          // Current round info
          if (!game.isGameOver) _buildCurrentRoundInfo(context),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(
    BuildContext context,
    Player player,
    bool isActive,
    int index,
  ) {
    final color = _playerColor(index);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? color.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color : AppColors.border,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Player name + active dot
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isActive)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              Flexible(
                child: Text(
                  player.name,
                  style: TextStyle(
                    color: isActive ? color : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Legs / Sets badges
          if (_hasLegsOrSets) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (game.setsToWin > 1)
                  _buildBadge('S', '${player.setsWon}', AppColors.gold),
                if (game.setsToWin > 1) const SizedBox(width: 6),
                _buildBadge('L', '${player.legsWon}', AppColors.primary),
              ],
            ),
          ],

          const Spacer(),

          // Main score
          Text(
            '${player.scoreRemaining}',
            style: TextStyle(
              fontSize: game.players.length <= 2 ? 48 : 36,
              fontWeight: FontWeight.w900,
              color: isActive
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              height: 1,
            ),
          ),

          const Spacer(),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStat('Ø', player.average.toStringAsFixed(1)),
              _buildStat('D', '${player.dartsThrown}'),
              if (player.ton80s > 0)
                _buildStat('180', '${player.ton80s}'),
              if (player.ton80s == 0)
                _buildStat('Hi', '${player.highestRound}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 3),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
        Text(value,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildCurrentRoundInfo(BuildContext context) {
    final player = game.currentPlayer;
    final currentRound =
        player.rounds.isNotEmpty ? player.rounds.last : <dynamic>[];
    final dartsInRound = currentRound.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            player.name,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          // Dart slots
          ...List.generate(3, (i) {
            if (i < dartsInRound) {
              final dart = currentRound[i];
              return Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dart.shortName,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
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
          const SizedBox(width: 8),
          Text(
            '= ${player.currentRoundScore}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Color _playerColor(int index) {
    const colors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.accentOrange,
      AppColors.gold,
      Color(0xFF7C4DFF),
      Color(0xFF00BCD4),
      Color(0xFFFF6E40),
      Color(0xFF76FF03),
    ];
    return colors[index % colors.length];
  }
}



