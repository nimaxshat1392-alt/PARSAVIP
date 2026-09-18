import 'dart:async';
import 'package:flutter/services.dart';

/// پل ارتباطی بین Flutter و ParsaVpnService
class NativeVpn {
  NativeVpn._();

  static const _method = MethodChannel('com.parsavip.parsavip/xray');
  static const _event = EventChannel('com.parsavip.parsavip/xray_events');

  static Stream<Map<String, dynamic>>? _stream;

  static Future<bool> start(String uri) async {
    try {
      final r = await _method.invokeMethod<bool>('start', {'config': uri});
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stop() async {
    try {
      final r = await _method.invokeMethod<bool>('stop');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> status() async {
    try {
      return await _method.invokeMapMethod<String, dynamic>('status');
    } catch (_) {
      return null;
    }
  }

  static Stream<Map<String, dynamic>> get events {
    _stream ??= _event
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _stream!;
  }
}
