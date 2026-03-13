import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/dart_throw.dart';

/// Full-screen bottom sheet to review, edit, add, remove AI-detected darts
/// before they are committed to the game.
class DartEditSheet extends StatefulWidget {
  final List<DartThrow> detectedDarts;
  final void Function(List<DartThrow> confirmed) onConfirm;

  const DartEditSheet({
    super.key,
    required this.detectedDarts,
    required this.onConfirm,
  });

  @override
  State<DartEditSheet> createState() => _DartEditSheetState();
}

class _DartEditSheetState extends State<DartEditSheet> {
  late List<_EditableDart> _darts;

  @override
  void initState() {
    super.initState();
    _darts = widget.detectedDarts.asMap().entries.map((e) {
      return _EditableDart(
        index: e.key,
        segment: e.value.segment,
        ring: e.value.ring,
        confidence: e.value.confidence,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.edit_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Erkennung prüfen & korrigieren',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                // Add dart button
                IconButton(
                  onPressed: _addDart,
                  icon: const Icon(Icons.add_circle_outline,
                      color: AppColors.primary),
                  tooltip: 'Dart hinzufügen',
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),

          // Dart list
          Flexible(
            child: _darts.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _darts.length,
                    itemBuilder: (context, index) {
                      return _buildDartRow(index);
                    },
                  ),
          ),

          const Divider(color: AppColors.border, height: 1),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _darts.isEmpty ? null : _confirm,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                        '${_darts.length} Dart(s) übernehmen'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.sports_rounded,
              size: 48, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'Keine Darts erkannt.\nFüge manuell Darts hinzu oder nimm ein neues Foto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDartRow(int index) {
    final dart = _darts[index];
    final score = _calcScore(dart.segment, dart.ring);
    final confidencePct = (dart.confidence * 100).toInt();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dart.confidence < 0.6
              ? AppColors.accentOrange.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: dart number + confidence + delete
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _displayName(dart.segment, dart.ring),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '= $score Pkt.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              // Confidence badge
              if (dart.confidence < 1.0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: dart.confidence < 0.6
                        ? AppColors.accentOrange.withValues(alpha: 0.15)
                        : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$confidencePct%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: dart.confidence < 0.6
                          ? AppColors.accentOrange
                          : AppColors.primary,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              // Delete button
              IconButton(
                onPressed: () => _removeDart(index),
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.accent, size: 20),
                visualDensity: VisualDensity.compact,
                tooltip: 'Dart entfernen',
              ),
            ],
          ),
          if (dart.confidence < 0.6)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 38),
              child: Text(
                '⚠ Niedrige Konfidenz – bitte prüfen',
                style: TextStyle(
                  color: AppColors.accentOrange.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(height: 10),
          // Segment selector
          Row(
            children: [
              const SizedBox(
                width: 70,
                child: Text('Segment:',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ...List.generate(20, (i) {
                        final num = i + 1;
                        final selected = dart.segment == num;
                        return _buildChip(
                          '$num',
                          selected,
                          () => _updateSegment(index, num),
                        );
                      }),
                      _buildChip(
                        'Bull',
                        dart.segment == 25,
                        () => _updateSegment(index, 25),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Ring selector
          Row(
            children: [
              const SizedBox(
                width: 70,
                child: Text('Ring:',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ),
              if (dart.segment == 25) ...[
                _buildRingChip('Outer Bull', RingType.outerBull,
                    dart.ring == RingType.outerBull, index),
                _buildRingChip('Bullseye', RingType.innerBull,
                    dart.ring == RingType.innerBull, index),
              ] else ...[
                _buildRingChip('Single', RingType.singleOuter,
                    dart.ring == RingType.singleOuter ||
                        dart.ring == RingType.singleInner,
                    index),
                _buildRingChip('Double', RingType.double_,
                    dart.ring == RingType.double_, index),
                _buildRingChip('Triple', RingType.triple,
                    dart.ring == RingType.triple, index),
              ],
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.05);
  }

  Widget _buildChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildRingChip(
      String label, RingType ring, bool selected, int index) {
    Color color;
    if (ring == RingType.double_ || ring == RingType.innerBull) {
      color = AppColors.dartRed;
    } else if (ring == RingType.triple) {
      color = AppColors.dartGreen;
    } else {
      color = AppColors.textSecondary;
    }

    return GestureDetector(
      onTap: () => _updateRing(index, ring),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _updateSegment(int index, int segment) {
    setState(() {
      _darts[index].segment = segment;
      _darts[index].confidence = 1.0; // Manual = 100%
      // Adjust ring for bull
      if (segment == 25) {
        if (_darts[index].ring != RingType.outerBull &&
            _darts[index].ring != RingType.innerBull) {
          _darts[index].ring = RingType.outerBull;
        }
      } else {
        if (_darts[index].ring == RingType.outerBull ||
            _darts[index].ring == RingType.innerBull) {
          _darts[index].ring = RingType.singleOuter;
        }
      }
    });
  }

  void _updateRing(int index, RingType ring) {
    setState(() {
      _darts[index].ring = ring;
      _darts[index].confidence = 1.0;
    });
  }

  void _removeDart(int index) {
    setState(() {
      _darts.removeAt(index);
      for (int i = 0; i < _darts.length; i++) {
        _darts[i].index = i;
      }
    });
  }

  void _addDart() {
    setState(() {
      _darts.add(_EditableDart(
        index: _darts.length,
        segment: 20,
        ring: RingType.singleOuter,
        confidence: 1.0,
      ));
    });
  }

  void _confirm() {
    final confirmed = _darts.map((d) {
      return DartThrow.manual(d.segment, d.ring);
    }).toList();
    widget.onConfirm(confirmed);
    Navigator.pop(context);
  }

  int _calcScore(int segment, RingType ring) {
    if (ring == RingType.miss) return 0;
    if (ring == RingType.innerBull) return 50;
    if (ring == RingType.outerBull) return 25;
    if (ring == RingType.double_) return segment * 2;
    if (ring == RingType.triple) return segment * 3;
    return segment;
  }

  String _displayName(int segment, RingType ring) {
    if (ring == RingType.innerBull) return 'Bullseye';
    if (ring == RingType.outerBull) return 'Bull';
    final prefix = ring == RingType.double_
        ? 'D'
        : ring == RingType.triple
            ? 'T'
            : 'S';
    return '$prefix$segment';
  }
}

class _EditableDart {
  int index;
  int segment;
  RingType ring;
  double confidence;

  _EditableDart({
    required this.index,
    required this.segment,
    required this.ring,
    required this.confidence,
  });
}
