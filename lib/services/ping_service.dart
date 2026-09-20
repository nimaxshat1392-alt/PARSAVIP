import 'dart:async';
import 'dart:io';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';
import 'xray_config_builder.dart';

/// پینگ دو مرحله‌ای:
/// ۱. Xray ping با config ساخته‌شده دستی (مثل v2rayNG)
/// ۲. اگه Xray fail داد → TCP ping به عنوان fallback
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

  static Future<int?> _xrayPing(VpnConfig c) async {
    try {
      if (!_initialized) await initialize();
      if (_vless == null) return null;

      final jsonConfig = XrayConfigBuilder.build(c);
      final int delay = await _vless!
          .getServerDelay(config: jsonConfig, url: testUrl)
          .timeout(const Duration(seconds: 10), onTimeout: () => -1);

      if (delay < 0 || delay >= offlineThreshold || delay > 10000) return null;
      return delay;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _tcpPing(VpnConfig c) async {
    if (c.host.isEmpty || c.port <= 0) return null;
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        c.host,
        c.port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> pingOne(VpnConfig c) async {
    if (_cancelled) return null;
    final xray = await _xrayPing(c);
    if (xray != null) return xray;
    if (_cancelled) return null;
    return await _tcpPing(c);
  }

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
