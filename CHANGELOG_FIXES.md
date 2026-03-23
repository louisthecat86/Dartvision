# DartVision Code-Review Fixes

## Anleitung
Die 7 Dart-Dateien in diesem Paket sind Drop-in-Replacements.
Einfach die entsprechenden Dateien in deinem Projekt überschreiben.

**Zusätzlich manuell erledigen:**
- `lib/services/roboflow_detection_service_new.dart` löschen (toter Code, wird nirgends importiert)

---

## 🔴 Bugs gefixt

### Fix #1 — X01 Bust-Logik: Score-Rücksetzung korrekt
**Datei:** `lib/providers/game_provider.dart`
**Problem:** Bei Bust wurde `player.scoreRemaining += roundScore` genutzt.
`currentRoundScore` summiert aber die Raw-Scores aller Darts — auch von
noScore-Darts (Double-In nicht erfüllt), deren Score nie tatsächlich
abgezogen wurde. Das führte dazu, dass `scoreRemaining` zu hoch wurde.
**Fix:** Rundenstart-Score wird aus dem neuen Undo-Snapshot gelesen und
direkt wiederhergestellt.

### Fix #2 — Killer: All-Dead Edge-Case + Return nach _finishGame
**Datei:** `lib/providers/game_provider.dart`
**Problem:** Wenn alle Spieler gleichzeitig eliminiert wurden (theoretisch
möglich), gab es keinen Gewinner. Außerdem wurde nach `_finishGame` kein
`return` aufgerufen, sodass `_nextPlayer` noch State veränderte.
**Fix:** `alive.length <= 1` statt `== 1`, Fallback auf letzten Werfer,
sauberes `return` nach allen Game-Over-Pfaden.

### Fix #3 — Bob's 27: Nur Inner Bull = Double
**Datei:** `lib/providers/game_provider.dart`
**Problem:** Outer Bull (25 Punkte) wurde als gültiger Treffer für das
Bull-Target gewertet. Outer Bull ist aber kein Double.
**Fix:** Nur `RingType.innerBull` zählt als Treffer für Target 25.

### Fix #4 — DartEditSheet: Maximal 3 Darts
**Datei:** `lib/widgets/dart_edit_sheet.dart`
**Problem:** User konnte unbegrenzt Darts hinzufügen. Dart 4+ führte zu
Spielerwechsel mitten in der Verarbeitung (weil `rounds.last.length >= 3`
nach dem 3. Dart triggert).
**Fix:** `_maxDarts = 3` Limit, Add-Button verschwindet bei 3 Darts.

### Fix #11 — RingType.fromString matcht nicht .name
**Datei:** `lib/config/constants.dart`
**Problem:** `DartThrow.toJson()` speichert `ring.name` (z.B. `"double_"`,
`"singleInner"`), aber `fromString` erwartete `"double"`, `"single_inner"`.
Ergebnis: Deserialisierung gab immer `RingType.miss` zurück.
**Fix:** Beide Formate werden jetzt akzeptiert (camelCase + snake_case).

### Fix #12 — yuv420ToJpeg V-Plane Offset falsch
**Datei:** `lib/services/image_converter_service.dart`
**Problem:** `yuvData[uvOffset + uvPlaneSize + uvIdx - uvOffset]` vereinfacht
sich zu `yuvData[uvPlaneSize + uvIdx]`, was nicht das V-Plane addressiert.
**Fix:** Korrekte Berechnung: `yPlaneSize + uvPlaneSize + linearIdx` + Bounds-Check.

---

## 🟠 Edge-Cases gefixt

### Fix #6 — Double-In Bedingung falsch
**Datei:** `lib/services/score_calculator.dart` + `lib/providers/game_provider.dart`
**Problem:** `player.totalScore == 0` prüfte die Summe aller Raw-Scores.
Wenn ein Spieler S20 warf (kein Double), war totalScore=20, und die
Double-In-Bedingung griff nicht mehr obwohl noch kein gültiger Wurf zählte.
**Fix:** `player.scoreRemaining == game.startScore` (= noch kein Abzug erfolgt).

### Fix #7 — Cut Throat Cricket: else-Zweig semantisch falsch
**Datei:** `lib/providers/game_provider.dart`
**Problem:** Bei Cut Throat mit `pointsAdded == 0` fiel der Code in den
`else`-Zweig und addierte 0 zum werfenden Spieler — harmlos, aber semantisch
falsch (bei Cut Throat bekommt der Werfer nie Punkte).
**Fix:** Expliziter Guard: `else if (!cutThroat && result.pointsAdded > 0)`.

### Fix #8 — _nextPlayer Endlosschleife bei all-dead
**Datei:** `lib/providers/game_provider.dart`
**Problem:** Wenn alle Spieler tot waren, drehte die while-Schleife
`players.length` Mal und setzte dann einen toten Spieler als aktiv.
**Fix:** Bei `attempts >= players.length` → `return` ohne Index-Änderung.

### Fix #9 — Undo für alle 11 Modi (Snapshot-basiert)
**Datei:** `lib/providers/game_provider.dart`
**Problem:** Undo funktionierte nicht für Around the Clock, Killer, Bob's 27
(Kommentar im Code: "schwer rückgängig zu machen"). Die manuelle
Score-Rückrechnung war auch für X01/Cricket fehleranfällig.
**Fix:** Komplettes Snapshot-System: Vor jedem Wurf wird der gesamte
Spielzustand (alle Spieler-Felder, Game-State-Variablen) gespeichert.
Undo stellt den kompletten Snapshot wieder her. Funktioniert zuverlässig
für ALLE Modi, max. 30 Snapshots (ca. 10 Runden Puffer).

### Fix #13 — Player.average ignoriert Bust-Runden
**Datei:** `lib/models/player.dart`
**Problem:** Nur Runden mit genau 3 Darts wurden gezählt. Bust-Runden
(1 Miss-Dart nach Clear) wurden ignoriert → Average war zu hoch.
**Fix:** Zählt jetzt auch Bust-Runden (length==1 && ring==miss) als 0 Punkte.

### Fix #15 — NativeDetectionService ohne dispose
**Datei:** `lib/services/native_detection_service.dart`
**Problem:** StreamController und MethodChannel-Handler wurden nie aufgeräumt.
**Fix:** `dispose()` Methode hinzugefügt.
