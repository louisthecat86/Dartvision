import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/dart_throw.dart';
import '../config/constants.dart';
import 'detection_service.dart';
import 'local_detection_service.dart';
import 'image_converter_service.dart';

/// Roboflow Inference API Service
/// Sendet Frames an Roboflow YOLO Modell und erhält Dart-Erkennungen zurück
class RoboflowDetectionService implements DetectionService {
  final String? apiKey;
  final String? modelEndpoint;
  final LocalDetectionService _fallback = LocalDetectionService();

  static const int requestTimeoutSeconds = 10;
  static const int maxRetries = 2;

  RoboflowDetectionService({this.apiKey, this.modelEndpoint});

  @override
  bool get hasCalibration => _fallback.hasCalibration;

  @override
  bool get hasReference => _fallback.hasReference;

  @override
  BoardCalibration? get calibration => _fallback.calibration;

  @override
  void setCalibration(BoardCalibration cal) => _fallback.setCalibration(cal);

  @override
  void setReferenceFromYPlane(Uint8List yPlane, int width, int height) =>
      _fallback.setReferenceFromYPlane(yPlane, width, height);

  @override
  void clearReference() => _fallback.clearReference();

  @override
  bool hasMotionInYPlane(Uint8List currentY, int width, int height) =>
      _fallback.hasMotionInYPlane(currentY, width, height);

  @override
  Future<DetectionResult> detectFromYPlane(
      Uint8List currentY, int width, int height) async {
    // Falls keine API konfiguriert: Fallback
    if (!_hasValidConfig()) {
      debugPrint(
          'RoboflowDetectionService: Keine gültige Config, nutze Fallback');
      return _fallback.detectFromYPlane(currentY, width, height);
    }

    try {
      // 1. Y-Plane → JPEG
      final jpegBytes = ImageConverterService.yPlaneToJpeg(
        currentY,
        width,
        height,
        quality: 85,
      );

      // 2. Roboflow API aufrufen
      final darts = await _callRoboflowApi(jpegBytes);

      if (darts.isNotEmpty) {
        _apiAvailable = true;
        _lastSuccessfulRequest = DateTime.now();
        return DetectionResult(darts: darts, boardDetected: true);
      }

      // 3. Falls Roboflow keine Treffer: Fallback
      return _fallback.detectFromYPlane(currentY, width, height);
    } catch (e) {
      debugPrint('RoboflowDetectionService Fehler: $e');
      _apiAvailable = false;

      // Fallback bei Fehler
      return _fallback.detectFromYPlane(currentY, width, height);
    }
  }

