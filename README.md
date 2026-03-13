# 🎯 DartVision

**KI-gesteuerter Dart Board Tracker** – Erkennt Darts auf dem Board automatisch per Kamera, erlaubt manuelle Korrektur, und zählt Punkte in 11 Spielmodi.

![Flutter](https://img.shields.io/badge/Flutter-3.27+-blue?logo=flutter)
![Gemini](https://img.shields.io/badge/AI-Google%20Gemini%202.0%20Flash-orange?logo=google)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Features

### KI-Erkennung & Manuelle Korrektur
- **Kamera → KI-Analyse** – Dartboard fotografieren, Gemini erkennt automatisch Segment, Ring (Single/Double/Triple/Bull) und Konfidenz pro Dart
- **Korrektur-Sheet** – Jeder erkannte Dart kann vor Übernahme bearbeitet werden: Segment ändern, Ring-Typ anpassen, Darts entfernen oder manuell hinzufügen
- **Konfidenz-Anzeige** – Niedrige Konfidenz wird visuell markiert (⚠️) als Signal zum Prüfen
- **Manuelle Eingabe** – Schnelles Nummernpad mit Single/Double/Triple-Auswahl als Alternative

### 11 Spielmodi

| Modus | Beschreibung |
|-------|-------------|
| **501** | Klassisch. Von 501 auf 0, Double Out |
| **301** | Schnellere Variante. Von 301 auf 0 |
| **701** | Für Profis. Von 701 auf 0 |
| **Cricket** | Schließe 15–20 & Bull, sammle Punkte |
| **Cut Throat Cricket** | Cricket – aber Punkte gehen an Gegner! |
| **Around the Clock** | Treffe 1 bis 20 der Reihe nach |
| **Shanghai** | Pro Runde ein Ziel. Shanghai (S+D+T) = sofort gewonnen |
| **Killer** | Triff dein Double, werde Killer, eliminiere andere |
| **Bob's 27** | Double-Training: Treffer bringen Punkte, Misses kosten doppelt |
| **High Score** | X Runden: Wer hat den höchsten Gesamtscore? |
| **Double Training** | Trainiere alle 20 Doubles + Bull. Treffquote zählt |

### Legs & Sets (X01)
- Konfigurierbare **Legs** (First to X) und **Sets** (First to X Sets à Y Legs)
- Automatischer Leg/Set-Wechsel mit Score-Reset
- Anzeige von Legs/Sets im Scoreboard

### Weitere Features
- **1–8 Spieler** mit farbkodiertem Scoreboard
- **Checkout-Vorschläge** – Zeigt optimale Wege zum Finish (2–170)
- **Double In / Double Out** – Konfigurierbare Regeln
- **Undo-Funktion** – Letzte Würfe rückgängig machen
- **Spiellog** – Chronologisches Event-Log pro Spiel
- **Statistiken & Verlauf** – Gespeicherte Spiele mit Ø, 180er, Höchste Runde, etc.
- **Globale Stats** – Gesamtübersicht über alle gespielten Partien
- **Kamera-Blitz** – Für schlechte Lichtverhältnisse
- **Dunkles Design** – Augenschonendes UI im modernen Dark Theme

## Voraussetzungen

- Android 7.0+ (API 24)
- Google Gemini API-Key (kostenlos: [aistudio.google.com/apikey](https://aistudio.google.com/apikey))

## Installation

### Option A: APK direkt installieren
1. Lade die neueste APK von [Releases](../../releases) herunter
2. Öffne die APK auf deinem Android-Gerät
3. Erlaube "Installation aus unbekannten Quellen"
4. Nach dem Start: **Einstellungen → Gemini API-Key** eingeben

### Option B: Selbst bauen

```bash
git clone https://github.com/DEIN-USER/dart_scorer.git
cd dart_scorer
flutter pub get
dart run flutter_launcher_icons   # App-Icon generieren
flutter build apk --release
```

### Option C: GitHub Actions
- **Push auf `main`** → Baut APK automatisch (Download als Artifact)
- **Tag `v*` pushen** → Erstellt GitHub Release mit APKs + AAB

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Projektstruktur

```
dart_scorer/
├── .github/workflows/
│   └── build.yml                  # CI/CD Pipeline
├── android/                       # Android-Konfiguration
├── lib/
│   ├── config/
│   │   ├── constants.dart         # Spielmodi, Board-Layout, Prompts
│   │   └── theme.dart             # Dark Theme & Farben
│   ├── models/
│   │   ├── dart_throw.dart        # Einzelwurf-Model
│   │   ├── game_history.dart      # Spielverlauf-Persistenz
│   │   ├── game_state.dart        # Spielzustand mit Legs/Sets
│   │   └── player.dart            # Spieler mit allen Modi-Feldern
│   ├── providers/
│   │   ├── game_provider.dart     # Spiel-Logik (alle 11 Modi)
│   │   └── settings_provider.dart # Einstellungen (SharedPrefs)
│   ├── screens/
│   │   ├── camera_screen.dart     # Kamera + KI → Edit-Sheet
│   │   ├── game_screen.dart       # Hauptspiel-UI (alle Modi)
│   │   ├── game_setup_screen.dart # Spielkonfig mit Kategorien
│   │   ├── history_screen.dart    # Statistiken & Spielverlauf
│   │   ├── home_screen.dart       # Startbildschirm
│   │   └── settings_screen.dart   # API-Key & Einstellungen
│   ├── services/
│   │   ├── ai_detection_service.dart  # Gemini Vision API
│   │   ├── game_history_service.dart  # Verlauf laden/speichern
│   │   └── score_calculator.dart      # Punkteberechnung
│   ├── widgets/
│   │   ├── cricket_scoreboard_widget.dart  # Cricket-Anzeige
│   │   ├── dart_edit_sheet.dart            # KI-Korrektur-Sheet
│   │   ├── dartboard_input_widget.dart     # Manuelle Eingabe
│   │   ├── generic_scoreboard_widget.dart  # Alle anderen Modi
│   │   └── scoreboard_widget.dart          # X01-Anzeige
│   ├── app.dart
│   └── main.dart
├── test/
│   └── score_calculator_test.dart
├── assets/images/
├── pubspec.yaml
└── README.md
```

## Tipps für beste KI-Erkennung

- **Gute Beleuchtung** – Blitz-Button nutzen bei Bedarf
- **Frontale Perspektive** – Möglichst gerade von vorne
- **Ganzes Board im Bild** – Nicht zu nah dran
- **Ergebnisse prüfen** – Das Korrektur-Sheet zeigt Konfidenzwerte; bei ⚠️ manuell anpassen

## Lizenz

MIT License
