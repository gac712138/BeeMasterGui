import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class BurnTaskService {
  Process? _process;

  /// 啟動燒錄任務
  /// [exePath]: 由 ExeHelper 取得的絕對路徑
  /// [filePath]: ADS 檔案路徑
  /// [portName]: (可選) 指定 Port，全自動模式下可不傳
  /// [targetMac]: (可選) 指定 MAC，全自動模式下可不傳
  /// [extraArgs]: (可選) 額外參數，例如 ['-target', 'LLB']
  Future<void> startBurning({
    required String exePath,
    required String filePath,

    // 🔥 修改：變成可選參數，因為全自動模式下 Go 會自己找
    String? portName,
    String? targetMac,

    // 🔥 新增：額外參數 (用於傳遞 -target)
    List<String>? extraArgs,

    required Function(String) onLog, // Callback: 收到日誌
    required Function(double) onProgress, // Callback: 收到進度 (0.0 - 1.0)
    required Function(bool) onDone, // Callback: 結束 (true=成功, false=失敗)
  }) async {
    try {
      // 1. 建構參數列表
      List<String> args = [];

      // 加入額外參數 (例如 ["-target", "LLB"])
      if (extraArgs != null) {
        args.addAll(extraArgs);
      }

      // 加入檔案路徑 (Go 的 flag 是 -file)
      args.add('-file=$filePath');

      // ⚠️ 關鍵邏輯：
      // 如果 extraArgs 裡已經有 "-target"，代表是全自動獵人模式
      // 這時候 Go 不需要 (也不接受) -port 或 -mac (因為它會自己掃描)，所以我們略過它們
      bool isAutoHunterMode =
          extraArgs != null && extraArgs.contains('-target');

      // 只有在非自動模式下，才傳送 port 和 mac (相容舊模式)
      if (!isAutoHunterMode) {
        if (portName != null && portName.isNotEmpty) {
          args.add('-port=$portName');
        }
        if (targetMac != null && targetMac.isNotEmpty) {
          args.add('-mac=$targetMac');
        }
      }

      onLog("🚀 正在啟動 Go 核心引擎...");
      onLog("執行檔: $exePath");
      onLog("參數: ${args.join(' ')}");

      // 2. 啟動子進程
      _process = await Process.start(exePath, args, runInShell: false);

      // 3. 監聽標準輸出 (stdout) -> 這是 Go 給我們的訊息
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            // 解析 Go 協議
            if (line.startsWith('PROGRESS:')) {
              // 舊格式: PROGRESS:50
              // 新格式: PROGRESS:MAC_ADDRESS:50
              try {
                final parts = line.split(':');
                // 取最後一個部分作為百分比，這樣相容兩種格式
                if (parts.length >= 2) {
                  final pctStr = parts.last;
                  final pct = int.tryParse(pctStr) ?? 0;
                  onProgress(pct / 100.0);
                }
              } catch (e) {
                // 解析失敗忽略
              }
            } else if (line.startsWith('LOG:')) {
              // 格式: LOG:連線成功
              onLog("🤖 ${line.substring(4)}");
            } else if (line.startsWith('ERROR:')) {
              // 格式: ERROR:連線超時
              onLog("❌ ${line.substring(6)}");
            } else if (line.startsWith('SUCCESS')) {
              // 格式: SUCCESS
              onLog("✅ 任務成功完成！");
              onProgress(1.0);
            } else {
              // 其他未格式化的 Go Printf
              if (kDebugMode) print("[Go Raw]: $line");
            }
          });

      // 4. 監聽錯誤輸出 (stderr)
      _process!.stderr.transform(utf8.decoder).listen((data) {
        onLog("💥 系統錯誤: $data");
      });

      // 5. 等待程式結束
      final exitCode = await _process!.exitCode;

      // 只有 exitCode 為 0 才是真的成功
      if (exitCode == 0) {
        onDone(true);
      } else {
        onLog("⚠️ 燒錄程序異常退出 (Code: $exitCode)");
        onDone(false);
      }
    } catch (e) {
      onLog("💥 無法啟動執行檔: $e");
      onDone(false);
    } finally {
      _process = null;
    }
  }

  /// 強制中止任務
  void kill() {
    _process?.kill();
  }
}
