import 'dart:convert';
import '../models/vpn_config.dart';

class BackupService {
  BackupService._();

  /// خروجی JSON (شامل همه اطلاعات)
  static String exportJson(List<VpnConfig> configs) {
    final data = {
      'app': 'PARSAVIP',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'count': configs.length,
      'configs': configs.map((c) => c.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// خروجی متنی (هر خط یک URI)
  static String exportUriList(List<VpnConfig> configs) {
    return configs.map((c) => c.rawUri).join('\n');
  }

  /// وارد کردن از JSON
  static List<VpnConfig> importJson(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final list = j['configs'] as List;
      return list
          .map((e) => VpnConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// وارد کردن از متن (هر خط یک URI)
  static List<String> importUriList(String raw) {
    return raw
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) =>
            e.isNotEmpty &&
            (e.startsWith('ss://') ||
                e.startsWith('vless://') ||
                e.startsWith('vmess://') ||
                e.startsWith('trojan://')))
        .toList();
  }
}
