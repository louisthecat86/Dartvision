import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiKeyController;
  bool _showApiKey = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(
      text: context.read<SettingsProvider>().apiKey,
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

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
              // AI Section
              _buildSectionHeader('KI-Konfiguration', Icons.smart_toy_rounded),
              const SizedBox(height: 12),
              _buildApiKeyCard(settings),
              const SizedBox(height: 8),
              Text(
                'Hole dir einen kostenlosen API-Key unter:\nhttps://aistudio.google.com/apikey',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
              ),

              const SizedBox(height: 32),

              // Game defaults
              _buildSectionHeader('Spieleinstellungen', Icons.tune_rounded),
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

              // About
              _buildSectionHeader('Über', Icons.info_outline_rounded),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DartVision v1.0.0',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'KI-gesteuerter Dart Tracker.\n'
                        'Nutzt Google Gemini für die Darterkennung.\n\n'
                        'Spielmodi: 501, 301, 701, Cricket, Cut Throat,\n'
                        'Around the Clock, Shanghai, Killer, Bob\'s 27,\n'
                        'High Score, Double Training\n'
                        'Manuelle & Kamera-Eingabe mit KI-Korrektur',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5,
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

  Widget _buildApiKeyCard(SettingsProvider settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google Gemini API-Key',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: !_showApiKey,
              decoration: InputDecoration(
                hintText: 'AIzaSy...',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _showApiKey
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _showApiKey = !_showApiKey),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.save_rounded, size: 20),
                      onPressed: () {
                        settings.setApiKey(_apiKeyController.text.trim());
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('API-Key gespeichert'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  settings.hasApiKey
                      ? Icons.check_circle
                      : Icons.error_outline,
                  size: 14,
                  color: settings.hasApiKey
                      ? AppColors.primary
                      : AppColors.accentOrange,
                ),
                const SizedBox(width: 6),
                Text(
                  settings.hasApiKey
                      ? 'API-Key konfiguriert'
                      : 'Kein API-Key gesetzt',
                  style: TextStyle(
                    fontSize: 12,
                    color: settings.hasApiKey
                        ? AppColors.primary
                        : AppColors.accentOrange,
                  ),
                ),
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
