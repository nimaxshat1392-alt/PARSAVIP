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
    // بارگذاری کانفیگ‌ها
    configs = await storage.loadConfigs();

    if (configs.isEmpty) {
      final parsed = <VpnConfig>[];
      final seen = <String>{};
      for (var i = 0; i < defaultConfigUris.length; i++) {
        final c = ConfigParser.parse(defaultConfigUris[i], index: i);
        if (c == null) continue;
        if (!ConfigParser.isValidConfig(c)) continue;
        final k = '${c.host}:${c.port}';
        if (seen.contains(k)) continue;
        seen.add(k);
        parsed.add(c);
      }
      configs = parsed;
      await storage.saveConfigs(configs);
    } else {
      // فیلتر کانفیگ‌های نامعتبر
      final beforeCount = configs.length;
      configs = configs.where((c) => ConfigParser.isValidConfig(c)).toList();
      if (beforeCount != configs.length) {
        await storage.saveConfigs(configs);
      }
    }

    // انتخاب فعلی
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

    // لاگ‌ها
    await logs.init();
    await logs.add(LogLevel.info, 'App started');
    await logs.add(
      LogLevel.info,
      'Loaded ${configs.length} valid configs',
    );

    // راه‌اندازی VPN
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

  // ═══════════════════════════════════════════════
  // Ping
  // ═══════════════════════════════════════════════
  Future<void> pingAll() async {
    if (pinging) return;
    if (configs.isEmpty) return;

    pinging = true;
    pingProgress = 0;
    notifyListeners();
    await logs.add(LogLevel.info, 'Ping test started');

    try {
      configs = await ping.PingService.pingAll(
        configs,
        concurrency: 4,
        onProgress: (done, total) {
          pingProgress = total == 0 ? 0 : done / total;
          notifyListeners();
        },
      );

      await storage.saveConfigs(configs);

      final online = configs
          .where((c) => (c.ping ?? 9999) < 9999)
          .length;

      await logs.add(
        LogLevel.success,
        'Ping complete: $online online, ${configs.length - online} offline',
      );
    } catch (e) {
      await logs.add(LogLevel.error, 'Ping failed: $e');
    } finally {
      pinging = false;
      pingProgress = 0;
      notifyListeners();
    }
  }

  void cancelPing() {
    ping.PingService.cancel();
    pinging = false;
    pingProgress = 0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // Connection
  // ═══════════════════════════════════════════════
  Future<void> toggleConnection() async {
    if (selected == null) return;

    if (isConnected) {
      await vpn.disconnect();
      await logs.add(LogLevel.info, 'Disconnected by user');
    } else {
      await vpn.connect(selected!);
      await logs.add(LogLevel.info, 'Connecting to ${selected!.host}');
    }
    notifyListeners();
  }

  Future<void> connectToBest() async {
    await pingAll();

    final best = ping.PingService.best(configs);
    if (best == null) {
      await logs.add(LogLevel.warning, 'No valid server found');
      return;
    }

    await selectConfig(best);
    await vpn.connect(best);
    await logs.add(LogLevel.success, 'Connected to best: ${best.host}');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // Config Management
  // ═══════════════════════════════════════════════
  Future<void> selectConfig(VpnConfig c) async {
    selected = c;
    await storage.saveSelectedId(c.id);
    notifyListeners();
  }

  Future<bool> addConfig(String uri) async {
    final c = ConfigParser.parse(uri, index: configs.length);
    if (c == null) {
      await logs.add(LogLevel.error, 'Cannot parse URI');
      return false;
    }

    if (!ConfigParser.isValidConfig(c)) {
      await logs.add(
        LogLevel.warning,
        'Invalid config rejected: ${c.host}:${c.port}',
      );
      return false;
    }

    if (configs.any((x) => x.host == c.host && x.port == c.port)) {
      await logs.add(LogLevel.warning, 'Duplicate config skipped');
      return false;
    }

    configs.add(c);
    await storage.saveConfigs(configs);
    await logs.add(LogLevel.success, 'Added ${c.host}:${c.port}');
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
      await logs.add(LogLevel.success, 'Bulk import: $added configs added');
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

  // ═══════════════════════════════════════════════
  // Admin
  // ═══════════════════════════════════════════════
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
    await logs.add(LogLevel.info, 'Admin logged out');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════
  @override
  void dispose() {
    vpn.dispose();
    super.dispose();
  }
}
