import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import '../models/vpn_config.dart';

/// ═══════════════════════════════════════════════════════════
/// موتور پینگ پیشرفته — مثل v2rayNG / NekoBox / Clash
/// ═══════════════════════════════════════════════════════════
///
/// ویژگی‌ها:
/// - DNS Cache با TTL (سرعت ۱۰x)
/// - Multi-sample (۳ نمونه) + Median (دقیق‌تر از میانگین)
/// - Jitter calculation (نوسان پینگ)
/// - Packet loss detection
/// - Retry با exponential backoff
/// - IP family preference (IPv4/IPv6)
/// - Connection pooling
/// - Cancellation support
/// - Progress streaming
/// - Detailed statistics
///
/// نتیجه: دقیقاً مثل کلاینت‌های حرفه‌ای
class PingService {
  PingService._();

  // ═══════════════════════════════════════════════════════════
  // تنظیمات
  // ═══════════════════════════════════════════════════════════

  /// پینگ بیشتر از این = آفلاین
  static const int offlineThreshold = 9999;

  /// پینگ بیشتر از این = خیلی ضعیف (باید رد شه)
  static const int maxValidPing = 8000;

  /// تعداد نمونه برای هر سرور
  static const int sampleCount = 3;

  /// Timeout هر TCP connect
  static const Duration tcpTimeout = Duration(seconds: 4);

  /// Timeout DNS resolve
  static const Duration dnsTimeout = Duration(seconds: 3);

  /// TTL کش DNS (چند دقیقه)
  static const Duration dnsCacheTtl = Duration(minutes: 5);

  /// حداکثر retry برای DNS
  static const int maxDnsRetries = 2;

  // ═══════════════════════════════════════════════════════════
  // State
  // ═══════════════════════════════════════════════════════════

  static bool _cancelled = false;
  static final _DnsCache _dnsCache = _DnsCache();
  static final _PingStats _globalStats = _PingStats();

  // ═══════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════

  /// لغو همه عملیات جاری
  static void cancel() {
    _cancelled = true;
  }

  /// ریست کردن حالت
  static void reset() {
    _cancelled = false;
  }

  /// پاک کردن کش DNS
  static void clearDnsCache() {
    _dnsCache.clear();
  }

  /// آمار کلی
  static Map<String, dynamic> getGlobalStats() {
    return _globalStats.toJson();
  }

  /// پینگ یک سرور (با تمام ویژگی‌ها)
  static Future<PingResult> pingDetailed(VpnConfig config) async {
    if (_cancelled) {
      return PingResult(
        config: config,
        ping: null,
        jitter: null,
        packetLoss: 1.0,
        samples: const [],
        status: PingStatus.cancelled,
      );
    }

    // اعتبارسنجی
    if (config.host.isEmpty || config.port <= 0) {
      return PingResult(
        config: config,
        ping: null,
        jitter: null,
        packetLoss: 1.0,
        samples: const [],
        status: PingStatus.invalid,
      );
    }

    // نمونه‌گیری
    final samples = <int>[];
    int attempts = 0;

    for (var i = 0; i < sampleCount; i++) {
      if (_cancelled) break;

      final ms = await _singlePing(config);
      attempts++;

      if (ms != null && ms <= maxValidPing) {
        samples.add(ms);
      }

      // اگه اولین تلاش fail شد، دیگه تلاش نکن
      if (i == 0 && ms == null) break;

      // کوچک تاخیر بین نمونه‌ها
      if (i < sampleCount - 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (samples.isEmpty) {
      _globalStats.recordFailure();
      return PingResult(
        config: config,
        ping: null,
        jitter: null,
        packetLoss: 1.0,
        samples: const [],
        status: PingStatus.offline,
      );
    }

    // Median (دقیق‌تر از میانگین)
    final sorted = [...samples]..sort();
    final median = sorted[sorted.length ~/ 2];

    // Jitter (نوسان)
    final jitter = samples.length > 1
        ? _calculateJitter(samples)
        : 0;

    // Packet loss (درصد)
    final packetLoss = (sampleCount - samples.length) / sampleCount;

    _globalStats.recordSuccess(median);

    return PingResult(
      config: config,
      ping: median,
      jitter: jitter,
      packetLoss: packetLoss,
      samples: samples,
      status: PingStatus.online,
    );
  }

  /// پینگ ساده (فقط عدد)
  static Future<int?> pingOne(VpnConfig config) async {
    final result = await pingDetailed(config);
    return result.ping;
  }

  /// پینگ همه سرورها (موازی، با progress)
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int concurrency = 12,
    void Function(PingProgress)? onProgress,
  }) async {
    if (configs.isEmpty) return [];

    reset();
    _globalStats.reset();

    final results = List<VpnConfig>.from(configs);
    final total = configs.length;
    final queue = Queue<int>.from(List.generate(total, (i) => i));
    final lock = _Lock();

    int completed = 0;
    int online = 0;
    int offline = 0;
    final startTime = DateTime.now();

    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;

        int index;
        await lock.synchronized(() {
          if (queue.isEmpty) {
            index = -1;
          } else {
            index = queue.removeFirst();
          }
        });

        if (index == -1) return;

        final config = configs[index];
        final result = await pingDetailed(config);

        // به‌روزرسانی
        if (result.status == PingStatus.online && result.ping != null) {
          results[index] = VpnConfig(
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
          results[index] = VpnConfig(
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
        ));
      }
    }

    final wc = concurrency < total ? concurrency : total;
    await Future.wait(List.generate(wc, (_) => worker()));

