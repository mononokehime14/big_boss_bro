import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/menu_importer.dart';
import '../state/pos_controller.dart';

/// 从 Excel 导入菜单。
///
/// Excel 的列（顺序随意，按表头名字识别）：
/// - `分类`（种类 / 类别 / categoria）
/// - `菜名`（菜品名字 / nombre / name）
/// - `价格`（可选；支持 `12,50` 这种西语写法）
/// - 其余列**两两一组**：`(定制项名, 选项列表)`，选项用 `/` 分隔
///   例如 `Size` + `Mediano/Grande`
class MenuImportScreen extends StatefulWidget {
  const MenuImportScreen({super.key});

  @override
  State<MenuImportScreen> createState() => _MenuImportScreenState();
}

class _MenuImportScreenState extends State<MenuImportScreen> {
  final _pathCtl = TextEditingController();
  MenuImportResult? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pathCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('menu.import'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 说明
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.t('menu.import.hint'),
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade700)),
                  const SizedBox(height: 6),
                  Text(
                    '例： 分类 | 菜名 | 价格 | Size | Mediano/Grande',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          FilledButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(_busy
                ? L10n.t('settings.scanning')
                : L10n.t('menu.import.pick')),
          ),
          const SizedBox(height: 8),

          // 兜底：直接填路径
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathCtl,
                  decoration: const InputDecoration(
                    hintText: r'C:\path\to\menu.xlsx',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy ? null : _readFromPath,
                child: const Text('OK'),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: const Color(0xFFFFEBEE),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  '${L10n.t('menu.import.fail')}$_error',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
          ],

          if (_result != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.t('menu.import.ok'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text('${L10n.t('menu.import.readCategories')}: '
                        '${_result!.categoryCount}'),
                    Text('${L10n.t('menu.import.readItems')}: '
                        '${_result!.itemCount}'),
                    Text('${L10n.t('menu.import.readOptions')}: '
                        '${_result!.optionGroupCount}'),
                    for (final w in _result!.warnings) ...[
                      const SizedBox(height: 6),
                      Text('⚠ $w',
                          style: TextStyle(
                              fontSize: 12, color: Colors.orange.shade800)),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      _result!.data.categories
                          .map((c) => c.name)
                          .join(' | '),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _apply,
                        icon: const Icon(Icons.check),
                        label: Text(L10n.t('menu.import')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      final f = res.files.single;
      List<int>? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) {
        throw const MenuImportException('读不到文件内容。');
      }
      _parse(bytes);
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
        _result = null;
      });
    }
  }

  Future<void> _readFromPath() async {
    final p = _pathCtl.text.trim();
    if (p.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await File(p).readAsBytes();
      _parse(bytes);
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
        _result = null;
      });
    }
  }

  void _parse(List<int> bytes) {
    try {
      final r = MenuImporter.fromXlsx(bytes);
      setState(() {
        _result = r;
        _busy = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
        _result = null;
      });
    }
  }

  void _apply() {
    final r = _result;
    if (r == null) return;
    context.read<PosController>().replaceMenu(r.data);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(L10n.t('menu.import.ok'))));
    Navigator.pop(context);
  }
}
