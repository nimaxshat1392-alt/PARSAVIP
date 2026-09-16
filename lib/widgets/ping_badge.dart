import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PingBadge extends StatelessWidget {
  final int? ping;
  final bool large;

  const PingBadge({super.key, required this.ping, this.large = false});

  @override
  Widget build(BuildContext context) {
    final color = C.pingColor(ping);
    final text = ping == null
        ? '--'
        : ping! >= 9999
            ? 'OFF'
            : '$ping ms';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 8,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: large ? 13 : 11,
        ),
      ),
    );
  }
}
