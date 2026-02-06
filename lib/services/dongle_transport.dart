import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class DongleTransport {
  final String portName;
  SerialPort? _port;
  SerialPortReader? _reader;
  int _internalFid = 0;
  final List<int> _rxBuffer = [];

  DongleTransport(this.portName);

  bool open() {
    try {
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) {
        debugPrint("❌ 無法開啟 Serial Port: $portName");
        return false;
      }

      final config = SerialPortConfig();
      config.baudRate = 115200;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = 0; // None
      _port!.config = config;
      // config.dispose(); // ⚠️ Windows 上若這裡崩潰，也可註解掉，但通常 create 的是安全的

      // 啟動監聽
      _reader = SerialPortReader(_port!);
      _reader!.stream.listen((data) {
        _rxBuffer.addAll(data);
      });

      return true;
    } catch (e) {
      debugPrint("❌ Open Error: $e");
      return false;
    }
  }

  void close() {
    _reader?.close();
    if (_port != null) {
      try {
        _port!.close();
        _port!.dispose();
      } catch (e) {
        debugPrint("⚠️ Close Warning: $e");
      }
      _port = null;
    }
  }

  void resetBuffer() {
    _rxBuffer.clear();
  }

  /// DTR/RTS 重置訊號
  Future<void> toggleDtrRts() async {
    if (_port == null) return;

    try {
      // 1. 拉低電位 (False / Off)
      // ⚠️ 注意：這裡不呼叫 dispose() 以避免 Windows Debug Assertion Failed
      var config1 = _port!.config;
      config1.dtr = SerialPortDtr.off;
      config1.rts = SerialPortRts.off;
      _port!.config = config1;
      // config1.dispose(); // ❌ 註解掉這行以防止崩潰

      await Future.delayed(const Duration(milliseconds: 100));

      // 2. 拉高電位 (True / On)
      var config2 = _port!.config;
      config2.dtr = SerialPortDtr.on;
      config2.rts = SerialPortRts.on;
      _port!.config = config2;
      // config2.dispose(); // ❌ 註解掉這行以防止崩潰
    } catch (e) {
      debugPrint("⚠️ Toggle DTR/RTS Error: $e");
    }
  }

  /// 連線至安全帽
  Future<bool> connectToHelmet(List<int> macBytes) async {
    debugPrint("[$portName] 正在連線至裝置...");

    await toggleDtrRts();
    await Future.delayed(const Duration(seconds: 1));
    resetBuffer();

    // 盲發初始化 0x83, 0x00
    await _sendCmd(0x24, [0x83, 0x00]);
    await Future.delayed(const Duration(milliseconds: 200));

    // 發送 MAC 連線指令 0x85
    List<int> payload = [0x85, ...macBytes.reversed];
    await _sendCmd(0x24, payload);

    // 等待 4 秒連線
    await Future.delayed(const Duration(seconds: 4));

    await toggleDtrRts();
    await Future.delayed(const Duration(milliseconds: 500));

    // 進入模式 0x21, 0x01
    await _sendCmd(0x21, [0x01]);
    await Future.delayed(const Duration(seconds: 1));

    return true;
  }

  /// 發送音訊切片
  Future<bool> sendAudioChunk(int offset, Uint8List data) async {
    final builder = BytesBuilder();
    builder.addByte(0xC5); // OpCode

    // Offset (Little Endian 4 bytes)
    builder.addByte(offset & 0xFF);
    builder.addByte((offset >> 8) & 0xFF);
    builder.addByte((offset >> 16) & 0xFF);
    builder.addByte((offset >> 24) & 0xFF);

    // Size (Little Endian 2 bytes)
    int len = data.length;
    builder.addByte(len & 0xFF);
    builder.addByte((len >> 8) & 0xFF);

    builder.add(data);

    return await _sendCmd(0x20, builder.toBytes());
  }

  /// 底層發送指令封裝
  Future<bool> _sendCmd(int target, List<int> payload) async {
    if (_port == null) return false;
    _internalFid++;
    int f = _internalFid;
    int plLen = payload.length;

    final packet = BytesBuilder();
    packet.addByte(0x25);
    packet.addByte(target);
    packet.addByte(f & 0xFF);
    packet.addByte((f >> 8) & 0xFF);
    packet.addByte(0x00);
    packet.addByte(0x00);
    packet.addByte(plLen & 0xFF);
    packet.addByte((plLen >> 8) & 0xFF);
    packet.add(payload);

    int sum = 0;
    final bytes = packet.toBytes();
    for (int i = 1; i < bytes.length; i++) {
      sum += bytes[i];
    }
    packet.addByte(sum & 0xFF);

    try {
      _port!.write(packet.toBytes());
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 等待 ACK
  Future<bool> waitForAck(Duration timeout) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      if (_rxBuffer.isNotEmpty) {
        if (_rxBuffer.contains(0x27) ||
            _rxBuffer.contains(0x25) ||
            _rxBuffer.contains(0x26) ||
            _rxBuffer.contains(0x23)) {
          return true;
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }
}
