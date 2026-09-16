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
    required this.id,
    required this.name,
    required this.protocol,
    required this.rawUri,
    required this.host,
    required this.port,
    this.ping,
  });

  String get protocolShort => switch (protocol) {
        VpnProtocol.ss => 'SS',
        VpnProtocol.vless => 'VLESS',
        VpnProtocol.vmess => 'VMess',
        VpnProtocol.trojan => 'Trojan',
        VpnProtocol.unknown => '?',
      };

  String get protocolLabel => switch (protocol) {
        VpnProtocol.ss => 'Shadowsocks',
        VpnProtocol.vless => 'VLESS',
        VpnProtocol.vmess => 'VMess',
        VpnProtocol.trojan => 'Trojan',
        VpnProtocol.unknown => 'Unknown',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'rawUri': rawUri,
        'host': host,
        'port': port,
        'ping': ping,
      };

  factory VpnConfig.fromJson(Map<String, dynamic> j) => VpnConfig(
        id: j['id'],
        name: j['name'],
        protocol: VpnProtocol.values.firstWhere(
          (p) => p.name == j['protocol'],
          orElse: () => VpnProtocol.unknown,
        ),
        rawUri: j['rawUri'],
        host: j['host'],
        port: j['port'],
        ping: j['ping'],
      );
}
