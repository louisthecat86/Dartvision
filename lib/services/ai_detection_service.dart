import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image/image.dart' as img;
import '../config/constants.dart';
import '../models/dart_throw.dart';

class ImageQuality {
  final bool isDark;
  final bool isBright;
  final bool isBlurry;
  final String? warning;
  final double luminance;

  const ImageQuality({
    this.isDark = false,
    this.isBright = false,
    this.isBlurry = false,
    this.warning,
    this.luminance = 128,
  });

  bool get isOk => !isDark && !isBright && !isBlurry;
}

class DetectionResult {
  final List<DartThrow> darts;
  final bool boardDetected;
  final String? error;
  final ImageQuality? quality;

  DetectionResult({
    required this.darts,
    this.boardDetected = false,
    this.error,
    this.quality,
  });

  bool get hasError => error != null;
  bool get hasDarts => darts.isNotEmpty;
}

class AiDetectionService {
  GenerativeModel? _model;
  String? _apiKey;

  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  void configure(String apiKey) {
    _apiKey = apiKey;
    _model = GenerativeModel(
      model: AppConstants.geminiModel,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1,
        topP: 0.95,
        maxOutputTokens: 1024,
        responseMimeType: 'application/json',
      ),
    );
  }

  /// Prüft ob sich das Bild gegenüber dem Referenzbild merklich verändert hat.
  /// Gibt true zurück wenn eine Veränderung erkannt wurde (neuer Pfeil).
  /// Wird OHNE API-Aufruf durchgeführt — spart Kontingent.
  Future<bool> hasImageChanged(
    Uint8List newBytes,
    Uint8List baselineBytes,
  ) async {
    try {
      final newImg = img.decodeImage(newBytes);
      final baseImg = img.decodeImage(baselineBytes);
      if (newImg == null || baseImg == null) return true;

      // Auf gemeinsame kleine Größe skalieren für schnellen Vergleich
      const sampleSize = 80;
      final resNew = img.copyResize(newImg,
          width: sampleSize,
          height: sampleSize,
          interpolation: img.Interpolation.average);
      final resBase = img.copyResize(baseImg,
          width: sampleSize,
          height: sampleSize,
          interpolation: img.Interpolation.average);

      double totalDiff = 0;
      double centerDiff = 0; // Mitte stärker gewichten (da Scheibe dort ist)
      int count = 0;
      int centerCount = 0;

      for (int y = 0; y < sampleSize; y++) {
        for (int x = 0; x < sampleSize; x++) {
          final p1 = resNew.getPixel(x, y);
          final p2 = resBase.getPixel(x, y);
          final lum1 = 0.299 * p1.r.toDouble() +
              0.587 * p1.g.toDouble() +
              0.114 * p1.b.toDouble();
          final lum2 = 0.299 * p2.r.toDouble() +
              0.587 * p2.g.toDouble() +
              0.114 * p2.b.toDouble();
          final diff = (lum1 - lum2).abs();
          totalDiff += diff;
          count++;

          // Mittlere 40% stärker auswerten (Scheibenbereich)
          final cx = (x - sampleSize / 2).abs();
          final cy = (y - sampleSize / 2).abs();
          if (cx < sampleSize * 0.2 && cy < sampleSize * 0.2) {
            centerDiff += diff;
            centerCount++;
          }
        }
      }

      final avgDiff = count > 0 ? totalDiff / count : 0;
      final avgCenterDiff = centerCount > 0 ? centerDiff / centerCount : 0;

      // Änderung erkannt wenn: Gesamtdiff > 6 ODER Mitte-Diff > 10
      return avgDiff > 6.0 || avgCenterDiff > 10.0;
    } catch (_) {
      return true; // Im Fehlerfall lieber analysieren
    }
  }

  /// Analysiert Bildqualität ohne API-Aufruf.
  Future<ImageQuality> analyzeQuality(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return const ImageQuality();

      double totalLum = 0;
      double totalSqLum = 0;
      int count = 0;

      for (int y = 0; y < decoded.height; y += 10) {
        for (int x = 0; x < decoded.width; x += 10) {
          final pixel = decoded.getPixel(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();
          final lum = 0.299 * r + 0.587 * g + 0.114 * b;
          totalLum += lum;
          totalSqLum += lum * lum;
          count++;
        }
      }

      final avgLum = count > 0 ? totalLum / count : 128;
      final variance =
          (count > 0 ? totalSqLum / count : 0) - avgLum * avgLum;
      final isBlurry = variance < 200;
      final isDark = avgLum < 45;
      final isBright = avgLum > 215;

      String? warning;
      if (isDark) {
        warning = 'Bild zu dunkel – Blitz aktivieren oder mehr Licht';
      } else if (isBright) {
        warning = 'Bild überbelichtet – weniger direktes Licht';
      } else if (isBlurry) {
        warning = 'Bild unscharf – Kamera ruhig halten';
      }

      return ImageQuality(
        isDark: isDark,
        isBright: isBright,
        isBlurry: isBlurry,
        warning: warning,
        luminance: avgLum,
      );
    } catch (_) {
      return const ImageQuality();
    }
  }

  Future<DetectionResult> detectDarts(
    Uint8List imageBytes, {
    Uint8List? referenceImageBytes,
  }) async {
    if (_model == null) {
      return DetectionResult(
        darts: [],
        error: 'KI nicht konfiguriert. Bitte Gemini API-Key eingeben.',
      );
    }

    final quality = await analyzeQuality(imageBytes);
    if (quality.isDark || quality.isBlurry) {
      return DetectionResult(
        darts: [],
        error: quality.warning,
        quality: quality,
      );
    }

    try {
      final List<Part> parts = [];
      if (referenceImageBytes != null) {
        parts.add(TextPart(AppConstants.calibrationPromptPrefix));
        parts.add(DataPart('image/jpeg', referenceImageBytes));
        parts.add(TextPart(AppConstants.calibrationPromptSuffix));
        parts.add(DataPart('image/jpeg', imageBytes));
      } else {
        parts.add(TextPart(AppConstants.detectionPrompt));
        parts.add(DataPart('image/jpeg', imageBytes));
      }

      final content = Content.multi(parts);
      final response = await _model!.generateContent([content]);
      final text = response.text;

      if (text == null || text.isEmpty) {
        return DetectionResult(
            darts: [], error: 'Keine Antwort von der KI.', quality: quality);
      }

      final result = _parseResponse(text);
      return DetectionResult(
        darts: result.darts,
        boardDetected: result.boardDetected,
        error: result.error,
        quality: quality,
      );
    } catch (e) {
      final msg = e.toString();
      String userMsg;
      if (msg.contains('quota') || msg.contains('RESOURCE_EXHAUSTED')) {
        userMsg =
            'Tageslimit erreicht (1.500/Tag kostenlos). Morgen wieder verfügbar.';
      } else if (msg.contains('API_KEY') || msg.contains('invalid')) {
        userMsg = 'Ungültiger API-Key. Bitte in den Einstellungen prüfen.';
      } else {
        userMsg =
            'KI-Fehler: ${msg.substring(0, msg.length.clamp(0, 100))}';
      }
      return DetectionResult(darts: [], error: userMsg, quality: quality);
    }
  }

  DetectionResult _parseResponse(String text) {
    try {
      String cleaned = text.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '');
        cleaned = cleaned.replaceAll(RegExp(r'\n?```$'), '');
      }
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final boardDetected = json['board_detected'] as bool? ?? false;
      final dartsJson = json['darts'] as List<dynamic>? ?? [];
      final darts = dartsJson.map((d) {
        final dartMap = d as Map<String, dynamic>;
        return DartThrow(
          segment: dartMap['segment'] as int,
          ring: RingType.fromString(dartMap['ring'] as String),
          confidence:
              (dartMap['confidence'] as num?)?.toDouble() ?? 0.5,
        );
      }).toList();
      return DetectionResult(darts: darts, boardDetected: boardDetected);
    } catch (e) {
      return DetectionResult(
          darts: [], error: 'Fehler beim Parsen der KI-Antwort: $e');
    }
  }
}