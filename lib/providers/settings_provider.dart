import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  final SharedPreferences _prefs;

  SettingsProvider(this._prefs);

  static const _keyApiKey = 'gemini_api_key';
  static const _keyPlayerNames = 'player_names';
  static const _keyLastGameType = 'last_game_type';
  static const _keyDoubleOut = 'double_out';
  static const _keyDoubleIn = 'double_in';
  static const _keySoundEnabled = 'sound_enabled';
  static const _keyVibrationEnabled = 'vibration_enabled';
  static const _keyCalibrationImage = 'calibration_image_b64';

  String get apiKey => _prefs.getString(_keyApiKey) ?? '';
  bool get hasApiKey => apiKey.isNotEmpty;

  List<String> get savedPlayerNames =>
      _prefs.getStringList(_keyPlayerNames) ?? ['Spieler 1', 'Spieler 2'];

  String get lastGameType => _prefs.getString(_keyLastGameType) ?? '501';
  bool get doubleOut => _prefs.getBool(_keyDoubleOut) ?? true;
  bool get doubleIn => _prefs.getBool(_keyDoubleIn) ?? false;
  bool get soundEnabled => _prefs.getBool(_keySoundEnabled) ?? true;
  bool get vibrationEnabled => _prefs.getBool(_keyVibrationEnabled) ?? true;

  bool get hasCalibrationImage =>
      _prefs.getString(_keyCalibrationImage) != null;

  Uint8List? get calibrationImageBytes {
    final b64 = _prefs.getString(_keyCalibrationImage);
    if (b64 == null) return null;
    return base64Decode(b64);
  }

  Future<void> setApiKey(String key) async {
    await _prefs.setString(_keyApiKey, key);
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
    final b64 = base64Encode(bytes);
    await _prefs.setString(_keyCalibrationImage, b64);
    notifyListeners();
  }

  Future<void> clearCalibrationImage() async {
    await _prefs.remove(_keyCalibrationImage);
    notifyListeners();
  }
}