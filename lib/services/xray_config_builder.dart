import 'dart:convert';
import '../models/vpn_config.dart';

/// سازنده دستی JSON برای Xray — بدون نیاز به parseFromURL پکیج
class XrayConfigBuilder {
  XrayConfigBuilder._();

  static const int socksPort = 10808;

  static String build(VpnConfig config) {
    switch (config.protocol) {
      case VpnProtocol.vless:
        return _vless(config);
      case VpnProtocol.vmess:
        return _vmess(config);
      case VpnProtocol.trojan:
        return _trojan(config);
      case VpnProtocol.ss:
        return _ss(config);
      default:
        throw 'پروتکل پشتیبانی نمی‌شود: ${config.protocol}';
    }
  }

  // ═══════════════════════════════════════════════
  // VLESS
  // ═══════════════════════════════════════════════
  static String _vless(VpnConfig c) {
    final uri = Uri.parse(c.rawUri);
    final q = uri.queryParameters;

    final network = (q['type'] ?? 'tcp').toLowerCase();
    final security = (q['security'] ?? '').toLowerCase();
    final sni = q['sni'] ?? q['host'] ?? '';
    final host = q['host'] ?? '';
    final path = Uri.decodeComponent(q['path'] ?? '/');
    final fp = q['fp'] ?? 'chrome';
    final pbk = q['pbk'] ?? '';
    final sid = q['sid'] ?? '';
    final spx = q['spx'] ?? '';
    final flow = q['flow'] ?? '';
    final serviceName = q['serviceName'] ?? '';
    final alpn = q['alpn'] ?? '';

    final ss = <String, dynamic>{'network': network};

    if (security == 'tls') {
      ss['security'] = 'tls';
      ss['tlsSettings'] = {
        'serverName': sni,
        'allowInsecure': false,
        'fingerprint': fp,
        if (alpn.isNotEmpty)
          'alpn': alpn.split(',').map((e) => e.trim()).toList(),
      };
    } else if (security == 'reality') {
      ss['security'] = 'reality';
      ss['realitySettings'] = {
        'serverName': sni,
        'publicKey': pbk,
        'shortId': sid,
        'fingerprint': fp.isNotEmpty ? fp : 'chrome',
        'spiderX': spx,
      };
    } else {
      ss['security'] = 'none';
    }

    if (network == 'ws') {
      ss['wsSettings'] = {
        'path': path,
        'headers': {'Host': host.isNotEmpty ? host : sni},
      };
    } else if (network == 'grpc') {
      ss['grpcSettings'] = {
        'serviceName': serviceName,
        if (q['mode'] == 'gun') 'multiMode': true,
      };
    } else if (network == 'tcp') {
      if (q['headerType'] == 'http') {
        ss['tcpSettings'] = {
          'header': {
            'type': 'http',
            'request': {
              'path': path.split(','),
              'headers': {
                'Host': host.split(','),
              },
            }
          }
        };
      }
    } else if (network == 'xhttp') {
      ss['xhttpSettings'] = {
        'path': path,
        'host': host,
        'mode': q['mode'] ?? 'auto',
      };
    }

    final user = <String, dynamic>{
      'id': uri.userInfo,
      'encryption': 'none',
    };
    if (flow.isNotEmpty) user['flow'] = flow;

    final vnext = {
      'address': uri.host,
      'port': uri.port == 0 ? 443 : uri.port,
      'users': [user],
    };

    return _wrapConfig(
      protocol: 'vless',
      settings: {
        'vnext': [vnext]
      },
      streamSettings: ss,
    );
  }

  // ═══════════════════════════════════════════════
  // VMess
  // ═══════════════════════════════════════════════
  static String _vmess(VpnConfig c) {
    final raw = c.rawUri.substring(8).split('#').first;
    var s = raw.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    final j = jsonDecode(utf8.decode(base64.decode(s))) as Map<String, dynamic>;

    final addr = j['add'].toString();
    final port = int.tryParse(j['port'].toString()) ?? 443;
    final uuid = j['id'].toString();
    final aid = int.tryParse((j['aid'] ?? '0').toString()) ?? 0;
    final scy = (j['scy'] ?? 'auto').toString();
    final net = (j['net'] ?? 'tcp').toString();
    final host = (j['host'] ?? '').toString();
    final path = (j['path'] ?? '/').toString();
    final tls = (j['tls'] ?? '').toString();
    final sni = (j['sni'] ?? '').toString();
    final alpn = (j['alpn'] ?? '').toString();

    final ss = <String, dynamic>{'network': net};

    if (tls == 'tls') {
      ss['security'] = 'tls';
      ss['tlsSettings'] = {
        'serverName': sni.isNotEmpty ? sni : host,
        'allowInsecure': false,
        if (alpn.isNotEmpty)
          'alpn': alpn.split(',').map((e) => e.trim()).toList(),
      };
    } else {
      ss['security'] = 'none';
    }

    if (net == 'ws') {
      ss['wsSettings'] = {
        'path': path,
        'headers': {'Host': host},
      };
    } else if (net == 'grpc') {
      ss['grpcSettings'] = {'serviceName': path};
    } else if (net == 'h2' || net == 'http') {
      ss['httpSettings'] = {
        'host': host.split(','),
        'path': path,
      };
    }

    final vnext = {
      'address': addr,
      'port': port,
      'users': [
        {
          'id': uuid,
          'alterId': aid,
          'security': scy,
        }
      ],
    };

    return _wrapConfig(
      protocol: 'vmess',
      settings: {
        'vnext': [vnext]
      },
      streamSettings: ss,
    );
  }

