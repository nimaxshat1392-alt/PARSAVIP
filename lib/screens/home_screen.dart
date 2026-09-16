import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/vpn_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/connect_orb.dart';
import '../widgets/glass_card.dart';
import '../widgets/ping_badge.dart';
import 'configs_screen.dart';
import 'admin_login_screen.dart';
import 'admin_panel_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.settings_rounded),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        title: const Text('PARSAVIP', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900)),
        actions: [IconButton(
          icon: Icon(app.isAdmin ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined),
          color: app.isAdmin ? C.success : null,
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => app.isAdmin ? const AdminPanelScreen() : const AdminLoginScreen())),
        )],
      ),
      body: GradientBackground(child: SafeArea(child: Column(children: [
        const SizedBox(height: 8),
        _StatusChip(),
        const SizedBox(height: 8),
        const Expanded(flex: 5, child: Center(child: ConnectOrb())),
        Expanded(flex: 4, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            _QuickStats(),
            const SizedBox(height: 12),
            _SelectedConfigCard(),
            const SizedBox(height: 12),
            _ActionRow(),
          ]),
        )),
        const SizedBox(height: 12),
      ]))),
    );
  }
}

class _StatusChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.status;
    Color color; String text;
    if (s == VpnStatus.connected) { color = C.success; text = 'CONNECTED'; }
    else if (s == VpnStatus.connecting) { color = C.warning; text = 'CONNECTING...'; }
    else if (s == VpnStatus.disconnecting) { color = C.warning; text = 'DISCONNECTING...'; }
    else if (s == VpnStatus.error) { color = C.danger; text = 'ERROR'; }
    else { color = C.danger; text = 'DISCONNECTED'; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(30), border: Border.all(color: color.withOpacity(0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color, blurRadius: 8)])),
        const SizedBox(width: 8),
        Text(text, textDirection: TextDirection.ltr, style: TextStyle(
          color: color, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 11)),
      ]),
    );
  }
}

class _QuickStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return StreamBuilder<Duration>(
      stream: app.vpn.durationStream,
      builder: (_, snap) {
        final d = snap.data ?? Duration.zero;
        final hh = d.inHours.toString().padLeft(2, '0');
        final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
        final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
        return GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat(Icons.timer_outlined, 'مدت', '$hh:$mm:$ss', C.secondary),
            _divider(),
            _stat(Icons.bolt_rounded, 'پینگ', '${app.activeConfig?.ping ?? app.selected?.ping ?? "--"} ms', C.warning),
            _divider(),
            _stat(Icons.language_rounded, 'پروتکل', app.activeConfig?.protocolShort ?? app.selected?.protocolShort ?? '--', C.accent),
          ]),
        );
      },
    );
  }
  Widget _stat(IconData i, String label, String value, Color color) {
    return Column(children: [
      Container(padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
        child: Icon(i, color: color, size: 14)),
      const SizedBox(height: 4),
      Text(value, textDirection: TextDirection.ltr,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      Text(label, style: const TextStyle(fontSize: 9, color: C.textSecondary)),
    ]);
  }
  Widget _divider() => Container(width: 1, height: 30, color: Colors.white12);
}

class _SelectedConfigCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = app.selected;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [C.primary, C.secondary]),
          borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.dns_rounded, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c?.name ?? 'سروری انتخاب نشده', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(c == null ? 'برای انتخاب ضربه بزنید' : '${c.host}:${c.port}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: C.textSecondary, fontSize: 11),
            overflow: TextOverflow.ellipsis),
        ])),
        if (c?.ping != null) PingBadge(ping: c!.ping),
        IconButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfigsScreen())),
          icon: const Icon(Icons.swap_horiz_rounded, color: C.secondary)),
      ]),
    );
  }
}

class _ActionRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Row(children: [
      Expanded(child: GlassCard(
        onTap: app.pinging ? null : () => app.pingAll(),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (app.pinging) const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: C.secondary))
          else const Icon(Icons.speed_rounded, color: C.secondary),
          const SizedBox(width: 8),
          Text(app.pinging ? 'در حال تست...' : 'تست پینگ', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      )),
      const SizedBox(width: 10),
      Expanded(child: GlassCard(
        onTap: app.pinging ? null : () => app.connectToBest(),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.rocket_launch_rounded, color: C.accent),
          SizedBox(width: 8),
          Text('بهترین سرور', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
      )),
    ]);
  }
}
