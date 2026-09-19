import 'dart:async';
import 'dart:convert';
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

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _client.initialize();
      _initialized = true;
      await _logs.add(LogLevel.info, 'Sing-box core initialized');

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
      if (!_initialized) await initialize();

      final jsonConfig = _buildSingboxConfig(config);
      await _logs.add(LogLevel.info, 'Config JSON: $jsonConfig');

      await _logs.add(LogLevel.info, 'Validating config...');
      await _client.checkConfig(jsonConfig);
      await _logs.add(LogLevel.info, 'Config is valid ✅');

      final permitted = await _client.requestVPNPermission();
      if (!permitted) throw Exception('VPN permission denied');

      await _client.connect(SessionOptions(
        config: jsonConfig,
        networkMode: NetworkMode.vpn,
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

  String _b64Decode(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return utf8.decode(base64.decode(s));
  }

  String _buildSingboxConfig(VpnConfig config) {
    final u = Uri.parse(config.rawUri);
    final q = u.queryParameters;

    Map<String, dynamic> outbound;

    if (config.protocol == VpnProtocol.vless) {
      final security = q['security'] ?? 'none';
      final sni = q['sni'] ?? '';
      final flow = q['flow'] ?? '';

      final result = <String, dynamic>{
        'type': 'vless',
        'tag': 'proxy',
        'server': u.host,
        'server_port': u.port == 0 ? 443 : u.port,
        'uuid': u.userInfo,
      };
      if (flow.isNotEmpty) result['flow'] = flow;

      if (security == 'tls') {
        result['tls'] = {
          'enabled': true,
          'server_name': sni,
        };
      } else if (security == 'reality') {
        result['tls'] = {
          'enabled': true,
          'server_name': sni,
          'utls': {
            'enabled': true,
            'fingerprint': q['fp'] ?? 'chrome',
          },
          'reality': {
            'enabled': true,
            'public_key': q['pbk'] ?? '',
            'short_id': q['sid'] ?? '',
          },
        };
      }

      final type = q['type'] ?? 'tcp';
      if (type == 'ws') {
        result['transport'] = {
          'type': 'ws',
          'path': q['path'] ?? '/',
          'headers': {'Host': q['host'] ?? sni},
        };
      } else if (type == 'grpc') {
        result['transport'] = {
          'type': 'grpc',
          'service_name': q['serviceName'] ?? '',
        };
      }
      outbound = result;
    } else if (config.protocol == VpnProtocol.trojan) {
      final sni = q['sni'] ?? '';
      final host = q['host'] ?? sni;
      final path = q['path'] ?? '/';
      final result = <String, dynamic>{
        'type': 'trojan',
        'tag': 'proxy',
        'server': u.host,
        'server_port': u.port == 0 ? 443 : u.port,
        'password': u.userInfo,
        'tls': {
          'enabled': true,
          'server_name': sni,
        },
      };
      if (q['type'] == 'ws') {
        result['transport'] = {
          'type': 'ws',
          'path': path,
          'headers': {'Host': host},
        };
      }
      outbound = result;
    } else if (config.protocol == VpnProtocol.vmess) {
      final raw = config.rawUri.substring(8).split('#').first;
      final j = jsonDecode(_b64Decode(raw)) as Map<String, dynamic>;
      final host = (j['host'] ?? '').toString();
      final sni = (j['sni'] ?? '').toString();
      final tls = (j['tls'] ?? '').toString();
      final net = (j['net'] ?? 'tcp').toString();
      final path = (j['path'] ?? '/').toString();

      final result = <String, dynamic>{
        'type': 'vmess',
        'tag': 'proxy',
        'server': j['add'],
        'server_port': int.tryParse((j['port'] ?? '443').toString()) ?? 443,
        'uuid': j['id'],
        'security': j['scy'] ?? 'auto',
        'alter_id': int.tryParse((j['aid'] ?? '0').toString()) ?? 0,
      };

      if (tls == 'tls') {
        result['tls'] = {
          'enabled': true,
          'server_name': sni.isNotEmpty ? sni : host,
        };
      }

      if (net == 'ws') {
        result['transport'] = {
          'type': 'ws',
          'path': path,
          'headers': {'Host': host},
        };
      } else if (net == 'grpc') {
        result['transport'] = {
          'type': 'grpc',
          'service_name': path,
        };
      }
      outbound = result;
    } else if (config.protocol == VpnProtocol.ss) {
      final body = config.rawUri.substring(5).split('#').first;
      String userInfo;
      String hostPort;

      if (body.contains('@')) {
        final at = body.indexOf('@');
        userInfo = body.substring(0, at);
        if (!userInfo.contains(':')) {
          userInfo = _b64Decode(userInfo);
        }
        hostPort = body.substring(at + 1);
      } else {
        final d = _b64Decode(body);
        final at = d.lastIndexOf('@');
        userInfo = d.substring(0, at);
        hostPort = d.substring(at + 1);
      }

      final colon = userInfo.indexOf(':');
      final method = userInfo.substring(0, colon);
      final password = userInfo.substring(colon + 1);
      final hp = hostPort.split(':');

      outbound = {
        'type': 'shadowsocks',
        'tag': 'proxy',
        'server': hp[0],
        'server_port': int.tryParse(hp.length > 1 ? hp[1] : '443') ?? 443,
        'method': method,
        'password': password,
      };
    } else {
      throw 'پروتکل پشتیبانی نمی‌شود';
    }

    // ⭐ نسخه جدید: sniff منتقل شده به route.rules (Sing-box 1.13+)
    final fullConfig = {
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30'],
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
        }
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'rules': [
          {'action': 'sniff'},
          {'protocol': 'dns', 'action': 'hijack-dns'},
          {'ip_is_private': true, 'outbound': 'direct'},
        ],
        'final': 'proxy',
      },
    };

    return jsonEncode(fullConfig);
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
