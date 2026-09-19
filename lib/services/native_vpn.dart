import 'dart:async';
import 'package:flutter/services.dart';

/// پل ارتباطی بین Flutter و کد Native v2rayNG
class NativeVpn {
  NativeVpn._();

  static const _method = MethodChannel('com.parsavip.parsavip/xray');
  static const _event = EventChannel('com.parsavip.parsavip/xray_events');

  static Stream<Map<String, dynamic>>? _eventStream;

  /// شروع اتصال VPN با URI کانفیگ
  static Future<bool> start(String uri) async {
    try {
      final result = await _method.invokeMethod<bool>('start', {'config': uri});
      return result ?? false;
    } on PlatformException catch (e) {
      print('NativeVpn start error: ${e.message}');
      return false;
    }
  }

  /// قطع اتصال VPN
  static Future<bool> stop() async {
    try {
      final result = await _method.invokeMethod<bool>('stop');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// دریافت وضعیت فعلی اتصال
  static Future<Map<String, dynamic>?> status() async {
    try {
      return await _method.invokeMapMethod<String, dynamic>('status');
    } catch (_) {
      return null;
    }
  }

  /// استریم رویدادها (اتصال، قطع، خطا)
  static Stream<Map<String, dynamic>> get events {
    _eventStream ??= _event
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _eventStream!;
  }
}