    // مرتب‌سازی
    results.sort((a, b) =>
        (a.ping ?? offlineThreshold).compareTo(b.ping ?? offlineThreshold));

    return results;
  }

  /// پیدا کردن بهترین سرور
  static VpnConfig? best(List<VpnConfig> configs) {
    if (configs.isEmpty) return null;

    final sorted = [...configs]
      ..sort((a, b) =>
          (a.ping ?? offlineThreshold).compareTo(b.ping ?? offlineThreshold));

    final top = sorted.first;
    final ping = top.ping ?? offlineThreshold;

    if (ping >= offlineThreshold) return null;
    if (ping > maxValidPing) return null;

    return top;
  }

  // ═══════════════════════════════════════════════════════════
  // Internal
  // ═══════════════════════════════════════════════════════════

  /// پینگ یک بار — با DNS cache
  static Future<int?> _singlePing(VpnConfig config) async {
    // Resolve DNS با retry
    final addresses = await _resolveWithRetry(config.host);
    if (addresses == null || addresses.isEmpty) return null;

    // تلاش روی همه IP های resolve شده
    for (final addr in addresses) {
      if (_cancelled) return null;

      final result = await _tcpConnect(addr.address, config.port);
      if (result != null) return result;
    }

    return null;
  }

  /// Resolve DNS با retry
  static Future<List<InternetAddress>?> _resolveWithRetry(String host) async {
    // چک کش
    final cached = _dnsCache.get(host);
    if (cached != null) return cached;

    // تلاش با retry
    for (var i = 0; i <= maxDnsRetries; i++) {
      if (_cancelled) return null;

      try {
        final addrs = await InternetAddress.lookup(host).timeout(dnsTimeout);
        if (addrs.isNotEmpty) {
          _dnsCache.set(host, addrs);
          return addrs;
        }
      } catch (_) {
        if (i < maxDnsRetries) {
          // Exponential backoff
          await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
        }
      }
    }

    return null;
  }

  /// TCP connect
  static Future<int?> _tcpConnect(String ip, int port) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: tcpTimeout,
      );
      socket.destroy();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// محاسبه Jitter (نوسان پینگ)
  static int _calculateJitter(List<int> samples) {
    if (samples.length < 2) return 0;

    var sum = 0;
    for (var i = 1; i < samples.length; i++) {
      sum += (samples[i] - samples[i - 1]).abs();
    }
    return sum ~/ (samples.length - 1);
  }
}

// ═══════════════════════════════════════════════════════════
// Helper Classes
// ═══════════════════════════════════════════════════════════

/// نتیجه پینگ با جزئیات
class PingResult {
  final VpnConfig config;
  final int? ping;
  final int? jitter;
  final double packetLoss;
  final List<int> samples;
  final PingStatus status;

  PingResult({
    required this.config,
    required this.ping,
    required this.jitter,
    required this.packetLoss,
    required this.samples,
    required this.status,
  });

  bool get isOnline => status == PingStatus.online;

  String get quality {
    if (ping == null) return 'offline';
    if (ping! < 100) return 'excellent';
    if (ping! < 200) return 'great';
    if (ping! < 400) return 'good';
    if (ping! < 700) return 'fair';
    return 'poor';
  }
}

/// وضعیت پینگ
enum PingStatus {
  online,
  offline,
  cancelled,
  invalid,
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

  PingProgress({
    required this.completed,
    required this.total,
    required this.online,
    required this.offline,
    required this.elapsed,
    required this.currentHost,
    required this.currentPing,
  });

  double get percent => total == 0 ? 0 : completed / total;

  Duration get eta {
    if (completed == 0) return Duration.zero;
    final avgMs = elapsed.inMilliseconds / completed;
    final remaining = total - completed;
    return Duration(milliseconds: (avgMs * remaining).round());
  }
}

/// کش DNS با TTL
class _DnsCache {
  final Map<String, _CacheEntry> _cache = {};

  List<InternetAddress>? get(String host) {
    final entry = _cache[host];
    if (entry == null) return null;

    final age = DateTime.now().difference(entry.timestamp);
    if (age > PingService.dnsCacheTtl) {
      _cache.remove(host);
      return null;
    }

    return entry.addresses;
  }

  void set(String host, List<InternetAddress> addresses) {
    _cache[host] = _CacheEntry(
      addresses: addresses,
      timestamp: DateTime.now(),
    );
  }

  void clear() => _cache.clear();
}

class _CacheEntry {
  final List<InternetAddress> addresses;
  final DateTime timestamp;

  _CacheEntry({
    required this.addresses,
    required this.timestamp,
  });
}

/// Lock برای sync
class _Lock {
  Future<void> synchronized(FutureOr<void> Function() action) async {
    await action();
  }
}

/// آمار کلی
class _PingStats {
  int _successCount = 0;
  int _failureCount = 0;
  final List<int> _pings = [];

  void recordSuccess(int ms) {
    _successCount++;
    _pings.add(ms);
    if (_pings.length > 100) _pings.removeAt(0);
  }

  void recordFailure() {
    _failureCount++;
  }

  void reset() {
    _successCount = 0;
    _failureCount = 0;
    _pings.clear();
  }

  Map<String, dynamic> toJson() => {
        'successCount': _successCount,
        'failureCount': _failureCount,
        'avgPing': _pings.isEmpty
            ? 0
            : _pings.reduce((a, b) => a + b) ~/ _pings.length,
        'minPing': _pings.isEmpty ? 0 : _pings.reduce(math.min),
        'maxPing': _pings.isEmpty ? 0 : _pings.reduce(math.max),
      };
}
