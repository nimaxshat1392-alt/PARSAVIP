import 'dart:convert';
import 'dart:io';
import '../models/vpn_config.dart';

class StorageService {
  static const _adminPass = 'poiiu';

  File get _configFile => File('${Directory.systemTemp.path}/parsavip_configs.json');
  File get _selectedFile => File('${Directory.systemTemp.path}/parsavip_selected.txt');
  File get _adminFile => File('${Directory.systemTemp.path}/parsavip_admin.txt');

  Future<List<VpnConfig>> loadConfigs() async {
    try {
      if (!await _configFile.exists()) return [];
      final raw = await _configFile.readAsString();
      if (raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => VpnConfig.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConfigs(List<VpnConfig> configs) async {
    try {
      await _configFile.writeAsString(
        jsonEncode(configs.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<String?> loadSelectedId() async {
    try {
      if (!await _selectedFile.exists()) return null;
      final v = await _selectedFile.readAsString();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSelectedId(String? id) async {
    try {
      if (id == null) {
        if (await _selectedFile.exists()) await _selectedFile.delete();
      } else {
        await _selectedFile.writeAsString(id);
      }
    } catch (_) {}
  }

  Future<bool> verifyAdmin(String pass) async => pass.trim() == _adminPass;

  Future<void> setAdminSession(bool v) async {
    try {
      await _adminFile.writeAsString(v ? '1' : '0');
    } catch (_) {}
  }

  Future<bool> isAdminSession() async {
    try {
      if (!await _adminFile.exists()) return false;
      final v = await _adminFile.readAsString();
      return v == '1';
    } catch (_) {
      return false;
    }
  }
}
