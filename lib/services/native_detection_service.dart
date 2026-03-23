import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../models/dart_throw.dart';
import '../config/constants.dart';
import 'detection_service.dart';
import 'local_detection_service.dart';

/// DetectionService that uses the native Android Detector via MethodChannel.
/// This provides Dartsmind-level AI accuracy by reusing the decompiled Detector class.
class NativeDetectionService implements DetectionService {
  static const platform = MethodChannel('com.dartvision/detection');
  final LocalDetectionService _fallback = LocalDetectionService();

  bool _isSetup = false;
  StreamController<DetectionResult>? _resultController;

  NativeDetectionService() {
    _setupMethodChannel();
  }

  /// Ressourcen freigeben: StreamController und MethodChannel-Handler.
  void dispose() {
    _resultController?.close();
    _resultController = null;
    platform.setMethodCallHandler(null);
  }

  void _setupMethodChannel() {
    platform.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSetupSuccess':
        _isSetup = true;
        debugPrint('Detector setup successful');
        break;
      case 'onSetupFailed':
        _isSetup = false;
        debugPrint('Detector setup failed: ${call.arguments}');
        break;
      case 'onCannotDetect':
        debugPrint('Cannot detect: ${call.arguments}');
        break;
      case 'onDetectionResult':
        final args = call.arguments as Map<dynamic, dynamic>;
        final boxes = args['boxes'] as List<dynamic>;
        final bufferW = args['bufferW'] as int;
        final bufferH = args['bufferH'] as int;

        final darts = _convertBoxesToDarts(boxes, bufferW, bufferH);
        final result = DetectionResult(darts: darts, boardDetected: true);

        _resultController?.add(result);
        break;
    }
  }

  List<DartThrow> _convertBoxesToDarts(List<dynamic> boxes, int width, int height) {
    final cal = calibration;
    if (cal == null) return [];

    return boxes.map((box) {
      final b = box as Map<dynamic, dynamic>;
      final cx = (b['cx'] as num).toDouble();
      final cy = (b['cy'] as num).toDouble();
      final cnf = (b['cnf'] as num).toDouble();

      // Use the same position to dart conversion as local service
      return _positionToDart(cx, cy, width, height, cnf);
    }).toList();
  }

  DartThrow _positionToDart(double x, double y, int width, int height, double confidence) {
    final cal = calibration!;
    final scaleX = width / cal.imageWidth;
    final scaleY = height / cal.imageHeight;
    final cx = cal.centerX * scaleX;
    final cy = cal.centerY * scaleY;
    final rx = cal.radiusX * scaleX;
    final ry = cal.radiusY * scaleY;

    final dx = x - cx;
    final dy = y - cy;

    // Rotation correction
    final cosRot = math.cos(-cal.rotation);
    final sinRot = math.sin(-cal.rotation);
    final adx = dx * cosRot - dy * sinRot;
    final ady = dx * sinRot + dy * cosRot;

    // Ellipse normalization
    final normX = rx > 0 ? adx / rx : adx;
    final normY = ry > 0 ? ady / ry : ady;
    final relDist = math.sqrt(normX * normX + normY * normY);

    final ring = _ringFromRelDist(relDist);
    if (ring == RingType.miss) {
      return DartThrow(segment: 0, ring: ring, confidence: confidence);
    }

    if (ring == RingType.innerBull || ring == RingType.outerBull) {
      return DartThrow(segment: 25, ring: ring, confidence: confidence);
    }

    // Angle calculation
    var angle = math.atan2(normY, normX) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    if (angle >= 2 * math.pi) angle -= 2 * math.pi;

    // Segment offset
    var adjusted = angle + math.pi / 20;
    if (adjusted >= 2 * math.pi) adjusted -= 2 * math.pi;

    final segIndex = (adjusted / (2 * math.pi / 20)).floor() % 20;
    final segment = AppConstants.boardOrder[segIndex];

    return DartThrow(segment: segment, ring: ring, confidence: confidence);
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

  Future<void> setupDetector() async {
    try {
      await platform.invokeMethod('setupDetector');
    } on PlatformException catch (e) {
      debugPrint('Failed to setup detector: ${e.message}');
    }
  }

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
  Future<DetectionResult> detectFromYPlane(Uint8List currentY, int width, int height) async {
    if (!_isSetup) {
      await setupDetector();
      // Wait a bit for setup
      await Future.delayed(const Duration(seconds: 2));
    }

    if (!_isSetup) {
      // Fallback to local detection
      return _fallback.detectFromYPlane(currentY, width, height);
    }

    // Convert YUV to RGB bitmap bytes
    final bitmapBytes = await _convertYUVToBitmapBytes(currentY, width, height);

    _resultController = StreamController<DetectionResult>();

    try {
      await platform.invokeMethod('detectFrame', {
        'bitmapBytes': bitmapBytes,
        'width': width,
        'height': height,
      });

      // Wait for result with timeout
      final result = await _resultController!.stream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => _fallback.detectFromYPlane(currentY, width, height),
      );

      return result;
    } catch (e) {
      debugPrint('Native detection failed: $e');
      return _fallback.detectFromYPlane(currentY, width, height);
    } finally {
      _resultController?.close();
      _resultController = null;
    }
  }

  Future<Uint8List> _convertYUVToBitmapBytes(Uint8List yPlane, int width, int height) async {
    // Create a simple RGB bitmap from Y plane (grayscale)
    // In a real implementation, you'd want proper YUV to RGB conversion
    final rgbBytes = Uint8List(width * height * 4); // RGBA

    for (int i = 0; i < yPlane.length; i++) {
      final y = yPlane[i];
      rgbBytes[i * 4] = y;     // R
      rgbBytes[i * 4 + 1] = y; // G
      rgbBytes[i * 4 + 2] = y; // B
      rgbBytes[i * 4 + 3] = 255; // A
    }

    // For now, return the Y plane as bytes - the Android side will need to handle conversion
    // In production, you'd want to convert to proper JPEG or PNG bytes
    return yPlane;
  }

  @override
  Future<void> submitCorrection({
    required Uint8List yPlane,
    required int width,
    required int height,
    required List<DartThrow> detected,
    required List<DartThrow> corrected,
  }) async {
    // For now, just delegate to fallback
    return _fallback.submitCorrection(
      yPlane: yPlane,
      width: width,
      height: height,
      detected: detected,
      corrected: corrected,
    );
  }
}


