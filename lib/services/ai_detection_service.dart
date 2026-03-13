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

  /// Analysiert die Bildqualität (Helligkeit, Unschärfe) ohne API-Aufruf.
  Future<ImageQuality> analyzeQuality(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return const ImageQuality();

      // Helligkeit berechnen (jedes 10. Pixel für Geschwindigkeit)
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

      // Unschärfe: geringe Kontrastabweichung = unscharf
      final variance = (count > 0 ? totalSqLum / count : 0) - avgLum * avgLum;
      final isBlurry = variance < 200; // niedrige Varianz = wenig Kanten/Details

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

    // Qualität vorab prüfen
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
        // Mit Kalibrierungsbild: Vergleichsprompt
        parts.add(TextPart(AppConstants.calibrationPromptPrefix));
        parts.add(DataPart('image/jpeg', referenceImageBytes));
        parts.add(TextPart(AppConstants.calibrationPromptSuffix));
        parts.add(DataPart('image/jpeg', imageBytes));
      } else {
        // Ohne Kalibrierungsbild: Standard-Prompt
        parts.add(TextPart(AppConstants.detectionPrompt));
        parts.add(DataPart('image/jpeg', imageBytes));
      }

      final content = Content.multi(parts);
      final response = await _model!.generateContent([content]);
      final text = response.text;

      if (text == null || text.isEmpty) {
        return DetectionResult(
          darts: [],
          error: 'Keine Antwort von der KI erhalten.',
          quality: quality,
        );
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
            'Tageslimit erreicht. Morgen wieder verfügbar (1.500 Anfragen/Tag kostenlos).';
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
        final segment = dartMap['segment'] as int;
        final ringStr = dartMap['ring'] as String;
        final confidence = (dartMap['confidence'] as num?)?.toDouble() ?? 0.5;
        return DartThrow(
          segment: segment,
          ring: RingType.fromString(ringStr),
          confidence: confidence,
        );
      }).toList();

      return DetectionResult(darts: darts, boardDetected: boardDetected);
    } catch (e) {
      return DetectionResult(
          darts: [], error: 'Fehler beim Parsen der KI-Antwort: $e');
    }
  }
}