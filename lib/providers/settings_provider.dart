import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/local_detection_service.dart';

class SettingsProvider extends ChangeNotifier {
  final SharedPreferences _prefs;

  SettingsProvider(this._prefs);

  static const _keyPlayerNames = 'player_names';
  static const _keyLastGameType = 'last_game_type';
  static const _keyDoubleOut = 'double_out';
  static const _keyDoubleIn = 'double_in';
  static const _keySoundEnabled = 'sound_enabled';
  static const _keyVibrationEnabled = 'vibration_enabled';
  static const _keyHasCalibration = 'has_calibration_image';
  static const _keyBoardCalibration = 'board_calibration_json';
  static const _calibrationFileName = 'calibration_board.jpg';

  // Board-Kalibrierung
  bool get hasBoardCalibration =>
      _prefs.containsKey(_keyBoardCalibration) &&
      _prefs.getString(_keyBoardCalibration) != null;

  BoardCalibration? get boardCalibration {
    final json = _prefs.getString(_keyBoardCalibration);
    if (json == null) return null;
    try {
      return BoardCalibration.fromJson(
          jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // Legacy-Kompatibilität
  bool get hasCalibrationImage =>
      _prefs.getBool(_keyHasCalibration) ?? false;

  List<String> get savedPlayerNames =>
      _prefs.getStringList(_keyPlayerNames) ?? ['Spieler 1', 'Spieler 2'];

  String get lastGameType => _prefs.getString(_keyLastGameType) ?? '501';
  bool get doubleOut => _prefs.getBool(_keyDoubleOut) ?? true;
  bool get doubleIn => _prefs.getBool(_keyDoubleIn) ?? false;
  bool get soundEnabled => _prefs.getBool(_keySoundEnabled) ?? true;
  bool get vibrationEnabled => _prefs.getBool(_keyVibrationEnabled) ?? true;

  Future<String?> _getCalibrationPath() async {
    if (!hasCalibrationImage) return null;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_calibrationFileName');
    return await file.exists() ? file.path : null;
  }

  Future<Uint8List?> getCalibrationImageBytes() async {
    final path = await _getCalibrationPath();
    if (path == null) return null;
    return await File(path).readAsBytes();
  }

  Future<void> setBoardCalibration(BoardCalibration cal) async {
    final json = jsonEncode(cal.toJson());
    await _prefs.setString(_keyBoardCalibration, json);
    notifyListeners();
  }

  Future<void> clearBoardCalibration() async {
    await _prefs.remove(_keyBoardCalibration);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_calibrationFileName');
    if (await file.exists()) await file.delete();
    await _prefs.setBool(_keyHasCalibration, false);
    notifyListeners();
  }

  Future<void> setPlayerNames(List<String> names) async {
    await _prefs.setStringList(_keyPlayerNames, names);
    notifyListeners();
  }

  Future<void> setLastGameType(String type) async {
    await _prefs.setString(_keyLastGameType, type);
    notifyListeners();
  }

  Future<void> setDoubleOut(bool value) async {
    await _prefs.setBool(_keyDoubleOut, value);
    notifyListeners();
  }

  Future<void> setDoubleIn(bool value) async {
    await _prefs.setBool(_keyDoubleIn, value);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    await _prefs.setBool(_keySoundEnabled, value);
    notifyListeners();
  }

  Future<void> setVibrationEnabled(bool value) async {
    await _prefs.setBool(_keyVibrationEnabled, value);
    notifyListeners();
  }

  Future<void> setCalibrationImage(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_calibrationFileName');
    await file.writeAsBytes(bytes, flush: true);
    await _prefs.setBool(_keyHasCalibration, true);
    notifyListeners();
  }

  Future<void> clearCalibrationImage() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_calibrationFileName');
    if (await file.exists()) await file.delete();
    await _prefs.setBool(_keyHasCalibration, false);
    notifyListeners();
  }
}
