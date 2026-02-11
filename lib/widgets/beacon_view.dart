// lib/pages/devices/beacon_view.dart
import 'package:flutter/material.dart';

class BeaconView extends StatelessWidget {
  const BeaconView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 50),
          // 使用 sensors 圖示，看起來比較像 Beacon
          Icon(Icons.sensors, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text(
            "Beacon 裝置管理 施工中",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 10),
          Text("Under Construction", style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }
}
