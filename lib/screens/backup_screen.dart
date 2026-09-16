import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_background.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _importCtrl = TextEditingController();
  bool _isJson = true;

  @override
  void dispose() {
    _importCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('پشتیبان‌گیری')),
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'خروجی (Export)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${app.configs.length} سرور موجود',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'فایل JSON شامل تمام اطلاعات است. فایل URI فقط لینک‌ها را ذخیره می‌کند.',
                      style: TextStyle(
                        color: C.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final json =
                                  BackupService.exportJson(app.configs);
                              await Clipboard.setData(
                                ClipboardData(text: json),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ JSON کپی شد'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.code_rounded),
                            label: const Text('JSON'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: C.secondary,
                            ),
                            onPressed: () async {
                              final list =
                                  BackupService.exportUriList(app.configs);
                              await Clipboard.setData(
                                ClipboardData(text: list),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ لیست URI کپی شد'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.list_rounded),
                            label: const Text('URI'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'ورودی (Import)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _pill(
                            label: 'JSON',
                            active: _isJson,
                            onTap: () => setState(() => _isJson = true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _pill(
                            label: 'URI List',
                            active: !_isJson,
                            onTap: () => setState(() => _isJson = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _importCtrl,
                      maxLines: 8,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        hintText: _isJson
                            ? 'Paste JSON...'
                            : 'هر خط یک URI...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: C.success,
                        ),
                        onPressed: () async {
                          final raw = _importCtrl.text.trim();
                          if (raw.isEmpty) return;

                          if (_isJson) {
                            final list = BackupService.importJson(raw);
                            var count = 0;
                            for (final c in list) {
                              final ok = await app.addConfig(c.rawUri);
                              if (ok) count++;
                            }
                            if (context.mounted) {
                              _importCtrl.clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('✅ $count سرور اضافه شد'),
                                ),
                              );
                            }
                          } else {
                            final lines =
                                BackupService.importUriList(raw);
                            final added = await app.addMultiple(lines);
                            if (context.mounted) {
                              _importCtrl.clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('✅ $added سرور اضافه شد'),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('ایمپورت'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? C.secondary.withOpacity(0.2) : C.bgCardLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? C.secondary : C.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? C.secondary : C.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
