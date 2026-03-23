import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/game_state.dart';

class CricketScoreboardWidget extends StatelessWidget {
  final GameState game;

  const CricketScoreboardWidget({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final segments = [...AppConstants.cricketNumbers, 25];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Header row with player names and points
          _buildHeaderRow(context),
          const SizedBox(height: 8),
          // Cricket grid
          Expanded(
            child: ListView.builder(
              itemCount: segments.length,
              itemBuilder: (context, index) {
                return _buildSegmentRow(context, segments[index]);
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

  Widget _buildHeaderRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const SizedBox(width: 50), // Segment label space
          ...game.players.asMap().entries.map((entry) {
            final index = entry.key;
            final player = entry.value;
            final isActive = index == game.currentPlayerIndex;
            final color = _playerColor(index);

            return Expanded(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isActive)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
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
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${player.cricketPoints}',
                    style: TextStyle(
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSegmentRow(BuildContext context, int segment) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Segment label
          SizedBox(
            width: 50,
            child: Text(
              segment == 25 ? 'BULL' : '$segment',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          // Player marks
          ...game.players.asMap().entries.map((entry) {
            final index = entry.key;
            final player = entry.value;
            final marks = player.cricketMarks[segment] ?? 0;
            final color = _playerColor(index);

            return Expanded(
              child: Center(
                child: _buildMarksIndicator(marks, color),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMarksIndicator(int marks, Color color) {
    if (marks == 0) {
      return const SizedBox(height: 28);
    }

    if (marks >= 3) {
      // Closed - show filled circle
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: Icon(
          Icons.close_rounded,
          size: 16,
          color: color,
        ),
      );
    }

    // Show X marks
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(marks, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Text(
            '/',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        );
      }),
    );
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
          Text(
            player.name,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          ...List.generate(3, (i) {
            if (i < currentRound.length) {
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
    ];
    return colors[index % colors.length];
  }
}



