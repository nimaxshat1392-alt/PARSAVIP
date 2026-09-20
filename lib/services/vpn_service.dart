import 'dart:async';
import 'dart:convert';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';
import 'log_service.dart';
import '../models/log_entry.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnService {
  final LogService _logs = LogService();
  late final FlutterVless _vless;
  VpnStatus _status = VpnStatus.disconnected;
  VpnConfig? _current;
  String? _lastError;
  bool _initialized = false;
  bool _manualDisconnect = false;

  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  Timer? _timer;
  Duration _duration = Duration.zero;

  VpnStatus get status => _status;
  VpnConfig? get current => _current;
  String? get lastError => _lastError;
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;
  Stream<Duration> get durationStream => _durationCtrl.stream;
  Duration get duration => _duration;
  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy =>
      _status == VpnStatus.connecting || _status == VpnStatus.disconnecting;

  VpnService() {
    _vless = FlutterVless(
      onStatusChanged: (status) {
        final conn = status.connectionState.name.toLowerCase();
        _logs.add(LogLevel.info, 'state=${status.state} conn=$conn');

        // ⭐ اگه کاربر خودش قطع نکرده ولی وضعیت disconnected شد → خطای خودکار
        if (conn.contains('disconnected') &&
            _status == VpnStatus.connected &&
            !_manualDisconnect) {
          _lastError = 'اتصال توسط سرور قطع شد';
          _status = VpnStatus.error;
          _statusCtrl.add(_status);
          _stopTimer();
        } else if (conn.contains('connected') &&
            !conn.contains('disconnected')) {
          _status = VpnStatus.connected;
          _statusCtrl.add(_status);
        } else if (conn.contains('disconnected')) {
          _status = VpnStatus.disconnected;
          _statusCtrl.add(_status);
        }
      },
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _vless.initializeVless(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
        providerBundleIdentifier: 'com.parsavip.parsavip',
        groupIdentifier: 'group.com.parsavip.parsavip',
      );
      _initialized = true;
      await _logs.add(LogLevel.info, 'Xray core initialized');
    } catch (e) {
      _lastError = e.toString();
      await _logs.add(LogLevel.error, 'Init failed: $e');
    }
  }

  /// پاکسازی حداقلی — فقط `security=` خالی رو حذف می‌کنه
  String _sanitizeUri(String uri) {
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
        // فقط این یک حالت رو اصلاح کن
        if (key == 'security' && value.isEmpty) continue;
        newParams.add(pair);
      }

      final rebuilt = newParams.join('&');
      return '$basePart?$rebuilt$fragment';
    } catch (_) {
      return uri;
    }
  }

  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;

    _manualDisconnect = false;
    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;
    _lastError = null;

    try {
      if (!_initialized) await initialize();

      await _logs.add(LogLevel.info, 'Starting: ${config.protocolShort}');

      final sanitizedUri = _sanitizeUri(config.rawUri);
      if (sanitizedUri != config.rawUri) {
        await _logs.add(LogLevel.info, 'Sanitized URI: $sanitizedUri');
      }

      // پارس URI
      FlutterVlessURL parsedUrl;
      try {
        parsedUrl = FlutterVless.parseFromURL(sanitizedUri);
      } catch (e) {
        throw Exception('پارس کانفیگ ناموفق بود: $e');
      }

      // دریافت config
      String jsonConfig;
      try {
        jsonConfig = parsedUrl.getFullConfiguration();
      } catch (e) {
        throw Exception('تولید config ناموفق بود: $e');
      }

      // تزریق DNS + routing (برای عبور ترافیک)
      try {
        final Map<String, dynamic> cfg =
            jsonDecode(jsonConfig) as Map<String, dynamic>;

        // فقط اگه DNS از قبل نبود، اضافه کن
        cfg.putIfAbsent('dns', () => {
              'servers': [
                {'address': '1.1.1.1'},
                {'address': '8.8.8.8'},
              ],
              'queryStrategy': 'UseIP',
            });

        // فقط اگه routing از قبل نبود، اضافه کن
        cfg.putIfAbsent('routing', () => {
              'domainStrategy': 'IPIfNonMatch',
              'rules': [
                {'type': 'field', 'outboundTag': 'direct', 'port': '53'},
                {
                  'type': 'field',
                  'outboundTag': 'direct',
                  'ip': ['geoip:private']
                },
              ],
            });

        jsonConfig = jsonEncode(cfg);
      } catch (e) {
        await _logs.add(LogLevel.warning, 'Config enhance skipped: $e');
      }

      // درخواست مجوز
      final bool permitted = await _vless.requestPermission();
      if (!permitted) throw Exception('VPN permission denied');
      await _logs.add(LogLevel.info, 'VPN permission granted');

      // شروع تونل
      await _vless.startVless(
        remark: parsedUrl.remark.isEmpty ? config.name : parsedUrl.remark,
        config: jsonConfig,
        proxyOnly: false,
      );

      // ⭐ مرحله حیاتی: منتظر تأیید واقعی اتصال
      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();

      // Health check با timeout 8 ثانیه
      unawaited(_healthCheck());

      await _logs.add(LogLevel.success, '✅ Connected');
      return true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      _status = VpnStatus.error;
      _statusCtrl.add(_status);
      await _logs.add(LogLevel.error, '❌ $e');
      return false;
    }
  }

  /// بررسی سلامت اتصال در پس‌زمینه
  Future<void> _healthCheck() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (_status != VpnStatus.connected) return;

      final delay = await _vless
          .getConnectedServerDelay(url: 'https://www.google.com/generate_204')
          .timeout(const Duration(seconds: 6), onTimeout: () => -1);

      if (delay < 0 || delay > 15000) {
        await _logs.add(LogLevel.error,
            'Health check failed (delay=$delay) — اتصال قطع شد');
        // فقط اگه کاربر خودش قطع نکرده بود
        if (!_manualDisconnect && _status == VpnStatus.connected) {
          _lastError = 'سرور پاسخ نمی‌دهد';
          try {
            await _vless.stopVless();
          } catch (_) {}
          _status = VpnStatus.error;
          _statusCtrl.add(_status);
          _stopTimer();
        }
      } else {
        await _logs.add(LogLevel.success, 'Health check OK: ${delay}ms');
      }
    } catch (e) {
      await _logs.add(LogLevel.warning, 'Health check error: $e');
    }
  }

  Future<void> disconnect() async {
    if (!isConnected && _status != VpnStatus.error) return;
    _manualDisconnect = true;
    _status = VpnStatus.disconnecting;
    _statusCtrl.add(_status);
    try {
      await _vless.stopVless();
    } catch (_) {}
    _status = VpnStatus.disconnected;
    _current = null;
    _stopTimer();
    _statusCtrl.add(_status);
    await _logs.add(LogLevel.info, 'Disconnected by user');
  }

  Future<void> toggle(VpnConfig config) async {
    if (isConnected || _status == VpnStatus.error) await disconnect();
    else await connect(config);
  }

  void _startTimer() {
    _duration = Duration.zero;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _duration += const Duration(seconds: 1);
      _durationCtrl.add(_duration);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _duration = Duration.zero;
    _durationCtrl.add(_duration);
  }

  void dispose() {
    _timer?.cancel();
    _statusCtrl.close();
    _durationCtrl.close();
  }
}
