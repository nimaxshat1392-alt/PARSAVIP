
import 'dart:async';
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
  String _socksPort = '10808';
  String _httpPort = '10809';

  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  Timer? _timer;
  Duration _duration = Duration.zero;

  VpnStatus get status => _status;
  VpnConfig? get current => _current;
  String? get lastError => _lastError;
  String get socksPort => _socksPort;
  String get httpPort => _httpPort;
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
    }
  }

  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;
    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;
    _lastError = null;

    try {
      if (config.rawUri.contains('security=reality')) {
        throw Exception('کانفیگ Reality پشتیبانی نمی‌شود');
      }

      await _logs.add(LogLevel.info, 'Connecting: ${config.protocolShort}');

      final parser = FlutterV2ray.parseFromURL(config.rawUri);
      final json = parser.getFullConfiguration();

      final permitted = await _v2ray.requestPermission();
      if (!permitted) throw Exception('دسترسی رد شد');

      // ✅ proxyOnly = true → حالت پروکسی SOCKS5
      await _v2ray.startV2Ray(
        remark: config.name,
        config: json,
        proxyOnly: true,   // ← این خط کلیدیه
      );

      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();
      await _logs.add(LogLevel.success, '✅ پروکسی فعال شد');
      await _logs.add(LogLevel.info, 'SOCKS5: 127.0.0.1:$_socksPort');
      await _logs.add(LogLevel.info, 'HTTP: 127.0.0.1:$_httpPort');
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
