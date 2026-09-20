import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
        _logs.add(LogLevel.info,
            'state=${status.state} conn=${status.connectionState.name}');
        if (status.connectionState.name.contains('connected') &&
            !status.connectionState.name.contains('disconnected')) {
          _status = VpnStatus.connected;
          _statusCtrl.add(_status);
        } else if (status.connectionState.name.contains('disconnected')) {
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

  /// ⭐ پاکسازی URI از پارامترهای خالی یا ناقص
  String _sanitizeUri(String uri) {
    try {
      // جدا کردن fragment (#remark)
      final hashIndex = uri.indexOf('#');
      String mainPart = hashIndex >= 0 ? uri.substring(0, hashIndex) : uri;
      String fragment = hashIndex >= 0 ? uri.substring(hashIndex) : '';

      // جدا کردن query params
      final qIndex = mainPart.indexOf('?');
      if (qIndex < 0) return uri;

      String basePart = mainPart.substring(0, qIndex);
      String queryPart = mainPart.substring(qIndex + 1);

      // پارس query params
      final params = <String, String>{};
      for (final pair in queryPart.split('&')) {
        final eqIndex = pair.indexOf('=');
        if (eqIndex < 0) continue;
        final key = pair.substring(0, eqIndex);
        final value = pair.substring(eqIndex + 1);
        // اگه مقدار خالی بود، رد کن
        if (value.isEmpty) continue;
        params[key] = value;
      }

      // ⭐ اگه security نداریم، مقدار پیش‌فرض 'none' بذار
      if (!params.containsKey('security')) {
        params['security'] = 'none';
      }

      // ⭐ اگه fp داریم ولی TLS نیست، fp رو حذف کن
      final security = params['security'];
      if (security != 'tls' && security != 'reality') {
        params.remove('fp');
        params.remove('sni');
        params.remove('alpn');
        params.remove('allowInsecure');
      }

      // بازسازی URI
      final rebuilt = params.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&');

      return '$basePart?$rebuilt$fragment';
    } catch (e) {
      return uri;
    }
  }

  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;

    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;
    _lastError = null;

    try {
      if (!_initialized) await initialize();

      await _logs.add(LogLevel.info, 'Starting: ${config.protocolShort}');

      // ⭐ پاکسازی URI
      final sanitizedUri = _sanitizeUri(config.rawUri);
      await _logs.add(LogLevel.info, 'Sanitized URI: $sanitizedUri');

      // ⭐ پارس URI
      final FlutterVlessURL parsedUrl = FlutterVless.parseFromURL(sanitizedUri);

      // ⭐ دریافت config JSON
      String jsonConfig = parsedUrl.getFullConfiguration();
      await _logs.add(LogLevel.info, 'Parsed config OK');

      // ⭐ تزریق DNS + routing
      try {
        final Map<String, dynamic> cfg =
            jsonDecode(jsonConfig) as Map<String, dynamic>;

        cfg['dns'] = {
          'servers': [
            {'address': '1.1.1.1'},
            {'address': '8.8.8.8'},
          ],
          'queryStrategy': 'UseIP',
        };

        cfg['routing'] = {
          'domainStrategy': 'IPIfNonMatch',
          'rules': [
            {'type': 'field', 'outboundTag': 'direct', 'port': '53'},
            {'type': 'field', 'outboundTag': 'direct', 'ip': ['geoip:private']},
          ],
        };

        jsonConfig = jsonEncode(cfg);
        await _logs.add(LogLevel.info, 'Config enhanced with DNS+routing ✅');
      } catch (e) {
        await _logs.add(LogLevel.warning, 'Config enhance failed: $e');
      }

      final bool permitted = await _vless.requestPermission();
      if (!permitted) throw Exception('VPN permission denied');
      await _logs.add(LogLevel.info, 'VPN permission granted');

      await _vless.startVless(
        remark: parsedUrl.remark.isEmpty ? config.name : parsedUrl.remark,
        config: jsonConfig,
        proxyOnly: false,
      );

      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();
      await _logs.add(LogLevel.success, '✅ Connected via Xray');
      return true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      _status = VpnStatus.error;
      _statusCtrl.add(_status);
      await _logs.add(LogLevel.error, '❌ $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (!isConnected) return;
    _status = VpnStatus.disconnecting;
    _statusCtrl.add(_status);
    try {
      await _vless.stopVless();
    } catch (_) {}
    _status = VpnStatus.disconnected;
    _current = null;
    _stopTimer();
    _statusCtrl.add(_status);
    await _logs.add(LogLevel.info, 'Disconnected');
  }

  Future<void> toggle(VpnConfig config) async {
    if (isConnected) await disconnect();
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
