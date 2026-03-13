import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/dart_throw.dart';
import '../providers/settings_provider.dart';
import '../services/ai_detection_service.dart';
import '../widgets/dart_edit_sheet.dart';
import 'calibration_screen.dart';

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
  String? _qualityWarning;
  bool _isInitialized = false;
  bool _flashOn = false;

  // Live-Erkennung
  bool _isLiveDetecting = false;
  Timer? _detectionTimer;
  List<DartThrow> _detectedDarts = [];
  int _lastDartCount = -1;
  int _analysisCount = 0;

  static const int _maxDarts = 3;
  // 4 Sekunden Intervall = max 15 Anfragen/Minute (kostenloses Limit)
  static const Duration _detectionInterval = Duration(seconds: 4);

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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusMessage = null;
        });
        _startLiveDetection();
      }
    } catch (e) {
      setState(() => _statusMessage = 'Kamera-Fehler: $e');
    }
  }

  void _startLiveDetection() {
    if (!_isInitialized || _controller == null) return;
    setState(() {
      _isLiveDetecting = true;
      _detectedDarts = [];
      _lastDartCount = -1;
      _analysisCount = 0;
      _qualityWarning = null;
      _statusMessage = 'Warte auf Pfeile...';
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isLiveDetecting && !_isProcessing) {
        _captureAndAnalyze();
      }
    });

    _detectionTimer = Timer.periodic(_detectionInterval, (_) {
      if (mounted && _isLiveDetecting && !_isProcessing) {
        _captureAndAnalyze();
      }
    });
  }

  void _stopLiveDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = null;
    if (mounted) {
      setState(() => _isLiveDetecting = false);
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final file = await _controller!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      await File(file.path).delete().catchError((_) {});

      final refImage = context.read<SettingsProvider>().calibrationImageBytes;
      final result = await _aiService.detectDarts(
        bytes,
        referenceImageBytes: refImage,
      );

      if (!mounted) return;

      // Qualitätswarnung separat anzeigen (nicht als Fehler)
      if (result.quality != null && result.quality!.warning != null) {
        setState(() => _qualityWarning = result.quality!.warning);
      } else {
        setState(() => _qualityWarning = null);
      }

      if (result.hasError) {
        setState(() {
          _statusMessage = result.error;
          _isProcessing = false;
        });
        return;
      }

      final newCount = result.darts.length;
      _analysisCount++;

      setState(() {
        if (newCount > 0) {
          _detectedDarts = result.darts;
          _lastDartCount = newCount;
          if (newCount == 1) {
            _statusMessage = '1 Pfeil erkannt – warte auf mehr...';
          } else if (newCount < _maxDarts) {
            _statusMessage = '$newCount Pfeile erkannt – warte auf mehr...';
          } else {
            _statusMessage = '$newCount Pfeile erkannt!';
          }
        } else {
          _statusMessage = 'Kein Pfeil erkannt – Pfeil werfen...';
        }
      });

      // Automatisch Korrektur-Dialog bei 3 Pfeilen
      if (newCount >= _maxDarts && _isLiveDetecting) {
        _stopLiveDetection();
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) _showEditSheet(_detectedDarts);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage =
            'Fehler: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    try {
      _flashOn = !_flashOn;
      await _controller!
          .setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  void _resetDetection() {
    _stopLiveDetection();
    setState(() {
      _detectedDarts = [];
      _lastDartCount = -1;
      _analysisCount = 0;
      _qualityWarning = null;
    });
    _startLiveDetection();
  }

  Future<void> _openCalibration() async {
    _stopLiveDetection();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CalibrationScreen()),
    );
    if (mounted) _startLiveDetection();
  }

  @override
  void dispose() {
    _stopLiveDetection();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCalibration =
        context.watch<SettingsProvider>().hasCalibrationImage;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Dart-Erkennung'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            _stopLiveDetection();
            Navigator.pop(context);
          },
        ),
        actions: [
          // Kalibrierungs-Button mit orangem Punkt wenn nicht kalibriert
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: hasCalibration
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                if (!hasCalibration)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: hasCalibration
                ? 'Scheibe kalibriert – neu einlesen'
                : 'Scheibe kalibrieren (empfohlen)',
            onPressed: _openCalibration,
          ),
          // Blitz-Button
          if (_isInitialized && _controller != null)
            IconButton(
              icon: Icon(
                _flashOn ? Icons.flash_on : Icons.flash_off,
                color:
                    _flashOn ? AppColors.gold : AppColors.textSecondary,
              ),
              onPressed: _toggleFlash,
              tooltip: 'Blitz',
            ),
        ],
      ),
      body: Column(
        children: [
          // Kalibrierungs-Hinweis (einmalig, wenn keine Kalibrierung vorhanden)
          if (!hasCalibration && _isInitialized)
            _buildCalibrationHint(),

          // Qualitätswarnung (dunkel, unscharf etc.)
          if (_qualityWarning != null)
            _buildQualityWarning(_qualityWarning!),

          // Kamera-Vorschau
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
                            child: Text(
                              _statusMessage!,
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(color: Colors.white),
                            ),
                          )
                        : const CircularProgressIndicator(
                            color: AppColors.primary),
                  ),
          ),

          // Statusbereich unten
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            child: Column(
              children: [
                // Statuszeile
                if (_statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          _statusMessage!.contains('Fehler') ||
                                  _statusMessage!.contains('KI-Fehler')
                              ? Icons.warning_amber_rounded
                              : _detectedDarts.isNotEmpty
                                  ? Icons.check_circle_rounded
                                  : Icons.radar_rounded,
                          size: 16,
                          color: _statusMessage!.contains('Fehler')
                              ? AppColors.error
                              : _detectedDarts.isNotEmpty
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              color: _statusMessage!.contains('Fehler')
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (_isLiveDetecting)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                      ],
                    ),
                  ),

                // Erkannte Pfeile als Chips
                if (_detectedDarts.isNotEmpty || _analysisCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_maxDarts, (i) {
                        final hasThrow = i < _detectedDarts.length;
                        final dart =
                            hasThrow ? _detectedDarts[i] : null;
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          child: _buildDartChip(i + 1, dart),
                        );
                      }),
                    ),
                  ),

                // Aktions-Buttons
                Row(
                  children: [
                    // Neustart
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _resetDetection,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Neustart'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Fertig / Prüfen
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _detectedDarts.isNotEmpty
                            ? () {
                                _stopLiveDetection();
                                _showEditSheet(_detectedDarts);
                              }
                            : null,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          _detectedDarts.isEmpty
                              ? 'Pfeile prüfen'
                              : '${_detectedDarts.length} Pfeil(e) prüfen',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hilfs-Widgets ──────────────────────────────────────────

  Widget _buildCalibrationHint() {
    return GestureDetector(
      onTap: _openCalibration,
      child: Container(
        width: double.infinity,
        color: Colors.orange.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: Colors.orange, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Für bessere Erkennung: Scheibe einmalig kalibrieren',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.orange, size: 16),
          ],
        ),
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 400));
  }

  Widget _buildQualityWarning(String warning) {
    final isDark = warning.contains('dunkel');
    return Container(
      width: double.infinity,
      color: (isDark ? Colors.blue : Colors.amber).withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            isDark ? Icons.brightness_2_rounded : Icons.blur_on_rounded,
            color: isDark ? Colors.lightBlueAccent : Colors.amber,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warning,
              style: TextStyle(
                color: isDark ? Colors.lightBlueAccent : Colors.amber,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 300));
  }

  Widget _buildDartChip(int number, DartThrow? dart) {
    final hasThrow = dart != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: hasThrow
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasThrow ? AppColors.primary : AppColors.border,
          width: hasThrow ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Pfeil $number',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasThrow ? _dartLabel(dart) : '–',
            style: TextStyle(
              fontSize: 16,
              color: hasThrow ? AppColors.primary : AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasThrow)
            Text(
              '${dart.score} Pkt.',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    ).animate(target: hasThrow ? 1 : 0).scaleXY(
          begin: 0.9,
          end: 1.0,
          curve: Curves.elasticOut,
        );
  }

  String _dartLabel(DartThrow dart) {
    if (dart.ring == RingType.innerBull) return 'Bull';
    if (dart.ring == RingType.outerBull) return '25';
    if (dart.ring == RingType.double_) return 'D${dart.segment}';
    if (dart.ring == RingType.triple) return 'T${dart.segment}';
    if (dart.ring == RingType.miss) return 'Miss';
    return '${dart.segment}';
  }

  Widget _buildOverlay() {
    return CustomPaint(
      painter: _BoardOverlayPainter(
        isActive: _isLiveDetecting,
        dartCount: _detectedDarts.length,
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 12),
            Text(
              'KI analysiert...',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditSheet(List<DartThrow> detected) async {
    if (!mounted) return;
    await showModalBottomSheet(
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

// ── Overlay Painter ────────────────────────────────────────────

class _BoardOverlayPainter extends CustomPainter {
  final bool isActive;
  final int dartCount;

  const _BoardOverlayPainter({
    this.isActive = false,
    this.dartCount = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;

    final color = dartCount >= 3
        ? Colors.greenAccent
        : AppColors.primary;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius * 0.6, paint..strokeWidth = 1);

    final dashPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
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
  bool shouldRepaint(_BoardOverlayPainter old) =>
      old.isActive != isActive || old.dartCount != dartCount;
}