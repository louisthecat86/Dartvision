import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/settings_provider.dart';
import '../services/ai_detection_service.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _flashOn = false;
  String? _errorMessage;
  bool _calibrationDone = false;

  final AiDetectionService _aiService = AiDetectionService();

  @override
  void initState() {
    super.initState();
    _initCamera();
    final apiKey = context.read<SettingsProvider>().apiKey;
    _aiService.configure(apiKey);
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
    await _controller!
        .setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  Future<void> _captureCalibration() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    try {
      final file = await _controller!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      await File(file.path).delete().catchError((_) => File(file.path));

      // Qualität prüfen
      final quality = await _aiService.analyzeQuality(bytes);
      if (quality.isDark || quality.isBlurry) {
        setState(() {
          _errorMessage = quality.warning;
          _isCapturing = false;
        });
        return;
      }

      // Als Datei speichern (nicht als Base64 in SharedPreferences)
      final settings = context.read<SettingsProvider>();
      await settings.setCalibrationImage(bytes);

      setState(() {
        _calibrationDone = true;
        _isCapturing = false;
        _statusMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler: $e';
        _isCapturing = false;
        _statusMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scheibe kalibrieren'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isInitialized)
            IconButton(
              icon: Icon(
                _flashOn ? Icons.flash_on : Icons.flash_off,
                color: _flashOn ? AppColors.gold : AppColors.textSecondary,
              ),
              onPressed: _toggleFlash,
            ),
        ],
      ),
      body: Column(
        children: [
          // Kamera
          Expanded(
            child: _isInitialized && _controller != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
                      _buildGuideOverlay(),
                      if (_isCapturing) _buildProcessingOverlay(),
                      if (_calibrationDone) _buildSuccessOverlay(),
                    ],
                  )
                : Center(
                    child: _errorMessage != null
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(_errorMessage!,
                                style: const TextStyle(color: Colors.white),
                                textAlign: TextAlign.center),
                          )
                        : const CircularProgressIndicator(
                            color: AppColors.primary),
                  ),
          ),

          // Unterbereich
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Anleitung
                if (!_calibrationDone) ...[
                  const Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: AppColors.primary, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Richte die Kamera auf die LEERE Scheibe (ohne Pfeile).',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.only(left: 26),
                    child: Text(
                      '• Gleiche Position wie beim Spielen verwenden\n'
                      '• Die gesamte Scheibe sollte sichtbar sein\n'
                      '• Gute Beleuchtung sicherstellen',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12, height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Fehlerhinweis
                if (_errorMessage != null && !_calibrationDone)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.accent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                                color: AppColors.accent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(),

                // Button
                if (_calibrationDone)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Fertig – Kalibrierung gespeichert'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ).animate().fadeIn().scaleXY(begin: 0.95)
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isCapturing ? null : _captureCalibration,
                      icon: _isCapturing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt_rounded),
                      label: Text(_isCapturing
                          ? 'Wird analysiert...'
                          : 'Scheibe einlesen'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideOverlay() {
    return CustomPaint(painter: _CalibrationGuidePainter());
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 12),
            Text('Bild wird analysiert...',
                style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Kalibrierung gespeichert!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }
}

class _CalibrationGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    // Äußerer Hilfskreis
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, paint);

    // Gestrichelter innerer Kreis
    final innerPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius * 0.15, innerPaint);

    // Ecken-Marker für Ausrichtungshilfe
    final cornerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const cs = 20.0; // corner size
    final margin = size.width * 0.08;
    // oben links
    canvas.drawLine(Offset(margin, margin + cs), Offset(margin, margin), cornerPaint);
    canvas.drawLine(Offset(margin, margin), Offset(margin + cs, margin), cornerPaint);
    // oben rechts
    canvas.drawLine(Offset(size.width - margin - cs, margin), Offset(size.width - margin, margin), cornerPaint);
    canvas.drawLine(Offset(size.width - margin, margin), Offset(size.width - margin, margin + cs), cornerPaint);
    // unten links
    canvas.drawLine(Offset(margin, size.height - margin - cs), Offset(margin, size.height - margin), cornerPaint);
    canvas.drawLine(Offset(margin, size.height - margin), Offset(margin + cs, size.height - margin), cornerPaint);
    // unten rechts
    canvas.drawLine(Offset(size.width - margin - cs, size.height - margin), Offset(size.width - margin, size.height - margin), cornerPaint);
    canvas.drawLine(Offset(size.width - margin, size.height - margin - cs), Offset(size.width - margin, size.height - margin), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}