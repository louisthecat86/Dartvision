import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../config/constants.dart';
import '../models/dart_throw.dart';

/// Kalibrierdaten: Mittelpunkt und Radius des Boards im Kamerabild.
class BoardCalibration {
  final double centerX;
  final double centerY;
  final double radius;
  final int imageWidth;
  final int imageHeight;

  const BoardCalibration({
    required this.centerX,
    required this.centerY,
    required this.radius,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Normalisierte Koordinaten (0..1) für Board-Mittelpunkt.
  double get normalizedX => centerX / imageWidth;
  double get normalizedY => centerY / imageHeight;

  /// Normalisierter Radius (relativ zur Bildbreite).
  double get normalizedRadius => radius / imageWidth;

  Map<String, dynamic> toJson() => {
        'centerX': centerX,
        'centerY': centerY,
        'radius': radius,
        'imageWidth': imageWidth,
        'imageHeight': imageHeight,
      };

  factory BoardCalibration.fromJson(Map<String, dynamic> json) =>
      BoardCalibration(
        centerX: (json['centerX'] as num).toDouble(),
        centerY: (json['centerY'] as num).toDouble(),
        radius: (json['radius'] as num).toDouble(),
        imageWidth: (json['imageWidth'] as num).toInt(),
        imageHeight: (json['imageHeight'] as num).toInt(),
      );
}

/// Ergebnis einer Frame-Differenzanalyse.
class MotionRegion {
  final double x;
  final double y;
  final double strength;

  const MotionRegion({
    required this.x,
    required this.y,
    required this.strength,
  });
}

/// Lokaler Erkennungsservice — kein API-Aufruf, kein Freeze.
///
/// Funktionsprinzip:
///   1. Referenzframe speichern (leeres Board)
///   2. Neue Frames mit Referenz per Pixeldifferenz vergleichen
///   3. Bewegungsregionen (= neue Pfeile) lokalisieren
///   4. Position relativ zum Board-Mittelpunkt → Winkel → Segment + Ring
class LocalDetectionService {
  static const int _sampleSize = 80;
  static const double _motionThreshold = 12.0;
  static const double _centerWeightFactor = 1.5;

  BoardCalibration? _calibration;
  Uint8List? _referenceFrame;
  img.Image? _referenceImageCached;

  bool get hasCalibration => _calibration != null;
  bool get hasReference => _referenceFrame != null;

  void setCalibration(BoardCalibration cal) {
    _calibration = cal;
  }

  BoardCalibration? get calibration => _calibration;

  void setReferenceFrame(Uint8List bytes) {
    _referenceFrame = bytes;
    _referenceImageCached = null;
  }

  void clearReference() {
    _referenceFrame = null;
    _referenceImageCached = null;
  }

  /// Schneller Differenz-Check: Gibt true zurück wenn Bewegung erkannt.
  Future<bool> hasMotion(Uint8List newBytes) async {
    if (_referenceFrame == null) return false;
    try {
      final diff = await _computeDiff(newBytes, _referenceFrame!);
      return diff.avgDiff > 5.0 || diff.centerDiff > 8.0;
    } catch (_) {
      return false;
    }
  }

  /// Analysiert einen Frame und gibt erkannte Pfeile zurück.
  ///
  /// Erfordert:
  /// - gesetzten Referenzframe (leeres Board)
  /// - BoardCalibration (Mitte + Radius)
  Future<DetectionResult> detectDarts(Uint8List currentBytes) async {
    if (_referenceFrame == null) {
      return DetectionResult(
        darts: [],
        error: 'Kein Referenzbild vorhanden – bitte kalibrieren',
      );
    }

    try {
      final ref = _getCachedReference();
      final cur = img.decodeImage(currentBytes);
      if (ref == null || cur == null) {
        return DetectionResult(darts: [], error: 'Bild konnte nicht geladen werden');
      }

      final motionRegions = _findMotionRegions(ref, cur);

      if (motionRegions.isEmpty) {
        return DetectionResult(darts: [], boardDetected: _calibration != null);
      }

      if (_calibration == null) {
        // Ohne Kalibrierung: Treffer melden aber kein Segment
        return DetectionResult(
          darts: _regionsToGenericDarts(motionRegions, cur),
          boardDetected: false,
        );
      }

      final darts = _regionsToDarts(motionRegions, cur);
      return DetectionResult(darts: darts, boardDetected: true);
    } catch (e) {
      return DetectionResult(darts: [], error: 'Erkennungsfehler: $e');
    }
  }

  // ────────────────────────────────────────────────
  //  PRIVATE HELPERS
  // ────────────────────────────────────────────────

  img.Image? _getCachedReference() {
    if (_referenceImageCached != null) return _referenceImageCached;
    if (_referenceFrame == null) return null;
    _referenceImageCached = img.decodeImage(_referenceFrame!);
    return _referenceImageCached;
  }

  /// Berechnet Differenz zwischen zwei Frames (auf _sampleSize skaliert).
  Future<_DiffResult> _computeDiff(Uint8List newBytes, Uint8List baseBytes) async {
    final newImg = img.decodeImage(newBytes);
    final baseImg = img.decodeImage(baseBytes);
    if (newImg == null || baseImg == null) return const _DiffResult(0, 0);

    final resNew = img.copyResize(newImg,
        width: _sampleSize, height: _sampleSize,
        interpolation: img.Interpolation.average);
    final resBase = img.copyResize(baseImg,
        width: _sampleSize, height: _sampleSize,
        interpolation: img.Interpolation.average);

    double totalDiff = 0;
    double centerDiff = 0;
    int count = 0;
    int centerCount = 0;

    for (int y = 0; y < _sampleSize; y++) {
      for (int x = 0; x < _sampleSize; x++) {
        final p1 = resNew.getPixel(x, y);
        final p2 = resBase.getPixel(x, y);
        final lum1 = _luminance(p1);
        final lum2 = _luminance(p2);
        final diff = (lum1 - lum2).abs();
        totalDiff += diff;
        count++;

        final cx = (x - _sampleSize / 2).abs();
        final cy = (y - _sampleSize / 2).abs();
        if (cx < _sampleSize * 0.25 && cy < _sampleSize * 0.25) {
          centerDiff += diff;
          centerCount++;
        }
      }
    }

    return _DiffResult(
      count > 0 ? totalDiff / count : 0,
      centerCount > 0 ? centerDiff / centerCount : 0,
    );
  }

  /// Findet Bewegungsregionen (Pixelcluster mit hoher Differenz).
  List<MotionRegion> _findMotionRegions(img.Image ref, img.Image cur) {
    final w = math.min(ref.width, cur.width);
    final h = math.min(ref.height, cur.height);

    // Kleinere Auflösung für Performance
    final scale = math.min(1.0, 200.0 / math.max(w, h));
    final sw = (w * scale).round();
    final sh = (h * scale).round();

    final resRef = img.copyResize(ref, width: sw, height: sh,
        interpolation: img.Interpolation.average);
    final resCur = img.copyResize(cur, width: sw, height: sh,
        interpolation: img.Interpolation.average);

    // Differenzkarte aufbauen
    final diffMap = List.generate(sh, (_) => List.filled(sw, 0.0));
    for (int y = 0; y < sh; y++) {
      for (int x = 0; x < sw; x++) {
        final l1 = _luminance(resRef.getPixel(x, y));
        final l2 = _luminance(resCur.getPixel(x, y));
        diffMap[y][x] = (l1 - l2).abs();
      }
    }

    // Regionen mit starker Bewegung finden (Grid-basiert)
    const gridSize = 10;
    final regions = <MotionRegion>[];
    for (int gy = 0; gy < sh - gridSize; gy += gridSize) {
      for (int gx = 0; gx < sw - gridSize; gx += gridSize) {
        double sum = 0;
        int cnt = 0;
        for (int dy = 0; dy < gridSize; dy++) {
          for (int dx = 0; dx < gridSize; dx++) {
            sum += diffMap[gy + dy][gx + dx];
            cnt++;
          }
        }
        final avg = sum / cnt;
        if (avg > _motionThreshold) {
          // Mittelpunkt dieser Region in Originalkoordinaten
          final px = (gx + gridSize / 2) / scale;
          final py = (gy + gridSize / 2) / scale;
          regions.add(MotionRegion(x: px, y: py, strength: avg));
        }
      }
    }

    // Regionen clustern (nahe Regionen zusammenfassen)
    return _clusterRegions(regions, w, h);
  }

  /// Fasst nahe beieinander liegende Bewegungsregionen zu Dart-Treffern zusammen.
  List<MotionRegion> _clusterRegions(List<MotionRegion> regions, int w, int h) {
    if (regions.isEmpty) return [];

    final clusterDist = math.min(w, h) * 0.08; // 8% der Bildbreite
    final visited = List.filled(regions.length, false);
    final clusters = <MotionRegion>[];

    for (int i = 0; i < regions.length; i++) {
      if (visited[i]) continue;
      visited[i] = true;
      double sumX = regions[i].x * regions[i].strength;
      double sumY = regions[i].y * regions[i].strength;
      double sumStr = regions[i].strength;

      for (int j = i + 1; j < regions.length; j++) {
        if (visited[j]) continue;
        final dx = regions[i].x - regions[j].x;
        final dy = regions[i].y - regions[j].y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < clusterDist) {
          visited[j] = true;
          sumX += regions[j].x * regions[j].strength;
          sumY += regions[j].y * regions[j].strength;
          sumStr += regions[j].strength;
        }
      }

      clusters.add(MotionRegion(
        x: sumX / sumStr,
        y: sumY / sumStr,
        strength: sumStr,
      ));
    }

    // Stärkste 3 Cluster (max. 3 Pfeile)
    clusters.sort((a, b) => b.strength.compareTo(a.strength));
    return clusters.take(3).toList();
  }

  /// Ohne Kalibrierung: nur Treffer melden (keine Segmentzuordnung).
  List<DartThrow> _regionsToGenericDarts(List<MotionRegion> regions, img.Image cur) {
    return regions.map((_) => DartThrow(
      segment: 0,
      ring: RingType.miss,
      confidence: 0.5,
    )).toList();
  }

  /// Mit Kalibrierung: Position → Winkel → Segment + Ring.
  List<DartThrow> _regionsToDarts(List<MotionRegion> regions, img.Image cur) {
    final cal = _calibration!;

    // Skalierungsfaktor falls Bild-Auflösung anders als Kalibrierung
    final scaleX = cur.width / cal.imageWidth;
    final scaleY = cur.height / cal.imageHeight;
    final cx = cal.centerX * scaleX;
    final cy = cal.centerY * scaleY;
    final r = cal.radius * ((scaleX + scaleY) / 2);

    return regions.map((region) {
      final dx = region.x - cx;
      final dy = region.y - cy;
      final dist = math.sqrt(dx * dx + dy * dy);

      // Ring bestimmen
      final relDist = dist / r;
      final ring = _ringFromRelDist(relDist);

      if (ring == RingType.miss) {
        return DartThrow(segment: 0, ring: RingType.miss, confidence: 0.6);
      }

      // Segment aus Winkel
      // Dartboard: 20 oben (= -90° / -π/2), im Uhrzeigersinn
      double angle = math.atan2(dy, dx); // -π .. π, 0 = rechts
      // Um 90° drehen: 20 ist oben
      angle = angle + math.pi / 2;
      if (angle < 0) angle += 2 * math.pi;
      if (angle >= 2 * math.pi) angle -= 2 * math.pi;

      final segment = _angleToSegment(angle);
      return DartThrow(
        segment: segment,
        ring: ring,
        confidence: math.min(1.0, region.strength / 30.0),
      );
    }).toList();
  }

  /// Bestimmt den Ring aus dem normierten Abstand (0 = Mitte, 1 = Außenkante).
  RingType _ringFromRelDist(double relDist) {
    if (relDist < 0.05) return RingType.innerBull;
    if (relDist < 0.13) return RingType.outerBull;
    if (relDist < 0.55) return RingType.singleInner;
    if (relDist < 0.65) return RingType.triple;
    if (relDist < 0.90) return RingType.singleOuter;
    if (relDist < 1.02) return RingType.double_;
    return RingType.miss;
  }

  /// Berechnet das Segment (1-20) aus dem Winkel im Uhrzeigersinn ab "oben".
  int _angleToSegment(double angleRad) {
    // Jedes Segment nimmt 360°/20 = 18° ein
    // Segment 20 ist mittig oben → fängt bei -9° an (= 351°)
    // Wir verschieben um 9° (= π/20) damit 20 in der Mitte liegt
    double adjusted = angleRad - (math.pi / 20);
    if (adjusted < 0) adjusted += 2 * math.pi;

    final segIndex = (adjusted / (2 * math.pi / 20)).floor() % 20;
    return AppConstants.boardOrder[segIndex];
  }

  double _luminance(img.Pixel p) =>
      0.299 * p.r.toDouble() + 0.587 * p.g.toDouble() + 0.114 * p.b.toDouble();
}

class _DiffResult {
  final double avgDiff;
  final double centerDiff;
  const _DiffResult(this.avgDiff, this.centerDiff);
}

/// Ergebnis einer Erkennung.
class DetectionResult {
  final List<DartThrow> darts;
  final bool boardDetected;
  final String? error;

  DetectionResult({
    required this.darts,
    this.boardDetected = false,
    this.error,
  });

  bool get hasError => error != null;
  bool get hasDarts => darts.isNotEmpty;
}
