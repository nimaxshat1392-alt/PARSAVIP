import 'package:flutter/material.dart';
import '../data/faq_data.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_background.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('سوالات متداول')),
      body: GradientBackground(child: SafeArea(child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: faqList.length,
        itemBuilder: (_, i) => _FaqTile(item: faqList[i], index: i),
      ))),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final FaqItem item;
  final int index;
  const _FaqTile({required this.item, required this.index});
  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Container(
      decoration: BoxDecoration(color: C.bgCard.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
      child: Column(children: [
        InkWell(borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _open = !_open),
          child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Container(width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(color: C.primary.withOpacity(0.2), shape: BoxShape.circle),
              child: Text('${widget.index + 1}', textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w800, color: C.secondary, fontSize: 12))),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.item.question, style: const TextStyle(fontWeight: FontWeight.w700))),
            AnimatedRotation(turns: _open ? 0.5 : 0, duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.keyboard_arrow_down_rounded, color: C.textSecondary)),
          ]))),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(widget.item.answer, style: const TextStyle(color: C.textSecondary, fontSize: 13, height: 1.7))),
        ),
      ]),
    ));
  }
}
