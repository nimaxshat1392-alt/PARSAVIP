import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';

/// پینگ دو مرحله‌ای — دقیقاً مثل v2rayNG
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

  /// پاکسازی URI
  static String _sanitizeUri(String uri) {
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

  /// پاکسازی JSON
  static String _cleanJsonConfig(String jsonStr) {
    try {
      final Map<String, dynamic> root =
          jsonDecode(jsonStr) as Map<String, dynamic>;

      void cleanSecurity(Map<String, dynamic> ss) {
        final sec = ss['security'];
        if (sec == null || sec == '' || sec == 'none' || sec == 'None') {
          ss.remove('security');
          ss.remove('tlsSettings');
          ss.remove('realitySettings');
          if (ss['network'] == null || ss['network'] == '') {
            ss['network'] = 'tcp';
          }
        }
      }

      final inbounds = root['inbounds'];
      if (inbounds is List) {
        for (final ib in inbounds) {
          if (ib is Map<String, dynamic>) {
            final ss = ib['streamSettings'];
            if (ss is Map<String, dynamic>) cleanSecurity(ss);
          }
        }
      }

      final outbounds = root['outbounds'];
      if (outbounds is List) {
        for (final ob in outbounds) {
          if (ob is Map<String, dynamic>) {
            final ss = ob['streamSettings'];
            if (ss is Map<String, dynamic>) cleanSecurity(ss);
          }
        }
      }

      return jsonEncode(root);
    } catch (_) {
      return jsonStr;
    }
  }

  /// پینگ Xray
  static Future<int?> _xrayPing(VpnConfig c) async {
    try {
      if (!_initialized) await initialize();
      if (_vless == null) return null;

      final cleanUri = _sanitizeUri(c.rawUri);
      final FlutterVlessURL parsed = FlutterVless.parseFromURL(cleanUri);
      String jsonConfig = parsed.getFullConfiguration();

      // ⭐ پاکسازی JSON
      jsonConfig = _cleanJsonConfig(jsonConfig);

      final int delay = await _vless!
          .getServerDelay(config: jsonConfig, url: testUrl)
          .timeout(const Duration(seconds: 10), onTimeout: () => -1);

      if (delay < 0 || delay >= offlineThreshold || delay > 10000) return null;
      return delay;
    } catch (_) {
      return null;
    }
  }

  /// پینگ TCP
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
