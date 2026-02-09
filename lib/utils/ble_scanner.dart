import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleScanner {
  static StreamSubscription? _subscription;
  static bool _isScanning = false;

  /// 啟動持續掃描監聽器
  static Future<void> startListening({
    required Function(String name, String mac, int rssi) onDeviceFound,
    Function(String error)? onError,
  }) async {
    // 🔥 1. 強制開啟底層 Log (除錯完後可關閉)
    FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);

    // 🔥 2. 印出目前的藍牙狀態 (不要只用 await first，因為可能會卡死)
    var state = await FlutterBluePlus.adapterState.first;
    print("[BLE DEBUG] 目前藍牙狀態: $state");

    if (state != BluetoothAdapterState.on) {
      if (Platform.isWindows) {
        print("[BLE DEBUG] 嘗試呼叫 turnOn (Windows 可能不支援)...");
        // Windows 通常需要手動開，但我們可以印出警告
        onError?.call("⚠️ 藍牙狀態為 $state，請檢查 Windows 設定是否已開啟藍牙");
        // 注意：不要 return，有時候狀態會滯後，我們嘗試硬跑看看
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
      print("[BLE DEBUG] 正在停止上一次掃描...");
      await stop();
    }

    // 3. 設定監聽器
    print("[BLE DEBUG] 設定監聽器...");
    _subscription = FlutterBluePlus.scanResults.listen((results) {
      // 🔥 如果這裡有印東西，代表底層有收到封包
      if (results.isNotEmpty) {
        print("[BLE DEBUG] 收到 ${results.length} 筆資料");
      }

      for (ScanResult r in results) {
        final String name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : (r.advertisementData.localName.isNotEmpty
                  ? r.advertisementData.localName
                  : "");

        final String mac = r.device.remoteId.str;
        final int rssi = r.rssi;

        // 只要有 MAC 就吐出來
        if (mac.isNotEmpty) {
          // print("[BLE DEBUG] RAW DEVICE: $name ($mac)"); // 太吵可以註解
          onDeviceFound(name, mac, rssi);
        }
      }
    }, onError: (e) => onError?.call("Scan Stream Error: $e"));

    // 4. 啟動掃描
    try {
      print("[BLE DEBUG] 發送 startScan 指令...");
      _isScanning = true;

      await FlutterBluePlus.startScan(
        timeout: null, // 持續掃描
        continuousUpdates: true, // 允許 RSSI 更新
      );
      print("[BLE DEBUG] startScan 指令已發送成功！");
    } catch (e) {
      _isScanning = false;
      print("[BLE DEBUG] startScan 發生例外: $e");
      onError?.call("掃描啟動失敗: $e");
    }
  }

  static Future<void> stop() async {
    try {
      _isScanning = false;
      await FlutterBluePlus.stopScan();
      await _subscription?.cancel();
      _subscription = null;
      print("[BLE DEBUG] 掃描已停止");
    } catch (e) {
      print("Stop scan error: $e");
    }
  }
}
