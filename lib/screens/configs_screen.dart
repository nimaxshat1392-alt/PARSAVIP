import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/config_tile.dart';

class ConfigsScreen extends StatefulWidget {
  const ConfigsScreen({super.key});
  @override
  State<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends State<ConfigsScreen> {
  String _filter = '';
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    var list = app.configs;
    if (_filter.isNotEmpty) {
      list = list.where((c) => c.name.toLowerCase().contains(_filter.toLowerCase())
        || c.host.toLowerCase().contains(_filter.toLowerCase())).toList();
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('سرورها'), actions: [
        IconButton(icon: const Icon(Icons.speed_rounded),
          onPressed: app.pinging ? null : () => app.pingAll()),
      ]),
      body: GradientBackground(child: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: TextField(
          onChanged: (v) => setState(() => _filter = v),
          decoration: const InputDecoration(hintText: 'جستجو...', prefixIcon: Icon(Icons.search_rounded)),
        )),
        if (app.pinging) Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LinearProgressIndicator(value: app.pingProgress, color: C.secondary, backgroundColor: C.bgCardLight)),
        Expanded(child: list.isEmpty
          ? const Center(child: Text('هیچ سروری موجود نیست', style: TextStyle(color: C.textSecondary)))
          : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => ConfigTile(config: list[i]),
          )),
      ]))),
    );
  }
}
