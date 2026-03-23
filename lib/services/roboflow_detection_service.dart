import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/dart_throw.dart';
import '../config/constants.dart';
import 'detection_service.dart';
import 'local_detection_service.dart';
import 'image_converter_service.dart';

/// Ein DetectionService, der optional einen Roboflow Inference API Endpunkt
/// nutzt. Bei fehlender Konfiguration fällt er zurück auf lokale Heuristik.
class RoboflowDetectionService implements DetectionService {
  final String? apiKey;
  final String? modelEndpoint;
  final LocalDetectionService _fallback = LocalDetectionService();

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
    if (!_hasValidConfig()) {
      return _fallback.detectFromYPlane(currentY, width, height);
    }

    try {
      final jpegBytes = ImageConverterService.yPlaneToJpeg(
        currentY,
        width,
        height,
        quality: 85,
      );
      final darts = await _callRoboflowApi(jpegBytes);
      if (darts.isNotEmpty) {
        return DetectionResult(darts: darts, boardDetected: true);
      }
      return _fallback.detectFromYPlane(currentY, width, height);
    } catch (e) {
      return _fallback.detectFromYPlane(currentY, width, height);
    }
  }

  Future<List<DartThrow>> _callRoboflowApi(Uint8List jpegBytes) async {
    if (!_hasValidConfig()) throw Exception('API nicht konfiguriert');
    
    final uri = Uri.parse(modelEndpoint!);
    final base64Image = base64Encode(jpegBytes);
    
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          uri.replace(queryParameters: {...uri.queryParameters, 'api_key': apiKey, 'format': 'json'}),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'imageToUpload=$base64Image',
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) return _parseRoboflowResponse(response.body);
        if (response.statusCode == 401) throw Exception('API Key ungültig');
        if (response.statusCode == 404) throw Exception('Modell nicht gefunden');
      } catch (e) {
        if (attempt < 1) await Future.delayed(const Duration(milliseconds: 500));
        else rethrow;
      }
    }
    throw Exception('API Anfrage fehlgeschlagen');
  }

  List<DartThrow> _parseRoboflowResponse(String jsonString) {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final predictions = (data['predictions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final darts = <DartThrow>[];
    
    for (final pred in predictions) {
      final dart = _predictionToDartThrow(pred);
      if (dart != null) darts.add(dart);
    }
    darts.sort((a, b) => b.confidence.compareTo(a.confidence));
    return darts.take(3).toList();
  }

  DartThrow? _predictionToDartThrow(Map<String, dynamic> prediction) {
    final className = (prediction['class'] as String?)?.toLowerCase() ?? '';
    final confidence = (prediction['confidence'] as num?)?.toDouble() ?? 0.5;
    if (confidence < 0.3) return null;
    
    if (className == 'dart' || className.isEmpty) {
      return DartThrow(segment: 20, ring: RingType.singleInner, confidence: confidence);
    }
    return _parseSegmentAndRing(className, confidence);
  }

  DartThrow? _parseSegmentAndRing(String className, double confidence) {
    final normalized = className.trim().toUpperCase();
    
    if (normalized.contains('BULL')) {
      return DartThrow(
        segment: 25,
        ring: normalized == 'DB' ? RingType.innerBull : RingType.outerBull,
        confidence: confidence,
      );
    }
    
    if (normalized.length >= 2) {
      final ringChar = normalized[0];
      final segment = int.tryParse(normalized.substring(1));
      if (segment == null || segment < 1 || segment > 20) return null;
      
      final ring = _ringFromChar(ringChar);
      return ring != null ? DartThrow(segment: segment, ring: ring, confidence: confidence) : null;
    }
    return null;
  }

  RingType? _ringFromChar(String char) {
    switch (char) {
      case 'T': return RingType.triple;
      case 'D': return RingType.double_;
      case 'S': return RingType.singleInner;
      case 'B': return RingType.outerBull;
      default: return null;
    }
  }

  bool _hasValidConfig() => apiKey != null && apiKey!.isNotEmpty && modelEndpoint != null && modelEndpoint!.isNotEmpty;

  @override
  Future<void> submitCorrection({
    required Uint8List yPlane,
    required int width,
    required int height,
    required List<DartThrow> detected,
    required List<DartThrow> corrected,
  }) async {
    // Speichern für Training
  }
}



