import 'dart:async';
import 'dart:io';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// ═══════════════════════════════════════════════════════════════════
/// PingEngine Pro — موتور پینگ فوق‌پیشرفته
/// ═══════════════════════════════════════════════════════════════════
///
/// ویژگی‌ها:
/// ✅ Xray ping (getServerDelay) — دقیقاً مثل v2rayNG
/// ✅ TCP ping fallback
/// ✅ میانگین / Median / Min / Max / Jitter
/// ✅ Packet Loss detection
/// ✅ Adaptive Retry با Exponential Backoff
/// ✅ DNS Cache با TTL
/// ✅ Timeout سختگیرانه
/// ✅ Concurrency Control
/// ✅ Cancel Support
/// ✅ Real-time Progress
/// ✅ جعلی‌یاب (fake ping detector)
/// ✅ کیفیت‌بندی خودکار سرور
/// ═══════════════════════════════════════════════════════════════════

class PingService {
  PingService._();

  // ═══════════════════════════════════════════════════════════════════
  // تنظیمات
  // ═══════════════════════════════════════════════════════════════════

  static const int offlineThreshold = 9999;
  static const int maxValidPing = 20000;
  static const int minValidPing = 15;

  static const String testUrl = 'https://www.google.com/generate_204';

  static const Duration xrayTimeout = Duration(seconds: 10);
  static const Duration tcpTimeout = Duration(seconds: 4);
  static const Duration dnsTimeout = Duration(seconds: 3);
  static const Duration dnsCacheTtl = Duration(minutes: 5);

  static const int maxAttempts = 2;
  static const Duration baseRetryDelay = Duration(milliseconds: 200);

  /// تعداد نمونه برای محاسبه دقیق
  static const int sampleCount = 2;

  // ═══════════════════════════════════════════════════════════════════
  // State
  // ═══════════════════════════════════════════════════════════════════

  static FlutterVless? _vless;
  static bool _initialized = false;
  static bool _cancelled = false;

  static final Map<String, _DnsEntry> _dnsCache = {};
  static final _PingStats _stats = _PingStats();

  // ═══════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════

  static void cancel() => _cancelled = true;

  static void reset() {
    _cancelled = false;
    _stats.reset();
  }

  static void clearDnsCache() => _dnsCache.clear();

  static Map<String, dynamic> getGlobalStats() => _stats.toJson();

