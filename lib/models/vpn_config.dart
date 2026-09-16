enum VpnProtocol { ss, vless, vmess, trojan, unknown }

class VpnConfig {
  final String id;
  final String name;
  final VpnProtocol protocol;
  final String rawUri;
  final String host;
  final int port;
  int? ping;

  VpnConfig({
    required this.id, required this.name, required this.protocol,
    required this.rawUri, required this.host, required this.port, this.ping,
  });

  String get protocolShort {
    switch (protocol) {
      case VpnProtocol.ss: return 'SS';
      case VpnProtocol.vless: return 'VLESS';
      case VpnProtocol.vmess: return 'VMess';
      case VpnProtocol.trojan: return 'Trojan';
      case VpnProtocol.unknown: return '?';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'protocol': protocol.name,
    'rawUri': rawUri, 'host': host, 'port': port, 'ping': ping,
  };

  factory VpnConfig.fromJson(Map<String, dynamic> j) => VpnConfig(
    id: j['id'], name: j['name'],
    protocol: VpnProtocol.values.firstWhere(
      (p) => p.name == j['protocol'],
      orElse: () => VpnProtocol.unknown,
    ),
    rawUri: j['rawUri'], host: j['host'], port: j['port'], ping: j['ping'],
  );
}
