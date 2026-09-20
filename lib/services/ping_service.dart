import 'dart:async';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// پینگ واقعی از طریق Xray core — دقیقاً مثل v2rayNG
/// برای هر سرور، یه Xray موقت با همون کانفیگ اجرا می‌شه
/// و یه HTTP request از پروکسی زده می‌شه
class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const String testUrl = 'https://www.google.com/generate_204';

  static FlutterVless? _vless;
  static bool _initialized = false;
  static bool _cancelled = false;

  /// مقداردهی core (فقط یک بار)
  static Future<void> initialize() async {
    if (_initialized) return;
    _vless ??= FlutterVless(onStatusChanged: (_) {});
    try {
      await _vless!.initializeVless();
      _initialized = true;
    } catch (_) {}
  }

  /// لغو پینگ
  static void cancel() {
    _cancelled = true;
  }

  static void reset() {
    _cancelled = false;
  }

  /// ⭐ پینگ واقعی از پروکسی (مثل v2rayNG)
  static Future<int?> pingOne(VpnConfig config) async {
    if (_cancelled) return null;
    if (config.host.isEmpty || config.port <= 0) return null;

    try {
      if (!_initialized) await initialize();
      if (_vless == null) return null;

      // پارس URI
      final FlutterVlessURL parsed = FlutterVless.parseFromURL(config.rawUri);
      final String jsonConfig = parsed.getFullConfiguration();

      // ⭐ پینگ واقعی از طریق Xray — دقیقاً مثل v2rayNG
      final int delay = await _vless!
          .getServerDelay(
            config: jsonConfig,
            url: testUrl,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => -1,
          );

      if (delay < 0 || delay >= offlineThreshold) return null;
      if (delay > 10000) return null;
      return delay;
    } catch (_) {
      return null;
    }
  }

  /// پینگ همه سرورها — دقیقاً مثل v2rayNG (concurrency ۲)
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

    final workerCount =
        concurrency < total ? concurrency : total;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    // آفلاین‌هایی که cancel شدن هم اضافه کن
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
