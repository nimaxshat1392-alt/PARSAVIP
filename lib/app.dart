import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

class ParsaVipApp extends StatelessWidget {
  const ParsaVipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PARSAVIP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}
