# 🎯 Dartvision YOLO/Roboflow Integration - Setup Guide

## Quick Start

### 1. Roboflow Model vorbereiten (auf roboflow.com)

```
1. Gehe zu: roboflow.com/universe
2. Suche: "dart" oder "dartboard detection"
3. Klick auf ein Modell → "Clone"
4. Wähle dein Workspace
```

### 2. API Credentials kopieren

**API Endpoint URL:**
- Gehe zu deinem geklonten Modell → "Deploy" oder "API"
- Kopiere die komplette URL (sieht so aus)
```
https://api.roboflow.com/v2/workspace/[WORKSPACE_ID]/projects/[PROJECT_ID]/versions/[VERSION]/detect?api_key=...
```

**API Key:**
- Rechts oben → dein Profil → "Account" → "API Keys"
- Kopiere deinen API Key

### 3. In der DartVision App eintragen

- Öffne: **Settings → Roboflow / YOLO Integration**
- Aktiviere: **"Roboflow-Erkennung nutzen"**
- Fülle aus:
  - `Roboflow API Key: [dein_api_key]`
  - `Roboflow Endpoint: [deine_url]`
- **Speichern**

### 4. Testen

- Öffne das Spiel
- Gehe zur Kalibrierung (Settings → Board kalibrieren)
- Starte dann ein Spiel
- Werfe einen Pfeil → Apps should erkennen

---

## 🔧 Code-Architektur

### Services

- `detection_service.dart` - Abstract Interface
- `local_detection_service.dart` - Lokale Heuristik-Erkennung (Fallback)
- `roboflow_detection_service.dart` - YOLO/Roboflow API
- `image_converter_service.dart` - Y-Plane → JPEG Konvertierung

### Flow

```
Kamera Frame (Y-Plane)
     ↓
[Hat Motion?] → LocalDetectionService
     ↓
[Roboflow aktiv?]
     ├─ JA → ImageConverter (Y-Plane → JPEG)
     │       ↓
     │       HTTP POST an Roboflow API
     │       ↓
     │       Parse JSON → DartThrow[]
     ├─ NEIN oder Fehler → Fallback (LocalDetectionService)
     ↓
Punkte berechnen → UI anzeigen
```

---

## 📊 Roboflow Response Format

Das Model deNnt folgende Klassen:
```
"dart"       - Generischer Pfeil
"S20"        - Single 20
"D20"        - Double 20
"T20"        - Triple 20
"Bull"       - Outer Bull (25)
"DB"         - Bullseye/Inner Bull (50)
```

Beispiel Response:
```json
{
  "predictions": [
    {
      "x": 150,
      "y": 200,
      "width": 30,
      "height": 40,
      "confidence": 0.92,
      "class": "T20"
    }
  ]
}
```

---

## ⚙️ Settings Storage

- `useRoboflow` - Boolean (on/off)
- `roboflowApiKey` - dein API Key
- `roboflowEndpoint` - deine Model URL

Diese werden in `SharedPreferences` gespeichert.

---

## 🐛 Fehlerbehandlung

Falls die Roboflow API nicht antwortet:
- ✅ Fällt automatisch auf lokale Erkennung zurück
- Kein Crash, kein Freeze
- User sieht weiterhin Schätzergebnisse

Status Debug:
- Android Studio → Logcat → suche: "Roboflow"
- Sieht alle API-Fehler + Timeouts

---

## 🎓 Nächste Schritte

1. Trainieren: Roboflow Model mit mehr Daten trainieren
2. Feedback: `submitCorrection()` speichert User-Korrektionen → später exportieren
3. Offline: Optional: Model lokal als ONNX/TFLite deployen

---

## 📞 Support

Falls Problems:
- API Key ungültig? → Check Account Settings
- Modell nicht gefunden? → Check URL Format 
- Timeout? → Check Internet Connection + Roboflow Status
