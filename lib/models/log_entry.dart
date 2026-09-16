enum LogLevel { info, warning, error, success }

class LogEntry {
  final String id;
  final LogLevel level;
  final String message;
  final DateTime timestamp;

  LogEntry({
    required this.id, required this.level,
    required this.message, required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'level': level.name,
    'message': message, 'timestamp': timestamp.toIso8601String(),
  };

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
    id: j['id'],
    level: LogLevel.values.firstWhere(
      (l) => l.name == j['level'],
      orElse: () => LogLevel.info,
    ),
    message: j['message'],
    timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
  );

  String get icon {
    switch (level) {
      case LogLevel.info: return 'ℹ️';
      case LogLevel.warning: return '⚠️';
      case LogLevel.error: return '❌';
      case LogLevel.success: return '✅';
    }
  }
}
