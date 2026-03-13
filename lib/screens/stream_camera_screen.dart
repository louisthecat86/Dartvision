import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../config/theme.dart';
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
  bool _baselineCaptured = false;
  bool _showNextPlayerBanner = false;

  String? _statusMessage;
  List<DartThrow> _detectedDarts = [];
  int _zeroStreak = 0;
  int _frameCount = 0;

  static const int _maxDarts = 3;
  static const int _analyzeEveryNFrames = 15; // ~500ms bei 30fps
  static const int _maxZeroStreak = 40;

  // Letzter Y-Plane-Frame (direkt aus Stream, kein JPEG-Decode)
  Uint8List? _latestY;
  int _latestWidth = 0;
  int _latestHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCalibration();
    _initCamera();
  }

  Future<void> _loadCalibration() async {
    final cal = context.read<SettingsProvider>().boardCalibration;
    if (cal != null) _detector.setCalibration(cal);
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
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _statusMessage = 'Kamera bereit';
        });
        _startStream();
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Kamera-Fehler: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  //  STREAM — kein JPEG, rohe Y-Plane-Bytes (kein Freeze!)
  // ─────────────────────────────────────────────────────────

  void _startStream() {
    if (!_isInitialized || _controller == null || _isStreaming) return;
    _frameCount = 0;

    _controller!.startImageStream((CameraImage frame) {
      if (!_isStreaming) return;
      // Y-Plane extrahieren (Grauwerte, immer planes[0] bei YUV420 + NV21)
      final yPlane = frame.planes[0];
      final w = frame.width;
      final h = frame.height;
      final stride = yPlane.bytesPerRow;

      // Padding entfernen falls stride != width
      if (stride == w) {
        _latestY = yPlane.bytes;
      } else {
        final clean = Uint8List(w * h);
        for (int row = 0; row < h; row++) {
          final src = row * stride;
          final dst = row * w;
          final end = dst + w;
          if (src + w <= yPlane.bytes.length) {
            clean.setRange(dst, end, yPlane.bytes, src);
          }
        }
        _latestY = clean;
      }
      _latestWidth = w;
      _latestHeight = h;

      _frameCount++;
      if (_frameCount % _analyzeEveryNFrames == 0 && !_isProcessing) {
        _analyze();
      }
    });

    setState(() {
      _isStreaming = true;
      _statusMessage = 'Referenzframe aufnehmen...';
    });

    // Referenz nach 1 Sekunde aufnehmen (Board leer, keine Pfeile)
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _isStreaming) _captureReference();
    });
  }

  void _stopStream() {
    if (_controller != null && _isStreaming) {
      try { _controller!.stopImageStream(); } catch (_) {}
    }
    if (mounted) setState(() => _isStreaming = false);
  }

  // ─────────────────────────────────────────────────────────
  //  REFERENZ + ANALYSE
  // ─────────────────────────────────────────────────────────

  void _captureReference() {
    if (_latestY == null) return;
    _detector.setReferenceFromYPlane(_latestY!, _latestWidth, _latestHeight);
    if (mounted) {
      setState(() {
        _baselineCaptured = true;
        _zeroStreak = 0;
        _detectedDarts = [];
        _statusMessage = 'Bereit – Pfeil werfen!';
      });
    }
  }

  Future<void> _analyze() async {
    if (!_baselineCaptured || _latestY == null || _isProcessing) return;

    _isProcessing = true;
    try {
      final y = _latestY!;
      final w = _latestWidth;
      final h = _latestHeight;

      // Schritt 1: Schneller Bewegungscheck (direkter Byte-Vergleich)
      final motion = _detector.hasMotionInYPlane(y, w, h);

      if (!motion) {
        _zeroStreak++;
        if (_zeroStreak > _maxZeroStreak && _detectedDarts.isEmpty && mounted) {
          setState(() => _statusMessage = 'Warte auf Pfeil...');
          _zeroStreak = 0;
        }
        return;
      }

      // Schritt 2: Bewegung erkannt → Position analysieren
      _zeroStreak = 0;
      if (mounted) setState(() => _statusMessage = 'Pfeil erkannt...');

      final result = _detector.detectFromYPlane(y, w, h);

      if (!mounted) return;
      if (result.hasError) {
        setState(() => _statusMessage = result.error);
        return;
      }
      if (result.darts.isEmpty) return;

      final newCount = result.darts.length;
      if (newCount > _detectedDarts.length) {
        final settings = context.read<SettingsProvider>();
        if (settings.vibrationEnabled) {
          final hasVib = await Vibration.hasVibrator();
          if (hasVib == true) Vibration.vibrate(duration: 80);
        }

        setState(() {
          _detectedDarts = result.darts;
          _statusMessage = newCount < _maxDarts
              ? '$newCount Pfeil erkannt – weiteren werfen...'
              : '$newCount Pfeile erkannt!';
        });

        // Referenz mit neuem Pfeil aktualisieren
        _detector.setReferenceFromYPlane(y, w, h);

        if (newCount >= _maxDarts) {
          _stopStream();
          await Future.delayed(const Duration(milliseconds: 400));
          if (mounted) await _showEditSheet(_detectedDarts);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  // ─────────────────────────────────────────────────────────
  //  AKTIONEN
  // ─────────────────────────────────────────────────────────

  void _resetDetection() {
    setState(() {
      _detectedDarts = [];
      _zeroStreak = 0;
      _baselineCaptured = false;
      _showNextPlayerBanner = false;
      _statusMessage = 'Referenzframe aufnehmen...';
    });
    _detector.clearReference();
    if (!_isStreaming) _startStream();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _isStreaming) _captureReference();
    });
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    try {
      _flashOn = !_flashOn;
      await _controller!.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
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
          maxHeight: MediaQuery.of(context).size.height * 0.85),
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed && _isInitialized) {
      _resetDetection();
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
    final hasCalibration =
        context.watch<SettingsProvider>().hasBoardCalibration;

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
                Icon(Icons.tune_rounded,
                    color: hasCalibration
                        ? AppColors.primary
                        : AppColors.textSecondary),
                if (!hasCalibration)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: Colors.orange, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            tooltip: 'Board kalibrieren',
            onPressed: _openCalibration,
          ),
          if (_isInitialized)
            IconButton(
              icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off,
                  color:
                      _flashOn ? AppColors.gold : AppColors.textSecondary),
              onPressed: _toggleFlash,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_showNextPlayerBanner) _buildNextPlayerBanner(),
          if (!hasCalibration && _isInitialized && !_showNextPlayerBanner)
            _buildCalibrationHint(),

          // Kamera-Preview (kein Freeze — Stream läuft immer)
          Expanded(
            child: _isInitialized && _controller != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
                      CustomPaint(
                        painter: _BoardOverlayPainter(
                          isActive: _isStreaming,
                          dartCount: _detectedDarts.length,
                          calibration: _detector.calibration,
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _buildStreamBadge(),
                      ),
                    ],
                  )
                : Center(
                    child: _statusMessage != null
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(_statusMessage!,
                                textAlign: TextAlign.center,
                                style:
                                    const TextStyle(color: Colors.white)))
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
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                      ],
                    ),
                  ),

                if (_detectedDarts.isNotEmpty || _baselineCaptured)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_maxDarts, (i) {
                        final dart =
                            i < _detectedDarts.length ? _detectedDarts[i] : null;
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          child: _buildDartChip(i + 1, dart),
                        );
                      }),
                    ),
                  ),

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

  // ─────────────────────────────────────────────────────────
  //  HILFS-WIDGETS
  // ─────────────────────────────────────────────────────────

  Widget _buildStreamBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
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
            child: Text('Nächster Spieler – Pfeile werfen!',
                style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
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
                'Board kalibrieren für Segmenterkennung (auch bei Schrägansicht)',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.orange, size: 16),
          ],
        ),
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 400));
  }

  Widget _buildDartChip(int number, DartThrow? dart) {
    final has = dart != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: has
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: has ? AppColors.primary : AppColors.border,
            width: has ? 1.5 : 1),
      ),
      child: Column(children: [
        Text('Pfeil $number',
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(
          has ? _dartLabel(dart) : '–',
          style: TextStyle(
              fontSize: 16,
              color: has ? AppColors.primary : AppColors.textMuted,
              fontWeight: FontWeight.w700),
        ),
        if (has)
          Text('${dart.score} Pkt.',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
      ]),
    ).animate(target: has ? 1 : 0).scaleXY(
          begin: 0.9, end: 1.0, curve: Curves.elasticOut);
  }

  String _dartLabel(DartThrow dart) {
    if (dart.ring == RingType.innerBull) return 'Bull';
    if (dart.ring == RingType.outerBull) return '25';
    if (dart.ring == RingType.double_) return 'D${dart.segment}';
    if (dart.ring == RingType.triple) return 'T${dart.segment}';
    if (dart.ring == RingType.miss) return '?';
    return '${dart.segment}';
  }
}

