import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class DongleTransport {
  final String portName;
  SerialPort? _port;
  SerialPortReader? _reader;

  int _seq = 0;
  final List<int> _rxBuffer = [];
  Completer<bool>? _ackCompleter;

  DongleTransport(this.portName);

  // 內部開啟函式
  bool _openInternal() {
    try {
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) {
        print("❌ Open Error: $portName");
        return false;
      }

      // 設定 DTR/RTS 為 ON (High)
      final config = SerialPortConfig();
      config.baudRate = 115200;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = 0;
      config.rts = SerialPortRts.on;
      config.dtr = SerialPortDtr.on; // 開啟時拉高 DTR
      config.cts = SerialPortCts.ignore;
      config.dsr = SerialPortDsr.ignore;
      config.xonXoff = SerialPortXonXoff.disabled;
      _port!.config = config;

      _reader = SerialPortReader(_port!);
      _reader!.stream.listen(
        (data) {
          // Debug: 印出 RX
          String hex = data
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ');
          if (hex.isNotEmpty) print("[$portName] RX: $hex");
          _rxBuffer.addAll(data);
          _checkAck();
        },
        onError: (e) {
          print("[$portName] Stream Error: $e");
        },
      );

      return true;
    } catch (e) {
      print("Exception opening port: $e");
      return false;
    }
  }

  bool open() {
    return _openInternal();
  }

  Future<void> close() async {
    _reader?.close();
    try {
      if (_port != null && _port!.isOpen) _port!.close();
    } catch (e) {}
    _port?.dispose();
  }

  // 🔥 核心修正：用「關閉再開啟」來模擬 DTR Reset
  // 這能產生與 Go 版本 SetDTR(false/true) 相同的電位變化，但不會讓 Flutter 崩潰
  Future<bool> _physicalReset() async {
    print("[$portName] 🔌 執行物理重置 (Close -> Open)...");

    // 1. 關閉 Port (DTR 會自動掉下來)
    await close();

    // 2. 等待 100ms (模擬 Reset Pulse)
    await Future.delayed(const Duration(milliseconds: 100));

    // 3. 重新開啟 Port (DTR 會被拉高)
    if (!_openInternal()) {
      print("[$portName] ❌ 重啟失敗！");
      return false;
    }
    return true;
  }

  void resetBuffer() {
    if (_port != null) {
      try {
        _port!.flush(SerialPortBuffer.input);
        _port!.flush(SerialPortBuffer.output);
      } catch (e) {}
    }
    _rxBuffer.clear();
    if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
      _ackCompleter = null;
    }
  }

  Future<bool> connect(String mac) async {
    _seq = 0;

    // 1. 第一次重置 (喚醒 Dongle)
    // Go: s.toggleDTR_RTS(100ms)
    await _physicalReset();
    await Future.delayed(const Duration(seconds: 1));
    resetBuffer();

    // 2. Stop Scan
    await sendCmd(0x24, [0x83, 0x00]);
    await Future.delayed(const Duration(milliseconds: 200));

    // 3. Connect (0x85)
    List<int> macBytes = mac
        .split(':')
        .map((s) => int.parse(s, radix: 16))
        .toList();
    List<int> reversedMac = macBytes.reversed.toList();
    List<int> connPayload = [0x85, ...reversedMac];

    print("[$portName] 發送連線指令...");
    await sendCmd(0x24, connPayload);

    // 4. 等待連線建立 (Go: 4s)
    print("[$portName] 等待連線建立 (4s)...");
    await Future.delayed(const Duration(seconds: 4));

    // 5. 🔥 第二次重置 (關鍵：切換透傳模式)
    // Go: s.toggleDTR_RTS(100ms)
    // 我們用物理重開來模擬這個動作，這是最安全的做法
    print("[$portName] 執行第二次重置 (切換模式)...");
    if (!await _physicalReset()) {
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 500));

    // 6. Magic Command (0x21 0x01)
    // Go: s.SendCmd(0x21...)
    print("[$portName] 發送 Magic Command (0x21)...");
    await sendCmd(0x21, [0x01]);

    // 如果這裡有收到回應，代表連線成功建立
    await Future.delayed(const Duration(seconds: 1));

    return true;
  }

  Future<void> disconnect() async {
    await sendCmd(0x24, [0x86]);
  }

  Future<void> sendAudioChunk(int target, int offset, List<int> data) async {
    int size = data.length;
    List<int> payload = [];
    payload.add(0xC5);
    payload.add(offset & 0xFF);
    payload.add((offset >> 8) & 0xFF);
    payload.add((offset >> 16) & 0xFF);
    payload.add((offset >> 24) & 0xFF);
    payload.add(size & 0xFF);
    payload.add((size >> 8) & 0xFF);
    payload.addAll(data);
    await sendCmd(target, payload);
  }

  Future<void> sendCmd(int target, List<int> payload) async {
    if (_port == null) return;
    _seq++;
    int f = _seq;
    int len = payload.length;

    final builder = BytesBuilder();
    builder.addByte(0x25);
    builder.addByte(target);
    builder.addByte(f & 0xFF);
    builder.addByte((f >> 8) & 0xFF);
    builder.addByte(0x00);
    builder.addByte(0x00);
    builder.addByte(len & 0xFF);
    builder.addByte((len >> 8) & 0xFF);
    builder.add(payload);

    List<int> bytes = builder.toBytes();
    int sum = 0;
    for (int i = 1; i < bytes.length; i++) sum += bytes[i];
    builder.addByte(sum & 0xFF);

    try {
      final dataToSend = builder.toBytes();
      String hex = dataToSend
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      print("[$portName] TX: $hex");
      _port!.write(dataToSend);
    } catch (e) {
      print("Write Error: $e");
    }
  }

  Future<bool> waitForAck({int timeoutMs = 2000}) async {
    _ackCompleter = Completer<bool>();
    _checkAck();
    if (_ackCompleter!.isCompleted) return true;
    try {
      return await _ackCompleter!.future.timeout(
        Duration(milliseconds: timeoutMs),
      );
    } catch (e) {
      return false;
    }
  }

  void _checkAck() {
    if (_ackCompleter == null || _ackCompleter!.isCompleted) return;
    for (int i = 0; i < _rxBuffer.length; i++) {
      int b = _rxBuffer[i];
      if (b == 0x25 || b == 0x23 || b == 0x26 || b == 0x27) {
        _ackCompleter!.complete(true);
        _rxBuffer.clear();
        return;
      }
    }
  }
}
