import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/dart_throw.dart';
import '../providers/settings_provider.dart';
import '../services/ai_detection_service.dart';
import '../widgets/dart_edit_sheet.dart';

class CameraScreen extends StatefulWidget {
  final void Function(List<DartThrow> darts) onDartsDetected;

  const CameraScreen({super.key, required this.onDartsDetected});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  final AiDetectionService _aiService = AiDetectionService();
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isInitialized = false;
  bool _flashOn = false;

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
        setState(() => _statusMessage = 'Keine Kamera gefunden');
        return;
      }

      _controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      setState(() => _statusMessage = 'Kamera-Fehler: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Dart-Erkennung'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isInitialized && _controller != null)
            IconButton(
              icon: Icon(
                _flashOn ? Icons.flash_on : Icons.flash_off,
                color: _flashOn ? AppColors.gold : AppColors.textSecondary,
              ),
              onPressed: _toggleFlash,
              tooltip: 'Blitz',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isInitialized && _controller != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
                      _buildOverlay(),
                      if (_isProcessing) _buildProcessingOverlay(),
                    ],
                  )
                : Center(
                    child: _statusMessage != null
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(_statusMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white)),
                          )
                        : const CircularProgressIndicator(
                            color: AppColors.primary),
                  ),
          ),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              children: [
                if (_statusMessage != null && !_isProcessing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          _statusMessage!.contains('Fehler') ||
                                  _statusMessage!.contains('Kein')
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline,
                          size: 16,
                          color: _statusMessage!.contains('Fehler')
                              ? AppColors.accent
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              color: _statusMessage!.contains('Fehler')
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_isProcessing && _statusMessage == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Richte die Kamera auf dein Dartboard.\n'
                      'Nach dem Foto kannst du die Erkennung korrigieren.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isProcessing || !_isInitialized ? null : _capture,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.background,
                            ),
                          )
                        : const Icon(Icons.camera_rounded),
                    label: Text(
                        _isProcessing ? 'KI analysiert...' : 'FOTO AUFNEHMEN'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return CustomPaint(painter: _BoardOverlayPainter());
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 60, height: 60,
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            const Text('KI analysiert Dartboard...',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Segmente & Ringe werden erkannt',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
          ].animate(interval: 100.ms).fadeIn(),
        ),
      ),
    );
  }

  void _toggleFlash() async {
    if (_controller == null) return;
    try {
      _flashOn = !_flashOn;
      await _controller!
          .setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  Future<void> _capture() async {
    if (_controller == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final result = await _aiService.detectDarts(bytes);

      setState(() => _isProcessing = false);

      if (result.hasError) {
        setState(() => _statusMessage = result.error);
        return;
      }

      if (!result.boardDetected) {
        setState(() =>
            _statusMessage = 'Kein Dartboard erkannt. Bitte erneut versuchen.');
        return;
      }

      if (!mounted) return;
      _openEditSheet(result.darts);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Fehler: $e';
      });
    }
  }

  void _openEditSheet(List<DartThrow> detected) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (_) {
        return DartEditSheet(
          detectedDarts: detected,
          onConfirm: (confirmed) {
            widget.onDartsDetected(confirmed);
            Navigator.pop(context);
          },
        );
      },
    );
  }
}

class _BoardOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;

    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius * 0.6, paint..strokeWidth = 1);

    final dashPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    canvas.drawLine(
        Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy),
        dashPaint);
    canvas.drawLine(
        Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius),
        dashPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
