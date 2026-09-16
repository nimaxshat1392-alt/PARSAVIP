import 'dart:convert';
import 'dart:io';
import '../models/log_entry.dart';

class LogService {
  static const int maxLogs = 500;
  final List<LogEntry> _buffer = [];

  File get _file => File('${Directory.systemTemp.path}/parsavip_logs.json');

  Future<void> init() async {
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

  int countByLevel(LogLevel level) =>
      _buffer.where((l) => l.level == level).length;
}
