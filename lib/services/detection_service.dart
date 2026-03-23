import 'dart:typed_data';
import '../models/dart_throw.dart';
import 'local_detection_service.dart';

abstract class DetectionService {
  bool get hasCalibration;
  bool get hasReference;
  BoardCalibration? get calibration;

  void setCalibration(BoardCalibration cal);
  void setReferenceFromYPlane(Uint8List yPlane, int width, int height);
  void clearReference();

  bool hasMotionInYPlane(Uint8List currentY, int width, int height);
  Future<DetectionResult> detectFromYPlane(Uint8List currentY, int width, int height);

  /// Optionale Speicherung von korrekter Trainingsdaten für spätere Modellanpassung.
  Future<void> submitCorrection({
    required Uint8List yPlane,
    required int width,
    required int height,
    required List<DartThrow> detected,
    required List<DartThrow> corrected,
  });
}



