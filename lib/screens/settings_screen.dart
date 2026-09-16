import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_background.dart';
import 'about_screen.dart';
import 'faq_screen.dart';
import 'logs_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('تنظیمات')),
      body: GradientBackground(child: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tile(icon: Icons.list_alt_rounded, title: 'گزارش‌ها',
            subtitle: 'مشاهده رویدادهای برنامه', color: C.warning,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LogsScreen()))),
          _tile(icon: Icons.help_outline_rounded, title: 'سوالات متداول',
            subtitle: 'پاسخ سوالات پرتکرار', color: C.success,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FaqScreen()))),
          _tile(icon: Icons.info_outline_rounded, title: 'درباره PARSAVIP',
            subtitle: 'اطلاعات برنامه', color: C.accent,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()))),
          const SizedBox(height: 20),
          const Center(child: Text('PARSAVIP v1.0.0',
            textDirection: TextDirection.ltr,
            style: TextStyle(color: C.textHint, fontSize: 12))),
        ],
      ))),
    );
  }

  Widget _tile({required IconData icon, required String title, required String subtitle,
    required Color color, required VoidCallback? onTap}) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: GlassCard(
      onTap: onTap, padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: C.textSecondary, fontSize: 11)),
        ])),
        if (onTap != null) const Icon(Icons.chevron_left_rounded, color: C.textSecondary),
      ]),
    ));
  }
}
