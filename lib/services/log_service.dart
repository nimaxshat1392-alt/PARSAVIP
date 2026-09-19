import 'dart:convert';
import 'dart:io';
import '../models/log_entry.dart';

class LogService {
  // ⭐ Singleton — همیشه یه نمونه واحد برمی‌گردونه
  LogService._internal();
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;

  static const int maxLogs = 500;
  final List<LogEntry> _buffer = [];
  bool _initialized = false;

  File get _file => File('${Directory.systemTemp.path}/parsavip_logs.json');

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      if (!await _file.exists()) return;
      final raw = await _file.readAsString();
      if (raw.isEmpty) return;
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
    try {
      await _file.writeAsString(
        jsonEncode(_buffer.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> clear() async {
    _buffer.clear();
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }
}
