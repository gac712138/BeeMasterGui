import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import '../../models/worker_import_data.dart';
// ❌ 已移除：不再這裡 import burn_task_sheet

class HelmetView extends StatefulWidget {
  // ✅ 修改 1: 新增 callback，讓父層知道資料解析完成了
  final Function(List<WorkerImportData>)? onDataParsed;

  const HelmetView({super.key, this.onDataParsed});

  @override
  State<HelmetView> createState() => _HelmetViewState();
}

class _HelmetViewState extends State<HelmetView> {
  List<WorkerImportData> _parsedWorkers = [];
  bool _isParsing = false;

  // --- 1. 範例檔下載邏輯 ---
  Future<void> _downloadTemplate() async {
    try {
      final data = await rootBundle.load('assets/template.xlsx');
      final bytes = data.buffer.asUint8List();

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '請選擇範例檔儲存位置',
        fileName: 'template.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
        _showMsg("範例檔下載成功", Colors.green);
      }
    } catch (e) {
      _showMsg("下載失敗: $e", Colors.red);
    }
  }

  // --- 2. 檔案選取與解析邏輯 ---
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

        final headerRow = rows.first
            .map((cell) => cell?.value?.toString().trim() ?? "")
            .toList();

        for (int i = 1; i < rows.length; i++) {
          final row = rows[i];
          Map<String, String> rowData = {};

          for (int j = 0; j < headerRow.length; j++) {
            if (j < row.length) {
              rowData[headerRow[j]] = row[j]?.value?.toString().trim() ?? "";
            }
          }

          final dasId = rowData['DasID*'] ?? rowData['DasID'] ?? "";
          final name = rowData['WorkerName*'] ?? rowData['WorkerName'] ?? "";
          final gender = rowData['Gender*'] ?? rowData['Gender'] ?? "";

          if (dasId.isNotEmpty || name.isNotEmpty) {
            tempList.add(
              WorkerImportData(
                dasId: dasId,
                workerName: name,
                gender: gender,
                uwbId: rowData['UWBID'],
                sim: rowData['SIM'],
                collisionId: rowData['CollisionID'],
                serialNumber: rowData['SerialNumber'],
                birthday: rowData['Birthday'],
                email: rowData['Email'],
                phone: rowData['Phone'],
                company: rowData['Company'],
                division: rowData['Division'],
                trade: rowData['Trade'],
                remark: rowData['Remark'],
              ),
            );
          }
        }
      }

      setState(() {
        _parsedWorkers = tempList;
        _isParsing = false;
      });

      // ✅ 修改 2: 資料解析完畢後，通知父層
      if (widget.onDataParsed != null) {
        widget.onDataParsed!(_parsedWorkers);
      }

      _showMsg("解析完成，共計 ${_parsedWorkers.length} 筆資料", Colors.green);
    } catch (e) {
      setState(() => _isParsing = false);
      _showMsg("解析失敗: $e", Colors.red);
    }
  }

  // --- 3. 驗證工具方法 ---
  bool _isDasIdValid(String id) => id.length == 13;
  bool _isGenderValid(String gender) {
    final g = gender.toLowerCase().trim();
    return g == 'male' || g == 'female';
  }

  void _showMsg(String msg, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "工作臺",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            // ✅ 修改 3: 移除了「開啟燒錄任務」按鈕，只保留下載範例
            TextButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download, size: 16),
              label: const Text("範例檔下載"),
              style: TextButton.styleFrom(foregroundColor: Colors.amber[800]),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: InkWell(
            onTap: _isParsing ? null : _handleFilePick,
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
    );
  }

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
                  setState(() => _parsedWorkers = []);
                  // 清除時也要通知父層清空
                  if (widget.onDataParsed != null) widget.onDataParsed!([]);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red[400],
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text("捨棄檔案", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  headingRowHeight: 40,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 40,
                  headingRowColor: MaterialStateProperty.all(Colors.grey[50]),
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
                    final dasIdValid = _isDasIdValid(worker.dasId);
                    final genderValid = _isGenderValid(worker.gender);
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            worker.dasId,
                            style: TextStyle(
                              color: dasIdValid ? Colors.black : Colors.red,
                              fontWeight: dasIdValid
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
                        DataCell(Text(worker.uwbId ?? '')),
                        DataCell(Text(worker.sim ?? '')),
                        DataCell(Text(worker.collisionId ?? '')),
                        DataCell(Text(worker.workerName)),
                        DataCell(
                          Text(
                            worker.gender,
                            style: TextStyle(
                              color: genderValid ? Colors.black : Colors.red,
                              fontWeight: genderValid
                                  ? FontWeight.normal
                                  : FontWeight.bold,
                            ),
                          ),
                        ),
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
        const SizedBox(height: 8),
        Text(
          "必填：DasID*(13碼), WorkerName*, Gender*(male/female)",
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }
}
