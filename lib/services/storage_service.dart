// lib/services/storage_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sms_log.dart';

class StorageService {
  static const String _logsKey = 'sms_logs';
  static const String _apiKeyKey = 'api_key';
  static const String _serverPortKey = 'server_port';
  static const int _maxLogs = 50;

  static Future<List<SmsLog>> getLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_logsKey) ?? [];
    return raw
        .map((e) => SmsLog.fromMap(json.decode(e)))
        .toList()
        .reversed
        .take(_maxLogs)
        .toList();
  }

  static Future<void> addLog(SmsLog log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_logsKey) ?? [];
    raw.insert(0, json.encode(log.toMap()));
    // Keep only last _maxLogs entries
    if (raw.length > _maxLogs) {
      raw.removeRange(_maxLogs, raw.length);
    }
    await prefs.setStringList(_logsKey, raw);
  }

  static Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_logsKey);
  }

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey) ?? 'MY_SECRET_KEY_2024';
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key);
  }

  static Future<int> getServerPort() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_serverPortKey) ?? 8080;
  }

  static Future<void> setServerPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_serverPortKey, port);
  }
}