  // ═══════════════════════════════════════════════
  // Trojan
  // ═══════════════════════════════════════════════
  static String _trojan(VpnConfig c) {
    final uri = Uri.parse(c.rawUri);
    final q = uri.queryParameters;

    final network = (q['type'] ?? 'tcp').toLowerCase();
    final sni = q['sni'] ?? '';
    final host = q['host'] ?? sni;
    final path = Uri.decodeComponent(q['path'] ?? '/');
    final alpn = q['alpn'] ?? '';
    final serviceName = q['serviceName'] ?? '';

    final ss = <String, dynamic>{
      'network': network,
      'security': 'tls',
      'tlsSettings': {
        'serverName': sni,
        'allowInsecure': false,
        if (alpn.isNotEmpty)
          'alpn': alpn.split(',').map((e) => e.trim()).toList(),
      },
    };

    if (network == 'ws') {
      ss['wsSettings'] = {
        'path': path,
        'headers': {'Host': host},
      };
    } else if (network == 'grpc') {
      ss['grpcSettings'] = {'serviceName': serviceName};
    }

    return _wrapConfig(
      protocol: 'trojan',
      settings: {
        'servers': [
          {
            'address': uri.host,
            'port': uri.port == 0 ? 443 : uri.port,
            'password': uri.userInfo,
          }
        ],
      },
      streamSettings: ss,
    );
  }

  // ═══════════════════════════════════════════════
  // Shadowsocks
  // ═══════════════════════════════════════════════
  static String _ss(VpnConfig c) {
    final body = c.rawUri.substring(5).split('#').first;
    String userInfo;
    String hostPort;

    if (body.contains('@')) {
      final at = body.indexOf('@');
      userInfo = body.substring(0, at);
      if (!userInfo.contains(':')) {
        userInfo = _b64(userInfo);
      }
      hostPort = body.substring(at + 1);
    } else {
      final d = _b64(body);
      final at = d.lastIndexOf('@');
      userInfo = d.substring(0, at);
      hostPort = d.substring(at + 1);
    }

    final colon = userInfo.indexOf(':');
    final method = userInfo.substring(0, colon);
    final password = userInfo.substring(colon + 1);
    final hp = hostPort.split(':');

    return _wrapConfig(
      protocol: 'shadowsocks',
      settings: {
        'servers': [
          {
            'address': hp[0],
            'port': int.tryParse(hp.length > 1 ? hp[1] : '443') ?? 443,
            'method': method,
            'password': password,
          }
        ],
      },
      streamSettings: null,
    );
  }

  // ═══════════════════════════════════════════════
  // Helper — ساخت JSON نهایی
  // ═══════════════════════════════════════════════
  static String _wrapConfig({
    required String protocol,
    required Map<String, dynamic> settings,
    Map<String, dynamic>? streamSettings,
  }) {
    final outbound = <String, dynamic>{
      'protocol': protocol,
      'settings': settings,
      'tag': 'proxy',
    };
    if (streamSettings != null) {
      outbound['streamSettings'] = streamSettings;
    }

    final config = {
      'log': {'loglevel': 'warning'},
      'inbounds': [
        {
          'port': socksPort,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {
            'auth': 'noauth',
            'udp': true,
          },
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
          },
        }
      ],
      'outbounds': [
        outbound,
        {'protocol': 'freedom', 'tag': 'direct'},
        {'protocol': 'blackhole', 'tag': 'block'},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          {'type': 'field', 'outboundTag': 'direct', 'port': '53'},
          {
            'type': 'field',
            'outboundTag': 'direct',
            'ip': ['geoip:private']
          },
        ],
      },
    };

    return jsonEncode(config);
  }

  static String _b64(String s) {
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return utf8.decode(base64.decode(s));
  }
}
