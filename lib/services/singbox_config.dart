import 'dart:convert';
import '../models/vpn_config.dart';

/// تبدیل URI کانفیگ به JSON استاندارد Sing-box (نسخه حداقلی)
class SingboxConfig {
  static String build(VpnConfig config) {
    final u = Uri.parse(config.rawUri);
    final q = u.queryParameters;

    Map<String, dynamic> outbound;
    switch (config.protocol) {
      case VpnProtocol.vless:
        outbound = _vless(u, q);
        break;
      case VpnProtocol.vmess:
        outbound = _vmess(config.rawUri);
        break;
      case VpnProtocol.trojan:
        outbound = _trojan(u, q);
        break;
      case VpnProtocol.ss:
        outbound = _ss(config.rawUri);
        break;
      default:
        throw 'پروتکل پشتیبانی نمی‌شود';
    }

    // ⭐ ساختار حداقلی — فقط چیزهایی که Sing-box 1.12+ قطعاً قبول داره
    final fullConfig = {
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30'],
          'auto_route': true,
          'stack': 'system',
        }
      ],
      'outbounds': [
        outbound,
        {'type': 'direct', 'tag': 'direct'},
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(fullConfig);
  }

  static Map<String, dynamic> _vless(Uri u, Map<String, String> q) {
    final flow = q['flow'] ?? '';
    final sni = q['sni'] ?? '';
    final security = q['security'] ?? 'none';
    final pbk = q['pbk'] ?? '';
    final sid = q['sid'] ?? '';
    final fp = q['fp'] ?? 'chrome';
    final type = q['type'] ?? 'tcp';

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
        'utls': {'enabled': true, 'fingerprint': fp},
        'reality': {
          'enabled': true,
          'public_key': pbk,
          'short_id': sid,
        },
      };
    }

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

    return result;
  }

  static Map<String, dynamic> _vmess(String uri) {
    final raw = uri.substring(8).split('#').first;
    var s = raw.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    final j = jsonDecode(utf8.decode(base64.decode(s))) as Map<String, dynamic>;

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

    return result;
  }

  static Map<String, dynamic> _trojan(Uri u, Map<String, String> q) {
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

    return result;
  }

  static Map<String, dynamic> _ss(String uri) {
    final body = uri.substring(5).split('#').first;
    String userInfo;
    String hostPort;

    if (body.contains('@')) {
      final at = body.indexOf('@');
      userInfo = body.substring(0, at);
      if (!userInfo.contains(':')) userInfo = _b64(userInfo);
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

    return {
      'type': 'shadowsocks',
      'tag': 'proxy',
      'server': hp[0],
      'server_port': int.tryParse(hp.length > 1 ? hp[1] : '443') ?? 443,
      'method': method,
      'password': password,
    };
  }

  static String _b64(String s) {
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return utf8.decode(base64.decode(s));
  }
}
