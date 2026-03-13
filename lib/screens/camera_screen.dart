import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../models/dart_throw.dart';
import '../providers/settings_provider.dart';
import '../services/local_detection_service.dart';
import '../widgets/dart_edit_sheet.dart';
import 'board_calibration_screen.dart';

class CameraScreen extends StatefulWidget {
  final void Function(List<DartThrow> darts) onDartsDetected;

  const CameraScreen({super.key, required this.onDartsDetected});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final LocalDetectionService _detector = LocalDetectionService();

  bool _isInitialized = false;
  bool _isStreaming = false;
  bool _isProcessing = false;
  bool _flashOn = false;

  String? _statusMessage;
  String? _qualityWarning;
  List<DartThrow> _detectedDarts = [];
  int _zeroStreakCount = 0;

  bool _showNextPlayerBanner = false;
  bool _baselineCaptured = false;

  static const int _maxDarts = 3;
  static const int _maxZeroStreak = 20; // ~10 Sekunden bei 500ms Intervall
  static const Duration _analysisInterval = Duration(milliseconds: 500);
  Timer? _analysisTimer;

  // Letzter Frame aus dem Stream
  Uint8List? _latestFrameBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCalibration();
    _initCamera();
  }

  Future<void> _loadCalibration() async {
    final settings = context.read<SettingsProvider>();
    final cal = settings.boardCalibration;
    if (cal != null) {
      _detector.setCalibration(cal);
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _statusMessage = 'Keine Kamera gefunden');
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
          _statusMessage = 'Kamera bereit – Kalibrierung starten';
        });
        _startStream();
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Kamera-Fehler: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  //  KONTINUIERLICHER STREAM (kein Freeze!)
  // ─────────────────────────────────────────────────────────

  void _startStream() {
    if (!_isInitialized || _controller == null) return;
    if (_isStreaming) return;

    _controller!.startImageStream((CameraImage frame) {
      if (!_isStreaming) return;
      // Frame zu JPEG konvertieren (nur wenn nicht gerade verarbeitet)
      if (!_isProcessing) {
        _latestFrameBytes = _cameraImageToJpeg(frame);
      }
    });

    setState(() {
      _isStreaming = true;
      _statusMessage = 'Stream aktiv – Referenzframe aufnehmen';
    });

    // Timer für periodische Analyse
    _analysisTimer = Timer.periodic(_analysisInterval, (_) => _analyze());
  }

  void _stopStream() {
    _analysisTimer?.cancel();
    _analysisTimer = null;
    if (_controller != null && _isStreaming) {
      try {
        _controller!.stopImageStream();
      } catch (_) {}
    }
    if (mounted) setState(() => _isStreaming = false);
  }

  /// Konvertiert CameraImage (YUV/BGRA) zu JPEG-Bytes.
  /// Nutzt die platform-komprimierte JPEG-Version wenn verfügbar.
  Uint8List? _cameraImageToJpeg(CameraImage frame) {
    try {
      // Auf Android: planes[0] ist oft direkt ein JPEG
      if (frame.format.group == ImageFormatGroup.jpeg) {
        return frame.planes[0].bytes;
      }
      // Für YUV420: nur Y-Plane nehmen (Graustufen reichen für Differenzanalyse)
      if (frame.planes.isNotEmpty) {
        return frame.planes[0].bytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  //  ANALYSE-LOOP
  // ─────────────────────────────────────────────────────────

  Future<void> _analyze() async {
    if (!mounted || _isProcessing || _latestFrameBytes == null) return;

    final bytes = _latestFrameBytes!;

    // Phase 1: Referenzframe aufnehmen
    if (!_baselineCaptured) {
      _detector.setReferenceFrame(bytes);
      if (mounted) {
        setState(() {
          _baselineCaptured = true;
          _statusMessage = 'Bereit – Pfeil werfen!';
        });
      }
      return;
    }

    // Phase 2: Bewegungserkennung
    _isProcessing = true;
    try {
      final hasMotion = await _detector.hasMotion(bytes);

      if (!hasMotion) {
        _zeroStreakCount++;
        if (_zeroStreakCount > _maxZeroStreak && _detectedDarts.isEmpty) {
          if (mounted) {
            setState(() => _statusMessage = 'Warte auf Pfeil...');
          }
        }
        return;
      }

      // Bewegung erkannt – vollständige Analyse
      _zeroStreakCount = 0;
      if (mounted) setState(() => _statusMessage = 'Pfeil erkannt – analysiere...');

      final result = await _detector.detectDarts(bytes);

      if (!mounted) return;

      if (result.hasError) {
        setState(() => _statusMessage = result.error);
        return;
      }

      if (result.darts.isEmpty) return;

      // Neue Pfeile verarbeiten
      final newCount = result.darts.length;
      if (newCount > _detectedDarts.length) {
        final settings = context.read<SettingsProvider>();

        if (settings.vibrationEnabled) {
          final hasVib = await Vibration.hasVibrator();
          if (hasVib == true) Vibration.vibrate(duration: 80);
        }

        setState(() {
          _detectedDarts = result.darts;
          if (newCount < _maxDarts) {
            _statusMessage = '$newCount Pfeil erkannt – weiteren werfen...';
          } else {
            _statusMessage = '$newCount Pfeile – fertig!';
          }
        });

        // Referenz aktualisieren (Baseline mit neuem Pfeil)
        _detector.setReferenceFrame(bytes);

        if (newCount >= _maxDarts) {
          _stopStream();
          await Future.delayed(const Duration(milliseconds: 400));
          if (mounted) await _showEditSheet(_detectedDarts);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Fehler: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}');
      }
    } finally {
      _isProcessing = false;
    }
  }

  // ─────────────────────────────────────────────────────────
  //  AKTIONEN
  // ─────────────────────────────────────────────────────────

  void _captureReference() {
    if (_latestFrameBytes == null) return;
    _detector.setReferenceFrame(_latestFrameBytes!);
    setState(() {
      _baselineCaptured = true;
      _detectedDarts = [];
      _zeroStreakCount = 0;
      _statusMessage = 'Referenz aufgenommen – Pfeil werfen!';
    });
  }

  void _resetDetection() {
    setState(() {
      _detectedDarts = [];
      _zeroStreakCount = 0;
      _baselineCaptured = false;
      _showNextPlayerBanner = false;
      _qualityWarning = null;
      _statusMessage = 'Referenzframe aufnehmen...';
    });
    if (!_isStreaming) _startStream();
    // Neue Baseline in 500ms aufnehmen
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _latestFrameBytes != null) {
        _captureReference();
      }
    });
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

  Future<void> _openCalibration() async {
    _stopStream();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BoardCalibrationScreen()),
    );
    if (mounted) {
      await _loadCalibration();
      _resetDetection();
    }
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
      builder: (_) => DartEditSheet(
        detectedDarts: detected,
        onConfirm: (confirmed) {
          widget.onDartsDetected(confirmed);
          Navigator.pop(context);
        },
      ),
    );

    if (mounted && _isInitialized) {
      setState(() => _showNextPlayerBanner = true);
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) _resetDetection();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed && _isInitialized) {
      _startStream();
    }
  }

  @override
  void dispose() {
    _stopStream();
    _controller?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasCalibration = context.watch<SettingsProvider>().hasBoardCalibration;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Dart-Erkennung'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            _stopStream();
            Navigator.pop(context);
          },
        ),
        actions: [
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
                ? 'Kalibrierung anpassen'
                : 'Board kalibrieren (empfohlen)',
            onPressed: _openCalibration,
          ),
          if (_isInitialized)
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
          if (_showNextPlayerBanner) _buildNextPlayerBanner(),
          if (!hasCalibration && _isInitialized && !_showNextPlayerBanner)
            _buildCalibrationHint(),
          if (_qualityWarning != null) _buildQualityWarning(_qualityWarning!),

          // Kamerapreview (KEIN FREEZE — läuft kontinuierlich)
          Expanded(
            child: _isInitialized && _controller != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
                      _buildOverlay(),
                      if (_isProcessing) _buildProcessingIndicator(),
                      // Stream-Indikator
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _buildStreamIndicator(),
                      ),
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

          // Statusbereich
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            child: Column(
              children: [
                if (_statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          _statusMessage!.contains('Fehler')
                              ? Icons.warning_amber_rounded
                              : _detectedDarts.isNotEmpty
                                  ? Icons.check_circle_rounded
                                  : Icons.radar_rounded,
                          size: 16,
                          color: _statusMessage!.contains('Fehler')
                              ? AppColors.accent
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
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (_isStreaming && !_isProcessing)
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

                // Dart-Chips
                if (_detectedDarts.isNotEmpty || _baselineCaptured)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_maxDarts, (i) {
                        final hasThrow = i < _detectedDarts.length;
                        final dart = hasThrow ? _detectedDarts[i] : null;
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          child: _buildDartChip(i + 1, dart),
                        );
                      }),
                    ),
                  ),

                // Buttons
                Row(
                  children: [
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
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _stopStream();
                          _showEditSheet(_detectedDarts);
                        },
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          _detectedDarts.isEmpty
                              ? 'Manuell eingeben'
                              : '${_detectedDarts.length} Pfeil(e) prüfen',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
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

  // ─────────────────────────────────────────────────────────
  //  HILFS-WIDGETS
  // ─────────────────────────────────────────────────────────

  Widget _buildStreamIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _isStreaming ? AppColors.primary : AppColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _isStreaming ? 'LIVE' : 'STOP',
            style: TextStyle(
              color: _isStreaming ? AppColors.primary : AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextPlayerBanner() {
    return Container(
      width: double.infinity,
      color: Colors.green.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.person_rounded, color: Colors.green, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nächster Spieler – Pfeile werfen!',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 400));
  }

  Widget _buildCalibrationHint() {
    return GestureDetector(
      onTap: _openCalibration,
      child: Container(
        width: double.infinity,
        color: Colors.orange.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Board kalibrieren für präzise Segmenterkennung',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.orange, size: 16),
          ],
        ),
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 400));
  }

  Widget _buildQualityWarning(String warning) {
    return Container(
      width: double.infinity,
      color: Colors.amber.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.amber, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(warning,
                style:
                    const TextStyle(color: Colors.amber, fontSize: 12)),
          ),
        ],
      ),
    );
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
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasThrow ? AppColors.primary : AppColors.border,
          width: hasThrow ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Text('Pfeil $number',
              style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500)),
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
            Text('${dart.score} Pkt.',
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
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
        isActive: _isStreaming,
        dartCount: _detectedDarts.length,
        hasCalibration: _detector.hasCalibration,
        calibration: _detector.calibration,
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              ),
              SizedBox(width: 8),
              Text('Analysiere...',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  OVERLAY PAINTER
// ─────────────────────────────────────────────────────────

class _BoardOverlayPainter extends CustomPainter {
  final bool isActive;
  final int dartCount;
  final bool hasCalibration;
  final BoardCalibration? calibration;

  const _BoardOverlayPainter({
    this.isActive = false,
    this.dartCount = 0,
    this.hasCalibration = false,
    this.calibration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final color = dartCount >= 3 ? Colors.greenAccent : AppColors.primary;

    if (hasCalibration && calibration != null) {
      // Board-Mittelpunkt und Radius aus Kalibrierung
      final cal = calibration!;
      final scaleX = size.width / cal.imageWidth;
      final scaleY = size.height / cal.imageHeight;
      final cx = cal.centerX * scaleX;
      final cy = cal.centerY * scaleY;
      final r = cal.radius * ((scaleX + scaleY) / 2);

      final paint = Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(Offset(cx, cy), r, paint);
      canvas.drawCircle(Offset(cx, cy), r * 0.65, paint..strokeWidth = 1);
      canvas.drawCircle(Offset(cx, cy), r * 0.13, paint);
      canvas.drawCircle(Offset(cx, cy), r * 0.05,
          Paint()..color = color.withValues(alpha: 0.4));
    } else {
      // Standard-Kreis-Overlay (keine Kalibrierung)
      final center = Offset(size.width / 2, size.height / 2);
      final radius = size.width * 0.35;

      final paint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, radius, paint);
      canvas.drawCircle(center, radius * 0.6, paint..strokeWidth = 1);

      final dashPaint = Paint()
        ..color = color.withValues(alpha: 0.2)
        ..strokeWidth = 1;

      canvas.drawLine(Offset(center.dx - radius, center.dy),
          Offset(center.dx + radius, center.dy), dashPaint);
      canvas.drawLine(Offset(center.dx, center.dy - radius),
          Offset(center.dx, center.dy + radius), dashPaint);
    }
  }

  @override
  bool shouldRepaint(_BoardOverlayPainter old) =>
      old.isActive != isActive ||
      old.dartCount != dartCount ||
      old.hasCalibration != hasCalibration;
}
