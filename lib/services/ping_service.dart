import 'dart:async';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// موتور پینگ Xray — معادل Real Ping در v2rayNG
///
/// استراتژی:
/// - از getServerDelay برای اندازه‌گیری تأخیر واقعی از طریق پروکسی استفاده می‌کند.
/// - مقادیر کمتر از 20ms را به عنوان نتیجه جعلی رد می‌کند.
/// - تا 3 بار برای دریافت یک نتیجه معتبر تلاش می‌کند.
class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const int maxValidPing = 15000;
  static const int minValidPing = 20; // مقدار کمتر از این = جعلی

  static const String testUrl = 'https://www.google.com/generate_204';
  static const Duration pingTimeout = Duration(seconds: 15);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(milliseconds: 500);

  static FlutterVless? _vless;
  static bool _initialized = false;
  static bool _cancelled = false;

  static void cancel() => _cancelled = true;
  static void reset() => _cancelled = false;

  /// مقداردهی اولیه هسته Xray
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

  /// پینگ واقعی Xray برای یک سرور
  static Future<int?> pingOne(VpnConfig config) async {
    if (_cancelled || config.host.isEmpty || config.port <= 0) return null;

    try {
      if (!_initialized) await initialize();
      if (_vless == null) return null;

      final cleanUri = _sanitizeUri(config.rawUri);
      final FlutterVlessURL parsed = FlutterVless.parseFromURL(cleanUri);
      final String jsonConfig = parsed.getFullConfiguration();

      for (var attempt = 0; attempt < maxRetries; attempt++) {
        if (_cancelled) return null;

        try {
          final int delay = await _vless!
              .getServerDelay(config: jsonConfig, url: testUrl)
              .timeout(pingTimeout, onTimeout: () => -1);

          if (_cancelled) return null;

          // اعتبارسنجی نتیجه
          if (delay >= minValidPing && delay <= maxValidPing) {
            return delay;
          }

          if (attempt < maxRetries - 1) {
            await Future.delayed(retryDelay);
          }
        } catch (_) {
          if (attempt < maxRetries - 1) {
            await Future.delayed(retryDelay);
          }
        }
      }
      return null; // همه تلاش‌ها ناموفق
    } catch (_) {
      return null;
    }
  }

  /// پینگ همه سرورها به صورت موازی
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int concurrency = 3,
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

  /// انتخاب بهترین سرور بر اساس کمترین پینگ
  static VpnConfig? best(List<VpnConfig> configs) {
    if (configs.isEmpty) return null;
    final sorted = [...configs]
      ..sort((a, b) =>
          (a.ping ?? offlineThreshold).compareTo(b.ping ?? offlineThreshold));
    final top = sorted.first;
    final ping = top.ping ?? offlineThreshold;
    if (ping >= offlineThreshold || ping > maxValidPing) return null;
    return top;
  }

  /// پاکسازی URI برای جلوگیری از خطا در پارس کردن
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
}
