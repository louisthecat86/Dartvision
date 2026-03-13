import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../config/constants.dart';
import '../models/dart_throw.dart';

class DetectionResult {
  final List<DartThrow> darts;
  final bool boardDetected;
  final String? error;

  DetectionResult({
    required this.darts,
    this.boardDetected = false,
    this.error,
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

  Future<DetectionResult> detectDarts(Uint8List imageBytes) async {
    if (_model == null) {
      return DetectionResult(
        darts: [],
        error: 'AI nicht konfiguriert. Bitte Gemini API-Key eingeben.',
      );
    }

    try {
      final content = Content.multi([
        TextPart(AppConstants.detectionPrompt),
        DataPart('image/jpeg', imageBytes),
      ]);

      final response = await _model!.generateContent([content]);
      final text = response.text;

      if (text == null || text.isEmpty) {
        return DetectionResult(
          darts: [],
          error: 'Keine Antwort von der KI erhalten.',
        );
      }

      return _parseResponse(text);
    } catch (e) {
      return DetectionResult(
        darts: [],
        error: 'KI-Fehler: ${e.toString().substring(0, (e.toString().length).clamp(0, 100))}',
      );
    }
  }

  DetectionResult _parseResponse(String text) {
    try {
      // Clean up response - remove markdown code blocks if present
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
        final confidence =
            (dartMap['confidence'] as num?)?.toDouble() ?? 0.5;

        return DartThrow(
          segment: segment,
          ring: RingType.fromString(ringStr),
          confidence: confidence,
        );
      }).toList();

      return DetectionResult(
        darts: darts,
        boardDetected: boardDetected,
      );
    } catch (e) {
      return DetectionResult(
        darts: [],
        error: 'Fehler beim Parsen der KI-Antwort: $e',
      );
    }
  }
}
