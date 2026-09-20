import 'dart:async';
import 'dart:io';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// پینگ دو روشی:
/// ۱. اول Xray ping (مثل v2rayNG) — دقیق
/// ۲. اگه Xray fail داد → TCP ping (fallback)
class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const String testUrl = 'https://www.google.com/generate_204';

  static FlutterVless? _vless;
  static bool _initialized = false;
  static bool _cancelled = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _vless ??= FlutterVless(onStatusChanged: (_) {});
    try {
      await _vless!.initializeVless();
      _initialized = true;
    } catch (_) {}
  }

  static void cancel() => _cancelled = true;
  static void reset() => _cancelled = false;

  /// ⭐ پاکسازی کامل URI — حذف `security=none`، `security=` خالی و پارامترهای خالی
  static String sanitizeUri(String uri) {
    try {
      final hashIndex = uri.indexOf('#');
      String mainPart = hashIndex >= 0 ? uri.substring(0, hashIndex) : uri;
      String fragment = hashIndex >= 0 ? uri.substring(hashIndex) : '';

      final qIndex = mainPart.indexOf('?');
      if (qIndex < 0) return uri;

      String basePart = mainPart.substring(0, qIndex);
      String queryPart = mainPart.substring(qIndex + 1);

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

        // ⭐ حذف همه حالت‌های `security` که Xray قبول نمی‌کنه
        if (key == 'security') {
          if (value.isEmpty || value == 'none') continue;
        }

        // حذف پارامترهای خالی
        if (value.isEmpty) continue;

        newParams.add(pair);
      }

      return '$basePart?${newParams.join('&')}$fragment';
    } catch (_) {
      return uri;
    }
  }

  /// پینگ Xray (مثل v2rayNG)
  static Future<int?> _xrayPing(VpnConfig config) async {
    try {
      if (!_initialized) await initialize();
      if (_vless == null) return null;

      // ⭐ کانفیگ رو با sanitizer آماده کن
      final cleanUri = sanitizeUri(config.rawUri);
      final FlutterVlessURL parsed = FlutterVless.parseFromURL(cleanUri);
      final String jsonConfig = parsed.getFullConfiguration();

      final int delay = await _vless!
          .getServerDelay(config: jsonConfig, url: testUrl)
          .timeout(const Duration(seconds: 12), onTimeout: () => -1);

      if (delay < 0 || delay >= offlineThreshold || delay > 10000) return null;
      return delay;
    } catch (_) {
      return null;
    }
  }

  /// پینگ TCP (fallback)
  static Future<int?> _tcpPing(VpnConfig config) async {
    if (config.host.isEmpty || config.port <= 0) return null;
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        config.host,
        config.port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// پینگ یک سرور: اول Xray، اگه fail داد TCP
  static Future<int?> pingOne(VpnConfig config) async {
    if (_cancelled) return null;

    // ۱. Xray ping
    final xrayMs = await _xrayPing(config);
    if (xrayMs != null) return xrayMs;

    if (_cancelled) return null;

    // ۲. Fallback به TCP
    return await _tcpPing(config);
  }

  /// پینگ همه سرورها
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int concurrency = 2,
    void Function(int done, int total)? onProgress,
  }) async {
    if (configs.isEmpty) return [];
    reset();
    await initialize();

    final results = <VpnConfig>[];
    final total = configs.length;
    int idx = 0;
    int done = 0;

    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;
        final i = idx++;
        if (i >= total) return;
        final c = configs[i];
        final ms = await pingOne(c);
        results.add(VpnConfig(
          id: c.id,
          name: c.name,
          protocol: c.protocol,
          rawUri: c.rawUri,
          host: c.host,
          port: c.port,
          ping: ms ?? offlineThreshold,
        ));
        done++;
        onProgress?.call(done, total);
      }
    }

    final wc = concurrency < total ? concurrency : total;
    await Future.wait(List.generate(wc, (_) => worker()));

    if (results.length < total) {
      final doneIds = results.map((c) => c.id).toSet();
      for (final c in configs) {
        if (!doneIds.contains(c.id)) {
          results.add(VpnConfig(
            id: c.id,
            name: c.name,
            protocol: c.protocol,
            rawUri: c.rawUri,
            host: c.host,
            port: c.port,
            ping: offlineThreshold,
          ));
        }
      }
    }

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
    if ((top.ping ?? offlineThreshold) >= offlineThreshold) return null;
    return top;
  }
}
