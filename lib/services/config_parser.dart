import 'dart:convert';
import '../models/vpn_config.dart';

/// پارسر کانفیگ — پشتیبانی از همه پورت‌ها (1-65535)
class ConfigParser {
  ConfigParser._();

  static VpnConfig? parse(String uri, {int index = 0}) {
    uri = uri.trim();
    if (uri.isEmpty) return null;
    try {
      if (uri.startsWith('ss://')) return _ss(uri, index);
      if (uri.startsWith('vless://')) return _vless(uri, index);
      if (uri.startsWith('vmess://')) return _vmess(uri, index);
      if (uri.startsWith('trojan://')) return _trojan(uri, index);
    } catch (_) {}
    return null;
  }

  /// ⭐ اعتبارسنجی — همه پورت‌ها (۱ تا ۶۵۵۳۵) ساپورت می‌شن
  static bool isValidConfig(VpnConfig config) {
    // پورت باید در محدوده معتبر باشه
    if (config.port < 1 || config.port > 65535) return false;

    // host خالی
    if (config.host.isEmpty) return false;

    // URI خالی
    if (config.rawUri.isEmpty) return false;

    // host معتبر (بدون نقطه اضافی)
    if (config.host.endsWith('.')) return false;

    // host فقط حروف/عدد/نقطه/خط تیره
    final hostRegex = RegExp(r'^[a-zA-Z0-9.\-_:]+$');
    if (!hostRegex.hasMatch(config.host)) return false;

    return true;
  }

  // ═══════════════════════════════════════════════
  // Shadowsocks
  // ═══════════════════════════════════════════════
  static VpnConfig _ss(String uri, int i) {
    final body = uri.substring(5).split('#').first;
    String decoded = body;

    if (!body.contains('@')) {
      decoded = _b64(body);
    } else {
      final at = body.indexOf('@');
      if (!body.substring(0, at).contains(':')) {
        decoded = '${_b64(body.substring(0, at))}@${body.substring(at + 1)}';
      }
    }

    final at = decoded.lastIndexOf('@');
    final hostPort = decoded.substring(at + 1);
    final p = hostPort.split(':');
    final host = _cleanHost(p[0]);

    // پورت — همه پورت‌ها مجاز
    int port = 443;
    if (p.length > 1) {
      final portStr = p[1].split('/').first.split('?').first;
      port = int.tryParse(portStr) ?? 443;
    }

    return VpnConfig(
      id: 'ss_${i}_${host.hashCode}_$port',
      name: 'PARSAVIP',
      protocol: VpnProtocol.ss,
      rawUri: uri,
      host: host,
      port: port,
    );
  }

  // ═══════════════════════════════════════════════
  // VLESS
  // ═══════════════════════════════════════════════
  static VpnConfig _vless(String uri, int i) {
    final u = Uri.parse(uri);
    final host = _cleanHost(u.host);
    final port = u.port == 0 ? 443 : u.port;

    return VpnConfig(
      id: 'vless_${i}_${host.hashCode}_$port',
      name: 'PARSAVIP',
      protocol: VpnProtocol.vless,
      rawUri: uri,
      host: host,
      port: port,
    );
  }

  // ═══════════════════════════════════════════════
  // VMess
  // ═══════════════════════════════════════════════
  static VpnConfig _vmess(String uri, int i) {
    final j = jsonDecode(_b64(uri.substring(8))) as Map<String, dynamic>;
    final host = _cleanHost((j['add'] ?? '').toString());

    // پورت ممکنه String یا int باشه
    int port = 443;
    final portValue = j['port'];
    if (portValue is int) {
      port = portValue;
    } else if (portValue is String) {
      port = int.tryParse(portValue) ?? 443;
    } else if (portValue is num) {
      port = portValue.toInt();
    }

    return VpnConfig(
      id: 'vmess_${i}_${host.hashCode}_$port',
      name: 'PARSAVIP',
      protocol: VpnProtocol.vmess,
      rawUri: uri,
      host: host,
      port: port,
    );
  }

  // ═══════════════════════════════════════════════
  // Trojan
  // ═══════════════════════════════════════════════
  static VpnConfig _trojan(String uri, int i) {
    final u = Uri.parse(uri);
    final host = _cleanHost(u.host);
    final port = u.port == 0 ? 443 : u.port;

    return VpnConfig(
      id: 'trojan_${i}_${host.hashCode}_$port',
      name: 'PARSAVIP',
      protocol: VpnProtocol.trojan,
      rawUri: uri,
      host: host,
      port: port,
    );
  }

  /// حذف نقطه اضافی از انتهای host
  static String _cleanHost(String host) {
    var h = host.trim();
    while (h.endsWith('.')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  /// Decode Base64
  static String _b64(String s) {
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return utf8.decode(base64.decode(s));
  }
}
