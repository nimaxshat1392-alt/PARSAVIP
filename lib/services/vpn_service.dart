import 'dart:async';
import 'package:flutter_singbox_client/flutter_singbox_client.dart';
import '../models/vpn_config.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnService {
  final SingboxClient _client = SingboxClient();
  bool _initialized = false;

  VpnStatus _status = VpnStatus.disconnected;
  VpnConfig? _current;
  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  Timer? _timer;
  Duration _duration = Duration.zero;

  VpnStatus get status => _status;
  VpnConfig? get current => _current;
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;
  Stream<Duration> get durationStream => _durationCtrl.stream;
  Duration get duration => _duration;

  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy =>
      _status == VpnStatus.connecting ||
      _status == VpnStatus.disconnecting;

  /// یک بار در زمان راه‌اندازی برنامه فراخوانی می‌شود
  Future<void> initialize() async {
    if (_initialized) return;
    await _client.initialize();
    _initialized = true;
  }

  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;
    if (!_initialized) await initialize();

    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;

    try {
      // ۱. اعتبارسنجی کانفیگ با هسته Sing-box
      await _client.checkConfig(config.rawUri);

      // ۲. درخواست مجوز VPN (فقط بار اول نمایش داده می‌شود)
      final permissionGranted = await _client.requestVPNPermission();
      if (!permissionGranted) {
        _status = VpnStatus.error;
        _statusCtrl.add(_status);
        return false;
      }

      // ۳. اتصال با تنظیمات کامل
      await _client.connect(SessionOptions(
        config: config.rawUri,
        networkMode: NetworkMode.vpn,
        killSwitch: false, // در صورت نیاز true کنید
        notification: const NotificationConfig(
          title: 'PARSAVIP',
          showTrafficStats: true,
        ),
      ));

      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();
      return true;
    } catch (e) {
      _status = VpnStatus.error;
      _statusCtrl.add(_status);
      return false;
    }
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
  }

  Future<void> toggle(VpnConfig config) async {
    if (isConnected) {
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
