import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';
import '../services/local_detection_service.dart';

/// Kalibrierungsscreen: Benutzer fotografiert das leere Board,
/// markiert dann Mittelpunkt (Tippen) und Rand (Ziehen).
class BoardCalibrationScreen extends StatefulWidget {
  const BoardCalibrationScreen({super.key});

  @override
  State<BoardCalibrationScreen> createState() => _BoardCalibrationScreenState();
}

class _BoardCalibrationScreenState extends State<BoardCalibrationScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _flashOn = false;
  bool _isSaving = false;
  String? _errorMessage;

  Uint8List? _capturedBytes;
  bool _showPhotoEditor = false;

  // 3-Punkt-Kalibrierung: Bullseye, Rand bei 20, Rand bei 6
  Offset? _center;     // Bullseye
  Offset? _point20;    // Außenrand beim Segment 20 (oben)
  Offset? _point6;     // Außenrand beim Segment 6 (rechts)
  Size? _previewRenderSize;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMessage = 'Keine Kamera gefunden');
        return;
      }
      _controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _errorMessage = 'Kamera-Fehler: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    _flashOn = !_flashOn;
    await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isSaving = true);
    try {
      final file = await _controller!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      await File(file.path).delete().catchError((_) => File(file.path));
      setState(() {
        _capturedBytes = bytes;
        _showPhotoEditor = true;
        _center = null;
        _point20 = null;
        _point6 = null;
        _isSaving = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler beim Aufnehmen: $e';
        _isSaving = false;
      });
    }
  }

  Future<void> _saveCalibration() async {
    if (_capturedBytes == null || _center == null ||
        _point20 == null || _point6 == null) return;
    if (_previewRenderSize == null) return;
    setState(() => _isSaving = true);

    final pw = _previewRenderSize!.width;
    final ph = _previewRenderSize!.height;

    // Normalisierte Koordinaten → Referenzauflösung 480x360
    const refW = 480.0;
    const refH = 360.0;

    // Vektoren von Mitte zu den Markierungspunkten
    final v20dx = _point20!.dx - _center!.dx;
    final v20dy = _point20!.dy - _center!.dy;
    final v6dx = _point6!.dx - _center!.dx;
    final v6dy = _point6!.dy - _center!.dy;

    // Radien (Pixel-Distanzen)
    final r20 = math.sqrt(v20dx * v20dx + v20dy * v20dy);
    final r6 = math.sqrt(v6dx * v6dx + v6dy * v6dy);

    // Rotation: Winkel der 20-Richtung relativ zu Bild-Oben
    // atan2 in Bild-Koordinaten (Y nach unten), + π/2 verschiebt Nullpunkt auf "oben"
    final rotation = math.atan2(v20dy, v20dx) + math.pi / 2;

    final cal = BoardCalibration(
      centerX: (_center!.dx / pw) * refW,
      centerY: (_center!.dy / ph) * refH,
      radiusX: (r6 / pw) * refW,   // Halbachse Richtung 6 (Board-Horizontal)
      radiusY: (r20 / ph) * refH,  // Halbachse Richtung 20 (Board-Vertikal)
      rotation: rotation,
      imageWidth: refW.toInt(),
      imageHeight: refH.toInt(),
    );

    final settings = context.read<SettingsProvider>();
    await settings.setBoardCalibration(cal);
    await settings.setCalibrationImage(_capturedBytes!);

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kalibrierung gespeichert!'),
          backgroundColor: AppColors.primaryDark,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(_showPhotoEditor ? 'Board markieren' : 'Board fotografieren'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_showPhotoEditor) {
              setState(() {
                _showPhotoEditor = false;
                _capturedBytes = null;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (!_showPhotoEditor && _isInitialized)
            IconButton(
              icon: Icon(
                _flashOn ? Icons.flash_on : Icons.flash_off,
                color: _flashOn ? AppColors.gold : AppColors.textSecondary,
              ),
              onPressed: _toggleFlash,
            ),
        ],
      ),
      body: _showPhotoEditor && _capturedBytes != null
          ? _buildPhotoEditor()
          : _buildCameraView(),
    );
  }

  // ─── KAMERA-ANSICHT ──────────────────────────────────────

  Widget _buildCameraView() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Schritt 1: Leeres Board fotografieren',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
              SizedBox(height: 4),
              Text(
                'Positioniere die Kamera so wie beim Spielen. Das Board sollte das Bild gut ausfüllen. Keine Pfeile im Bild!',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isInitialized && _controller != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_controller!),
                    CustomPaint(painter: _CameraGuidePainter()),
                    if (_isSaving)
                      Container(
                        color: Colors.black.withValues(alpha: 0.6),
                        child: const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
                      ),
                  ],
                )
              : Center(
                  child: _errorMessage != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_errorMessage!,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center),
                        )
                      : const CircularProgressIndicator(color: AppColors.primary),
                ),
        ),
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 48),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isInitialized && !_isSaving ? _takePicture : null,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Foto aufnehmen'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── FOTO-EDITOR ─────────────────────────────────────────

  Widget _buildPhotoEditor() {
    final step = _center == null ? 1
        : _point20 == null ? 2
        : _point6 == null ? 3
        : 4;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Schritt 2: Board markieren',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
              const SizedBox(height: 4),
              _buildStepHint(step),
            ],
          ),
        ).animate().fadeIn(),
        Expanded(
          child: LayoutBuilder(builder: (ctx, constraints) {
            _previewRenderSize = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              onTapDown: (d) {
                if (_center == null) {
                  setState(() => _center = d.localPosition);
                } else if (_point20 == null) {
                  setState(() => _point20 = d.localPosition);
                } else if (_point6 == null) {
                  setState(() => _point6 = d.localPosition);
                }
              },
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(_capturedBytes!, fit: BoxFit.contain),
                    if (_center != null)
                      CustomPaint(
                        painter: _CalibrationPainter(
                          center: _center!,
                          point20: _point20,
                          point6: _point6,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _center = null;
                    _point20 = null;
                    _point6 = null;
                  }),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Neu markieren'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed:
                      (_center != null && _point20 != null && _point6 != null && !_isSaving)
                          ? _saveCalibration
                          : null,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.background))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_isSaving ? 'Speichern...' : 'Kalibrierung speichern'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepHint(int step) {
    final texts = [
      '① Tippe auf den MITTELPUNKT (Bullseye)',
      '② Tippe auf den Außenrand beim Segment 20 (oben)',
      '③ Tippe auf den Außenrand beim Segment 6 (rechts)',
      '✓ Fertig! Board mit Rotation & Perspektive erkannt.',
    ];
    return Text(
      texts[step - 1],
      style: TextStyle(
        color: step == 4 ? AppColors.primary : AppColors.textSecondary,
        fontSize: 13,
        fontWeight: step == 4 ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

// ─── PAINTER ─────────────────────────────────────────────

class _CameraGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center, r * 0.12, paint..strokeWidth = 1.5);
    final cp = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const cs = 20.0;
    final m = size.width * 0.08;
    canvas.drawLine(Offset(m, m + cs), Offset(m, m), cp);
    canvas.drawLine(Offset(m, m), Offset(m + cs, m), cp);
    canvas.drawLine(Offset(size.width - m - cs, m), Offset(size.width - m, m), cp);
    canvas.drawLine(Offset(size.width - m, m), Offset(size.width - m, m + cs), cp);
    canvas.drawLine(Offset(m, size.height - m - cs), Offset(m, size.height - m), cp);
    canvas.drawLine(Offset(m, size.height - m), Offset(m + cs, size.height - m), cp);
    canvas.drawLine(Offset(size.width - m - cs, size.height - m),
        Offset(size.width - m, size.height - m), cp);
    canvas.drawLine(Offset(size.width - m, size.height - m - cs),
        Offset(size.width - m, size.height - m), cp);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CalibrationPainter extends CustomPainter {
  final Offset center;
  final Offset? point20;
  final Offset? point6;

  const _CalibrationPainter({
    required this.center,
    this.point20,
    this.point6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Bullseye-Kreuz
    final crossPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const cs = 14.0;
    canvas.drawLine(center.translate(-cs, 0), center.translate(cs, 0), crossPaint);
    canvas.drawLine(center.translate(0, -cs), center.translate(0, cs), crossPaint);
    canvas.drawCircle(center, 6,
        Paint()..color = AppColors.primary..style = PaintingStyle.fill);

    void _drawMarker(Offset point, Color color, String label) {
      canvas.drawCircle(point, 8,
          Paint()..color = color..style = PaintingStyle.fill);
      canvas.drawCircle(point, 8,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      // Linie vom Center
      canvas.drawLine(center, point,
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round);
      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: ' $label',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, point.translate(10, -8));
    }

    if (point20 != null) {
      _drawMarker(point20!, Colors.green, '20');
    }

    if (point6 != null) {
      _drawMarker(point6!, Colors.orange, '6');
    }

    // Ellipse zeichnen wenn beide Punkte gesetzt
    if (point20 != null && point6 != null) {
      final r20 = (point20! - center).distance;
      final r6 = (point6! - center).distance;
      final angle20 = math.atan2(
          point20!.dy - center.dy, point20!.dx - center.dx);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle20 + math.pi / 2);

      // Ellipse: radiusY = r20 (Richtung 20), radiusX = r6 (Richtung 6)
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: r6 * 2,
        height: r20 * 2,
      );
      canvas.drawOval(
          rect,
          Paint()
            ..color = AppColors.primary.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r6 * 1.3, height: r20 * 1.3),
          Paint()
            ..color = AppColors.primary.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r6 * 0.26, height: r20 * 0.26),
          Paint()
            ..color = Colors.green.withValues(alpha: 0.5)
            ..style = PaintingStyle.fill);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CalibrationPainter old) =>
      old.center != center || old.point20 != point20 || old.point6 != point6;
}