import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/game_provider.dart';
import '../widgets/dartboard_input_widget.dart';
import '../widgets/scoreboard_widget.dart';
import '../widgets/cricket_scoreboard_widget.dart';
import '../widgets/generic_scoreboard_widget.dart';
import 'stream_camera_screen.dart';
import 'home_screen.dart';
import 'game_setup_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _showManualInput = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gp, _) {
        final game = gp.game;
        if (game == null) {
          return const Scaffold(
            body: Center(child: Text('Kein aktives Spiel')),
          );
        }

        final isX01 = game.gameType == AppConstants.game501 ||
            game.gameType == AppConstants.game301 ||
            game.gameType == AppConstants.game701;
        final isCricket = game.gameType == AppConstants.gameCricket ||
            game.gameType == AppConstants.gameCutThroat;

        return Scaffold(
          appBar: AppBar(
            title: _buildTitle(game.gameType, isX01, game),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _showExitDialog(context, gp),
            ),
            actions: [
              // Event log
              IconButton(
                icon: const Icon(Icons.list_alt_rounded, size: 22),
                onPressed: () => _showEventLog(context, game.eventLog),
                tooltip: 'Spiellog',
              ),
              IconButton(
                icon: const Icon(Icons.undo_rounded),
                onPressed: game.isGameOver ? null : gp.undoLastThrow,
                tooltip: 'Rückgängig',
              ),
            ],
          ),
          body: Column(
            children: [
              // Scoreboard area
              Expanded(
                flex: 3,
                child: isCricket
                    ? CricketScoreboardWidget(game: game)
                    : isX01
                        ? ScoreboardWidget(game: game)
                        : GenericScoreboardWidget(game: game),
              ),

              // Message bar
              if (gp.lastMessage != null) _buildMessageBar(gp.lastMessage!),

              // Checkout suggestion
              if (gp.checkoutSuggestion != null && !game.isGameOver)
                _buildCheckoutBar(gp.checkoutSuggestion!),

              // Game over
              if (game.isGameOver) _buildGameOverBanner(game.winner?.name, gp),

              // Input area
              if (!game.isGameOver)
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      _buildInputToggle(),
                      Expanded(
                        child: _showManualInput
                            ? DartboardInputWidget(onThrow: gp.addThrow)
                            : _buildCameraButton(context),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTitle(String gameType, bool isX01, game) {
    if (isX01 && (game.legsToWin > 1 || game.setsToWin > 1)) {
      String subtitle;
      if (game.setsToWin > 1) {
        subtitle = 'Set ${game.currentSet} Leg ${game.currentLeg}';
      } else {
        subtitle = 'Leg ${game.currentLeg}/${game.legsToWin}';
      }
      return Column(
        children: [
          Text(gameType,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600)),
        ],
      );
    }
    return Text(gameType);
  }

  Widget _buildInputToggle() {
        return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleBtn(
              'Manuell', Icons.touch_app_rounded, _showManualInput,
              () => setState(() => _showManualInput = true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildToggleBtn(
              'Kamera', Icons.camera_alt_rounded, !_showManualInput,
              () => setState(() => _showManualInput = false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(
      String label, IconData icon, bool active, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: onTap == null
                    ? AppColors.textMuted
                    : active
                        ? AppColors.primary
                        : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  color: onTap == null
                      ? AppColors.textMuted
                      : active
                          ? AppColors.primary
                          : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraButton(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: IconButton(
              icon: const Icon(Icons.camera_alt_rounded,
                  size: 36, color: AppColors.primary),
              onPressed: () => _openCamera(context),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Foto aufnehmen & KI erkennen',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('Ergebnisse können vor Übernahme\nkorrigiert werden',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  void _openCamera(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          onDartsDetected: (darts) {
            final gp = context.read<GameProvider>();
            for (final dart in darts) {
              gp.addThrow(dart);
            }
          },
        ),
      ),
    );
  }

  Widget _buildMessageBar(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surfaceLight,
      child: Text(message,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.accentOrange,
              fontWeight: FontWeight.w600,
              fontSize: 14)),
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _buildCheckoutBar(String checkout) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.primary.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lightbulb_outline,
              size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('Checkout: $checkout',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildGameOverBanner(String? winnerName, GameProvider gp) {
    // Build stats summary
    final game = gp.game!;
    final stats = game.players.map((p) {
      return '${p.name}: Ø${p.average.toStringAsFixed(1)} | ${p.dartsThrown}D | Best ${p.highestRound}';
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.primary.withValues(alpha: 0.15),
          AppColors.gold.withValues(alpha: 0.15),
        ]),
      ),
      child: Column(
        children: [
          const Text('🏆 SPIEL BEENDET 🏆',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.gold,
                  letterSpacing: 3)),
          if (winnerName != null) ...[
            const SizedBox(height: 6),
            Text('$winnerName gewinnt!',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ],
          const SizedBox(height: 10),
          // Mini stats
          ...stats.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(s,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              )),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.home_rounded),
                label: const Text('MENÜ'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GameSetupScreen()),
                  );
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('NEUES SPIEL'),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }

  void _showExitDialog(BuildContext context, GameProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Spiel beenden?'),
        content: const Text('Das aktuelle Spiel geht verloren.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () {
              provider.endGame();
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
            child: const Text('Beenden',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  void _showEventLog(BuildContext context, List<String> log) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Spiellog',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.textPrimary)),
            ),
            const Divider(color: AppColors.border, height: 1),
            SizedBox(
              height: 300,
              child: log.isEmpty
                  ? const Center(
                      child: Text('Noch keine Einträge.',
                          style: TextStyle(color: AppColors.textMuted)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: log.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(log[i],
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
