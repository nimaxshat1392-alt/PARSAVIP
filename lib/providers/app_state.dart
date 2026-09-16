import 'package:flutter/foundation.dart';
import '../models/vpn_config.dart';
import '../services/storage_service.dart';
import '../services/config_parser.dart';
import '../data/default_configs.dart';

class AppState extends ChangeNotifier {
  final storage = StorageService();

  List<VpnConfig> configs = [];
  VpnConfig? selected;
  bool isAdmin = false;
  bool loading = true;
  bool connected = false;

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
  }

  VpnConfig _empty() => VpnConfig(
        id: 'none',
        name: 'PARSAVIP',
        protocol: VpnProtocol.unknown,
        rawUri: '',
        host: '',
        port: 0,
      );

  void toggleConnection() {
    if (selected == null) return;
    connected = !connected;
    notifyListeners();
  }

  Future<void> selectConfig(VpnConfig c) async {
    selected = c;
    await storage.saveSelectedId(c.id);
    notifyListeners();
  }

  Future<bool> addConfig(String uri) async {
    final c = ConfigParser.parse(uri, index: configs.length);
    if (c == null) return false;
    if (configs.any((x) => x.host == c.host && x.port == c.port)) return false;
    configs.add(c);
    await storage.saveConfigs(configs);
    notifyListeners();
    return true;
  }

  Future<int> addMultiple(List<String> uris) async {
    var added = 0;
    for (final u in uris) {
      final ok = await addConfig(u);
      if (ok) added++;
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
    notifyListeners();
  }

  Future<bool> loginAdmin(String pass) async {
    final ok = await storage.verifyAdmin(pass);
    if (ok) {
      isAdmin = true;
      await storage.setAdminSession(true);
      notifyListeners();
    }
    return ok;
  }

  Future<void> logoutAdmin() async {
    isAdmin = false;
    await storage.setAdminSession(false);
    notifyListeners();
  }
}
