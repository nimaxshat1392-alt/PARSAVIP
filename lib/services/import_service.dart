import 'dart:convert';
import 'package:http/http.dart' as http;

class ImportService {
  ImportService._();

  /// دریافت لیست URI از یک لینک subscription
  static Future<List<String>> fetchSubscription(String url) async {
    final res = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': 'PARSAVIP/1.0'},
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw 'HTTP ${res.statusCode}';
    }

    var body = res.body.trim();

    // تلاش برای decode base64
    if (!body.contains('://')) {
      try {
        body = _tryB64(body);
      } catch (_) {}
    }

    return _parseLines(body);
  }

  static String _tryB64(String s) {
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return utf8.decode(base64.decode(s));
  }

  static List<String> _parseLines(String text) {
    return text
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