  /// مقداردهی Xray core
  static Future<void> initialize() async {
    if (_initialized) return;
    _vless ??= FlutterVless(onStatusChanged: (_) {});
    try {
      await _vless!.initializeVless(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
        providerBundleIdentifier: 'com.parsavip.parsavip',
        groupIdentifier: 'group.com.parsavip.parsavip',
      );
      _initialized = true;
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════
  // Core — Ping One Server (Detailed)
  // ═══════════════════════════════════════════════════════════════════

  /// پینگ دقیق یک سرور با تمام آمار
  static Future<PingResult> pingDetailed(VpnConfig config) async {
    if (_cancelled) {
      return PingResult.offline(config, PingStatus.cancelled);
    }

    if (config.host.isEmpty || config.port <= 0) {
      return PingResult.offline(config, PingStatus.invalid);
    }

    final samples = <int>[];
    int attempts = 0;

    // ⭐ مرحله ۱: Xray ping (دقیق‌ترین)
    for (var i = 0; i < sampleCount; i++) {
      if (_cancelled) break;

      final ms = await _xrayPing(config);
      attempts++;

      if (ms != null) {
        samples.add(ms);
      } else if (i == 0) {
        // اگه اولین fail شد، ادامه نده
        break;
      }

      if (i < sampleCount - 1) {
        await _smartDelay(i);
      }
    }

    // ⭐ مرحله ۲: اگه Xray fail داد، TCP fallback
    if (samples.isEmpty) {
      for (var i = 0; i < sampleCount; i++) {
        if (_cancelled) break;

        final ms = await _tcpPing(config);
        attempts++;

        if (ms != null) {
          samples.add(ms);
        } else if (i == 0) {
          break;
        }

        if (i < sampleCount - 1) {
          await _smartDelay(i);
        }
      }
    }

    if (samples.isEmpty) {
      _stats.recordFailure();
      return PingResult.offline(config, PingStatus.offline);
    }

    // ⭐ محاسبه آمار کامل
    samples.sort();
    final median = _median(samples);
    final min = samples.first;
    final max = samples.last;
    final avg = _average(samples);
    final jitter = _jitter(samples);
    final packetLoss = 1.0 - (samples.length / (sampleCount * 2));

    _stats.recordSuccess(median);

    return PingResult(
      config: config,
      ping: median,
      min: min,
      max: max,
      avg: avg,
      jitter: jitter,
      packetLoss: packetLoss.clamp(0.0, 1.0),
      samples: samples,
      status: PingStatus.online,
      attempts: attempts,
    );
  }

  /// پینگ ساده — فقط عدد
  static Future<int?> pingOne(VpnConfig config) async {
    final result = await pingDetailed(config);
    return result.ping;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Bulk Ping — همه سرورها
  // ═══════════════════════════════════════════════════════════════════

  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int concurrency = 4,
    void Function(PingProgress)? onProgress,
  }) async {
    if (configs.isEmpty) return [];

    reset();
    await initialize();

    final results = List<VpnConfig>.from(configs);
    final total = configs.length;
    final startTime = DateTime.now();

    int nextIndex = 0;
    int completed = 0;
    int online = 0;
    int offline = 0;

    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;

        final int i = nextIndex;
        if (i >= total) return;
        nextIndex = i + 1;

        final config = configs[i];
        final result = await pingDetailed(config);

        if (result.isOnline && result.ping != null) {
          results[i] = VpnConfig(
            id: config.id,
            name: config.name,
            protocol: config.protocol,
            rawUri: config.rawUri,
            host: config.host,
            port: config.port,
            ping: result.ping,
          );
          online++;
        } else {
          results[i] = VpnConfig(
            id: config.id,
            name: config.name,
            protocol: config.protocol,
            rawUri: config.rawUri,
            host: config.host,
            port: config.port,
            ping: offlineThreshold,
          );
          offline++;
        }

        completed++;

        onProgress?.call(PingProgress(
          completed: completed,
          total: total,
          online: online,
          offline: offline,
          elapsed: DateTime.now().difference(startTime),
          currentHost: config.host,
          currentPing: result.ping,
          currentQuality: result.quality,
        ));
      }
    }

    final wc = concurrency < total ? concurrency : total;
    await Future.wait(List.generate(wc, (_) => worker()));

    results.sort((a, b) =>
        (a.ping ?? offlineThreshold).compareTo(b.ping ?? offlineThreshold));

