// lib/main.dart
import 'package:flutter/material.dart';
import 'screen/main_layout.dart';

void main() {
  runApp(const BeeMasterApp());
}

class BeeMasterApp extends StatelessWidget {
  const BeeMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BeeMaster ROTW',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA), // 淡灰色背景
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFA000), // 蜜蜂黃
          primary: const Color(0xFFFFA000),
          surface: Colors.white,
        ),
      ),
      // 這裡直接呼叫我們做好的版型
      home: const MainLayout(),
    );
  }
}
