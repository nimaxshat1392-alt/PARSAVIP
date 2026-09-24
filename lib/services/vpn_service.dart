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

        if (conn.contains('connected') && !conn.contains('disconnected')) {
          if (_status != VpnStatus.connected) {
            _status = VpnStatus.connected;
            _statusCtrl.add(_status);
            if (_timer == null) _startTimer();
          }
        } else if (conn.contains('disconnected')) {
          if (!_manualDisconnect && _status == VpnStatus.connected) {
            _lastError = 'اتصال قطع شد';
            _status = VpnStatus.error;
            _statusCtrl.add(_status);
            _stopTimer();
          } else if (_status != VpnStatus.disconnecting) {
            _status = VpnStatus.disconnected;
            _statusCtrl.add(_status);
            _stopTimer();
          }
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

  /// پاکسازی URI — حذف security=none، fp بدون TLS، پارامترهای خالی
  String _sanitizeUri(String uri) {
    try {
      final hashIndex = uri.indexOf('#');
      String mainPart = hashIndex >= 0 ? uri.substring(0, hashIndex) : uri;
      String fragment = hashIndex >= 0 ? uri.substring(hashIndex) : '';

      final qIndex = mainPart.indexOf('?');
      if (qIndex < 0) return uri;

      String basePart = mainPart.substring(0, qIndex);
      String queryPart = mainPart.substring(qIndex + 1);

      final params = <String, String>{};
      for (final pair in queryPart.split('&')) {
        if (pair.isEmpty) continue;
        final eqIndex = pair.indexOf('=');
        if (eqIndex < 0) continue;
        final key = pair.substring(0, eqIndex);
        final value = pair.substring(eqIndex + 1);
        if (value.isEmpty) continue;
        params[key] = value;
      }

      // security=none یا خالی → حذف کامل
      final sec = params['security'];
      if (sec == null || sec.isEmpty || sec == 'none') {
        params.remove('security');
        params.remove('fp');
        params.remove('sni');
        params.remove('alpn');
        params.remove('allowInsecure');
        params.remove('pbk');
        params.remove('sid');
        params.remove('spx');
      }

      // حذف پارامترهای خالی
      params.removeWhere((k, v) => v.isEmpty);

      final rebuilt = params.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&');

      return '$basePart?$rebuilt$fragment';
    } catch (_) {
      return uri;
    }
  }

  /// تزریق DNS + routing
  String _enhanceConfig(String jsonStr) {
    try {
      final Map<String, dynamic> root =
          jsonDecode(jsonStr) as Map<String, dynamic>;

      // ۱. پاکسازی security:none
      void cleanSecurity(Map<String, dynamic> ss) {
        final sec = ss['security'];
        if (sec == null || sec == '' || sec == 'none') {
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

      // ۲. تزریق DNS
      root['dns'] = {
        'servers': [
          {'address': '1.1.1.1', 'domains': []},
          {'address': '8.8.8.8', 'domains': []},
        ],
        'queryStrategy': 'UseIPv4',
        'disableFallback': false,
      };

      // ۳. تزریق routing
      root['routing'] = {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {'type': 'field', 'outboundTag': 'direct', 'port': '53'},
          {
            'type': 'field',
            'outboundTag': 'direct',
            'ip': ['geoip:private']
          },
        ],
      };

      return jsonEncode(root);
    } catch (e) {
      return jsonStr;
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

      // ۱. پاکسازی
      final cleanUri = _sanitizeUri(config.rawUri);

      // ۲. پارس
      final FlutterVlessURL parsedUrl = FlutterVless.parseFromURL(cleanUri);
      String jsonConfig = parsedUrl.getFullConfiguration();

      // ۳. بهبود
      jsonConfig = _enhanceConfig(jsonConfig);

      // ۴. مجوز
      final bool permitted = await _vless.requestPermission();
      if (!permitted) throw Exception('VPN permission denied');

      // ۵. شروع
      await _vless.startVless(
        remark: parsedUrl.remark.isEmpty ? config.name : parsedUrl.remark,
        config: jsonConfig,
        proxyOnly: false,
      );

      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();
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

  Future<void> disconnect() async {
    if (_status == VpnStatus.disconnected) return;
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
  }

  Future<void> toggle(VpnConfig config) async {
    if (isConnected || _status == VpnStatus.error) {
      await disconnect();
    } else {
      await connect(config);
    }
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
