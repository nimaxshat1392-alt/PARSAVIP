import 'dart:async';
import 'dart:io';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// سرویس پینگ پیشرفته دو مرحله‌ای (مثل v2rayNG):
/// مرحله ۱: TCP scan موازی و سریع برای فیلتر سرورهای خاموش
/// مرحله ۲: پینگ واقعی از طریق پروکسی (Xray probe) برای سرورهای آنلاین
class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const String realPingUrl = 'https://www.google.com/generate_204';

  static FlutterVless? _vless;
  static bool _initialized = false;
  static bool _cancelled = false;

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

  static void cancel() {
    _cancelled = true;
  }

  /// مرحله ۱: پینگ TCP سریع
  static Future<int?> _tcpPing(VpnConfig config, Duration timeout) async {
    if (config.host.isEmpty || config.port <= 0) return null;
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        config.host,
        config.port,
        timeout: timeout,
      );
      socket.destroy();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// مرحله ۲: پینگ واقعی از پروکسی
  static Future<int?> _realPing(VpnConfig config, Duration timeout) async {
    if (_cancelled) return null;
    try {
      if (!_initialized) await initialize();
      if (_vless == null) return null;

      final FlutterVlessURL parsed = FlutterVless.parseFromURL(config.rawUri);
      final String jsonConfig = parsed.getFullConfiguration();

      final int delay = await _vless!
          .getServerDelay(config: jsonConfig, url: realPingUrl)
          .timeout(timeout, onTimeout: () => -1);

      if (delay < 0 || delay >= offlineThreshold) return null;
      if (delay > 15000) return null;
      return delay;
    } catch (_) {
      return null;
    }
  }

  /// پینگ همه سرورها — دو مرحله‌ای
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int tcpConcurrency = 24,
    int realConcurrency = 3,
    Duration tcpTimeout = const Duration(seconds: 2),
    Duration realTimeout = const Duration(seconds: 8),
    void Function(int done, int total)? onProgress,
  }) async {
    if (configs.isEmpty) return [];
    _cancelled = false;
    await initialize();

    final total = configs.length;
    final tcpResults = <String, int?>{};
    int tcpDone = 0;

    // ═══════ مرحله ۱: TCP scan موازی ═══════
    int tcpIdx = 0;
    Future<void> tcpWorker() async {
      while (true) {
        if (_cancelled) return;
        final i = tcpIdx++;
        if (i >= configs.length) return;
        final c = configs[i];
        final ms = await _tcpPing(c, tcpTimeout);
        tcpResults[c.id] = ms;
        tcpDone++;
        onProgress?.call(tcpDone, total * 2);
      }
    }

    final tcpWorkerCount =
        tcpConcurrency < configs.length ? tcpConcurrency : configs.length;
    await Future.wait(List.generate(tcpWorkerCount, (_) => tcpWorker()));

    if (_cancelled) {
      return configs;
    }

    // ═══════ مرحله ۲: Real ping فقط برای آنلاین‌ها ═══════
    final results = <VpnConfig>[];

    // آفلاین‌ها مستقیم
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

    // آنلاین‌ها با پینگ واقعی
    final alive = configs.where((c) => tcpResults[c.id] != null).toList();
    int realIdx = 0;
    int realDone = 0;

    Future<void> realWorker() async {
      while (true) {
        if (_cancelled) return;
        final i = realIdx++;
        if (i >= alive.length) return;
        final c = alive[i];
        final ms = await _realPing(c, realTimeout);
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

    final realWorkerCount =
        alive.length < realConcurrency ? alive.length : realConcurrency;
    if (realWorkerCount > 0) {
      await Future.wait(List.generate(realWorkerCount, (_) => realWorker()));
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
