import 'dart:io';
import 'dart:async';
import '../models/vpn_config.dart';

/// سرویس پینگ واقعی با اتصال TCP
/// دقیقاً مثل v2rayNG و بقیه کلاینت‌ها: زمان TCP handshake رو اندازه می‌گیره
class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const Duration timeout = Duration(seconds: 3);

  /// پینگ یک سرور (زمان TCP connect)
  static Future<int?> pingOne(VpnConfig config) async {
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

  /// پینگ همه سرورها به صورت موازی
  /// concurrency بالا = سرعت بیشتر، ولی فشار بیشتر روی شبکه
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int concurrency = 20,
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

    // مرتب‌سازی از سریع‌ترین به کندترین
    out.sort((a, b) =>
        (a.ping ?? offlineThreshold).compareTo(b.ping ?? offlineThreshold));
    return out;
  }

  /// پیدا کردن بهترین سرور (کمترین پینگ)
  static VpnConfig? best(List<VpnConfig> configs) {
    if (configs.isEmpty) return null;
    final sorted = [...configs]
      ..sort((a, b) =>
          (a.ping ?? offlineThreshold).compareTo(b.ping ?? offlineThreshold));
    final top = sorted.first;
    if ((top.ping ?? offlineThreshold) >= offlineThreshold) return null;
    return top;
  }

  /// پینگ مداوم یک سرور (برای اتصال زنده)
  static Future<int?> pingRealtime(VpnConfig config) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        config.host,
        config.port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }
}
