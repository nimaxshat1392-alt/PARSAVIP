import 'dart:async';
import 'dart:convert';
import 'package:flutter_vless/flutter_vless.dart';
import '../models/vpn_config.dart';
import 'log_service.dart';
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

  String _sanitizeUri(String uri) {
    try {
      final hashIndex = uri.indexOf('#');
      String mainPart = hashIndex >= 0 ? uri.substring(0, hashIndex) : uri;
      String fragment = hashIndex >= 0 ? uri.substring(hashIndex) : '';

      final qIndex = mainPart.indexOf('?');
      if (qIndex < 0) return uri;

      final basePart = mainPart.substring(0, qIndex);
      final queryPart = mainPart.substring(qIndex + 1);

      final newParams = <String>[];
      for (final pair in queryPart.split('&')) {
        if (pair.isEmpty) continue;
        final eqIndex = pair.indexOf('=');
        if (eqIndex < 0) {
          newParams.add(pair);
          continue;
        }
        final key = pair.substring(0, eqIndex);
        final value = pair.substring(eqIndex + 1);
        if (key == 'security' && (value.isEmpty || value == 'none')) continue;
        if (value.isEmpty) continue;
        newParams.add(pair);
      }

      return '$basePart?${newParams.join('&')}$fragment';
    } catch (_) {
      return uri;
    }
  }

  /// ⭐ حیاتی: پاکسازی null ها که Xray رد می‌کنه
  String _fixJsonConfig(String jsonStr) {
    try {
      final Map<String, dynamic> root =
          jsonDecode(jsonStr) as Map<String, dynamic>;

      final inbounds = root['inbounds'];
      if (inbounds is List) {
        for (final ib in inbounds) {
          if (ib is Map<String, dynamic>) {
            _fixStreamSettings(ib['streamSettings']);
          }
        }
      }

      final outbounds = root['outbounds'];
      if (outbounds is List) {
        for (final ob in outbounds) {
          if (ob is Map<String, dynamic>) {
            _fixStreamSettings(ob['streamSettings']);
          }
        }
      }

      return jsonEncode(root);
    } catch (_) {
      return jsonStr;
    }
  }

  void _fixStreamSettings(dynamic streamSettings) {
    if (streamSettings is! Map<String, dynamic>) return;

    final rs = streamSettings['realitySettings'];
    if (rs is Map<String, dynamic>) {
      if (rs['spiderX'] == null) rs['spiderX'] = '';
      if (rs['shortId'] == null) rs['shortId'] = '';
      if (rs['publicKey'] == null) rs['publicKey'] = '';
      if (rs['serverName'] == null) rs['serverName'] = '';
      if (rs['fingerprint'] == null || rs['fingerprint'] == '') {
        rs['fingerprint'] = 'chrome';
      }
      if (rs['show'] == null) rs['show'] = false;
    }

    final ts = streamSettings['tlsSettings'];
    if (ts is Map<String, dynamic>) {
      if (ts['serverName'] == null) ts['serverName'] = '';
      if (ts['fingerprint'] == null || ts['fingerprint'] == '') {
        ts['fingerprint'] = 'chrome';
      }
      if (ts['allowInsecure'] == null) ts['allowInsecure'] = false;
    }

    final ws = streamSettings['wsSettings'];
    if (ws is Map<String, dynamic>) {
      if (ws['path'] == null || ws['path'] == '') ws['path'] = '/';
      if (ws['headers'] == null) ws['headers'] = <String, String>{};
    }

    final gs = streamSettings['grpcSettings'];
    if (gs is Map<String, dynamic>) {
      if (gs['serviceName'] == null) gs['serviceName'] = '';
    }

    if (streamSettings['network'] == null ||
        streamSettings['network'] == '') {
      streamSettings['network'] = 'tcp';
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

      final cleanUri = _sanitizeUri(config.rawUri);
      final FlutterVlessURL parsedUrl = FlutterVless.parseFromURL(cleanUri);
      String jsonConfig = parsedUrl.getFullConfiguration();

      jsonConfig = _fixJsonConfig(jsonConfig);
      await _logs.add(LogLevel.info, 'Config fixed ✅');

      final bool permitted = await _vless.requestPermission();
      if (!permitted) throw Exception('VPN permission denied');
      await _logs.add(LogLevel.info, 'VPN permission granted');

      // ⭐⭐⭐ مهم‌ترین بخش — این ۲ خط باعث عبور ترافیک می‌شن
      await _vless.startVless(
        remark: parsedUrl.remark.isEmpty ? config.name : parsedUrl.remark,
        config: jsonConfig,
        proxyOnly: false,
        androidDnsPolicy: AndroidDnsPolicy.proxy,
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
