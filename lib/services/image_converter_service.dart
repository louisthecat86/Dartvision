import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Konvertiert YUV420 Y-Plane zu JPEG für Roboflow API
class ImageConverterService {
  /// Y-Plane (Grauwerte) → grayscale Image → JPEG
  static Uint8List yPlaneToJpeg(
    Uint8List yPlane,
    int width,
    int height, {
    int quality = 75,
  }) {
    try {
      // 1. Grayscale Image aus Y-Plane erstellen
      final image = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final idx = y * width + x;
          if (idx >= yPlane.length) continue;

          final grayValue = yPlane[idx];
          // RGBA: Grau auf allen Kanälen
          image.setPixelRgba(x, y, grayValue, grayValue, grayValue, 255);
        }
      }

      // 2. Image zu JPEG komprimieren
      final jpegData = img.encodeJpg(image, quality: quality);
      return Uint8List.fromList(jpegData);
    } catch (e) {
      throw Exception('Y-Plane zu JPEG Konvertierung fehlgeschlagen: $e');
    }
  }

  /// Alternative: Direkte RGB-Konvertierung (falls später YUV420 komplett vorhanden)
  static Uint8List yuv420ToJpeg(
    Uint8List yuvData,
    int width,
    int height, {
    int quality = 75,
  }) {
    try {
      final image = img.Image(width: width, height: height);
      final uvPixelStride = 1;

      final uvWidth = width ~/ 2;
      final uvHeight = height ~/ 2;
      final yPlaneSize = width * height;
      final uvPlaneSize = uvWidth * uvHeight;
      final uvOffset = yPlaneSize;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yIdx = y * width + x;
          final yVal = yuvData[yIdx];

          final uvX = x ~/ 2;
          final uvY = y ~/ 2;
          final uvIdx = uvOffset + (uvY * uvWidth + uvX);
          final uVal = yuvData[uvIdx];
          final vVal = yuvData[uvOffset + uvPlaneSize + uvIdx - uvOffset];

          // YUV 420 → RGB
          final r = (yVal + 1.402 * (vVal - 128)).clamp(0, 255).toInt();
          final g =
              (yVal - 0.34414 * (uVal - 128) - 0.71414 * (vVal - 128))
                  .clamp(0, 255)
                  .toInt();
          final b = (yVal + 1.772 * (uVal - 128)).clamp(0, 255).toInt();

          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return Uint8List.fromList(img.encodeJpg(image, quality: quality));
    } catch (e) {
      throw Exception('YUV420 zu JPEG Konvertierung fehlgeschlagen: $e');
    }
  }
}
