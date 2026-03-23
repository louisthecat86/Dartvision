import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';
import 'game_setup_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              _buildLogo(context),
              const SizedBox(height: 12),
              Text(
                'Lokale Kamera-Erkennung',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 2,
                    ),
              ),
              const Spacer(flex: 2),
              // Main actions
              _buildMainButton(context,
                  icon: Icons.play_arrow_rounded,
                  label: 'NEUES SPIEL',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GameSetupScreen()))),
              const SizedBox(height: 12),
              _buildSecondaryButton(context,
                  icon: Icons.bar_chart_rounded,
                  label: 'Statistiken & Verlauf',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()))),
              const SizedBox(height: 12),
              _buildSecondaryButton(context,
                  icon: Icons.settings_rounded,
                  label: 'Einstellungen',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()))),
              const SizedBox(height: 16),
              Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  return _buildStatusChip(context, hasCalibration: settings.hasBoardCalibration);
                },
              ),
              const Spacer(flex: 3),
              Text('Lokale Dart-Erkennung – kein API nötig',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(
            Icons.adjust_rounded,
            size: 56,
            color: AppColors.background,
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(duration: 3.seconds, color: Colors.white24),
        const SizedBox(height: 24),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.primary, AppColors.accent],
          ).createShader(bounds),
          child: Text(
            'DARTVISION',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                  color: Colors.white,
                ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.1);
  }

  Widget _buildMainButton(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 28),
        label: Text(label),
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2);
  }

  Widget _buildSecondaryButton(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: AppColors.textSecondary),
        label: Text(label,
            style: const TextStyle(color: AppColors.textSecondary)),
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2);
  }

  Widget _buildStatusChip(BuildContext context, {required bool hasCalibration}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: (hasCalibration ? AppColors.primary : AppColors.accentOrange)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (hasCalibration ? AppColors.primary : AppColors.accentOrange)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasCalibration ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 16,
            color: hasCalibration ? AppColors.primary : AppColors.accentOrange,
          ),
          const SizedBox(width: 8),
          Text(
            hasCalibration ? 'Kamera kalibriert' : 'Board kalibrieren – Einstellungen',
            style: TextStyle(
              color: hasCalibration ? AppColors.primary : AppColors.accentOrange,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms);
  }
}



