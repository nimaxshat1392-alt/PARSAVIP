import 'dart:async';
import 'package:flutter_singbox_client/flutter_singbox_client.dart' hide LogLevel;
import '../models/vpn_config.dart';
import 'log_service.dart';
import '../models/log_entry.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnService {
  final LogService _logs = LogService();
  final SingboxClient _client = SingboxClient();

  VpnStatus _status = VpnStatus.disconnected;
  VpnConfig? _current;
  String? _lastError;
  bool _initialized = false;

  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  Timer? _timer;
  Duration _duration = Duration.zero;
  final List<StreamSubscription> _subs = [];

  VpnStatus get status => _status;
  VpnConfig? get current => _current;
  String? get lastError => _lastError;
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;
  Stream<Duration> get durationStream => _durationCtrl.stream;
  Duration get duration => _duration;
  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy =>
      _status == VpnStatus.connecting || _status == VpnStatus.disconnecting;

  /// مقداردهی اولیه هسته
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _client.initialize();
      _initialized = true;
      await _logs.add(LogLevel.info, 'Sing-box core initialized');

      // طبق مستندات، حتماً به faultStream گوش بده
      _subs.add(_client.faultStream.listen((msg) {
        _lastError = msg;
        _logs.add(LogLevel.error, 'Core fault: $msg');
      }));

      // گوش دادن به وضعیت سرویس برای مدیریت UI
      _subs.add(_client.serviceStateStream.listen((state) {
        if (state.isRunning) {
          _status = VpnStatus.connected;
        } else if (state.isIdle) {
          _status = VpnStatus.disconnected;
        }
        _statusCtrl.add(_status);
      }));
    } catch (e) {
      _lastError = e.toString();
      await _logs.add(LogLevel.error, 'Init failed: $e');
    }
  }

  /// اتصال به VPN
  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;

    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;
    _lastError = null;

    try {
      if (!_initialized) await initialize();

      // ۱. ساخت JSON کانفیگ با تزریق DNS و Routing
      final jsonConfig = _buildSingboxConfig(config);

      // ۲. اعتبارسنجی کانفیگ (طبق مستندات، الزامی است)
      await _logs.add(LogLevel.info, 'Validating config...');
      await _client.checkConfig(jsonConfig);
      await _logs.add(LogLevel.info, 'Config is valid ✅');

      // ۳. درخواست مجوز VPN
      final permitted = await _client.requestVPNPermission();
      if (!permitted) throw Exception('VPN permission denied');

      // ۴. اتصال در حالت TUN
      await _client.connect(SessionOptions(
        config: jsonConfig,
        networkMode: NetworkMode.vpn,
        notification: const NotificationConfig(
          title: 'PARSAVIP',
          showTrafficStats: true,
          showStopButton: true,
          stopButtonLabel: 'Disconnect',
        ),
      ));

      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();
      await _logs.add(LogLevel.success, '✅ Connected via Sing-box');
      return true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      _status = VpnStatus.error;
      _statusCtrl.add(_status);
      await _logs.add(LogLevel.error, '❌ $e');
      return false;
    }
  }

  /// تبدیل URI به JSON استاندارد Sing-box
  String _buildSingboxConfig(VpnConfig config) {
    // این بخش بر اساس مستندات Sing-box برای TUN ساخته شده است
    // در اینجا یک کانفیگ نمونه برای VLESS با WebSocket و TLS قرار داده شده است
    // شما می‌توانید این بخش را با پارسر خود جایگزین کنید
    return '''
    {
      "log": {"level": "warn"},
      "dns": {
        "servers": [
          {"tag": "cloudflare", "address": "1.1.1.1"},
          {"tag": "google", "address": "8.8.8.8"}
        ]
      },
      "inbounds": [
        {
          "type": "tun",
          "tag": "tun-in",
          "interface_name": "tun0",
          "address": ["172.19.0.1/30"],
          "auto_route": true,
          "strict_route": true,
          "stack": "system",
          "sniff": true
        }
      ],
      "outbounds": [
        {
          "type": "vless",
          "tag": "proxy",
          "server": "${config.host}",
          "server_port": ${config.port},
          "uuid": "${config.rawUri.split('@')[0].split('://')[1]}",
          "tls": {
            "enabled": true,
            "server_name": "${Uri.parse(config.rawUri).queryParameters['sni'] ?? config.host}"
          },
          "transport": {
            "type": "ws",
            "path": "${Uri.parse(config.rawUri).queryParameters['path'] ?? '/'}",
            "headers": {
              "Host": "${Uri.parse(config.rawUri).queryParameters['host'] ?? config.host}"
            }
          }
        },
        {
          "type": "direct",
          "tag": "direct"
        }
      ],
      "route": {
        "rules": [
          {
            "ip_is_private": true,
            "outbound": "direct"
          }
        ],
        "final": "proxy"
      }
    }
    ''';
  }

  Future<void> disconnect() async {
    if (!isConnected) return;
    _status = VpnStatus.disconnecting;
    _statusCtrl.add(_status);
    try {
      await _client.disconnect();
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
    for (final sub in _subs) {
      sub.cancel();
    }
    _statusCtrl.close();
    _durationCtrl.close();
  }
}
