import 'dart:convert';
import '../models/vpn_config.dart';

class ConfigParser {
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
    return VpnConfig(
      id: 'ss_${i}_${p[0].hashCode}',
      name: 'PARSAVIP', protocol: VpnProtocol.ss,
      rawUri: uri, host: p[0],
      port: int.tryParse(p.length > 1 ? p[1].split('/').first : '443') ?? 443,
    );
  }

  static VpnConfig _vless(String uri, int i) {
    final u = Uri.parse(uri);
    return VpnConfig(
      id: 'vless_${i}_${u.host.hashCode}',
      name: 'PARSAVIP', protocol: VpnProtocol.vless,
      rawUri: uri, host: u.host, port: u.port == 0 ? 443 : u.port,
    );
  }

  static VpnConfig _vmess(String uri, int i) {
    final j = jsonDecode(_b64(uri.substring(8))) as Map<String, dynamic>;
    final host = (j['add'] ?? '').toString();
    return VpnConfig(
      id: 'vmess_${i}_${host.hashCode}',
      name: 'PARSAVIP', protocol: VpnProtocol.vmess,
      rawUri: uri, host: host,
      port: int.tryParse((j['port'] ?? '443').toString()) ?? 443,
    );
  }

  static VpnConfig _trojan(String uri, int i) {
    final u = Uri.parse(uri);
    return VpnConfig(
      id: 'trojan_${i}_${u.host.hashCode}',
      name: 'PARSAVIP', protocol: VpnProtocol.trojan,
      rawUri: uri, host: u.host, port: u.port == 0 ? 443 : u.port,
    );
  }

  static String _b64(String s) {
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) { s += '='; }
    return utf8.decode(base64.decode(s));
  }
}
