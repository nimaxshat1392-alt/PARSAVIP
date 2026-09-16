import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_background.dart';
import '../models/vpn_config.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () {
              context.read<AppState>().logoutAdmin();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(),
              const SizedBox(height: 16),
              _action(
                icon: Icons.add_link_rounded,
                title: 'افزودن سرور',
                color: C.secondary,
                onTap: () => _showAdd(context),
              ),
              _action(
                icon: Icons.playlist_add_rounded,
                title: 'افزودن گروهی',
                color: C.primary,
                onTap: () => _showBulk(context),
              ),
              _action(
                icon: Icons.delete_sweep_rounded,
                title: 'حذف همه',
                color: C.danger,
                onTap: () => _confirmClear(context),
              ),
              const SizedBox(height: 16),
              Text(
                'سرورها (${app.configs.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              ...app.configs.map(
                (c) => _configTile(context, c, app),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [C.success, C.secondary],
                ),
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, Admin',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'دسترسی کامل فعال است',
                  style: TextStyle(
                    color: C.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _action({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: C.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _configTile(
    BuildContext context,
    VpnConfig c,
    AppState app,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${c.host}:${c.port}',
                    style: const TextStyle(
                      color: C.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_rounded,
                color: C.danger,
              ),
              onPressed: () => app.removeConfig(c.id),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdd(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('افزودن سرور'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'ss:// vless:// vmess:// trojan://',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
          ElevatedButton(
            onPressed: () async {
              final ok =
                  await context.read<AppState>().addConfig(ctrl.text);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? '✅ اضافه شد' : '❌ URI نامعتبر',
                    ),
                  ),
                );
              }
            },
            child: const Text('افزودن'),
          ),
        ],
      ),
    );
  }

  void _showBulk(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('افزودن گروهی'),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            style: const TextStyle(fontSize: 11),
            decoration: const InputDecoration(
              hintText: 'هر خط یک URI...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
          ElevatedButton(
            onPressed: () async {
              final lines = ctrl.text
                  .split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              final added =
                  await context.read<AppState>().addMultiple(lines);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ $added سرور اضافه شد'),
                  ),
                );
              }
            },
            child: const Text('ایمپورت'),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف همه سرورها؟'),
        content: const Text('این عمل قابل بازگشت نیست.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: C.danger,
            ),
            onPressed: () {
              context.read<AppState>().clearAll();
              Navigator.pop(context);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}
