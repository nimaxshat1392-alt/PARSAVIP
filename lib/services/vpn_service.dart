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
  bool get isBusy => _status == VpnStatus.connecting || _status == VpnStatus.disconnecting;

  /// مقداردهی اولیه هسته Sing-box (فقط یک بار در کل عمر برنامه)
  Future<void> initialize() async {
    try {
      // طبق مستندات، چندین بار صدا زدن بی‌خطر است
      await _client.initialize();
      await _logs.add(LogLevel.info, 'Sing-box core initialized');

      // گوش دادن به خطاهای هسته (طبق best-practices پلاگین)
      _subs.add(_client.faultStream.listen((msg) {
        _lastError = msg;
        _logs.add(LogLevel.error, 'Core fault: $msg');
      }));
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
      await _logs.add(LogLevel.info, 'Validating config: ${config.protocolShort}');

      // ۱. اعتبارسنجی کانفیگ قبل از اتصال (طبق best-practices)
      await _client.checkConfig(config.rawUri);
      await _logs.add(LogLevel.info, 'Config is valid');

      // ۲. درخواست مجوز VPN
      final permitted = await _client.requestVPNPermission();
      if (!permitted) throw Exception('VPN permission denied');

      // ۳. اتصال در حالت VPN (TUN) با تنظیمات پیشرفته
      await _client.connect(SessionOptions(
        config: config.rawUri,
        networkMode: NetworkMode.vpn, // حالت تونل کامل
        killSwitch: false, // در صورت نیاز true کنید
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
      await _logs.add(LogLevel.success, '✅ Connected via Sing-box (TUN)');
      return true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      _status = VpnStatus.error;
      _statusCtrl.add(_status);
      await _logs.add(LogLevel.error, '❌ Connect failed: $e');
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
