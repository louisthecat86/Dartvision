import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'screens/home_screen.dart';

class DartScorerApp extends StatelessWidget {
  const DartScorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DartVision',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