// ─────────────────────────────────────────────────────────
//  OVERLAY PAINTER
// ─────────────────────────────────────────────────────────

class _BoardOverlayPainter extends CustomPainter {
  final bool isActive;
  final int dartCount;
  final BoardCalibration? calibration;

  const _BoardOverlayPainter({
    this.isActive = false,
    this.dartCount = 0,
    this.calibration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final color = dartCount >= 3 ? Colors.greenAccent : AppColors.primary;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (calibration != null) {
      final cal = calibration!;
      final sx = size.width / cal.imageWidth;
      final sy = size.height / cal.imageHeight;
      final cx = cal.centerX * sx;
      final cy = cal.centerY * sy;
      final rx = cal.radiusX * sx;
      final ry = cal.radiusY * sy;

      // Ellipse für schräge Ansicht
      final rect = Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);
      canvas.drawOval(rect, paint);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: rx * 1.3, height: ry * 1.3),
          paint..strokeWidth = 1);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: rx * 0.26, height: ry * 0.26),
          paint);
      // Mittelpunkt
      canvas.drawCircle(Offset(cx, cy), 3,
          Paint()..color = color.withValues(alpha: 0.8));
    } else {
      final center = Offset(size.width / 2, size.height / 2);
      final r = size.width * 0.35;
      canvas.drawCircle(center, r, paint);
      canvas.drawCircle(center, r * 0.6, paint..strokeWidth = 1);
      final d = Paint()
        ..color = color.withValues(alpha: 0.2)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(center.dx - r, center.dy),
          Offset(center.dx + r, center.dy), d);
      canvas.drawLine(Offset(center.dx, center.dy - r),
          Offset(center.dx, center.dy + r), d);
    }
  }

  @override
  bool shouldRepaint(_BoardOverlayPainter old) =>
      old.isActive != isActive ||
      old.dartCount != dartCount ||
      old.calibration != calibration;
}
