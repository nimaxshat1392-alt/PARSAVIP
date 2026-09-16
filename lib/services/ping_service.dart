import 'dart:io';
import 'dart:async';
import '../models/vpn_config.dart';

class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const Duration timeout = Duration(seconds: 3);

  /// اندازه‌گیری زمان اتصال TCP به host:port
  static Future<int?> pingOne(VpnConfig config) async {
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

  /// پینگ همه کانفیگ‌ها به صورت موازی با محدودیت همزمانی
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int concurrency = 8,
    void Function(int done, int total)? onProgress,
  }) async {
    if (configs.isEmpty) return [];

    final out = <VpnConfig>[];
    int idx = 0;
    int done = 0;

    Future<void> worker() async {
      while (true) {
        final i = idx++;
        if (i >= configs.length) return;
        final c = configs[i];
        final ms = await pingOne(c);
        out.add(
          VpnConfig(
            id: c.id,
            name: c.name,
            protocol: c.protocol,
            rawUri: c.rawUri,
            host: c.host,
            port: c.port,
            ping: ms ?? offlineThreshold,
          ),
        );
        done++;
        onProgress?.call(done, configs.length);
      }
    }

    final workerCount =
        concurrency < configs.length ? concurrency : configs.length;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    out.sort(
      (a, b) => (a.ping ?? offlineThreshold)
          .compareTo(b.ping ?? offlineThreshold),
    );
    return out;
  }

  /// بهترین سرور (کمترین پینگ)
  static VpnConfig? best(List<VpnConfig> configs) {
    if (configs.isEmpty) return null;
    final sorted = [...configs]
      ..sort((a, b) => (a.ping ?? offlineThreshold)
          .compareTo(b.ping ?? offlineThreshold));
    final top = sorted.first;
    if ((top.ping ?? offlineThreshold) >= offlineThreshold) return null;
    return top;
  }

  /// رنگ بر اساس کیفیت پینگ
  static String quality(int? ms) {
    if (ms == null || ms >= offlineThreshold) return 'offline';
    if (ms < 150) return 'great';
    if (ms < 350) return 'good';
    if (ms < 700) return 'ok';
    return 'bad';
  }
}
