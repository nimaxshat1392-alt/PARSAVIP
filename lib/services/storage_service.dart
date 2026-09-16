import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_config.dart';

class StorageService {
  static const _keyConfigs = 'parsavip_configs';
  static const _keySelected = 'parsavip_selected';
  static const _adminPass = 'poiiu';

  Future<List<VpnConfig>> loadConfigs() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_keyConfigs);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => VpnConfig.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConfigs(List<VpnConfig> c) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _keyConfigs,
      jsonEncode(c.map((e) => e.toJson()).toList()),
    );
  }

  Future<String?> loadSelectedId() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_keySelected);
  }

  Future<void> saveSelectedId(String? id) async {
    final sp = await SharedPreferences.getInstance();
    if (id == null) {
      await sp.remove(_keySelected);
    } else {
      await sp.setString(_keySelected, id);
    }
  }

  Future<bool> verifyAdmin(String pass) async => pass.trim() == _adminPass;

  Future<void> setAdminSession(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('parsavip_admin', v);
  }

  Future<bool> isAdminSession() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool('parsavip_admin') ?? false;
  }
}
