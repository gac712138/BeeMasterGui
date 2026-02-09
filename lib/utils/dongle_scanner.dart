import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class DongleScanner {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription? _subscription;

  // 緩衝區，處理斷包問題
  final List<int> _buffer = [];

  // 內部序列號
  int _seq = 0;

  bool get isScanning => _port != null && _port!.isOpen;

  /// 啟動硬體掃描
  /// [portName] 指定用來掃描的 COM Port (例如 COM12)
  /// [filterName] 裝置名稱過濾關鍵字 (例如 "Dasloop" 或 "LLB")
  Future<bool> start({
    required String portName,
    required Function(String name, String mac, int rssi) onDeviceFound,
    String filterName = "Dasloop", // Log 中的預設值
  }) async {
    try {
      // 1. 開啟 Port
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) {
        print("❌ 無法開啟掃描器 Port: $portName");
        return false;
      }

      // 2. 設定參數 (115200, 8N1)
      final config = SerialPortConfig();
      config.baudRate = 115200;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = 0;
      config.dtr = SerialPortDtr.on; // Log 顯示 DTR 被拉起
      _port!.config = config;

      // 3. 監聽回傳資料
      _reader = SerialPortReader(_port!);
      _subscription = _reader!.stream.listen((data) {
        _buffer.addAll(data);
        _processBuffer(onDeviceFound);
      });

      // 4. 發送掃描指令 (0x83, 0x02, Filter...)
      await _sendScanCommand(filterName);

      return true;
    } catch (e) {
      print("Dongle Scanner Error: $e");
      stop();
      return false;
    }
  }

  void stop() {
    try {
      if (isScanning) {
        // 發送停止指令 0xE4 00 (嘗試)
        _sendRawPayload([0xE4, 0x00]);
      }
      _subscription?.cancel();
      _reader?.close();
      _port?.close();
      _port?.dispose();
    } catch (e) {
      print("Stop Error: $e");
    } finally {
      _port = null;
    }
  }

  // --- 私有方法 ---

  Future<void> _sendScanCommand(String filter) async {
    // Payload: [0x83, 0x02] + FilterBytes
    List<int> payload = [0x83, 0x02];
    payload.addAll(utf8.encode(filter));

    await _sendRawPayload(payload);
  }

  Future<void> _sendRawPayload(List<int> payload) async {
    if (_port == null) return;

    _seq++;
    int f = _seq;
    int len = payload.length;

    // Header Structure:
    // [0x25, 0x24, SeqL, SeqH, 0x00, 0x00, LenL, LenH]
    final builder = BytesBuilder();
    builder.addByte(0x25);
    builder.addByte(0x24);
    builder.addByte(f & 0xFF);
    builder.addByte((f >> 8) & 0xFF);
    builder.addByte(0x00);
    builder.addByte(0x00);
    builder.addByte(len & 0xFF);
    builder.addByte((len >> 8) & 0xFF);
    builder.add(payload);

    // Checksum: Sum of all bytes excluding header(0x25)
    List<int> bytes = builder.toBytes();
    int sum = 0;
    for (int i = 1; i < bytes.length; i++) {
      sum += bytes[i];
    }
    builder.addByte(sum & 0xFF);

    _port!.write(builder.toBytes());
  }

  void _processBuffer(Function(String, String, int) onFound) {
    // 尋找封包頭 0x25
    while (_buffer.isNotEmpty) {
      int headIndex = _buffer.indexOf(0x25);
      if (headIndex == -1) {
        _buffer.clear();
        return;
      }

      // 移除垃圾資料
      if (headIndex > 0) {
        _buffer.removeRange(0, headIndex);
      }

      // 檢查 Header 長度 (至少 8 bytes)
      if (_buffer.length < 8) return;

      // 解析長度 (Offset 6, 7)
      int len = _buffer[6] + (_buffer[7] << 8);
      int totalPacketLen = 8 + len + 1; // Header + Payload + Checksum

      if (_buffer.length < totalPacketLen) return; // 資料還沒收完

      // 取出完整封包
      List<int> packet = _buffer.sublist(0, totalPacketLen);
      _buffer.removeRange(0, totalPacketLen); // 移除已處理資料

      // 解析 Payload (Offset 8 開始)
      // 掃描回報結構: [0x84, MAC(6), RSSI(1), NameLen(1), Name(N)]
      if (len > 0 && packet[8] == 0x84) {
        try {
          // MAC Address (Offset 9-14)
          // Log 顯示是 Big Endian (84 24 88...), 直接轉 Hex
          String mac = packet
              .sublist(9, 15)
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(":");

          // RSSI (Offset 15) - Signed Byte
          int rssiByte = packet[15];
          int rssi = (rssiByte > 127) ? rssiByte - 256 : rssiByte;

          // Name (Offset 17...End)
          int nameLen = packet[16];
          if (17 + nameLen <= packet.length) {
            // 安全檢查
            String name = utf8.decode(
              packet.sublist(17, 17 + nameLen),
              allowMalformed: true,
            );
            onFound(name, mac, rssi);
          }
        } catch (e) {
          print("Parse Packet Error: $e");
        }
      }
    }
  }
}
