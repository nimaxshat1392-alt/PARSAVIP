import 'dart:async';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import '../models/vpn_config.dart';
import 'log_service.dart';
import '../models/log_entry.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnService {
  final LogService _logs = LogService();
  late V2ray _v2ray;
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
    _v2ray = V2ray(
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
      await _logs.add(LogLevel.info, 'V2Ray (Xray) initialized');
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
      await _logs.add(LogLevel.info, 'Connecting: ${config.protocolShort} @ ${config.host}');

      // ۱. پارس کردن لینک اشتراک
      final parser = V2ray.parseFromURL(config.rawUri);
      final fullConfig = parser.getFullConfiguration();

      // ۲. درخواست مجوز VPN
      final permitted = await _v2ray.requestPermission();
      if (!permitted) throw Exception('دسترسی VPN رد شد');

      // ۳. شروع V2Ray در حالت TUN (VPN کامل)
      await _v2ray.startV2Ray(
        remark: config.name,
        config: fullConfig,
        proxyOnly: false, // false = TUN mode (VPN کامل)
      );

      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();
      await _logs.add(LogLevel.success, '✅ Connected via Xray (TUN)');
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
