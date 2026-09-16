import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../models/vpn_config.dart';

class StorageService {
  static const _adminHash = 'a35c4e8b8c6b8a1c6e1f1c8d0e5b9e8b8c6b8a1c6e1f1c8d0e5b9e8b8c6b8a1c';

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
    } catch (_) { return []; }
  }

  Future<void> saveConfigs(List<VpnConfig> c) async {
    try {
      await _configFile.writeAsString(jsonEncode(c.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<String?> loadSelectedId() async {
    try {
      if (!await _selectedFile.exists()) return null;
      final v = await _selectedFile.readAsString();
      return v.isEmpty ? null : v;
    } catch (_) { return null; }
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

  Future<bool> verifyAdmin(String pass) async {
    final hash = sha256.convert(utf8.encode(pass.trim())).toString();
    return hash == _adminHash;
  }

  Future<void> setAdminSession(bool v) async {
    try { await _adminFile.writeAsString(v ? '1' : '0'); } catch (_) {}
  }

  Future<bool> isAdminSession() async {
    try {
      if (!await _adminFile.exists()) return false;
      return (await _adminFile.readAsString()) == '1';
    } catch (_) { return false; }
  }
}
