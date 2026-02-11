import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:path/path.dart' as p;

// 引入專案元件
import 'package:beemaster_ui/models/worker_import_data.dart';
import 'package:beemaster_ui/widgets/dsm_settings_card.dart';
import 'package:beemaster_ui/utils/app_state.dart';

class HelmetView extends StatefulWidget {
  final Function(List<WorkerImportData>)? onDataParsed;

  const HelmetView({super.key, this.onDataParsed});

  @override
  State<HelmetView> createState() => _HelmetViewState();
}

class _HelmetViewState extends State<HelmetView> {
  // 資料狀態
  List<WorkerImportData> _parsedWorkers = [];
  List<String> _currentDasIds = [];
  bool _isParsing = false;

  // 捲軸控制器
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double rightPanelWidth = (screenWidth * 0.25).clamp(280.0, 450.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 👈 左側：工作臺
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              Expanded(
                child: InkWell(
                  // 🚩 修正：有資料時不跳視窗
                  onTap: (_isParsing || _parsedWorkers.isNotEmpty)
                      ? null
                      : _handleFilePick,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: _isParsing
                        ? const Center(child: CircularProgressIndicator())
                        : _parsedWorkers.isEmpty
                        ? _buildUploadHint()
                        : _buildParsedList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 20),

        // 👉 右側：設定區
        SizedBox(
          width: rightPanelWidth,
          child: Column(
            children: [
              _buildOpsStatusCard(),
              const SizedBox(height: 20),
              Expanded(child: DsmSettingsCard(validDasIds: _currentDasIds)),
            ],
          ),
        ),
      ],
    );
  }

  // --- 1. 頂部標題與下載 ---
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "工作臺",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        TextButton.icon(
          onPressed: _downloadTemplate,
          icon: const Icon(Icons.download, size: 16),
          label: const Text("範例檔下載"),
          style: TextButton.styleFrom(foregroundColor: Colors.amber[800]),
        ),
      ],
    );
  }

  // --- 2. 響應式解析列表 (僅此一份) ---
  Widget _buildParsedList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.list_alt_rounded,
                color: Colors.blueGrey,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                "檔案解析預覽 (共 ${_parsedWorkers.length} 筆)",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _parsedWorkers = [];
                    _currentDasIds = [];
                  });
                  if (widget.onDataParsed != null) widget.onDataParsed!([]);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
                child: const Text("捨棄檔案", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double minWidth = 1400.0;
              final double targetWidth = constraints.maxWidth > minWidth
                  ? constraints.maxWidth
                  : minWidth;
              final double dynamicSpacing = (targetWidth - 1100) / 13;

              return Scrollbar(
                controller: _verticalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _verticalController,
                  child: Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility: true,
                    notificationPredicate: (notif) => notif.depth == 0,
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: targetWidth,
                        child: DataTable(
                          columnSpacing: dynamicSpacing > 15
                              ? dynamicSpacing
                              : 15,
                          headingRowColor: WidgetStateProperty.all(
                            Colors.grey[50],
                          ),
                          border: TableBorder.all(color: Colors.grey[200]!),
                          columns: const [
                            DataColumn(
                              label: Text(
                                'DasID*',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(label: Text('UWBID')),
                            DataColumn(label: Text('SIM')),
                            DataColumn(label: Text('CollisionID')),
                            DataColumn(
                              label: Text(
                                'WorkerName*',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Gender*',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(label: Text('SerialNumber')),
                            DataColumn(label: Text('Birthday')),
                            DataColumn(label: Text('Email')),
                            DataColumn(label: Text('Phone')),
                            DataColumn(label: Text('Company')),
                            DataColumn(label: Text('Division')),
                            DataColumn(label: Text('Trade')),
                            DataColumn(label: Text('Remark')),
                          ],
                          rows: _parsedWorkers.map((worker) {
                            final dasValid = worker.dasId.length == 13;
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    worker.dasId,
                                    style: TextStyle(
                                      color: dasValid
                                          ? Colors.black
                                          : Colors.red,
                                    ),
                                  ),
                                ),
                                DataCell(Text(worker.uwbId ?? '')),
                                DataCell(Text(worker.sim ?? '')),
                                DataCell(Text(worker.collisionId ?? '')),
                                DataCell(Text(worker.workerName)),
                                DataCell(Text(worker.gender)),
                                DataCell(Text(worker.serialNumber ?? '')),
                                DataCell(Text(worker.birthday ?? '')),
                                DataCell(Text(worker.email ?? '')),
                                DataCell(Text(worker.phone ?? '')),
                                DataCell(Text(worker.company ?? '')),
                                DataCell(Text(worker.division ?? '')),
                                DataCell(Text(worker.trade ?? '')),
                                DataCell(Text(worker.remark ?? '')),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- 3. 檔案解析與下載邏輯 (修正缺失方法) ---
  Future<void> _handleFilePick() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null || result.files.single.path == null) return;
      setState(() => _isParsing = true);
      final file = File(result.files.single.path!);
      final bytes = file.readAsBytesSync();
      final excel = excel_pkg.Excel.decodeBytes(bytes);
      List<WorkerImportData> tempList = [];
      for (var table in excel.tables.keys) {
        final rows = excel.tables[table]!.rows;
        if (rows.isEmpty) continue;
        final headers = rows.first
            .map((c) => c?.value?.toString().trim() ?? "")
            .toList();
        for (int i = 1; i < rows.length; i++) {
          final row = rows[i];
          Map<String, String> data = {};
          for (int j = 0; j < headers.length; j++) {
            if (j < row.length)
              data[headers[j]] = row[j]?.value?.toString().trim() ?? "";
          }
          final dasId = data['DasID*'] ?? data['DasID'] ?? "";
          if (dasId.isNotEmpty) {
            tempList.add(
              WorkerImportData(
                dasId: dasId,
                workerName: data['WorkerName*'] ?? data['WorkerName'] ?? "",
                gender: data['Gender*'] ?? data['Gender'] ?? "",
                uwbId: data['UWBID'],
                sim: data['SIM'],
                collisionId: data['CollisionID'],
                serialNumber: data['SerialNumber'],
                birthday: data['Birthday'],
                email: data['Email'],
                phone: data['Phone'],
                company: data['Company'],
                division: data['Division'],
                trade: data['Trade'],
                remark: data['Remark'],
              ),
            );
          }
        }
      }
      setState(() {
        _parsedWorkers = tempList;
        _currentDasIds = tempList.map((w) => w.dasId).toList();
        _isParsing = false;
      });
    } catch (e) {
      setState(() => _isParsing = false);
      _showMsg("解析失敗: $e", Colors.red);
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final data = await rootBundle.load('assets/template.xlsx');
      final bytes = data.buffer.asUint8List();
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '儲存範例檔',
        fileName: 'template.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (outputFile != null) {
        await File(outputFile).writeAsBytes(bytes);
        _showMsg("下載成功", Colors.green);
      }
    } catch (e) {
      _showMsg("下載失敗: $e", Colors.red);
    }
  }

  // ==========================================
  //  🏗️ 右側 OPS / DSM 元件
  // ==========================================
  Widget _buildOpsStatusCard() {
    bool isOk = AppState.isOpsLoggedIn;
    return _simpleStatusCard(
      "OPS 設定",
      isOk,
      isOk
          ? ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
              ),
              child: const Text("建立 ENDPOINT"),
            )
          : const Center(
              child: Text("請先登入", style: TextStyle(color: Colors.grey)),
            ),
    );
  }

  Widget _simpleStatusCard(String title, bool isOk, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isOk ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isOk ? "已連線" : "未連線",
                style: TextStyle(
                  fontSize: 10,
                  color: isOk ? Colors.green : Colors.red,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildUploadHint() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.upload_file, size: 60, color: Colors.grey[300]),
        const SizedBox(height: 20),
        const Text(
          "點擊選取 Excel 檔案進行解析",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          "必填：DasID*(13碼), WorkerName*, Gender*",
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  void _showMsg(String msg, Color color) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }
}
