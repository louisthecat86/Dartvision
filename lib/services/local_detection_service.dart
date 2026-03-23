import 'dart:math' as math;
import 'dart:typed_data';
import '../config/constants.dart';
import '../models/dart_throw.dart';
import 'detection_service.dart';

/// Kalibrierdaten: Mittelpunkt + Ellipsen-Radien + Rotation.
///
/// 3-Punkt-Kalibrierung: Benutzer markiert Bullseye, Außenrand bei 20 und bei 6.
/// radiusX = Halbachse in Richtung Segment 6 (Board-Horizontale)
/// radiusY = Halbachse in Richtung Segment 20 (Board-Vertikale)
/// rotation = Drehwinkel des Boards in Rad (0 = 20 zeigt nach oben im Bild)
class BoardCalibration {
  final double centerX;
  final double centerY;
  final double radiusX;
  final double radiusY;
  final double rotation;
  final int imageWidth;
  final int imageHeight;

  const BoardCalibration({
    required this.centerX,
    required this.centerY,
    required this.radiusX,
    required this.radiusY,
    this.rotation = 0.0,
    required this.imageWidth,
    required this.imageHeight,
  });

  factory BoardCalibration.fromJson(Map<String, dynamic> json) {
    final rx = (json['radiusX'] as num?)?.toDouble() ??
        (json['radius'] as num?)?.toDouble() ?? 100.0;
    final ry = (json['radiusY'] as num?)?.toDouble() ??
        (json['radius'] as num?)?.toDouble() ?? 100.0;
    return BoardCalibration(
      centerX: (json['centerX'] as num).toDouble(),
      centerY: (json['centerY'] as num).toDouble(),
      radiusX: rx,
      radiusY: ry,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      imageWidth: (json['imageWidth'] as num).toInt(),
      imageHeight: (json['imageHeight'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'centerX': centerX,
        'centerY': centerY,
        'radiusX': radiusX,
        'radiusY': radiusY,
        'rotation': rotation,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
      };
}

/// Ergebnis einer Erkennung.
class DetectionResult {
  final List<DartThrow> darts;
  final bool boardDetected;
  final String? error;

  DetectionResult({required this.darts, this.boardDetected = false, this.error});

  bool get hasError => error != null;
  bool get hasDarts => darts.isNotEmpty;
}

/// Lokaler Erkennungsservice — komplett ohne API, kein JPEG-Decode.
///
/// Arbeitet direkt auf rohen Y-Plane-Bytes (Grauwerte) aus dem Kamerastream.
/// Das vermeidet img.decodeImage()-Fehler und ermöglicht echten Live-Stream.
///
/// Ellipsenmodell für schräge Kamerawinkel:
/// radiusX ≠ radiusY kompensiert Perspektivverzerrung automatisch.
class LocalDetectionService implements DetectionService {
  static const int _sampleStep = 3;
  static const double _globalThreshold = 8.0;
  static const double _centerThreshold = 12.0;
  static const int _gridSize = 20;

  BoardCalibration? _calibration;
  Uint8List? _referenceY;
  int _refWidth = 0;
  int _refHeight = 0;

  @override
  bool get hasCalibration => _calibration != null;
  @override
  bool get hasReference => _referenceY != null;
  @override
  BoardCalibration? get calibration => _calibration;

  @override
  void setCalibration(BoardCalibration cal) => _calibration = cal;

  /// Speichert Y-Plane-Frame als Referenz (leeres Board, keine Pfeile).
  @override
  void setReferenceFromYPlane(Uint8List yPlane, int width, int height) {
    _referenceY = Uint8List.fromList(yPlane);
    _refWidth = width;
    _refHeight = height;
  }

  @override
  void clearReference() {
    _referenceY = null;
  }

  /// Schneller Bewegungscheck direkt auf rohen Y-Plane-Bytes.
  /// KEIN img.decodeImage() — kein Fehler, kein Freeze.
  @override
  bool hasMotionInYPlane(Uint8List currentY, int width, int height) {
    if (_referenceY == null) return false;

    final w = math.min(width, _refWidth);
    final h = math.min(height, _refHeight);

    double totalDiff = 0;
    double centerDiff = 0;
    int count = 0;
    int centerCount = 0;

    for (int y = 0; y < h; y += _sampleStep) {
      final rowCur = y * width;
      final rowRef = y * _refWidth;
      for (int x = 0; x < w; x += _sampleStep) {
        final ci = rowCur + x;
        final ri = rowRef + x;
        if (ci >= currentY.length || ri >= _referenceY!.length) continue;

        final diff = (currentY[ci] - _referenceY![ri]).abs().toDouble();
        totalDiff += diff;
        count++;

        // Mittlere 40% stärker gewichten
        final rx = (x / w - 0.5).abs();
        final ry = (y / h - 0.5).abs();
        if (rx < 0.2 && ry < 0.2) {
          centerDiff += diff;
          centerCount++;
        }
      }
    }

    if (count == 0) return false;
    return (totalDiff / count) > _globalThreshold ||
        (centerCount > 0 && (centerDiff / centerCount) > _centerThreshold);
  }

  /// Erkennt Dart-Positionen aus Y-Plane-Differenz und gibt Würfe zurück.
  @override
  Future<DetectionResult> detectFromYPlane(Uint8List currentY, int width, int height) async {
    if (_referenceY == null) {
      return DetectionResult(darts: [], error: 'Kein Referenzbild – Neustart nötig');
    }

    try {
      final positions = _findDartPositions(currentY, width, height);
      if (positions.isEmpty) {
        return DetectionResult(darts: [], boardDetected: _calibration != null);
      }

      if (_calibration == null) {
        return DetectionResult(
          darts: positions
              .map((_) => DartThrow(segment: 0, ring: RingType.miss, confidence: 0.4))
              .toList(),
          boardDetected: false,
        );
      }

      final darts = positions.map((p) => _positionToDart(p, width, height)).toList();
      return DetectionResult(darts: darts, boardDetected: true);
    } catch (e) {
      return DetectionResult(darts: [], error: 'Erkennungsfehler: $e');
    }
  }

  @override
  Future<void> submitCorrection({
    required Uint8List yPlane,
    required int width,
    required int height,
    required List<DartThrow> detected,
    required List<DartThrow> corrected,
  }) async {
    // Lokaler Modus speichert kein Training, kann später erweitert werden.
    return;
  }

  // ── PRIVATE ──────────────────────────────────────────────────────

  List<_Pos> _findDartPositions(Uint8List currentY, int width, int height) {
    final w = math.min(width, _refWidth);
    final h = math.min(height, _refHeight);

    final cellW = w / _gridSize;
    final cellH = h / _gridSize;
    final sums = List.generate(_gridSize, (_) => List.filled(_gridSize, 0.0));
    final counts = List.generate(_gridSize, (_) => List.filled(_gridSize, 0));

    for (int y = 0; y < h; y += 2) {
      final rowCur = y * width;
      final rowRef = y * _refWidth;
      for (int x = 0; x < w; x += 2) {
        final ci = rowCur + x;
        final ri = rowRef + x;
        if (ci >= currentY.length || ri >= _referenceY!.length) continue;

        final diff = (currentY[ci] - _referenceY![ri]).abs().toDouble();
        final gx = (x / cellW).floor().clamp(0, _gridSize - 1);
        final gy = (y / cellH).floor().clamp(0, _gridSize - 1);
        sums[gy][gx] += diff;
        counts[gy][gx]++;
      }
    }

    // Durchschnitt + dynamische Schwelle
    final avgs = List.generate(
        _gridSize, (gy) => List.generate(_gridSize, (gx) {
      final c = counts[gy][gx];
      return c > 0 ? sums[gy][gx] / c : 0.0;
    }));

    final flat = [for (var row in avgs) ...row]..sort();
    final p75 = flat[(flat.length * 0.75).toInt()];
    final threshold = math.max(_globalThreshold, p75 * 2.0);

    final hotCells = <_Pos>[];
    for (int gy = 0; gy < _gridSize; gy++) {
      for (int gx = 0; gx < _gridSize; gx++) {
        if (avgs[gy][gx] > threshold) {
          hotCells.add(_Pos(
            x: (gx + 0.5) * cellW,
            y: (gy + 0.5) * cellH,
            strength: avgs[gy][gx],
          ));
        }
      }
    }

    if (hotCells.isEmpty) return [];
    return _cluster(hotCells, w, h);
  }

  List<_Pos> _cluster(List<_Pos> pts, int w, int h) {
    final dist = math.min(w, h) * 0.10;
    final visited = List.filled(pts.length, false);
    final result = <_Pos>[];

    for (int i = 0; i < pts.length; i++) {
      if (visited[i]) continue;
      visited[i] = true;
      double sx = pts[i].x * pts[i].strength;
      double sy = pts[i].y * pts[i].strength;
      double ss = pts[i].strength;

      for (int j = i + 1; j < pts.length; j++) {
        if (visited[j]) continue;
        final dx = pts[i].x - pts[j].x;
        final dy = pts[i].y - pts[j].y;
        if (math.sqrt(dx * dx + dy * dy) < dist) {
          visited[j] = true;
          sx += pts[j].x * pts[j].strength;
          sy += pts[j].y * pts[j].strength;
          ss += pts[j].strength;
        }
      }
      result.add(_Pos(x: sx / ss, y: sy / ss, strength: ss));
    }

    result.sort((a, b) => b.strength.compareTo(a.strength));
    return result.take(3).toList();
  }

  /// Pixelposition → Dart-Wurf mit Ellipsen- und Rotations-Normalisierung.
  DartThrow _positionToDart(_Pos pos, int width, int height) {
    final cal = _calibration!;
    final scaleX = width / cal.imageWidth;
    final scaleY = height / cal.imageHeight;
    final cx = cal.centerX * scaleX;
    final cy = cal.centerY * scaleY;
    final rx = cal.radiusX * scaleX;
    final ry = cal.radiusY * scaleY;

    final dx = pos.x - cx;
    final dy = pos.y - cy;

    // Schritt 1: Rotation rückgängig machen (Board in Bildausrichtung drehen)
    // rotation = 0 bedeutet 20 zeigt nach oben im Bild.
    // Positive Rotation = Board im Uhrzeigersinn gedreht.
    final cosR = math.cos(-cal.rotation);
    final sinR = math.sin(-cal.rotation);
    final adx = dx * cosR - dy * sinR;
    final ady = dx * sinR + dy * cosR;

    // Schritt 2: Ellipsen-Normalisierung (Perspektivkorrektur)
    final normX = rx > 0 ? adx / rx : adx;
    final normY = ry > 0 ? ady / ry : ady;
    final relDist = math.sqrt(normX * normX + normY * normY);

    final ring = _ringFromRelDist(relDist);
    if (ring == RingType.miss) {
      return DartThrow(segment: 0, ring: RingType.miss, confidence: 0.5);
    }

    // Bull/Bullseye: Segment muss 25 sein (nicht aus Winkel berechnen)
    if (ring == RingType.innerBull || ring == RingType.outerBull) {
      return DartThrow(
        segment: 25,
        ring: ring,
        confidence: math.min(1.0, pos.strength / 35.0),
      );
    }

    // Schritt 3: Winkel im normierten Board-Raum berechnen.
    // atan2 mit Y-nach-unten: Winkel wächst im Uhrzeigersinn.
    // +π/2 verschiebt den Nullpunkt von "rechts" nach "oben" (= Segment 20).
    double angle = math.atan2(normY, normX) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    if (angle >= 2 * math.pi) angle -= 2 * math.pi;

    // Offset um halbe Segmentbreite, damit Segmentgrenzen korrekt zentriert sind.
    // Jedes Segment = 2π/20 = π/10 breit. +π/20 verschiebt so, dass
    // angle=0 (Mitte der 20) auf segIndex=0 abgebildet wird.
    double adjusted = angle + (math.pi / 20);
    if (adjusted >= 2 * math.pi) adjusted -= 2 * math.pi;

    final segIndex = (adjusted / (2 * math.pi / 20)).floor() % 20;
    final segment = AppConstants.boardOrder[segIndex];

    return DartThrow(
      segment: segment,
      ring: ring,
      confidence: math.min(1.0, pos.strength / 35.0),
    );
  }

  RingType _ringFromRelDist(double d) {
    if (d < 0.05) return RingType.innerBull;
    if (d < 0.13) return RingType.outerBull;
    if (d < 0.55) return RingType.singleInner;
    if (d < 0.65) return RingType.triple;
    if (d < 0.90) return RingType.singleOuter;
    if (d < 1.02) return RingType.double_;
    return RingType.miss;
  }
}

class _Pos {
  final double x;
  final double y;
  final double strength;
  const _Pos({required this.x, required this.y, required this.strength});
}