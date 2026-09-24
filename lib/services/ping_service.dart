import 'dart:async';
import 'dart:io';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// ═══════════════════════════════════════════════════════════
/// موتور پینگ Xray — با اعتبارسنجی دقیق
/// ═══════════════════════════════════════════════════════════
///
/// استراتژی:
/// ۱. getServerDelay (Xray ping) — مثل v2rayNG
/// ۲. اعتبارسنجی: اگه < 20ms یا > 15000ms بود → رد
/// ۳. اگه Xray fail داد → TCP fallback
/// ۴. انتخاب بهترین نتیجه
class PingService {
  PingService._();

  // ═══════════════════════════════════════════════════════════
  // تنظیمات
  // ═══════════════════════════════════════════════════════════

  static const int offlineThreshold = 9999;
  static const int maxValidPing = 15000;
  static const int minValidPing = 20; // ⭐ کمتر از این = جعلی

  static const String testUrl = 'https://www.google.com/generate_204';

  static const Duration xrayTimeout = Duration(seconds: 12);
  static const Duration tcpTimeout = Duration(seconds: 4);
  static const Duration dnsTimeout = Duration(seconds: 3);

  static const int sampleCount = 2;
  static const Duration sampleDelay = Duration(milliseconds: 150);

  // ═══════════════════════════════════════════════════════════
  // State
  // ═══════════════════════════════════════════════════════════

  static FlutterVless? _vless;
  static bool _initialized = false;
  static bool _cancelled = false;
  static final _PingStats _stats = _PingStats();
  static final Map<String, List<InternetAddress>> _dnsCache = {};

  // ═══════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════

  static void cancel() => _cancelled = true;

  static void reset() {
    _cancelled = false;
    _stats.reset();
  }

  static Map<String, dynamic> getGlobalStats() => _stats.toJson();

  static Future<void> initialize() async {
    if (_initialized) return;
    _vless ??= FlutterVless(onStatusChanged: (_) {});
    try {
      await _vless!.initializeVless(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
      _initialized = true;
    } catch (_) {}
  }

  /// ⭐ پینگ کامل یک سرور
  static Future<PingResult> pingDetailed(VpnConfig config) async {
    if (_cancelled) {
      return PingResult(
        config: config,
        ping: null,
        samples: const [],
        status: PingStatus.cancelled,
      );
    }

    if (config.host.isEmpty || config.port <= 0) {
      return PingResult(
        config: config,
        ping: null,
        samples: const [],
        status: PingStatus.invalid,
      );
    }

    final samples = <int>[];

    // ⭐ مرحله ۱: Xray ping
    for (var i = 0; i < sampleCount; i++) {
      if (_cancelled) break;

      final ms = await _xrayPing(config);

      if (ms != null) {
        samples.add(ms);
      }

      if (i == 0 && ms == null) break;

      if (i < sampleCount - 1) {
        await Future.delayed(sampleDelay);
      }
    }

    // ⭐ مرحله ۲: اگه Xray fail داد → TCP fallback
    if (samples.isEmpty) {
      final tcpMs = await _tcpPing(config);
      if (tcpMs != null) samples.add(tcpMs);
    }

    if (samples.isEmpty) {
      _stats.recordFailure();
      return PingResult(
        config: config,
        ping: null,
        samples: const [],
        status: PingStatus.offline,
      );
    }

    // Median
    final sorted = [...samples]..sort();
    final median = sorted[sorted.length ~/ 2];

    _stats.recordSuccess(median);

    return PingResult(
      config: config,
      ping: median,
      samples: samples,
      status: PingStatus.online,
    );
  }

  static Future<int?> pingOne(VpnConfig config) async {
    final result = await pingDetailed(config);
    return result.ping;
  }

  /// پینگ همه — موازی
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

        final int currentIndex = nextIndex;
        if (currentIndex >= total) return;
        nextIndex = currentIndex + 1;

        final config = configs[currentIndex];
        final result = await pingDetailed(config);

        if (result.status == PingStatus.online && result.ping != null) {
          results[currentIndex] = VpnConfig(
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
          results[currentIndex] = VpnConfig(
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

    results.sort((a, b) =>
        (a.ping ?? offlineThreshold).compareTo(b.ping ?? offlineThreshold));

    return results;
  }

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
  // Internal — Xray Ping
  // ═══════════════════════════════════════════════════════════

  /// ⭐ Xray ping با اعتبارسنجی
  static Future<int?> _xrayPing(VpnConfig config) async {
    if (_cancelled) return null;
    if (_vless == null) return null;

    try {
      final cleanUri = _sanitizeUri(config.rawUri);

      final FlutterVlessURL parsed;
      try {
        parsed = FlutterVless.parseFromURL(cleanUri);
      } catch (_) {
        return null;
      }

      final String jsonConfig;
      try {
        jsonConfig = parsed.getFullConfiguration();
      } catch (_) {
        return null;
      }

      final int delay = await _vless!
          .getServerDelay(
            config: jsonConfig,
            url: testUrl,
          )
          .timeout(xrayTimeout, onTimeout: () => -1);

      if (_cancelled) return null;

      // ⭐ اعتبارسنجی: مقادیر جعلی رد می‌شن
      if (delay < minValidPing) return null; // ۲-۳ms = جعلی
      if (delay > maxValidPing) return null;
      if (delay >= offlineThreshold) return null;

      return delay;
    } catch (_) {
      return null;
    }
  }

  /// حذف پارامترهای مشکل‌دار
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

        if (key == 'security' && (value.isEmpty || value == 'none')) {
          continue;
        }
        if (value.isEmpty) continue;

        newParams.add(pair);
      }

      return '$basePart?${newParams.join('&')}$fragment';
    } catch (_) {
      return uri;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Fallback — TCP
  // ═══════════════════════════════════════════════════════════

  static Future<int?> _tcpPing(VpnConfig config) async {
    try {
      List<InternetAddress>? addresses = _dnsCache[config.host];
      addresses ??= await InternetAddress.lookup(config.host)
          .timeout(dnsTimeout);
      if (addresses.isEmpty) return null;
      _dnsCache[config.host] = addresses;

      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        addresses.first.address,
        config.port,
        timeout: tcpTimeout,
      );
      socket.destroy();
      sw.stop();

      final ms = sw.elapsedMilliseconds;
      if (ms < minValidPing) return null; // چک نهایی
      if (ms > maxValidPing) return null;
      return ms;
    } catch (_) {
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Data Classes
// ═══════════════════════════════════════════════════════════

class PingResult {
  final VpnConfig config;
  final int? ping;
  final List<int> samples;
  final PingStatus status;

  PingResult({
    required this.config,
    required this.ping,
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

enum PingStatus { online, offline, cancelled, invalid }

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

class _PingStats {
  int _successCount = 0;
  int _failureCount = 0;
  final List<int> _pings = [];

  void recordSuccess(int ms) {
    _successCount++;
    _pings.add(ms);
    if (_pings.length > 100) _pings.removeAt(0);
  }

  void recordFailure() => _failureCount++;

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
      };
}
