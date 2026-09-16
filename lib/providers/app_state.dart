import 'package:flutter/foundation.dart';
import '../models/vpn_config.dart';
import '../services/storage_service.dart';
import '../services/config_parser.dart';
import '../services/ping_service.dart';
import '../services/vpn_service.dart';
import '../data/default_configs.dart';

class AppState extends ChangeNotifier {
  final storage = StorageService();
  final vpn = VpnService();

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
    // بارگذاری یا ساخت از پیش‌فرض
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

    // گوش دادن به تغییرات وضعیت VPN
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

  // ============ پینگ ============
  Future<void> pingAll() async {
    if (pinging) return;
    pinging = true;
    pingProgress = 0;
    notifyListeners();

    configs = await PingService.pingAll(
      configs,
      onProgress: (d, t) {
        pingProgress = d / t;
        notifyListeners();
      },
    );

    await storage.saveConfigs(configs);
    pinging = false;
    pingProgress = 0;
    notifyListeners();
  }

  Future<void> pingOne(VpnConfig c) async {
    final ms = await PingService.pingOne(c);
    final idx = configs.indexWhere((x) => x.id == c.id);
    if (idx == -1) return;
    configs[idx] = VpnConfig(
      id: c.id,
      name: c.name,
      protocol: c.protocol,
      rawUri: c.rawUri,
      host: c.host,
      port: c.port,
      ping: ms,
    );
    await storage.saveConfigs(configs);
    notifyListeners();
  }

  // ============ اتصال ============
  Future<void> toggleConnection() async {
    if (selected == null) return;
    await vpn.toggle(selected!);
    notifyListeners();
  }

  Future<void> connectToBest() async {
    // اول پینگ همه، بعد به بهترین وصل شو
    await pingAll();
    final best = PingService.best(configs);
    if (best != null) {
      await selectConfig(best);
      await vpn.connect(best);
      notifyListeners();
    }
  }

  // ============ انتخاب و مدیریت کانفیگ ============
  Future<void> selectConfig(VpnConfig c) async {
    selected = c;
    await storage.saveSelectedId(c.id);
    notifyListeners();
  }

  Future<bool> addConfig(String uri) async {
    final c = ConfigParser.parse(uri, index: configs.length);
    if (c == null) return false;
    if (configs.any((x) => x.host == c.host && x.port == c.port)) {
      return false;
    }
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

  // ============ ادمین ============
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

  @override
  void dispose() {
    vpn.dispose();
    super.dispose();
  }
}
