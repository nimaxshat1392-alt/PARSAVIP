import 'dart:async';
import 'dart:io';
import '../models/vpn_config.dart';
import 'native_vpn.dart';
import 'log_service.dart';
import '../models/log_entry.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnService {
  final LogService _logs = LogService();
  VpnStatus _status = VpnStatus.disconnected;
  VpnConfig? _current;
  String? _lastError;

  final _statusCtrl = StreamController<VpnStatus>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  Timer? _timer;
  Duration _duration = Duration.zero;
  StreamSubscription? _eventSub;

  VpnStatus get status => _status;
  VpnConfig? get current => _current;
  String? get lastError => _lastError;
  Stream<VpnStatus> get statusStream => _statusCtrl.stream;
  Stream<Duration> get durationStream => _durationCtrl.stream;
  Duration get duration => _duration;
  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy => _status == VpnStatus.connecting || _status == VpnStatus.disconnecting;

  /// مقداردهی اولیه: گوش دادن به رویدادهای Native
  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    _eventSub = NativeVpn.events.listen((event) {
      final ev = event['event'];
      if (ev == 'connected') {
        _status = VpnStatus.connected;
        _statusCtrl.add(_status);
      } else if (ev == 'disconnected') {
        _status = VpnStatus.disconnected;
        _statusCtrl.add(_status);
      } else if (ev == 'error') {
        _lastError = event['message'];
        _status = VpnStatus.error;
        _statusCtrl.add(_status);
      }
    }, onError: (_) {});
  }

  /// اتصال به VPN با استفاده از کد Native
  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;
    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;
    _lastError = null;

    try {
      await _logs.add(LogLevel.info, 'Starting Native VPN: ${config.protocolShort}');
      // کد Native مسئول تبدیل URI به JSON و مدیریت اتصال است
      final ok = await NativeVpn.start(config.rawUri);
      if (!ok) {
        throw Exception('Native VPN start failed');
      }
      // وضعیت نهایی از طریق استریم رویدادها به‌روزرسانی می‌شود
      return true;
    } catch (e) {
      _lastError = e.toString();
      _status = VpnStatus.error;
      _statusCtrl.add(_status);
      await _logs.add(LogLevel.error, 'Native connect failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (!isConnected) return;
    _status = VpnStatus.disconnecting;
    _statusCtrl.add(_status);
    try {
      await NativeVpn.stop();
    } catch (_) {}
    // وضعیت نهایی از طریق استریم رویدادها به‌روزرسانی می‌شود
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
    _eventSub?.cancel();
    _statusCtrl.close();
    _durationCtrl.close();
  }
}
