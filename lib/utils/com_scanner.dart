import 'package:flutter_libserialport/flutter_libserialport.dart';

class DongleDeviceInfo {
  final String portName;
  final String? productName;
  final int? vendorId;
  final int? productId;

  DongleDeviceInfo({
    required this.portName,
    this.productName,
    this.vendorId,
    this.productId,
  });
}

class ComScanner {
  // 🎯 這是 Silicon Labs CP210x 常見的 VID
  static const int _siliconLabsVid = 0x10C4;

  /// 掃描並過濾出所有的 Silicon Labs Dongles
  static List<DongleDeviceInfo> findDonglePorts() {
    List<DongleDeviceInfo> foundDongles = [];

    // 1. 取得系統所有可用序列埠的 ID 名稱 (例如 COM3, COM4)
    final List<String> availablePorts = SerialPort.availablePorts;

    for (final name in availablePorts) {
      final port = SerialPort(name);

      try {
        // 2. 取得硬體細節 (對應 Go 版的 GetDetailedPortsList)
        final int? vid = port.vendorId;
        final int? pid = port.productId;
        final String? product = port.productName;

        // 3. 過濾邏輯 (對應 Go 版的 strings.Contains)
        bool isDongle = false;

        // 條件 A: 檢查 VID 是否為 Silicon Labs (10C4)
        if (vid == _siliconLabsVid) {
          isDongle = true;
        }
        // 條件 B: 檢查產品名稱關鍵字
        else if (product != null) {
          final pUpper = product.toUpperCase();
          if (pUpper.contains("SILICON LABS") || pUpper.contains("CP210X")) {
            isDongle = true;
          }
        }

        if (isDongle) {
          foundDongles.add(
            DongleDeviceInfo(
              portName: name,
              productName: product,
              vendorId: vid,
              productId: pid,
            ),
          );
        }
      } catch (e) {
        // 有些 Port 可能被其他程式佔用無法讀取描述，直接跳過
        continue;
      } finally {
        // 釋放資源，不要開著 Port，只做掃描
        port.dispose();
      }
    }

    return foundDongles;
  }
}
