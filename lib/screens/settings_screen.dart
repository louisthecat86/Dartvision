import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';
import 'board_calibration_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EINSTELLUNGEN'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Kalibrierung
              _buildSectionHeader('Kamera-Kalibrierung', Icons.tune_rounded),
              const SizedBox(height: 12),
              _buildCalibrationCard(context, settings),

              const SizedBox(height: 32),

              // Spieleinstellungen
              _buildSectionHeader('Spieleinstellungen', Icons.sports_rounded),
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Double Out (Standard)',
                'Spiel muss mit Double beendet werden',
                settings.doubleOut,
                settings.setDoubleOut,
              ),
              _buildSwitchTile(
                'Double In',
                'Spiel muss mit Double begonnen werden',
                settings.doubleIn,
                settings.setDoubleIn,
              ),

              const SizedBox(height: 32),

              // Sound & Vibration
              _buildSectionHeader('Audio & Haptik', Icons.vibration_rounded),
              const SizedBox(height: 12),
              _buildSwitchTile(
                'Vibration',
                'Vibriert wenn ein Pfeil erkannt wird',
                settings.vibrationEnabled,
                settings.setVibrationEnabled,
              ),

              const SizedBox(height: 32),

              // Über
              _buildSectionHeader('Über DartVision', Icons.info_outline_rounded),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DartVision v1.1.0',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '✓ Lokale Dart-Erkennung – kein API-Key nötig\n'
                        '✓ Kein Kamera-Freeze – kontinuierlicher Stream\n'
                        '✓ Offline-fähig – funktioniert ohne Internet\n'
                        '✓ Keine Tageslimits\n\n'
                        'Spielmodi: 501, 301, 701, Cricket, Cut Throat,\n'
                        'Around the Clock, Shanghai, Killer, Bob\'s 27,\n'
                        'High Score, Double Training',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCalibrationCard(
      BuildContext context, SettingsProvider settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  settings.hasBoardCalibration
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: settings.hasBoardCalibration
                      ? AppColors.primary
                      : AppColors.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  settings.hasBoardCalibration
                      ? 'Board kalibriert'
                      : 'Noch nicht kalibriert',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: settings.hasBoardCalibration
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Die Kalibrierung ermöglicht präzise Segment-Erkennung. '
              'Einmal kalibrieren, dann automatische Dart-Erkennung ohne API.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BoardCalibrationScreen()),
                    ),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16),
                    label: Text(settings.hasBoardCalibration
                        ? 'Neu kalibrieren'
                        : 'Jetzt kalibrieren'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                if (settings.hasBoardCalibration) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.accent, size: 20),
                    onPressed: () => settings.clearBoardCalibration(),
                    tooltip: 'Kalibrierung löschen',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Future<void> Function(bool) onChanged,
  ) {
    return Card(
      child: SwitchListTile(
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }
}
