import 'dart:async';
import 'dart:io';
import '../models/vpn_config.dart';

/// موتور پینگ پیشرفته — مثل v2rayNG
///
/// استراتژی:
/// ۱. کش DNS (resolve یک بار برای همه)
/// ۲. TCP connect موازی با IP کش‌شده
/// ۳. میانگین ۲ نمونه برای دقت
/// ۴. Timeout سختگیرانه (بدون گیر)
/// ۵. Cancel support
class PingService {
  PingService._();

  static const int offlineThreshold = 9999;
  static const int maxValidPing = 5000;
  static const Duration tcpTimeout = Duration(seconds: 4);
  static const Duration dnsTimeout = Duration(seconds: 3);

  static bool _cancelled = false;
  static final Map<String, List<InternetAddress>> _dnsCache = {};

  static void cancel() => _cancelled = true;
  static void reset() {
    _cancelled = false;
    _dnsCache.clear();
  }

  /// Resolve DNS با کش
  static Future<List<InternetAddress>?> _resolveDns(String host) async {
    if (_dnsCache.containsKey(host)) {
      return _dnsCache[host];
    }
    try {
      final addrs = await InternetAddress.lookup(host).timeout(dnsTimeout);
      if (addrs.isNotEmpty) {
        _dnsCache[host] = addrs;
        return addrs;
      }
    } catch (_) {}
    return null;
  }

  /// پینگ یک بار
  static Future<int?> _singlePing(VpnConfig config) async {
    if (config.host.isEmpty || config.port <= 0) return null;

    final addresses = await _resolveDns(config.host);
    if (addresses == null || addresses.isEmpty) return null;

    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        addresses.first.address,
        config.port,
        timeout: tcpTimeout,
      );
      socket.destroy();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// پینگ دقیق — میانگین ۲ نمونه
  static Future<int?> pingOne(VpnConfig config) async {
    if (_cancelled) return null;

    final first = await _singlePing(config);
    if (first == null) return null;
    if (_cancelled) return null;

    final second = await _singlePing(config);
    final result = second == null ? first : (first + second) ~/ 2;

    if (result > maxValidPing) return null;
    return result;
  }

  /// پینگ همه — موازی با concurrency قابل تنظیم
  static Future<List<VpnConfig>> pingAll(
    List<VpnConfig> configs, {
    int concurrency = 12,
    void Function(int done, int total)? onProgress,
  }) async {
    if (configs.isEmpty) return [];
    reset();

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

    // اضافه کردن باقی‌مانده‌ها اگه cancel شد
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
    if ((top.ping ?? offlineThreshold) > maxValidPing) return null;
    return top;
  }
}
