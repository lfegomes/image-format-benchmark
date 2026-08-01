import 'package:flutter/material.dart';

import 'presentation/setup_screen.dart';

class BenchmarkApp extends StatelessWidget {
  const BenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Benchmark de imagens',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const SetupScreen(),
    );
  }
}
