import 'dart:async';
import 'dart:io';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// سرویس پینگ دو مرحله‌ای (مثل v2rayNG):
/// مرحله ۱: TCP scan سریع — فیلتر سرورهای خاموش
/// مرحله ۲: پینگ واقعی از پروکسی — فقط برای سرورهای آنلاین
class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const int tcpTimeoutSec = 2;
  static const String realPingUrl = 'https://www.google.com/generate_204';

  static FlutterVless? _vless;
  static bool _initialized = false;

  /// مقداردهی core
  static Future<void> initialize() async {
    if (_initialized) return;
    _vless ??= FlutterVless(onStatusChanged: (_) {});
    try {
      await _vless!.initializeVless();
      _initialized = true;
    } catch (_) {}
  }

  /// پینگ TCP سریع
  static Future<int?> _tcpPing(VpnConfig config) async {
    if (config.host.isEmpty || config.port <= 0) return null;
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        config.host,
        config.port,
        timeout: Duration(seconds: tcpTimeoutSec),
      );
      socket.destroy();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// پینگ واقعی از طریق پروکسی (مثل v2rayNG)
  static Future<int?> realPing(VpnConfig config) async {
    try {
      if (!_initialized) await initialize();
      if (_vless == null) return null;

      final FlutterVlessURL parsed = FlutterVless.parseFromURL(config.rawUri);
      final String jsonConfig = parsed.getFullConfiguration();

      final int delay = await _vless!.getServerDelay(
        config: jsonConfig,
        url: realPingUrl,
      );

      if (delay < 0 || delay >= offlineThreshold) return null;
      if (delay > 15000) return null;
      return delay;
    } catch (_) {
      return null;
    }
  }

  /// پینگ همه سرورها (دو مرحله‌ای)
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (configs.isEmpty) return [];

    final total = configs.length;

    // ═══ مرحله ۱: TCP scan سریع (concurrency بالا) ═══
    final tcpResults = <String, int?>{};
    int tcpDone = 0;

    Future<void> tcpWorker(List<VpnConfig> batch) async {
      for (final c in batch) {
        final ms = await _tcpPing(c);
        tcpResults[c.id] = ms;
        tcpDone++;
        onProgress?.call(tcpDone, total * 2); // نیمی از کار
      }
    }

    // تقسیم به batch های ۱۶ تایی
    const batchSize = 16;
    final batches = <List<VpnConfig>>[];
    for (var i = 0; i < configs.length; i += batchSize) {
      batches.add(configs.sublist(
        i,
        i + batchSize > configs.length ? configs.length : i + batchSize,
      ));
    }
    await Future.wait(batches.map(tcpWorker));

    // ═══ مرحله ۲: پینگ واقعی فقط برای آنلاین‌ها ═══
    final alive = configs.where((c) => tcpResults[c.id] != null).toList();
    final results = <VpnConfig>[];
    int realDone = 0;

    // اضافه کردن آفلاین‌ها مستقیم
    for (final c in configs) {
      if (tcpResults[c.id] == null) {
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

    // پینگ واقعی با concurrency 4 (چون هر پینگ Xray اجرا می‌کنه)
    int idx = 0;
    Future<void> realWorker() async {
      while (true) {
        final i = idx++;
        if (i >= alive.length) return;
        final c = alive[i];
        final ms = await realPing(c);
        results.add(VpnConfig(
          id: c.id,
          name: c.name,
          protocol: c.protocol,
          rawUri: c.rawUri,
          host: c.host,
          port: c.port,
          ping: ms ?? offlineThreshold,
        ));
        realDone++;
        onProgress?.call(total + realDone, total * 2);
      }
    }

    final realWorkerCount = alive.length < 4 ? alive.length : 4;
    if (realWorkerCount > 0) {
      await Future.wait(List.generate(realWorkerCount, (_) => realWorker()));
    }

    // مرتب‌سازی
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
