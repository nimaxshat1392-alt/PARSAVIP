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
      await _logs.add(LogLevel.info, 'V2Ray initialized');
    } catch (e) {
      _lastError = e.toString();
    }
  }

  /// ⭐ این متد config رو بازنویسی می‌کنه تا sockopt.mark اضافه کنه
  /// بدون mark، ترافیک خروجی خود V2Ray هم از تونل رد می‌شه و loop می‌شه
  String _prepareConfig(VpnConfig config) {
    try {
      final parser = FlutterV2ray.parseFromURL(config.rawUri);
      final baseJson = parser.getFullConfiguration();
      final map = jsonDecode(baseJson) as Map<String, dynamic>;

      // ⭐ ۱. اضافه کردن sockopt.mark به outbound اصلی
      final outbounds = map['outbounds'] as List?;
      if (outbounds != null) {
        for (var ob in outbounds) {
          if (ob is Map<String, dynamic>) {
            final tag = ob['tag']?.toString() ?? '';
            // فقط به outbound اصلی mark اضافه کن (نه direct/block)
            if (tag != 'direct' && tag != 'block' && tag != 'dns_out') {
              ob['streamSettings'] ??= <String, dynamic>{};
              final ss = ob['streamSettings'] as Map<String, dynamic>;
              ss['sockopt'] = {
                'mark': 255,  // ⭐ کلید ماجرا
                'tcpFastOpen': true,
                'tcpNoDelay': true,
              };
            }
          }
        }
      }

      // ⭐ ۲. اضافه کردن DNS
      map['dns'] = {
        'servers': ['1.1.1.1', '8.8.8.8'],
        'tag': 'dns_inbound',
      };

      // ⭐ ۳. اضافه کردن routing با mark rule
      map['routing'] = {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          // DNS traffic مستقیم (نه از پروکسی)
          {
            'type': 'field',
            'outboundTag': 'direct',
            'port': '53',
          },
          // ترافیک mark=255 مستقیم (جلوگیری از loop)
          {
            'type': 'field',
            'outboundTag': 'direct',
            'inboundTag': ['mark'],
          },
          // private IPs مستقیم
          {
            'type': 'field',
            'outboundTag': 'direct',
            'ip': ['geoip:private'],
          },
        ],
      };

      // ⭐ ۴. log
      map['log'] = {'loglevel': 'warning'};

      return jsonEncode(map);
    } catch (e) {
      _logs.add(LogLevel.error, 'Config prep fail: $e');
      // برگشت به config اصلی
      try {
        return FlutterV2ray.parseFromURL(config.rawUri).getFullConfiguration();
      } catch (_) {
        return config.rawUri;
      }
    }
  }

  Future<bool> connect(VpnConfig config) async {
    if (isBusy || isConnected) return false;
    _status = VpnStatus.connecting;
    _statusCtrl.add(_status);
    _current = config;
    _lastError = null;

    try {
      await _logs.add(LogLevel.info, 'Connecting: ${config.protocolShort}');

      // ⭐ استفاده از config آماده شده با sockopt
      final finalConfig = _prepareConfig(config);

      final permitted = await _v2ray.requestPermission();
      if (!permitted) throw Exception('دسترسی VPN رد شد');

      await _v2ray.startV2Ray(
        remark: config.name,
        config: finalConfig,
        proxyOnly: false,
      );

      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();
      await _logs.add(LogLevel.success, '✅ Connected with sockopt.mark');
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