    return results;
  }

  /// بهترین سرور بر اساس پینگ و کیفیت
  static VpnConfig? best(List<VpnConfig> configs) {
    if (configs.isEmpty) return null;

    final valid = configs
        .where((c) =>
            c.ping != null &&
            c.ping! < offlineThreshold &&
            c.ping! <= maxValidPing)
        .toList();

    if (valid.isEmpty) return null;

    valid.sort((a, b) => a.ping!.compareTo(b.ping!));
    return valid.first;
  }

  /// بهترین n سرور
  static List<VpnConfig> bestN(List<VpnConfig> configs, int n) {
    if (configs.isEmpty) return [];

    final valid = configs
        .where((c) =>
            c.ping != null &&
            c.ping! < offlineThreshold &&
            c.ping! <= maxValidPing)
        .toList();

    valid.sort((a, b) => a.ping!.compareTo(b.ping!));
    return valid.take(n).toList();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Xray Ping
  // ═══════════════════════════════════════════════════════════════════

  static Future<int?> _xrayPing(VpnConfig config) async {
    if (_vless == null) return null;

    String? jsonConfig;
    try {
      final cleanUri = _sanitizeUri(config.rawUri);
      final parsed = FlutterVless.parseFromURL(cleanUri);
      jsonConfig = parsed.getFullConfiguration();
    } catch (_) {
      return null;
    }

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_cancelled) return null;

      try {
        final int delay = await _vless!
            .getServerDelay(config: jsonConfig, url: testUrl)
            .timeout(xrayTimeout, onTimeout: () => -1);

        if (_cancelled) return null;

        // ⭐ اعتبارسنجی سختگیرانه
        if (delay < minValidPing) {
          // جعلی → تلاش دوباره
          if (attempt < maxAttempts - 1) {
            await _backoffDelay(attempt);
            continue;
          }
          return null;
        }

        if (delay > maxValidPing) {
          if (attempt < maxAttempts - 1) {
            await _backoffDelay(attempt);
            continue;
          }
          return null;
        }

        return delay;
      } catch (_) {
        if (attempt < maxAttempts - 1) {
          await _backoffDelay(attempt);
        }
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════
  // TCP Ping (Fallback)
  // ═══════════════════════════════════════════════════════════════════

  static Future<int?> _tcpPing(VpnConfig config) async {
    if (_cancelled) return null;

    try {
      final addresses = await _resolveDns(config.host);
      if (addresses == null || addresses.isEmpty) return null;

      // ⭐ تلاش روی همه IP ها
      for (final addr in addresses) {
        if (_cancelled) return null;

        final ms = await _tcpConnect(addr.address, config.port);
        if (ms != null) return ms;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _tcpConnect(String ip, int port) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(ip, port, timeout: tcpTimeout);
      socket.destroy();
      sw.stop();

      final ms = sw.elapsedMilliseconds;
      if (ms < minValidPing) return null;
      if (ms > maxValidPing) return null;
      return ms;
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // DNS Cache
  // ═══════════════════════════════════════════════════════════════════

  static Future<List<InternetAddress>?> _resolveDns(String host) async {
    // چک cache
    final cached = _dnsCache[host];
    if (cached != null) {
      final age = DateTime.now().difference(cached.timestamp);
      if (age < dnsCacheTtl) {
        return cached.addresses;
      } else {
        _dnsCache.remove(host);
      }
    }

    // resolve
    try {
      final addrs = await InternetAddress.lookup(host).timeout(dnsTimeout);
      if (addrs.isNotEmpty) {
        _dnsCache[host] = _DnsEntry(
          addresses: addrs,
          timestamp: DateTime.now(),
        );
        return addrs;
      }
    } catch (_) {}

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════
  // Statistics Helpers
  // ═══════════════════════════════════════════════════════════════════

  /// Median (دقیق‌تر از میانگین برای پینگ)
  static int _median(List<int> sorted) {
    if (sorted.isEmpty) return 0;
    return sorted[sorted.length ~/ 2];
  }

  /// میانگین
  static int _average(List<int> samples) {
    if (samples.isEmpty) return 0;
    return samples.reduce((a, b) => a + b) ~/ samples.length;
  }

  /// Jitter — نوسان پینگ
  static int _jitter(List<int> samples) {
    if (samples.length < 2) return 0;
    var sum = 0;
    for (var i = 1; i < samples.length; i++) {
      sum += (samples[i] - samples[i - 1]).abs();
    }
    return sum ~/ (samples.length - 1);
  }

  // ═══════════════════════════════════════════════════════════════════
  // Delay Helpers
  // ═══════════════════════════════════════════════════════════════════

  /// Delay هوشمند بین نمونه‌ها
  static Future<void> _smartDelay(int index) async {
    // ۱۵۰ms + ۵۰ms * index
    final ms = 150 + (index * 50);
    await Future.delayed(Duration(milliseconds: ms));
  }

  /// Exponential Backoff
  static Future<void> _backoffDelay(int attempt) async {
    final ms = baseRetryDelay.inMilliseconds * (1 << attempt);
    await Future.delayed(Duration(milliseconds: ms.clamp(200, 2000)));
  }

  // ═══════════════════════════════════════════════════════════════════
  // URI Sanitizer
  // ═══════════════════════════════════════════════════════════════════

  static String _sanitizeUri(String uri) {
    try {
      final hashIndex = uri.indexOf('#');
      String mainPart = hashIndex >= 0 ? uri.substring(0, hashIndex) : uri;
      String fragment = hashIndex >= 0 ? uri.substring(hashIndex) : '';

      final qIndex = mainPart.indexOf('?');
      if (qIndex < 0) return uri;

      final basePart = mainPart.substring(0, qIndex);
      final queryPart = mainPart.substring(qIndex + 1);

      final newParams = <String>[];
      for (final pair in queryPart.split('&')) {
        if (pair.isEmpty) continue;
        final eqIndex = pair.indexOf('=');
        if (eqIndex < 0) {
          newParams.add(pair);
          continue;
        }
        final key = pair.substring(0, eqIndex);
        final value = pair.substring(eqIndex + 1);
        if (key == 'security' && (value.isEmpty || value == 'none')) continue;
        if (value.isEmpty) continue;
        newParams.add(pair);
      }

      return '$basePart?${newParams.join('&')}$fragment';
    } catch (_) {
      return uri;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Data Classes
// ═══════════════════════════════════════════════════════════════════

/// نتیجه‌ی کامل پینگ
class PingResult {
  final VpnConfig config;
  final int? ping; // Median
  final int? min;
  final int? max;
  final int? avg;
  final int? jitter;
  final double packetLoss;
  final List<int> samples;
  final PingStatus status;
  final int attempts;

  PingResult({
    required this.config,
    required this.ping,
    this.min,
    this.max,
    this.avg,
    this.jitter,
    this.packetLoss = 0,
    required this.samples,
    required this.status,
    this.attempts = 0,
  });

  factory PingResult.offline(VpnConfig config, PingStatus status) {
    return PingResult(
      config: config,
      ping: null,
      samples: const [],
      status: status,
    );
  }

  bool get isOnline => status == PingStatus.online && ping != null;

  /// کیفیت سرور بر اساس پینگ و jitter
  ServerQuality get quality {
    if (ping == null) return ServerQuality.offline;
    if (ping! < 80 && (jitter ?? 0) < 20) return ServerQuality.excellent;
    if (ping! < 150 && (jitter ?? 0) < 50) return ServerQuality.great;
    if (ping! < 300) return ServerQuality.good;
    if (ping! < 600) return ServerQuality.fair;
    return ServerQuality.poor;
  }

  String get qualityLabel => quality.label;
  String get qualityEmoji => quality.emoji;
}

enum PingStatus { online, offline, cancelled, invalid }

/// کیفیت سرور
enum ServerQuality {
  excellent,
  great,
  good,
  fair,
  poor,
  offline,
}

extension ServerQualityX on ServerQuality {
  String get label {
    switch (this) {
      case ServerQuality.excellent:
        return 'عالی';
      case ServerQuality.great:
        return 'خیلی خوب';
      case ServerQuality.good:
        return 'خوب';
      case ServerQuality.fair:
        return 'متوسط';
      case ServerQuality.poor:
        return 'ضعیف';
      case ServerQuality.offline:
        return 'آفلاین';
    }
  }

  String get emoji {
    switch (this) {
      case ServerQuality.excellent:
        return '🟢';
      case ServerQuality.great:
        return '🟢';
      case ServerQuality.good:
        return '🔵';
      case ServerQuality.fair:
        return '🟡';
      case ServerQuality.poor:
        return '🔴';
      case ServerQuality.offline:
        return '⚫';
    }
  }
}

/// پیشرفت پینگ
class PingProgress {
  final int completed;
  final int total;
  final int online;
  final int offline;
  final Duration elapsed;
  final String currentHost;
  final int? currentPing;
  final ServerQuality? currentQuality;

  PingProgress({
    required this.completed,
    required this.total,
    required this.online,
    required this.offline,
    required this.elapsed,
    required this.currentHost,
    required this.currentPing,
    this.currentQuality,
  });

  double get percent => total == 0 ? 0 : completed / total;

  Duration get eta {
    if (completed == 0) return Duration.zero;
    final avgMs = elapsed.inMilliseconds / completed;
    final remaining = total - completed;
    return Duration(milliseconds: (avgMs * remaining).round());
  }

  String get etaLabel {
    final d = eta;
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }
}

/// DNS cache entry
class _DnsEntry {
  final List<InternetAddress> addresses;
  final DateTime timestamp;

  _DnsEntry({required this.addresses, required this.timestamp});
}

/// آمار کلی
class _PingStats {
  int _success = 0;
  int _failure = 0;
  final List<int> _pings = [];

  void recordSuccess(int ms) {
    _success++;
    _pings.add(ms);
    if (_pings.length > 200) _pings.removeAt(0);
  }

  void recordFailure() => _failure++;

  void reset() {
    _success = 0;
    _failure = 0;
    _pings.clear();
  }

  Map<String, dynamic> toJson() => {
        'successCount': _success,
        'failureCount': _failure,
        'totalTested': _success + _failure,
        'avgPing': _pings.isEmpty
            ? 0
            : _pings.reduce((a, b) => a + b) ~/ _pings.length,
        'minPing': _pings.isEmpty ? 0 : _pings.reduce((a, b) => a < b ? a : b),
        'maxPing': _pings.isEmpty ? 0 : _pings.reduce((a, b) => a > b ? a : b),
      };
}
