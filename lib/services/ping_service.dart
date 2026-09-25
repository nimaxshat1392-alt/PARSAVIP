import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// ═══════════════════════════════════════════════════════════
/// موتور پینگ Xray — مثل v2rayNG
/// ═══════════════════════════════════════════════════════════
///
/// ویژگی‌ها:
/// - Xray ping (getServerDelay) + TCP fallback
/// - رد کردن پینگ‌های جعلی (< 15ms)
/// - تلاش مجدد در صورت خطا
/// - Timeout سختگیرانه
/// - DNS cache
/// - Concurrency محدود برای پایداری
class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const int maxValidPing = 20000;
  static const int minValidPing = 15; // کمتر از این = جعلی

  static const String testUrl = 'https://www.google.com/generate_204';
  static const Duration xrayTimeout = Duration(seconds: 10);
  static const Duration tcpTimeout = Duration(seconds: 4);
  static const Duration dnsTimeout = Duration(seconds: 3);
  static const Duration retryDelay = Duration(milliseconds: 300);
  static const int maxAttempts = 2;

  static FlutterVless? _vless;
  static bool _initialized = false;
  static bool _cancelled = false;
  static final Map<String, List<InternetAddress>> _dnsCache = {};

  // ═══════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════

  static void cancel() => _cancelled = true;
  static void reset() {
    _cancelled = false;
  }
  static void clearDnsCache() => _dnsCache.clear();

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

  /// ⭐ پینگ یک سرور
  static Future<int?> pingOne(VpnConfig config) async {
    if (_cancelled) return null;
    if (config.host.isEmpty || config.port <= 0) return null;

    // ⭐ اول Xray ping
    final xrayPing = await _tryXrayPing(config);
    if (xrayPing != null) return xrayPing;

    if (_cancelled) return null;

    // ⭐ اگه Xray fail شد → TCP ping
    final tcpPing = await _tryTcpPing(config);
    return tcpPing;
  }

  /// پینگ همه سرورها
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int concurrency = 4,
    void Function(int done, int total)? onProgress,
  }) async {
    if (configs.isEmpty) return [];
    reset();
    await initialize();

    final results = List<VpnConfig>.from(configs);
    final total = configs.length;
    int nextIndex = 0;
    int completed = 0;

    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;
        final int i = nextIndex;
        if (i >= total) return;
        nextIndex = i + 1;

        final config = configs[i];
        final ms = await pingOne(config);

        results[i] = VpnConfig(
          id: config.id,
          name: config.name,
          protocol: config.protocol,
          rawUri: config.rawUri,
          host: config.host,
          port: config.port,
          ping: ms ?? offlineThreshold,
        );

        completed++;
        onProgress?.call(completed, total);
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

  /// ⭐ پینگ Xray با retry
  static Future<int?> _tryXrayPing(VpnConfig config) async {
    if (_vless == null) return null;

    String? jsonConfig;

    // آماده‌سازی config
    try {
      final cleanUri = _sanitizeUri(config.rawUri);
      final parsed = FlutterVless.parseFromURL(cleanUri);
      jsonConfig = parsed.getFullConfiguration();
    } catch (_) {
      return null;
    }

    // تلاش چند باره
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_cancelled) return null;

      try {
        final int delay = await _vless!
            .getServerDelay(
              config: jsonConfig,
              url: testUrl,
            )
            .timeout(
              xrayTimeout,
              onTimeout: () => -1,
            );

        if (_cancelled) return null;

        // ⭐ اعتبارسنجی: جعلی رد
        if (delay < minValidPing) {
          // عدد جعلی — باز تلاش کن
          if (attempt < maxAttempts - 1) {
            await Future.delayed(retryDelay);
            continue;
          }
          return null;
        }

        if (delay > maxValidPing) {
          if (attempt < maxAttempts - 1) {
            await Future.delayed(retryDelay);
            continue;
          }
          return null;
        }

        // ⭐ پینگ معتبر
        return delay;
      } catch (_) {
        if (attempt < maxAttempts - 1) {
          await Future.delayed(retryDelay);
        }
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // Internal — TCP Ping (fallback)
  // ═══════════════════════════════════════════════════════════

  /// ⭐ TCP ping با DNS cache
  static Future<int?> _tryTcpPing(VpnConfig config) async {
    if (_cancelled) return null;

    try {
      // DNS resolve
      final addresses = await _resolveDns(config.host);
      if (addresses == null || addresses.isEmpty) return null;

      // TCP connect
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        addresses.first.address,
        config.port,
        timeout: tcpTimeout,
      );
      socket.destroy();
      sw.stop();

      final ms = sw.elapsedMilliseconds;

      // ⭐ اعتبارسنجی
      if (ms < minValidPing) return null;
      if (ms > maxValidPing) return null;

      return ms;
    } catch (_) {
      return null;
    }
  }

  /// DNS resolve با cache
  static Future<List<InternetAddress>?> _resolveDns(String host) async {
    final cached = _dnsCache[host];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final addrs = await InternetAddress.lookup(host).timeout(dnsTimeout);
      if (addrs.isNotEmpty) {
        _dnsCache[host] = addrs;
        return addrs;
      }
    } catch (_) {}
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // URI Sanitizer
  // ═══════════════════════════════════════════════════════════

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
