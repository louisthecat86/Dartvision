import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import 'game_screen.dart';

class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({super.key});

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  late String _selectedGameType;
  bool _doubleOut = true;
  bool _doubleIn = false;
  int _legsToWin = 1;
  int _setsToWin = 1;
  int _legsPerSet = 3;
  int _shanghaiRounds = 7;
  int _highScoreRounds = 10;
  final List<TextEditingController> _playerControllers = [];
  int _playerCount = 2;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _selectedGameType = settings.lastGameType;
    _doubleOut = settings.doubleOut;
    _doubleIn = settings.doubleIn;

    final names = settings.savedPlayerNames;
    for (int i = 0; i < AppConstants.maxPlayers; i++) {
      _playerControllers.add(TextEditingController(
        text: i < names.length ? names[i] : 'Spieler ${i + 1}',
      ));
    }
    _playerCount = names.length.clamp(1, AppConstants.maxPlayers);

    // Validate game type still exists
    if (!AppConstants.allGameTypes.contains(_selectedGameType)) {
      _selectedGameType = AppConstants.game501;
    }
  }

  @override
  void dispose() {
    for (final c in _playerControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isX01 =>
      _selectedGameType == AppConstants.game501 ||
      _selectedGameType == AppConstants.game301 ||
      _selectedGameType == AppConstants.game701;

  int get _minPlayers =>
      AppConstants.minPlayers[_selectedGameType] ?? 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEUES SPIEL'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Game type selection ──
            Text('Spielmodus',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildGameTypeSelector(),
            // Description
            if (AppConstants.gameDescriptions[_selectedGameType] != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppConstants.gameDescriptions[_selectedGameType]!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // ── X01 Options ──
            if (_isX01) ...[
              Text('Regeln', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildToggle('Double Out', _doubleOut,
                  (v) => setState(() => _doubleOut = v)),
              _buildToggle('Double In', _doubleIn,
                  (v) => setState(() => _doubleIn = v)),
              const SizedBox(height: 16),

              // Legs & Sets
              Text('Legs & Sets',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildCounter('Legs (First to)', _legsToWin, 1, AppConstants.maxLegs,
                  (v) => setState(() => _legsToWin = v)),
              _buildCounter('Sets (First to)', _setsToWin, 1, AppConstants.maxSets,
                  (v) => setState(() => _setsToWin = v)),
              if (_setsToWin > 1)
                _buildCounter('Legs pro Set', _legsPerSet, 1, AppConstants.maxLegs,
                    (v) => setState(() => _legsPerSet = v)),
              const SizedBox(height: 24),
            ],

            // ── Shanghai rounds ──
            if (_selectedGameType == AppConstants.gameShanghai) ...[
              Text('Optionen', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildCounter('Runden (Zahlen 1–X)', _shanghaiRounds, 3, 20,
                  (v) => setState(() => _shanghaiRounds = v)),
              const SizedBox(height: 24),
            ],

            // ── High Score rounds ──
            if (_selectedGameType == AppConstants.gameHighScore) ...[
              Text('Optionen', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildCounter('Runden', _highScoreRounds, 3, 30,
                  (v) => setState(() => _highScoreRounds = v)),
              const SizedBox(height: 24),
            ],

            // ── Players ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Spieler',
                    style: Theme.of(context).textTheme.titleMedium),
                Row(
                  children: [
                    _buildSmallButton(Icons.remove, () {
                      if (_playerCount > _minPlayers) {
                        setState(() => _playerCount--);
                      }
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('$_playerCount',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    _buildSmallButton(Icons.add, () {
                      if (_playerCount < AppConstants.maxPlayers) {
                        setState(() => _playerCount++);
                      }
                    }),
                  ],
                ),
              ],
            ),
            if (_playerCount < _minPlayers)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Mindestens $_minPlayers Spieler für $_selectedGameType',
                  style: const TextStyle(
                      color: AppColors.accentOrange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            ...List.generate(_playerCount, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _playerControllers[i],
                  decoration: InputDecoration(
                    prefixIcon: CircleAvatar(
                      radius: 14,
                      backgroundColor: _playerColor(i),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                    hintText: 'Spieler ${i + 1}',
                  ),
                ),
              ).animate().fadeIn(delay: (80 * i).ms).slideX(begin: 0.05);
            }),

            const SizedBox(height: 32),

            // ── Start ──
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _playerCount >= _minPlayers ? _startGame : null,
                icon: const Icon(Icons.sports_esports_rounded, size: 24),
                label: const Text('SPIEL STARTEN'),
              ),
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildGameTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: AppConstants.gameCategories.entries.map((category) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 4),
              child: Text(
                category.key,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: category.value.map((type) {
                final selected = type == _selectedGameType;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedGameType = type;
                    if (_playerCount < (_minPlayers)) {
                      _playerCount = _minPlayers;
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary)),
          Switch(
              value: value, onChanged: onChanged, activeColor: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildCounter(
      String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14)),
          ),
          _buildSmallButton(Icons.remove, () {
            if (value > min) onChanged(value - 1);
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('$value',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18)),
          ),
          _buildSmallButton(Icons.add, () {
            if (value < max) onChanged(value + 1);
          }),
        ],
      ),
    );
  }

  Widget _buildSmallButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 18, color: AppColors.textSecondary),
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

  void _startGame() {
    final playerNames = List.generate(
      _playerCount,
      (i) => _playerControllers[i].text.trim().isEmpty
          ? 'Spieler ${i + 1}'
          : _playerControllers[i].text.trim(),
    );

    final settings = context.read<SettingsProvider>();
    settings.setPlayerNames(playerNames);
    settings.setLastGameType(_selectedGameType);
    settings.setDoubleOut(_doubleOut);
    settings.setDoubleIn(_doubleIn);

    context.read<GameProvider>().startGame(
          gameType: _selectedGameType,
          playerNames: playerNames,
          doubleIn: _doubleIn,
          doubleOut: _doubleOut,
          legsToWin: _legsToWin,
          setsToWin: _setsToWin,
          legsPerSet: _legsPerSet,
          shanghaiRounds: _shanghaiRounds,
          highScoreRounds: _highScoreRounds,
        );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
  }
}



