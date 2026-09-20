import 'dart:async';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// سرویس پینگ واقعی از طریق Xray core
/// دقیقاً مثل v2rayNG: یه Xray موقت اجرا می‌کنه و HTTP probe می‌زنه
class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const String testUrl = 'https://www.google.com/generate_204';

  static FlutterVless? _vless;
  static bool _initialized = false;

  /// مقداردهی اولیه core
  static Future<void> initialize() async {
    if (_initialized) return;
    if (_vless == null) {
      _vless = FlutterVless(onStatusChanged: (_) {});
    }
    try {
      await _vless!.initializeVless();
      _initialized = true;
    } catch (_) {}
  }

  /// پینگ واقعی یک سرور از طریق پروکسی
  /// return: میلی‌ثانیه یا null (آفلاین)
  static Future<int?> pingOne(VpnConfig config) async {
    try {
      if (!_initialized) await initialize();
      if (_vless == null) return null;

      // پارس URI به JSON config
      final FlutterVlessURL parsed = FlutterVless.parseFromURL(config.rawUri);
      final String jsonConfig = parsed.getFullConfiguration();

      // اجرای probe از طریق پروکسی
      final int delay = await _vless!.getServerDelay(
        config: jsonConfig,
        url: testUrl,
      );

      // بررسی نتیجه
      if (delay < 0 || delay >= offlineThreshold) return null;
      if (delay > 30000) return null; // بیشتر از ۳۰ ثانیه = آفلاین
      return delay;
    } catch (_) {
      return null;
    }
  }

  /// پینگ همه سرورها به صورت موازی
  /// concurrency پایین‌تر = پایدارتر (چون هر پینگ یه Xray جدا اجرا می‌کنه)
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int concurrency = 4,
    void Function(int done, int total)? onProgress,
  }) async {
    if (configs.isEmpty) return [];

    await initialize();

    final out = <VpnConfig>[];
    int idx = 0;
    int done = 0;

    Future<void> worker() async {
      while (true) {
        final i = idx++;
        if (i >= configs.length) return;
        final c = configs[i];
        final ms = await pingOne(c);
        out.add(VpnConfig(
          id: c.id,
          name: c.name,
          protocol: c.protocol,
          rawUri: c.rawUri,
          host: c.host,
          port: c.port,
          ping: ms ?? offlineThreshold,
        ));
        done++;
        onProgress?.call(done, configs.length);
      }
    }

    final workerCount =
        concurrency < configs.length ? concurrency : configs.length;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    // مرتب‌سازی از سریع‌ترین
    out.sort((a, b) =>
        (a.ping ?? offlineThreshold).compareTo(b.ping ?? offlineThreshold));
    return out;
  }

  /// پیدا کردن بهترین سرور
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
