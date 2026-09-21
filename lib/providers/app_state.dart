import 'package:flutter/foundation.dart';
import '../models/vpn_config.dart';
import '../services/storage_service.dart';
import '../services/config_parser.dart';
import '../services/ping_service.dart' as ping;
import '../services/vpn_service.dart';
import '../services/log_service.dart';
import '../models/log_entry.dart';
import '../data/default_configs.dart';

class AppState extends ChangeNotifier {
  final storage = StorageService();
  final vpn = VpnService();
  final logs = LogService();

  List<VpnConfig> configs = [];
  VpnConfig? selected;
  bool isAdmin = false;
  bool loading = true;
  bool pinging = false;
  double pingProgress = 0;

  VpnStatus get status => vpn.status;
  bool get isConnected => vpn.isConnected;
  VpnConfig? get activeConfig => vpn.current;

  Future<void> init() async {
    configs = await storage.loadConfigs();
    if (configs.isEmpty) {
      final parsed = <VpnConfig>[];
      final seen = <String>{};
      for (var i = 0; i < defaultConfigUris.length; i++) {
        final c = ConfigParser.parse(defaultConfigUris[i], index: i);
        if (c == null) continue;
        final k = '${c.host}:${c.port}';
        if (seen.contains(k)) continue;
        seen.add(k);
        parsed.add(c);
      }
      configs = parsed;
      await storage.saveConfigs(configs);
    }

    final selId = await storage.loadSelectedId();
    if (selId != null) {
      selected = configs.firstWhere(
        (c) => c.id == selId,
        orElse: () => configs.isNotEmpty ? configs.first : _empty(),
      );
    } else if (configs.isNotEmpty) {
      selected = configs.first;
    }

    isAdmin = await storage.isAdminSession();
    loading = false;
    notifyListeners();

    await logs.init();
    await logs.add(LogLevel.info, 'App started');
    await vpn.initialize();
    vpn.statusStream.listen((_) => notifyListeners());
  }

  VpnConfig _empty() => VpnConfig(
        id: 'none',
        name: 'PARSAVIP',
        protocol: VpnProtocol.unknown,
        rawUri: '',
        host: '',
        port: 0,
      );

  Future<void> pingAll() async {
    if (pinging) return;
    pinging = true;
    pingProgress = 0;
    notifyListeners();
    await logs.add(LogLevel.info, 'Ping test started');

    configs = await ping.PingService.pingAll(
      configs,
      onProgress: (d, t) {
        pingProgress = d / t;
        notifyListeners();
      },
    );

    await storage.saveConfigs(configs);
    pinging = false;
    pingProgress = 0;
    await logs.add(LogLevel.success, 'Ping test complete');
    notifyListeners();
  }

  Future<void> toggleConnection() async {
    if (selected == null) return;
    await vpn.toggle(selected!);
    await logs.add(
      LogLevel.info,
      isConnected ? 'Connected to ${selected!.host}' : 'Disconnected',
    );
    notifyListeners();
  }

  Future<void> connectToBest() async {
    await pingAll();
    final best = ping.PingService.best(configs);
    if (best != null) {
      await selectConfig(best);
      await vpn.connect(best);
      await logs.add(
        LogLevel.success,
        'Connected to best: ${best.host}',
      );
      notifyListeners();
    }
  }

  Future<void> selectConfig(VpnConfig c) async {
    selected = c;
    await storage.saveSelectedId(c.id);
    notifyListeners();
  }

  Future<bool> addConfig(String uri) async {
    final c = ConfigParser.parse(uri, index: configs.length);
    if (c == null) {
      await logs.add(LogLevel.error, 'Invalid URI');
      return false;
    }
    if (configs.any((x) => x.host == c.host && x.port == c.port)) {
      return false;
    }
    configs.add(c);
    await storage.saveConfigs(configs);
    await logs.add(LogLevel.success, 'Added ${c.host}');
    notifyListeners();
    return true;
  }

  Future<int> addMultiple(List<String> uris) async {
    var added = 0;
    for (final u in uris) {
      final ok = await addConfig(u);
      if (ok) added++;
    }
    if (added > 0) {
      await logs.add(LogLevel.success, 'Bulk import: $added');
    }
    return added;
  }

  Future<void> removeConfig(String id) async {
    configs.removeWhere((c) => c.id == id);
    if (selected?.id == id) {
      selected = configs.isNotEmpty ? configs.first : null;
      await storage.saveSelectedId(selected?.id);
    }
    await storage.saveConfigs(configs);
    notifyListeners();
  }

  Future<void> clearAll() async {
    configs.clear();
    selected = null;
    await storage.saveConfigs(configs);
    await storage.saveSelectedId(null);
    await logs.add(LogLevel.warning, 'All configs cleared');
    notifyListeners();
  }

  Future<bool> loginAdmin(String pass) async {
    final ok = await storage.verifyAdmin(pass);
    if (ok) {
      isAdmin = true;
      await storage.setAdminSession(true);
      await logs.add(LogLevel.success, 'Admin logged in');
      notifyListeners();
    } else {
      await logs.add(LogLevel.warning, 'Failed admin login');
    }
    return ok;
  }

  Future<void> logoutAdmin() async {
    isAdmin = false;
    await storage.setAdminSession(false);
    notifyListeners();
  }

  @override
  void dispose() {
    vpn.dispose();
    super.dispose();
  }
}
