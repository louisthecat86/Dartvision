import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/dart_throw.dart';

class DartboardInputWidget extends StatefulWidget {
  final void Function(DartThrow dart) onThrow;

  const DartboardInputWidget({super.key, required this.onThrow});

  @override
  State<DartboardInputWidget> createState() => _DartboardInputWidgetState();
}

class _DartboardInputWidgetState extends State<DartboardInputWidget> {
  // Quick-entry mode
  int? _selectedSegment;
  RingType? _selectedRing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Quick number grid
        Expanded(child: _buildNumberGrid()),
        // Ring selector + confirm
        _buildRingSelector(),
        // Miss button
        _buildMissButton(),
      ],
    );
  }

  Widget _buildNumberGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: GridView.count(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          ...List.generate(20, (i) {
            final num = i + 1;
            final selected = _selectedSegment == num;
            return _buildNumberButton(num, selected);
          }),
          // Bull
          _buildSpecialButton('SB', 25, RingType.outerBull),
          // Bullseye
          _buildSpecialButton('DB', 25, RingType.innerBull),
        ],
      ),
    );
  }

  Widget _buildNumberButton(int number, bool selected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSegment = number;
          if (_selectedRing == RingType.outerBull ||
              _selectedRing == RingType.innerBull) {
            _selectedRing = RingType.singleOuter;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            '$number',
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialButton(String label, int segment, RingType ring) {
    final isBull = ring == RingType.outerBull;
    return GestureDetector(
      onTap: () {
        widget.onThrow(DartThrow.manual(segment, ring));
        setState(() {
          _selectedSegment = null;
          _selectedRing = null;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isBull
              ? AppColors.dartGreen.withValues(alpha: 0.2)
              : AppColors.dartRed.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isBull ? AppColors.dartGreen : AppColors.dartRed,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isBull ? AppColors.dartGreen : AppColors.dartRed,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRingSelector() {
    if (_selectedSegment == null) return const SizedBox.shrink();

    final rings = [
      ('S', RingType.singleOuter, AppColors.textSecondary),
      ('D', RingType.double_, AppColors.dartRed),
      ('T', RingType.triple, AppColors.dartGreen),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Text(
            '$_selectedSegment →',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 8),
          ...rings.map((r) {
            final score = r.$1 == 'S'
                ? _selectedSegment!
                : r.$1 == 'D'
                    ? _selectedSegment! * 2
                    : _selectedSegment! * 3;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () {
                    widget.onThrow(
                        DartThrow.manual(_selectedSegment!, r.$2));
                    setState(() {
                      _selectedSegment = null;
                      _selectedRing = null;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: r.$3.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: r.$3.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${r.$1}$_selectedSegment',
                          style: TextStyle(
                            color: r.$3,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '= $score',
                          style: TextStyle(
                            color: r.$3.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMissButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () {
            widget.onThrow(DartThrow.miss());
            setState(() {
              _selectedSegment = null;
              _selectedRing = null;
            });
          },
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.textMuted),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: const Text(
            'MISS',
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}
