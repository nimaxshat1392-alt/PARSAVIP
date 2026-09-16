import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/log_entry.dart';

class LogService {
  static const _key = 'parsavip_logs_v1';
  static const int maxLogs = 500;

  final List<LogEntry> _buffer = [];

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      _buffer
        ..clear()
        ..addAll(list.map((e) => LogEntry.fromJson(e)));
    } catch (_) {}
  }

  List<LogEntry> get logs => List.unmodifiable(_buffer.reversed);

  Future<void> add(LogLevel level, String msg) async {
    _buffer.add(LogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      level: level,
      message: msg,
      timestamp: DateTime.now(),
    ));
    if (_buffer.length > maxLogs) {
      _buffer.removeRange(0, _buffer.length - maxLogs);
    }
    await _persist();
  }

  Future<void> clear() async {
    _buffer.clear();
    await _persist();
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode(_buffer.map((e) => e.toJson()).toList()),
    );
  }

  int countByLevel(LogLevel level) =>
      _buffer.where((l) => l.level == level).length;
}
