import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/dart_throw.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../services/detection_service.dart';
import '../services/local_detection_service.dart';
import '../services/roboflow_detection_service.dart';
import '../services/native_detection_service.dart';
import '../widgets/dart_edit_sheet.dart';
import 'board_calibration_screen.dart';

// Phasen des Kamera-Spielablaufs
enum _CameraPhase {
  waitingReference,
  detecting,
  review,
  removeDarts,
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  DetectionService _detector = LocalDetectionService();

  bool _isInitialized = false;
  bool _isStreaming = false;
  bool _isProcessing = false;
  bool _flashOn = false;

  _CameraPhase _phase = _CameraPhase.waitingReference;
  String? _statusMessage;
  List<DartThrow> _detectedDarts = [];
  List<ThrowPreview> _previews = [];
  RoundResult? _lastResult;
  int _zeroStreak = 0;
  int _frameCount = 0;

  static const int _maxDarts = 3;
  static const int _analyzeEveryNFrames = 15;
  static const int _maxZeroStreak = 40;

  Uint8List? _latestY;
  int _latestWidth = 0;
  int _latestHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDetectorAndCamera();
  }

  Future<void> _initDetectorAndCamera() async {
    await _initDetector();
    await _initCamera();
  }

  Future<void> _initDetector() async {
    final settings = context.read<SettingsProvider>();
    if (settings.useNativeAI) {
      _detector = NativeDetectionService();
    } else if (settings.useRoboflow) {
      _detector = RoboflowDetectionService(
        apiKey: settings.roboflowApiKey,
        modelEndpoint: settings.roboflowEndpoint,
      );
    } else {
      _detector = LocalDetectionService();
    }

    final cal = settings.boardCalibration;
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
          _statusMessage = null;
        });
        _startStream();
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Kamera-Fehler: $e');
    }
  }

  // ── STREAM ──────────────────────────────────────────────

  void _startStream() {
    if (!_isInitialized || _controller == null || _isStreaming) return;
    _frameCount = 0;

    _controller!.startImageStream((CameraImage frame) {
      if (!_isStreaming) return;
      final yPlane = frame.planes[0];
      final w = frame.width;
      final h = frame.height;
      final stride = yPlane.bytesPerRow;

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
      _phase = _CameraPhase.waitingReference;
      _statusMessage = 'Board ohne Pfeile zeigen, dann Referenz aufnehmen.';
    });
  }

  void _stopStream() {
    if (_controller != null && _isStreaming) {
      try { _controller!.stopImageStream(); } catch (_) {}
    }
    if (mounted) setState(() => _isStreaming = false);
  }

  // ── REFERENZ + ANALYSE ──────────────────────────────────

  void _captureReference() {
    if (_latestY == null) return;
    _detector.setReferenceFromYPlane(_latestY!, _latestWidth, _latestHeight);
    if (mounted) {
      setState(() {
        _phase = _CameraPhase.detecting;
        _zeroStreak = 0;
        _detectedDarts = [];
        _previews = [];
        _lastResult = null;
        _statusMessage = 'Bereit \u2013 Pfeil werfen!';
      });
    }
  }

  Future<void> _analyze() async {
    if (_phase != _CameraPhase.detecting || _latestY == null || _isProcessing) return;
    _isProcessing = true;
    try {
      final y = _latestY!;
      final w = _latestWidth;
      final h = _latestHeight;

      final motion = _detector.hasMotionInYPlane(y, w, h);
      if (!motion) {
        _zeroStreak++;
        if (_zeroStreak > _maxZeroStreak && _detectedDarts.isEmpty && mounted) {
          setState(() => _statusMessage = 'Warte auf Pfeil...');
          _zeroStreak = 0;
        }
        return;
      }

      _zeroStreak = 0;
      if (mounted) setState(() => _statusMessage = 'Pfeil erkannt...');

      final result = await _detector.detectFromYPlane(y, w, h);
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

        final gp = context.read<GameProvider>();
        final previews = gp.previewRound(result.darts);
        final hasBust = previews.any((p) => p.isBust);

        setState(() {
          _detectedDarts = result.darts;
          _previews = previews;
          if (hasBust) {
            _statusMessage = '\ud83d\udca5 Bust! Runde pr\u00fcfen & best\u00e4tigen.';
          } else {
            _statusMessage = newCount < _maxDarts
                ? '$newCount Pfeil erkannt \u2013 weiteren werfen...'
                : '$newCount Pfeile erkannt!';
          }
        });

        _detector.setReferenceFromYPlane(y, w, h);

        if (newCount >= _maxDarts || hasBust) {
          await Future.delayed(const Duration(milliseconds: 400));
          if (mounted) _showEditSheet();
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  // ── EDIT SHEET + COMMIT ──────────────────────────────────

  Future<void> _showEditSheet() async {
    if (!mounted) return;
    setState(() => _phase = _CameraPhase.review);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      builder: (_) => DartEditSheet(
        detectedDarts: _detectedDarts,
        onConfirm: (confirmed) => _commitRound(confirmed),
      ),
    );
  }

  Future<void> _commitRound(List<DartThrow> confirmed) async {
    final gp = context.read<GameProvider>();

    if (_latestY != null) {
      await _detector.submitCorrection(
        yPlane: _latestY!,
        width: _latestWidth,
        height: _latestHeight,
        detected: _detectedDarts,
        corrected: confirmed,
      );
    }

    final result = gp.submitRound(confirmed);

    if (mounted) {
      setState(() {
        _lastResult = result;
        _detectedDarts = [];
        _previews = [];

        if (result.gameOver) {
          _phase = _CameraPhase.removeDarts;
          _statusMessage = '\ud83c\udfc6 ${result.winnerName ?? "Spiel"} beendet!';
        } else {
          _phase = _CameraPhase.removeDarts;
          _statusMessage = null;
        }
      });
    }
  }

  void _prepareNextPlayer() {
    _detector.clearReference();
    setState(() {
      _phase = _CameraPhase.waitingReference;
      _detectedDarts = [];
      _previews = [];
      _lastResult = null;
      _statusMessage = 'Pfeile entfernt? Board zeigen & Referenz aufnehmen.';
    });
    if (!_isStreaming) _startStream();
  }

  // ── AKTIONEN ────────────────────────────────────────────

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
      await _initDetector();
      _prepareNextPlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed && _isInitialized) {
      if (!_isStreaming) _startStream();
    }
  }

  @override
  void dispose() {
    _stopStream();
    _controller?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── BUILD ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasCalibration = context.watch<SettingsProvider>().hasBoardCalibration;
    final gp = context.watch<GameProvider>();
    final game = gp.game;
    final isGameOver = game?.isGameOver ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(game != null ? game.gameType : 'Dart-Erkennung'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            _stopStream();
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: Stack(clipBehavior: Clip.none, children: [
              Icon(Icons.tune_rounded,
                  color: hasCalibration ? AppColors.primary : AppColors.textSecondary),
              if (!hasCalibration)
                Positioned(
                  right: -2, top: -2,
                  child: Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
                ),
            ]),
            tooltip: 'Board kalibrieren',
            onPressed: _openCalibration,
          ),
          if (_isInitialized)
            IconButton(
              icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off,
                  color: _flashOn ? AppColors.gold : AppColors.textSecondary),
              onPressed: _toggleFlash,
            ),
        ],
      ),
      body: Column(
        children: [
          // Game HUD
          if (game != null && !isGameOver) _buildGameHud(gp, game),

          // Kalibrierungshinweis
          if (!hasCalibration && _isInitialized)
            _buildCalibrationHint(),

          // Kamera
          Expanded(
            child: _isInitialized && _controller != null
                ? Stack(fit: StackFit.expand, children: [
                    CameraPreview(_controller!),
                    CustomPaint(
                      painter: _BoardOverlayPainter(
                        isActive: _phase == _CameraPhase.detecting,
                        dartCount: _detectedDarts.length,
                        calibration: _detector.calibration,
                      ),
                    ),
                    Positioned(top: 12, right: 12, child: _buildStreamBadge()),
                  ])
                : Center(
                    child: _statusMessage != null
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(_statusMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white)))
                        : const CircularProgressIndicator(color: AppColors.primary),
                  ),
          ),

          // Pfeile-entfernen-Banner
          if (_phase == _CameraPhase.removeDarts) _buildRemoveDartsBanner(gp, isGameOver),

          // Spiel vorbei Banner
          if (isGameOver) _buildGameOverBanner(game!),

          // Statusbereich + Buttons
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            child: Column(children: [
              // Status-Text
              if (_statusMessage != null && _phase != _CameraPhase.removeDarts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Icon(
                      _detectedDarts.isNotEmpty
                          ? Icons.check_circle_rounded : Icons.radar_rounded,
                      size: 16,
                      color: _previews.any((p) => p.isBust)
                          ? AppColors.accent
                          : _detectedDarts.isNotEmpty
                              ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_statusMessage!,
                      style: TextStyle(
                        color: _previews.any((p) => p.isBust)
                            ? AppColors.accent : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: _previews.any((p) => p.isBust)
                            ? FontWeight.w700 : FontWeight.normal,
                      ),
                    )),
                  ]),
                ),

              // Dart-Chips mit Regelvorschau
              if (_detectedDarts.isNotEmpty || _phase == _CameraPhase.detecting)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_maxDarts, (i) {
                      final dart = i < _detectedDarts.length ? _detectedDarts[i] : null;
                      final preview = i < _previews.length ? _previews[i] : null;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: _buildDartChip(i + 1, dart, preview),
                      );
                    }),
                  ),
                ),

              // Checkout-Vorschlag
              if (gp.checkoutSuggestion != null &&
                  _phase == _CameraPhase.detecting &&
                  _detectedDarts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.lightbulb_outline, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('Checkout: ${gp.checkoutSuggestion}',
                        style: const TextStyle(
                            color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                  ]),
                ),

              // Buttons
              _buildActionButtons(isGameOver),
            ]),
          ),
        ],
      ),
    );
  }

  // ── GAME HUD ────────────────────────────────────────────

  Widget _buildGameHud(GameProvider gp, game) {
    final player = game.currentPlayer;
    final isX01 = game.gameType == AppConstants.game501 ||
        game.gameType == AppConstants.game301 ||
        game.gameType == AppConstants.game701;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(player.name,
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        const SizedBox(width: 12),
        if (isX01)
          Text('${player.scoreRemaining}',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 28)),
        const Spacer(),
        if (isX01 && (game.legsToWin > 1 || game.setsToWin > 1))
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (game.setsToWin > 1)
              Text('Set ${game.currentSet}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            Text('Leg ${game.currentLeg}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
        IconButton(
          icon: const Icon(Icons.undo_rounded, size: 20),
          color: AppColors.textSecondary,
          onPressed: game.isGameOver ? null : gp.undoLastThrow,
          tooltip: 'R\u00fcckg\u00e4ngig',
        ),
      ]),
    );
  }

  // ── ACTION BUTTONS ──────────────────────────────────────

  Widget _buildActionButtons(bool isGameOver) {
    if (isGameOver) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () { _stopStream(); Navigator.pop(context); },
          icon: const Icon(Icons.home_rounded, size: 18),
          label: const Text('Zur\u00fcck zum Men\u00fc'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      );
    }

    switch (_phase) {
      case _CameraPhase.waitingReference:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isStreaming && _latestY != null ? _captureReference : null,
            icon: const Icon(Icons.camera_rounded, size: 18),
            label: const Text('Referenz aufnehmen (leeres Board)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        );

      case _CameraPhase.detecting:
        return Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                _detector.clearReference();
                setState(() {
                  _phase = _CameraPhase.waitingReference;
                  _detectedDarts = [];
                  _previews = [];
                  _statusMessage = 'Neue Referenz aufnehmen.';
                });
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Neustart'),
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
              onPressed: () => _showEditSheet(),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                _detectedDarts.isEmpty
                    ? 'Manuell eingeben'
                    : '${_detectedDarts.length} Pfeil(e) pr\u00fcfen',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]);

      case _CameraPhase.review:
        return const SizedBox.shrink();

      case _CameraPhase.removeDarts:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isStreaming && _latestY != null ? () {
              _captureReference();
            } : null,
            icon: const Icon(Icons.camera_rounded, size: 18),
            label: const Text('Pfeile entfernt \u2013 Referenz aufnehmen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        );
    }
  }

  // ── BANNER ──────────────────────────────────────────────

  Widget _buildRemoveDartsBanner(GameProvider gp, bool isGameOver) {
    final nextName = gp.currentPlayerName;
    return Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(children: [
        if (_lastResult?.message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_lastResult!.message!,
                style: const TextStyle(
                    color: AppColors.accentOrange, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        if (!isGameOver)
          Row(children: [
            const Icon(Icons.arrow_forward_rounded, color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('N\u00e4chster Spieler: $nextName \u2013 Pfeile entfernen!',
                  style: const TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ]),
      ]),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildGameOverBanner(game) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.primary.withValues(alpha: 0.15),
          AppColors.gold.withValues(alpha: 0.15),
        ]),
      ),
      child: Column(children: [
        const Text('\ud83c\udfc6 SPIEL BEENDET \ud83c\udfc6',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900,
                color: AppColors.gold, letterSpacing: 2)),
        if (game.winner != null) ...[
          const SizedBox(height: 4),
          Text('${game.winner!.name} gewinnt!',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ]),
    ).animate().fadeIn().slideY(begin: -0.1);
  }

  // ── HILFS-WIDGETS ───────────────────────────────────────

  Widget _buildStreamBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6,
          decoration: BoxDecoration(
            color: _phase == _CameraPhase.detecting ? AppColors.primary : AppColors.textMuted,
            shape: BoxShape.circle,
          )),
        const SizedBox(width: 4),
        Text(
          _phase == _CameraPhase.detecting ? 'LIVE' : 'PAUSE',
          style: TextStyle(
            color: _phase == _CameraPhase.detecting ? AppColors.primary : AppColors.textMuted,
            fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1,
          ),
        ),
      ]),
    );
  }

  Widget _buildCalibrationHint() {
    return GestureDetector(
      onTap: _openCalibration,
      child: Container(
        width: double.infinity,
        color: Colors.orange.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text('Board kalibrieren f\u00fcr Segmenterkennung',
              style: TextStyle(color: Colors.orange, fontSize: 12))),
          Icon(Icons.chevron_right_rounded, color: Colors.orange, size: 16),
        ]),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildDartChip(int number, DartThrow? dart, ThrowPreview? preview) {
    final has = dart != null;
    final isBust = preview?.isBust ?? false;
    final isNoScore = preview?.isNoScore ?? false;

    final chipColor = isBust ? AppColors.accent
        : isNoScore ? AppColors.accentOrange
        : AppColors.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: has ? chipColor.withValues(alpha: 0.15) : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: has ? chipColor : AppColors.border, width: has ? 1.5 : 1),
      ),
      child: Column(children: [
        Text('Pfeil $number',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(has ? _dartLabel(dart) : '\u2013',
            style: TextStyle(fontSize: 15, color: has ? chipColor : AppColors.textMuted,
                fontWeight: FontWeight.w700)),
        if (has && preview != null) ...[
          if (isBust)
            Text('BUST', style: TextStyle(fontSize: 9, color: chipColor, fontWeight: FontWeight.w800))
          else if (isNoScore)
            Text('Kein Score', style: TextStyle(fontSize: 9, color: chipColor, fontWeight: FontWeight.w800))
          else
            Text('${dart.score} Pkt.',
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ]),
    ).animate(target: has ? 1 : 0).scaleXY(begin: 0.9, end: 1.0, curve: Curves.elasticOut);
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

// ── OVERLAY PAINTER ───────────────────────────────────────

class _BoardOverlayPainter extends CustomPainter {
  final bool isActive;
  final int dartCount;
  final BoardCalibration? calibration;

  const _BoardOverlayPainter({this.isActive = false, this.dartCount = 0, this.calibration});

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

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(cal.rotation);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), paint);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: rx * 1.3, height: ry * 1.3),
          paint..strokeWidth = 1);
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: rx * 0.26, height: ry * 0.26), paint);
      canvas.restore();
      canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = color.withValues(alpha: 0.8));
    } else {
      final c = Offset(size.width / 2, size.height / 2);
      final r = size.width * 0.35;
      canvas.drawCircle(c, r, paint);
      canvas.drawCircle(c, r * 0.6, paint..strokeWidth = 1);
      final d = Paint()..color = color.withValues(alpha: 0.2)..strokeWidth = 1;
      canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), d);
      canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), d);
    }
  }

  @override
  bool shouldRepaint(_BoardOverlayPainter old) =>
      old.isActive != isActive || old.dartCount != dartCount || old.calibration != calibration;
}


