import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';

class ConnectOrb extends StatefulWidget {
  const ConnectOrb({super.key});
  @override
  State<ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<ConnectOrb>
    with TickerProviderStateMixin {
  late AnimationController _pulse;
  late AnimationController _rotate;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _rotate = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _rotate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isConnected = app.connected;
    final primary = isConnected ? C.success : C.primary;
    final secondary =
        isConnected ? const Color(0xFF69F0AE) : C.secondary;

    return GestureDetector(
      onTap: () => app.toggleConnection(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _rotate]),
        builder: (_, __) {
          final scale = 1 + (_pulse.value * 0.05);
          return SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ...List.generate(3, (i) {
                  final p = (i + 1) / 3;
                  return Transform.scale(
                    scale: scale + p * 0.15,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primary.withOpacity(0.15 - p * 0.03),
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }),
                Transform.rotate(
                  angle: _rotate.value * 6.283,
                  child: Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          primary.withOpacity(0),
                          primary.withOpacity(0.7),
                          primary.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primary.withOpacity(0.35),
                        primary.withOpacity(0.05),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [primary, secondary],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primary.withOpacity(0.6),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.power_settings_new_rounded,
                          size: 42,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isConnected ? 'STOP' : 'START',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
