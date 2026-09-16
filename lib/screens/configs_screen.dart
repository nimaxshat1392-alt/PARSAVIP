import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/config_tile.dart';

class ConfigsScreen extends StatelessWidget {
  const ConfigsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Configs')),
      body: GradientBackground(
        child: SafeArea(
          child: app.configs.isEmpty
              ? const Center(
                  child: Text(
                    'هیچ سروری موجود نیست',
                    style: TextStyle(color: C.textSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: app.configs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      ConfigTile(config: app.configs[i]),
                ),
        ),
      ),
    );
  }
}
