import 'dart:async';
import 'dart:convert';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import '../models/vpn_config.dart';
import 'log_service.dart';
import '../models/log_entry.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnService {
  final LogService _logs = LogService();
  late FlutterV2ray _v2ray;
  VpnStatus _status = VpnStatus.disconnected;
  VpnConfig? _current;
  String? _lastError;

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
  bool get isBusy => _status == VpnStatus.connecting || _status == VpnStatus.disconnecting;

  VpnService() {
    _v2ray = FlutterV2ray(
      onStatusChanged: (status) {
        final s = status.state.toLowerCase();
        if (s.contains('connect') && !s.contains('disconnect')) {
          _status = VpnStatus.connected;
          _statusCtrl.add(_status);
        } else if (s.contains('disconnect')) {
          _status = VpnStatus.disconnected;
          _statusCtrl.add(_status);
        }
      },
    );
  }

  Future<void> initialize() async {
    try {
      await _v2ray.initializeV2Ray();
      await _logs.add(LogLevel.info, 'V2Ray init OK');
    } catch (e) {
      _lastError = e.toString();
      await _logs.add(LogLevel.error, 'Init failed: $e');
    }
  }

  /// ساخت config کامل با TUN + DNS + routing
  String _buildConfig(String uri) {
    try {
      final parser = FlutterV2ray.parseFromURL(uri);
      final baseConfig = parser.getFullConfiguration();
      final configMap = jsonDecode(baseConfig) as Map<String, dynamic>;

      // ✅ Log کن که ببینیم چی هست
      _logs.add(LogLevel.info, 'Config keys: ${configMap.keys.join(",")}');

      // ✅ DNS
      configMap['dns'] = {
        'servers': ['1.1.1.1', '8.8.8.8', '1.0.0.1'],
        'queryStrategy': 'UseIP',
        'disableCache': false,
      };

      // ✅ routing - همه چیز به پروکسی
      configMap['routing'] = {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {
            'type': 'field',
            'outboundTag': 'direct',
            'ip': ['geoip:private'],
            'domain': ['geosite:private']
          },
        ],
        'final': 'proxy',
      };

      // ✅ sniffing به inbound
      final inbounds = configMap['inbounds'] as List?;
      if (inbounds != null) {
        for (var inb in inbounds) {
          if (inb is Map<String, dynamic>) {
            inb['sniffing'] = {
              'enabled': true,
              'destOverride': ['http', 'tls', 'quic'],
              'routeOnly': true,
            };
          }
        }
      }

      final finalConfig = jsonEncode(configMap);
      _logs.add(LogLevel.info, 'Config built OK');
      return finalConfig;
    } catch (e) {
      _logs.add(LogLevel.error, 'buildConfig fail: $e');
      return FlutterV2ray.parseFromURL(uri).getFullConfiguration();
    }
  }

  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;
    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;
    _lastError = null;

    try {
      await _logs.add(LogLevel.info, 'Connecting: ${config.protocolShort} ${config.host}');

      final fullConfig = _buildConfig(config.rawUri);

      final permitted = await _v2ray.requestPermission();
      if (!permitted) throw Exception('VPN permission denied');

      await _v2ray.startV2Ray(
        remark: config.name,
        config: fullConfig,
        proxyOnly: false,
      );

      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();
      await _logs.add(LogLevel.success, 'Connected');
      return true;
    } catch (e) {
      _lastError = e.toString();
      _status = VpnStatus.error;
      _statusCtrl.add(_status);
      await _logs.add(LogLevel.error, 'Failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (!isConnected) return;
    _status = VpnStatus.disconnecting;
    _statusCtrl.add(_status);
    try { _v2ray.stopV2Ray(); } catch (_) {}
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
