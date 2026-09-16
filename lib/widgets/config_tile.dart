import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vpn_config.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';
import 'ping_badge.dart';

class ConfigTile extends StatelessWidget {
  final VpnConfig config;
  const ConfigTile({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final selected = app.selected?.id == config.id;
    final protoColor = C.protoColor(config.protocolShort);

    return GlassCard(
      onTap: () async {
        await app.selectConfig(config);
        if (context.mounted) Navigator.pop(context);
      },
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(width: 6, height: 44, decoration: BoxDecoration(
          color: selected ? C.success : protoColor,
          borderRadius: BorderRadius.circular(3),
          boxShadow: [BoxShadow(color: (selected ? C.success : protoColor).withOpacity(0.5), blurRadius: 8)],
        )),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(config.name, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
            if (selected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle_rounded, size: 14, color: C.success),
            ],
          ]),
          const SizedBox(height: 3),
          Text('${config.host}:${config.port}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 11, color: C.textSecondary),
            overflow: TextOverflow.ellipsis),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          PingBadge(ping: config.ping),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: protoColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(config.protocolShort, style: TextStyle(fontSize: 9, color: protoColor, fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }
}
