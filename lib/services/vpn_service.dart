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

  /// ⭐ بهینه‌سازی کامل JSON — fix null + speed
  String _optimizeConfig(String jsonStr) {
    try {
      final Map<String, dynamic> root =
          jsonDecode(jsonStr) as Map<String, dynamic>;

      // ═══════════════════════════════════════════════════
      // ۱. پاکسازی Inbounds
      // ═══════════════════════════════════════════════════
      final inbounds = root['inbounds'];
      if (inbounds is List) {
        for (final ib in inbounds) {
          if (ib is Map<String, dynamic>) {
            _fixStreamSettings(ib['streamSettings']);
            // ⭐ Sniffing بهتر برای route سریع
            if (ib['sniffing'] is Map) {
              final sn = ib['sniffing'] as Map<String, dynamic>;
              sn['enabled'] = true;
              sn['destOverride'] = ['http', 'tls', 'quic', 'fakedns'];
              sn['routeOnly'] = false;
              sn['metadataOnly'] = false;
            }
          }
        }
      }

      // ═══════════════════════════════════════════════════
      // ۲. پاکسازی و بهینه‌سازی Outbounds
      // ═══════════════════════════════════════════════════
      final outbounds = root['outbounds'];
      if (outbounds is List) {
        for (final ob in outbounds) {
          if (ob is! Map<String, dynamic>) continue;

          _fixStreamSettings(ob['streamSettings']);

          final protocol = ob['protocol'];
          // ⭐ فقط برای proxy (نه direct/blackhole) sockopt اضافه کن
          if (protocol != 'freedom' && protocol != 'blackhole') {
            final ss = ob['streamSettings'];
            if (ss is Map<String, dynamic>) {
              // ⭐ TCP Fast Open + No Delay + BBR
              ss['sockopt'] = {
                'tcpFastOpen': true,
                'tcpNoDelay': true,
                'tcpKeepAliveInterval': 15,
                'tcpCongestion': 'bbr',
                'mark': 0,
              };
            }
          }
        }
      }

      // ═══════════════════════════════════════════════════
      // ۳. DNS بهینه — سرعت باز شدن سایت‌ها رو زیاد می‌کنه
      // ═══════════════════════════════════════════════════
      root['dns'] = {
        'hosts': {
          'domain:googleapis.cn': 'googleapis.com',
          'dns.google': ['8.8.8.8', '8.8.4.4'],
          'cloudflare.com': ['1.1.1.1', '1.0.0.1'],
        },
        'servers': [
          // ⭐ Cloudflare اول (سریع‌ترین)
          {
            'address': '1.1.1.1',
            'skipFallback': false,
            'domains': [],
          },
          // ⭐ Google دوم
          {
            'address': '8.8.8.8',
            'skipFallback': false,
            'domains': [],
          },
          // ⭐ Quad9 سوم
          {
            'address': '9.9.9.9',
            'skipFallback': true,
          },
          // ⭐ DNS محلی برای دامنه‌های ایران
          {
            'address': 'localhost',
            'domains': ['domain:ir', 'geosite:category-ir'],
          },
        ],
        'queryStrategy': 'UseIPv4', // ⭐ IPv4 سریع‌تر از IPv6
        'disableCache': false,
        'disableFallback': false,
        'disableFallbackIfMatch': false,
        'tag': 'dns_inbound',
      };

      // ═══════════════════════════════════════════════════
      // ۴. Routing بهینه
      // ═══════════════════════════════════════════════════
      root['routing'] = {
        'domainStrategy': 'IPIfNonMatch',
        'domainMatcher': 'hybrid',
        'rules': [
          // ⭐ DNS مستقیم (سریع)
          {
            'type': 'field',
            'outboundTag': 'direct',
            'port': '53',
          },
          // ⭐ ترافیک محلی مستقیم
          {
            'type': 'field',
            'outboundTag': 'direct',
            'ip': ['geoip:private', 'geoip:ir'],
          },
          // ⭐ دامنه‌های ایران مستقیم (اینستا ایرانی سریع)
          {
            'type': 'field',
            'outboundTag': 'direct',
            'domain': ['geosite:category-ir', 'geosite:private'],
          },
          // ⭐ SNI sniffing برای بقیه
          {
            'type': 'field',
            'inboundTag': ['tun-in', 'socks-inbound'],
            'outboundTag': 'proxy',
          },
        ],
      };

      // ═══════════════════════════════════════════════════
      // ۵. Log level کم (کمتر CPU = سرعت بیشتر)
      // ═══════════════════════════════════════════════════
      root['log'] = {'loglevel': 'warning'};

      return jsonEncode(root);
    } catch (_) {
      return jsonStr;
    }
  }

  /// پاکسازی streamSettings
  void _fixStreamSettings(dynamic streamSettings) {
    if (streamSettings is! Map<String, dynamic>) return;

    // Reality
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

    // TLS
    final ts = streamSettings['tlsSettings'];
    if (ts is Map<String, dynamic>) {
      if (ts['serverName'] == null) ts['serverName'] = '';
      if (ts['fingerprint'] == null || ts['fingerprint'] == '') {
        ts['fingerprint'] = 'chrome';
      }
      if (ts['allowInsecure'] == null) ts['allowInsecure'] = false;
    }

    // WS
    final ws = streamSettings['wsSettings'];
    if (ws is Map<String, dynamic>) {
      if (ws['path'] == null || ws['path'] == '') ws['path'] = '/';
      if (ws['headers'] == null) ws['headers'] = <String, String>{};
    }

    // gRPC
    final gs = streamSettings['grpcSettings'];
    if (gs is Map<String, dynamic>) {
      if (gs['serviceName'] == null) gs['serviceName'] = '';
    }

    // XHTTP
    final xs = streamSettings['xhttpSettings'];
    if (xs is Map<String, dynamic>) {
      if (xs['path'] == null || xs['path'] == '') xs['path'] = '/';
      if (xs['mode'] == null) xs['mode'] = 'auto';
    }

    // network default
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

      // ⭐ بهینه‌سازی کامل (null fix + speed boost)
      jsonConfig = _optimizeConfig(jsonConfig);
      await _logs.add(LogLevel.info, 'Config optimized ⚡');

      final bool permitted = await _vless.requestPermission();
      if (!permitted) throw Exception('VPN permission denied');
      await _logs.add(LogLevel.info, 'VPN permission granted');

      await _vless.startVless(
        remark: parsedUrl.remark.isEmpty ? config.name : parsedUrl.remark,
        config: jsonConfig,
        proxyOnly: false,
        androidDnsPolicy: AndroidDnsPolicy.proxy,
      );

      _status = VpnStatus.connected;
      _statusCtrl.add(_status);
      _startTimer();
      await _logs.add(LogLevel.success, '✅ Connected (optimized)');
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
