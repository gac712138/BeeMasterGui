import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleScanner {
  static StreamSubscription? _subscription;
  static bool _isScanning = false;

  /// 啟動持續掃描監聽器 (模擬 CLI 的 StartIDScanner)
  static Future<void> startListening({
    required Function(String name, String mac, int rssi) onDeviceFound,
    Function(String error)? onError,
  }) async {
    // 1. 初始化與狀態檢查
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      if (Platform.isWindows) {
        onError?.call("⚠️ 藍牙未開啟：請至 Windows 設定 > 裝置 > 藍牙與其他裝置 開啟藍牙");
        return;
      } else if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          onError?.call("無法開啟藍牙: $e");
          return;
        }
      }
    }

    if (_isScanning) {
      await stop(); // 先停止舊的掃描
    }

    // 2. 設定監聽器 (無差別接收)
    _subscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        // 在 Windows 上，remoteId 通常就是 MAC Address
        final String name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : (r.advertisementData.localName.isNotEmpty
                  ? r.advertisementData.localName
                  : "");

        final String mac = r.device.remoteId.str;
        final int rssi = r.rssi;

        if (mac.isNotEmpty) {
          onDeviceFound(name, mac, rssi);
        }
      }
    }, onError: (e) => onError?.call("Scan Error: $e"));

    // 3. 啟動強力掃描
    try {
      _isScanning = true;
      await FlutterBluePlus.startScan(
        // ⚠️ 關鍵：不設 timeout，不設過濾條件
        timeout: null,
        // ⚠️ 關鍵：允許重複，確保持續收到 RSSI 更新 (Windows 也支援)
        continuousUpdates: true,
        // ❌ 移除 androidScanMode 以解決 Windows 編譯錯誤
      );
    } catch (e) {
      _isScanning = false;
      onError?.call("掃描啟動失敗: $e");
    }
  }

  static Future<void> stop() async {
    try {
      _isScanning = false;
      await FlutterBluePlus.stopScan();
      await _subscription?.cancel();
      _subscription = null;
    } catch (e) {
      print("Stop scan error: $e");
    }
  }
}
