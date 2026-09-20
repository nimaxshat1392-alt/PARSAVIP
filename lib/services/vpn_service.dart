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

  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;

    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;
    _lastError = null;

    try {
      if (!_initialized) await initialize();

      await _logs.add(LogLevel.info, 'Starting: ${config.protocolShort}');
      await _logs.add(LogLevel.info, 'URI: ${config.rawUri}');

      // ⭐ ۱. پارس URI به URL object
      final FlutterVlessURL parsedUrl = FlutterVless.parseFromURL(config.rawUri);

      // ⭐ ۲. دریافت config JSON
      String jsonConfig = parsedUrl.getFullConfiguration();
      await _logs.add(LogLevel.info, 'Parsed config OK');

      // ⭐ ۳. تزریق DNS + routing (کلید موفقیت اتصال!)
      try {
        final Map<String, dynamic> cfg =
            jsonDecode(jsonConfig) as Map<String, dynamic>;

        // DNS — کوئری‌های DNS مستقیم برن (سریع‌تر)
        cfg['dns'] = {
          'servers': [
            {'address': '1.1.1.1', 'skipFallback': false},
            {'address': '8.8.8.8', 'skipFallback': false},
          ],
          'queryStrategy': 'UseIP',
          'tag': 'dns_inbound',
        };

        // Routing — کلید موفقیت
        cfg['routing'] = {
          'domainStrategy': 'IPIfNonMatch',
          'rules': [
            // DNS queries مستقیم
            {
              'type': 'field',
              'outboundTag': 'direct',
              'port': '53',
            },
            // IPs خصوصی مستقیم
            {
              'type': 'field',
              'outboundTag': 'direct',
              'ip': ['geoip:private'],
            },
            // SNI sniffing
            {
              'type': 'field',
              'inboundTag': ['socks-inbound', 'tun-in'],
              'outboundTag': 'proxy',
            },
          ],
        };

        jsonConfig = jsonEncode(cfg);
        await _logs.add(LogLevel.info, 'Config enhanced with DNS+routing ✅');
      } catch (e) {
        await _logs.add(LogLevel.warning, 'Config enhance failed: $e');
      }

      // ⭐ ۴. درخواست مجوز Notification (اندروید ۱۳+)
      if (Platform.isAndroid) {
        await _logs.add(LogLevel.info, 'Requesting permissions...');
      }

      // ⭐ ۵. درخواست مجوز VPN
      final bool permitted = await _vless.requestPermission();
      if (!permitted) throw Exception('VPN permission denied');
      await _logs.add(LogLevel.info, 'VPN permission granted');

      // ⭐ ۶. شروع تونل VPN (TUN mode)
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
