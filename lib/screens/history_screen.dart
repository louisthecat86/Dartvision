import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/game_history.dart';
import '../services/game_history_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<GameHistoryEntry> _history = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final history = await GameHistoryService.loadHistory();
    final stats = await GameHistoryService.globalStats();
    setState(() {
      _history = history;
      _stats = stats;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('STATISTIKEN'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'Übersicht'),
            Tab(text: 'Verlauf'),
          ],
        ),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: _confirmClearHistory,
              tooltip: 'Verlauf löschen',
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStatsTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  Widget _buildStatsTab() {
    if (_history.isEmpty) {
      return _buildEmptyState('Noch keine Spiele gespielt.');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Key stats grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _buildStatCard(
                  'Spiele', '${_stats['totalGames']}', Icons.sports_esports),
              _buildStatCard(
                  'Darts geworfen', '${_stats['totalDarts']}', Icons.gps_fixed),
              _buildStatCard(
                  'Bester Schnitt',
                  (_stats['bestAverage'] as double).toStringAsFixed(1),
                  Icons.trending_up),
              _buildStatCard(
                  '180er', '${_stats['most180s']}', Icons.star_rounded),
              _buildStatCard('Beste Runde', '${_stats['bestHighRound']}',
                  Icons.emoji_events_rounded),
              _buildStatCard('Lieblingsspiel', '${_stats['favoriteGame']}',
                  Icons.favorite_rounded),
            ],
          ),
        ]
            .animate(interval: 80.ms)
            .fadeIn()
            .slideY(begin: 0.05),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return _buildEmptyState('Noch keine Spiele im Verlauf.');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final game = _history[index];
        return _buildHistoryCard(game, index);
      },
    );
  }

  Widget _buildHistoryCard(GameHistoryEntry game, int index) {
    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(game.playedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.sports_esports,
              color: AppColors.primary, size: 20),
        ),
        title: Row(
          children: [
            Text(game.gameType,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 8),
            const Text('•', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('🏆 ${game.winnerName}',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Text(
          '$dateStr • ${game.durationMinutes} Min.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        iconColor: AppColors.textMuted,
        children: [
          // Player details
          ...game.players.map((p) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  if (p.isWinner)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.emoji_events,
                          color: AppColors.gold, size: 16),
                    ),
                  Expanded(
                    child: Text(
                      p.name,
                      style: TextStyle(
                        fontWeight:
                            p.isWinner ? FontWeight.w700 : FontWeight.w500,
                        color: p.isWinner
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _buildMiniStat('Ø', p.average.toStringAsFixed(1)),
                  const SizedBox(width: 12),
                  _buildMiniStat('D', '${p.dartsThrown}'),
                  const SizedBox(width: 12),
                  _buildMiniStat('H', '${p.highestRound}'),
                  if (p.ton80s > 0) ...[
                    const SizedBox(width: 12),
                    _buildMiniStat('180', '${p.ton80s}'),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    ).animate().fadeIn(delay: (50 * index).ms).slideX(begin: 0.03);
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 9)),
      ],
    );
  }

  Widget _buildEmptyState(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bar_chart_rounded,
              size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(text,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
        ],
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Verlauf löschen?'),
        content: const Text('Alle gespeicherten Spiele werden gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () async {
              await GameHistoryService.clearHistory();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('Löschen',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }
}
