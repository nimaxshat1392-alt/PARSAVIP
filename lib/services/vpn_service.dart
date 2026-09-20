import 'dart:async';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';
import 'log_service.dart';
import 'ping_service.dart';
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

      // ⭐ پاکسازی کامل با PingService.sanitizeUri (همون تابعی که برای پینگ استفاده شد)
      final cleanUri = PingService.sanitizeUri(config.rawUri);
      if (cleanUri != config.rawUri) {
        await _logs.add(LogLevel.info, 'Cleaned URI: $cleanUri');
      }

      final FlutterVlessURL parsedUrl = FlutterVless.parseFromURL(cleanUri);
      final String jsonConfig = parsedUrl.getFullConfiguration();
      await _logs.add(LogLevel.info, 'Parsed config OK');

      final bool permitted = await _vless.requestPermission();
      if (!permitted) throw Exception('VPN permission denied');

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