  /// Ruft Roboflow Inference API auf
  Future<List<DartThrow>> _callRoboflowApi(Uint8List jpegBytes) async {
    if (!_hasValidConfig()) {
      throw Exception('Roboflow API nicht konfiguriert');
    }

    final uri = Uri.parse(modelEndpoint!);
    final base64Image = base64Encode(jpegBytes);

    var attempt = 0;
    while (attempt < maxRetries) {
      try {
        attempt++;

        final response = await http
            .post(
          uri.replace(
            queryParameters: {
              ...uri.queryParameters,
              'api_key': apiKey,
              'format': 'json',
            },
          ),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: 'imageToUpload=$base64Image',
        )
            .timeout(
          Duration(seconds: requestTimeoutSeconds),
          onTimeout: () => throw Exception('Roboflow API Timeout'),
        );

        if (response.statusCode == 200) {
          return _parseRoboflowResponse(response.body);
        } else if (response.statusCode == 401) {
          throw Exception('Roboflow API Key ungültig (401)');
        } else if (response.statusCode == 404) {
          throw Exception('Roboflow Modell nicht gefunden (404)');
        } else {
          throw const Exception(
              'Roboflow API Fehler: ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        if (attempt >= maxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    throw Exception('Alle Roboflow API Versuche fehlgeschlagen');
  }

  /// Parst Roboflow JSON Response zu DartThrow List
  List<DartThrow> _parseRoboflowResponse(String jsonString) {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final predictions = (data['predictions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final darts = <DartThrow>[];

      for (final pred in predictions) {
        try {
          final dart = _predictionToDartThrow(pred);
          if (dart != null) darts.add(dart);
        } catch (e) {
          debugPrint('Fehler beim Parsen einer Prediction: $e');
        }
      }

      // Sortiere nach Konfidenz (höchste zuerst)
      darts.sort((a, b) => b.confidence.compareTo(a.confidence));

      // Nimm max 3 Pfeile
      return darts.take(3).toList();
    } catch (e) {
      throw Exception('Roboflow JSON Parse Fehler: $e');
    }
  }

  /// Konvertiert eine einzelne Roboflow Prediction zu DartThrow
  DartThrow? _predictionToDartThrow(Map<String, dynamic> prediction) {
    try {
      final className = (prediction['class'] as String?)?.toLowerCase() ?? '';
      final confidence = (prediction['confidence'] as num?)?.toDouble() ?? 0.5;

      // Ignoriere sehr niedrige Konfidenz
      if (confidence < 0.3) return null;

      // Klassifizierung: "dart", "S20", "D20", "T20", etc.
      if (className == 'dart' || className.isEmpty) {
        // Generischer Pfeil
        return DartThrow(
          segment: 20, // Default Segment
          ring: RingType.singleInner,
          confidence: confidence,
        );
      }

      // Versuch: "T20" oder "D20" oder "S20" zu parsen
      return _parseSegmentAndRing(className, confidence);
    } catch (e) {
      debugPrint('Fehler beim Konvertieren zu DartThrow: $e');
      return null;
    }
  }

  /// Parst Segment und Ring aus Klassennamen wie "T20", "D15", "S6", "Bull"
  DartThrow? _parseSegmentAndRing(String className, double confidence) {
    final normalized = className.trim().toUpperCase();

    // Bull / InnerBull
    if (normalized.contains('BULL') || normalized.contains('DB')) {
      return DartThrow(
        segment: 25,
        ring: normalized.contains('INNER') || normalized == 'DB'
            ? RingType.innerBull
            : RingType.outerBull,
        confidence: confidence,
      );
    }

    // Format: T20, D20, S20, etc.
    if (normalized.length >= 2) {
      final ringChar = normalized[0];
      final segmentStr = normalized.substring(1);

      final segment = int.tryParse(segmentStr);
      if (segment == null || segment < 1 || segment > 20) {
        return null;
      }

      final ring = _ringFromChar(ringChar);
      if (ring == null) return null;

      return DartThrow(
        segment: segment,
        ring: ring,
        confidence: confidence,
      );
    }

    return null;
  }

  /// Konvertiert Zeichen zu RingType
  RingType? _ringFromChar(String char) {
    switch (char) {
      case 'T':
        return RingType.triple;
      case 'D':
        return RingType.double_;
      case 'S':
        return RingType.singleInner; // oder singleOuter
      case 'B':
        return RingType.outerBull;
      default:
        return null;
    }
  }

  /// Speichert Korrektionen für Training
  @override
  Future<void> submitCorrection({
    required Uint8List yPlane,
    required int width,
    required int height,
    required List<DartThrow> detected,
    required List<DartThrow> corrected,
  }) async {
    try {
      final correction = {
        'timestamp': DateTime.now().toIso8601String(),
        'detected': detected.map((d) => d.toJson()).toList(),
        'corrected': corrected.map((d) => d.toJson()).toList(),
        'match': detected.length == corrected.length &&
            detected
                .asMap()
                .entries
                .every((e) => e.value.segment == corrected[e.key].segment),
      };

      if (kDebugMode) {
        debugPrint('Roboflow Correction: ${jsonEncode(correction)}');
      }

      // TODO: Speichere lokal oder sende an Backend für Training
    } catch (e) {
      debugPrint('Fehler beim Speichern der Korrektur: $e');
    }
  }

  bool _hasValidConfig() {
    return apiKey != null &&
        apiKey!.isNotEmpty &&
        modelEndpoint != null &&
        modelEndpoint!.isNotEmpty;
  }
}
