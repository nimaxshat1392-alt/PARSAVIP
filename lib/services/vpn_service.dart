import 'dart:async';
import '../models/vpn_config.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnService {
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
  bool get isBusy =>
      _status == VpnStatus.connecting ||
      _status == VpnStatus.disconnecting;

  Future<void> initialize() async {}

  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;

    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;

    await Future.delayed(const Duration(milliseconds: 1200));

    _status = VpnStatus.connected;
    _statusCtrl.add(_status);
    _startTimer();
    return true;
  }

  Future<void> disconnect() async {
    if (!isConnected) return;

    _status = VpnStatus.disconnecting;
    _statusCtrl.add(_status);

    await Future.delayed(const Duration(milliseconds: 500));

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
