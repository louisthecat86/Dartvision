import '../config/constants.dart';

class DartThrow {
  final int segment; // 1-20, 25 for bull
  final RingType ring;
  final double confidence;
  final DateTime timestamp;

  DartThrow({
    required this.segment,
    required this.ring,
    this.confidence = 1.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  int get score {
    if (ring == RingType.miss) return 0;
    if (ring == RingType.innerBull) return 50;
    if (ring == RingType.outerBull) return 25;
    if (ring == RingType.double_) return segment * 2;
    if (ring == RingType.triple) return segment * 3;
    return segment;
  }

  String get displayName {
    if (ring == RingType.miss) return 'Miss';
    if (ring == RingType.innerBull) return 'Bullseye (50)';
    if (ring == RingType.outerBull) return 'Bull (25)';
    final prefix = ring == RingType.double_
        ? 'D'
        : ring == RingType.triple
            ? 'T'
            : 'S';
    return '$prefix$segment ($score)';
  }

  String get shortName {
    if (ring == RingType.miss) return 'M';
    if (ring == RingType.innerBull) return 'DB';
    if (ring == RingType.outerBull) return 'SB';
    final prefix = ring == RingType.double_
        ? 'D'
        : ring == RingType.triple
            ? 'T'
            : '';
    return '$prefix$segment';
  }

  bool get isDouble =>
      ring == RingType.double_ || ring == RingType.innerBull;

  Map<String, dynamic> toJson() => {
        'segment': segment,
        'ring': ring.name,
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
      };

  factory DartThrow.fromJson(Map<String, dynamic> json) => DartThrow(
        segment: json['segment'] as int,
        ring: RingType.fromString(json['ring'] as String),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );

  factory DartThrow.miss() => DartThrow(
        segment: 0,
        ring: RingType.miss,
      );

  factory DartThrow.manual(int segment, RingType ring) => DartThrow(
        segment: segment,
        ring: ring,
        confidence: 1.0,
      );
}



