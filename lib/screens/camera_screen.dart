import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../config/constants.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
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

  bool _isLiveDetecting = false;
  Timer? _detectionTimer;
  List<DartThrow> _detectedDarts = [];
  int _analysisCount = 0;
  int _zeroDetectionStreak = 0;

  Uint8List? _baselineImageBytes;
  bool _baselineReady = false;
  Uint8List? _cachedCalibrationBytes;

  // Verbesserung 3: Nächster-Spieler-Banner
  bool _showNextPlayerBanner = false;
  String _nextPlayerName = '';

  static const int _maxDarts = 3;
  static const int _maxZeroStreakBeforeFallback = 4;
  static const Duration _detectionInterval = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _initCamera();
    final apiKey = context.read<SettingsProvider>().apiKey;
    _aiService.configure(apiKey);
    _loadCalibrationImage();
  }

  Future<void> _loadCalibrationImage() async {
    final settings = context.read<SettingsProvider>();
    if (settings.hasCalibrationImage) {
      _cachedCalibrationBytes = await settings.getCalibrationImageBytes();
    }
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
      _analysisCount = 0;
      _zeroDetectionStreak = 0;
      _baselineReady = false;
      _baselineImageBytes = null;
      _qualityWarning = null;
      _showNextPlayerBanner = false;
      _statusMessage = 'Warte auf Pfeile...';
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isLiveDetecting && !_isProcessing) {
        _captureBaseline();
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
    if (mounted) setState(() => _isLiveDetecting = false);
  }

  Future<void> _captureBaseline() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final file = await _controller!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      await File(file.path).delete().catchError((_) => File(file.path));
      if (mounted) {
        setState(() {
          _baselineImageBytes = bytes;
          _baselineReady = true;
          _statusMessage = 'Bereit – Pfeile werfen...';
        });
      }
    } catch (_) {}
  }

  Future<void> _captureAndAnalyze() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isProcessing) return;

    try {
      final file = await _controller!.takePicture();
      final bytes = await File(file.path).readAsBytes();
      await File(file.path).delete().catchError((_) => File(file.path));

      // Qualitätsprüfung
      final quality = await _aiService.analyzeQuality(bytes);
      if (mounted) setState(() => _qualityWarning = quality.warning);
      if (quality.isDark || quality.isBlurry) return;

      // Verbesserung 1: Bildvergleich — API nur bei Veränderung aufrufen
      if (_baselineReady && _baselineImageBytes != null) {
        final changed =
            await _aiService.hasImageChanged(bytes, _baselineImageBytes!);
        if (!changed) {
          if (mounted) {
            setState(() => _statusMessage = _detectedDarts.isEmpty
                ? 'Bereit – Pfeile werfen...'
                : '${_detectedDarts.length} Pfeil(e) – weiteren werfen...');
          }
          return; // Kein API-Aufruf — Kontingent gespart
        }
      }

      setState(() => _isProcessing = true);

      final result = await _aiService.detectDarts(
        bytes,
        referenceImageBytes: _cachedCalibrationBytes,
      );

      if (!mounted) return;

      if (result.quality?.warning != null) {
        setState(() => _qualityWarning = result.quality!.warning);
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

      if (newCount > 0) {
        final isNew = newCount > _detectedDarts.length;
        _zeroDetectionStreak = 0;

        setState(() {
          _detectedDarts = result.darts;
          if (newCount == 1) {
            _statusMessage = '1 Pfeil erkannt – weiter werfen...';
          } else if (newCount < _maxDarts) {
            _statusMessage = '$newCount Pfeile erkannt – weiter werfen...';
          } else {
            _statusMessage = '$newCount Pfeile erkannt!';
          }
        });

        // Verbesserung 5: Vibration bei neu erkanntem Pfeil
        if (isNew) {
          final settings = context.read<SettingsProvider>();
          if (settings.vibrationEnabled) {
            final hasVib = await Vibration.hasVibrator() ?? false;
            if (hasVib) Vibration.vibrate(duration: 80);
          }
        }

        _baselineImageBytes = bytes;

        if (newCount >= _maxDarts && _isLiveDetecting) {
          _stopLiveDetection();
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) await _showEditSheet(_detectedDarts);
        }
      } else {
        _zeroDetectionStreak++;
        setState(() => _statusMessage = 'Kein Pfeil erkannt – Pfeil werfen...');

        // Verbesserung 4: Fallback nach mehrfach nichts erkannt
        if (_zeroDetectionStreak >= _maxZeroStreakBeforeFallback &&
            _analysisCount >= _maxZeroStreakBeforeFallback) {
          _stopLiveDetection();
          if (mounted) _showManualFallbackDialog();
        }
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

  void _showManualFallbackDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Pfeile nicht erkannt',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Die KI konnte nach mehreren Versuchen keine Pfeile erkennen.\n\n'
          'Mögliche Ursachen:\n'
          '• Zu wenig Kontrast / Beleuchtung\n'
          '• Kamera zu weit entfernt\n'
          '• Tageslimit erreicht\n\n'
          'Möchtest du die Würfe manuell eingeben?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startLiveDetection();
            },
            child: const Text('Nochmal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showEditSheet([]);
            },
            child: const Text('Manuell eingeben'),
          ),
        ],
      ),
    );
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
      _analysisCount = 0;
      _zeroDetectionStreak = 0;
      _qualityWarning = null;
      _baselineReady = false;
      _baselineImageBytes = null;
      _showNextPlayerBanner = false;
    });
    _startLiveDetection();
  }

  Future<void> _openCalibration() async {
    _stopLiveDetection();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CalibrationScreen()),
    );
    if (mounted) {
      await _loadCalibrationImage();
      _startLiveDetection();
    }
  }

  @override
  void dispose() {
    _stopLiveDetection();
    _controller?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────

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
                ? 'Kalibrierung neu einlesen'
                : 'Scheibe kalibrieren (empfohlen)',
            onPressed: _openCalibration,
          ),
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
          // Verbesserung 3: Nächster-Spieler-Banner
          if (_showNextPlayerBanner) _buildNextPlayerBanner(),

          // Kalibrierungs-Hinweis
          if (!hasCalibration && _isInitialized && !_showNextPlayerBanner)
            _buildCalibrationHint(),

          // Qualitätswarnung
          if (_qualityWarning != null) _buildQualityWarning(_qualityWarning!),

          // Kamera
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
                                style:
                                    const TextStyle(color: Colors.white)),
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

  // ─────────────────────────────────────────────────────────
  //  HILFS-WIDGETS
  // ─────────────────────────────────────────────────────────

  Widget _buildNextPlayerBanner() {
    return Container(
      width: double.infinity,
      color: Colors.green.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.person_rounded, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _nextPlayerName.isNotEmpty
                  ? 'Jetzt: $_nextPlayerName – Pfeile werfen!'
                  : 'Nächster Spieler – Pfeile werfen!',
              style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
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
            Icon(Icons.info_outline_rounded,
                color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Für bessere Erkennung: Scheibe einmalig kalibrieren',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
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
      color: (isDark ? Colors.blue : Colors.amber)
          .withValues(alpha: 0.15),
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
            : AppColors.surfaceLight,
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
                fontWeight: FontWeight.w500),
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
                  fontSize: 10, color: AppColors.textSecondary),
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
            Text('KI analysiert...',
                style: TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // Verbesserung 3: Kamera bleibt offen — automatisch für nächsten Spieler neu starten
  Future<void> _showEditSheet(List<DartThrow> detected) async {
    if (!mounted) return;
    String? confirmedPlayerName;

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

    // Sheet geschlossen (egal ob bestätigt oder abgebrochen)
    // → Kamera bleibt offen, automatisch für nächsten Spieler neu starten
    if (mounted && _isInitialized) {
      setState(() {
        _showNextPlayerBanner = true;
        _nextPlayerName = confirmedPlayerName ?? '';
      });
      // Kurze Pause damit Banner sichtbar ist, dann neu starten
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) _resetDetection();
    }
  }
}

// ─────────────────────────────────────────────────────────
//  OVERLAY PAINTER
// ─────────────────────────────────────────────────────────

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

    final color = dartCount >= 3 ? Colors.greenAccent : AppColors.primary;

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

  @override
  bool shouldRepaint(_BoardOverlayPainter old) =>
      old.isActive != isActive || old.dartCount != dartCount;
}