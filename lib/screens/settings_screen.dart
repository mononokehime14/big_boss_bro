import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/settings_store.dart';
import '../l10n/app_strings.dart';
import '../services/escpos.dart';
import '../services/receipt_print_service.dart';
import '../state/settings_controller.dart';
import 'menu_import_screen.dart';
import 'menu_manage_screen.dart';

/// 设置页：店名、货币符号、纸宽、界面语言、蓝牙打印机连接与测试。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storeCtl = TextEditingController();
  final _currencyCtl = TextEditingController();
  final _tableCtl = TextEditingController();
  final _ipCtl = TextEditingController();
  final _portCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  bool _initialized = false;
  bool _scanning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<SettingsController>().settings;
    if (!_initialized) {
      _storeCtl.text = settings.storeName;
      _currencyCtl.text = settings.currencySymbol;
      _ipCtl.text = settings.printerAddress;
      _portCtl.text = settings.printerPort.toString();
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _storeCtl.dispose();
    _currencyCtl.dispose();
    _tableCtl.dispose();
    _ipCtl.dispose();
    _portCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsCtl = context.watch<SettingsController>();
    final settings = settingsCtl.settings;

    // 语言切换：改了 L10n.lang 会自动刷新整个 App。
    String lang = L10n.currentLang;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('settings.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- 语言 ----
          _sectionTitle(L10n.t('settings.language')),
          _card(
            child: DropdownButtonFormField<String>(
              initialValue: lang,
              decoration: const InputDecoration(border: InputBorder.none),
              items: L10n.supported
                  .map((code) => DropdownMenuItem(
                        value: code,
                        child: Text(L10n.languageNames[code] ?? code),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) L10n.lang.value = v;
              },
            ),
          ),
          const SizedBox(height: 16),

          // ---- 菜品管理 ----
          _sectionTitle(L10n.t('settings.menuManage')),
          _card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restaurant_menu,
                      color: Color(0xFF1FA85A)),
                  title: Text(L10n.t('settings.menuManage')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MenuManageScreen()),
                  ),
                ),
                // 从 Excel 导入菜单
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_file,
                      color: Color(0xFF1FA85A)),
                  title: Text(L10n.t('menu.import')),
                  subtitle: Text(
                    L10n.t('menu.import.hint'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MenuImportScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- 常用备注（点菜时的“其他备注”标签）----
          _sectionTitle(L10n.t('settings.notes')),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (settings.savedNotes.isEmpty)
                  Text(
                    L10n.t('custom.note.hint'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final n in settings.savedNotes)
                        InputChip(
                          label: Text(n),
                          onDeleted: () => settingsCtl.removeSavedNote(n),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _noteCtl,
                        decoration: InputDecoration(
                          labelText: L10n.t('settings.notes.hint'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addNote(settingsCtl),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => _addNote(settingsCtl),
                      child: Text(L10n.t('settings.table.add')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- 桌号管理 ----
          _sectionTitle(L10n.t('settings.tables')),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in settings.tables)
                      InputChip(
                        label: Text(t),
                        onDeleted: () => settingsCtl.removeTable(t),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tableCtl,
                        decoration: InputDecoration(
                          labelText: L10n.t('settings.table.hint'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (v) => _addTable(settingsCtl),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => _addTable(settingsCtl),
                      child: Text(L10n.t('settings.table.add')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- 店名 & 货币 ----
          _sectionTitle(L10n.t('settings.storeName')),
          _card(
            child: TextField(
              controller: _storeCtl,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle(L10n.t('settings.currency')),
          _card(
            child: TextField(
              controller: _currencyCtl,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 16),

          // ---- 纸宽 ----
          _sectionTitle(L10n.t('settings.paperWidth')),
          _card(
            child: DropdownButtonFormField<String>(
              initialValue: settings.paperWidth,
              decoration: const InputDecoration(border: InputBorder.none),
              items: [
                DropdownMenuItem(
                    value: '58', child: Text(L10n.t('settings.paper.mm58'))),
                DropdownMenuItem(
                    value: '80', child: Text(L10n.t('settings.paper.mm80'))),
              ],
              onChanged: (v) {
                if (v != null) settingsCtl.setPaperWidth(v);
              },
            ),
          ),
          const SizedBox(height: 16),

          // ---- 打印机 ----
          _sectionTitle(L10n.t('settings.printer')),
          _card(child: _printerSection(settingsCtl, settings)),

          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => _save(settingsCtl),
            child: Text(L10n.t('settings.save')),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
          ),
        ),
      );

  Widget _card({required Widget child}) => Card(
        color: Colors.white,
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      );

  void _addTable(SettingsController ctl) {
    final v = _tableCtl.text.trim();
    if (v.isEmpty) return;
    ctl.addTable(v);
    _tableCtl.clear();
  }

  void _addNote(SettingsController ctl) {
    final v = _noteCtl.text.trim();
    if (v.isEmpty) return;
    ctl.addSavedNote(v);
    _noteCtl.clear();
  }

  void _save(SettingsController ctl) {
    ctl.update((s) {
      s.storeName = _storeCtl.text.trim().isEmpty
          ? '餐厅'
          : _storeCtl.text.trim();
      s.currencySymbol = _currencyCtl.text.trim().isEmpty
          ? '¥'
          : _currencyCtl.text.trim();
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(L10n.t('settings.saved'))));
  }

  /// 打印机设置区：选择「打印方式」+ 当前打印机 + 对应配置 + 测试页。
  Widget _printerSection(SettingsController ctl, Settings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.t('settings.transport'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _transportChip(ctl, settings, PrintTransport.bluetooth,
                L10n.t('transport.bluetooth')),
            _transportChip(ctl, settings, PrintTransport.network,
                L10n.t('transport.network')),
            _transportChip(ctl, settings, PrintTransport.windows,
                L10n.t('transport.windows')),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.print, color: Color(0xFF1FA85A)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                settings.printerName.isEmpty
                    ? L10n.t('settings.printer.none')
                    : settings.printerName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._transportConfig(ctl, settings),
        const SizedBox(height: 16),
        // ---- 小票编码（乱码就换一个再打测试页）----
        Text(L10n.t('settings.codec'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        DropdownButton<String>(
          value: settings.receiptCodec,
          isExpanded: true,
          items: kReceiptCodecs
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) {
            if (v != null) ctl.setReceiptCodec(v);
          },
        ),
        Text(
          L10n.t('settings.codec.hint'),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        // ---- 小票语言（可独立于界面语言）----
        Text(L10n.t('settings.receiptLang'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        DropdownButton<String>(
          value: settings.receiptLang,
          isExpanded: true,
          items: [
            DropdownMenuItem(
                value: '',
                child: Text(L10n.t('settings.receiptLang.follow'))),
            for (final code in L10n.supported)
              DropdownMenuItem(
                  value: code, child: Text(L10n.languageNames[code] ?? code)),
          ],
          onChanged: (v) => ctl.setReceiptLang(v ?? ''),
        ),
        const SizedBox(height: 8),
        // ---- 铺满纸宽（Font A）----
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.useFontA,
          onChanged: (v) => ctl.setUseFontA(v),
          title: Text(L10n.t('settings.fontA')),
          subtitle: Text(
            L10n.t('settings.fontA.hint'),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 4),
        FilledButton.tonalIcon(
          onPressed: () => _printTest(settings),
          icon: const Icon(Icons.local_printshop_outlined),
          label: Text(L10n.t('print.test')),
        ),
      ],
    );
  }

  Widget _transportChip(SettingsController ctl, Settings settings,
      PrintTransport t, String label) {
    final selected = settings.transport == t;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => ctl.setTransport(t),
      label: Text(label),
      showCheckmark: false,
      selectedColor: const Color(0xFF1FA85A),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF232829),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  List<Widget> _transportConfig(SettingsController ctl, Settings settings) {
    switch (settings.transport) {
      case PrintTransport.bluetooth:
        return [
          OutlinedButton.icon(
            onPressed: _scanning ? null : _scanAndChoose,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(_scanning
                ? L10n.t('settings.scanning')
                : L10n.t('settings.scan')),
          ),
        ];

      case PrintTransport.network:
        return [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipCtl,
                  decoration: InputDecoration(
                    labelText: L10n.t('settings.ip'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _portCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: L10n.t('settings.port'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => ctl.setNetworkPrinter(
              _ipCtl.text,
              int.tryParse(_portCtl.text.trim()) ?? 9100,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(L10n.t('settings.network.apply')),
          ),
        ];

      case PrintTransport.windows:
        return [
          OutlinedButton.icon(
            onPressed: _scanning ? null : _chooseWindowsPrinter,
            icon: const Icon(Icons.print_outlined),
            label: Text(_scanning
                ? L10n.t('settings.scanning')
                : L10n.t('settings.choosePrinter')),
          ),
        ];
    }
  }

  /// 扫描当前通道的设备（蓝牙设备 / Windows 已安装打印机）。
  Future<List<PrinterDevice>?> _scan() async {
    final service = context.read<ReceiptPrintService>();
    final settings = context.read<SettingsController>().settings;
    setState(() => _scanning = true);
    final devices = await service.scanDevices(settings);
    if (!mounted) return null;
    setState(() => _scanning = false);
    if (devices.isEmpty) {
      _toast(L10n.t('settings.scan.empty'));
      return null;
    }
    return devices;
  }

  /// 选择打印机：**屏幕中间的对话框**（不再是从底部弹出的抽屉）。
  Future<PrinterDevice?> _pickDevice(List<PrinterDevice> devices) {
    return showDialog<PrinterDevice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.t('settings.choosePrinter')),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final d in devices)
                ListTile(
                  leading: const Icon(Icons.print, color: Color(0xFF1FA85A)),
                  title: Text(d.name),
                  subtitle: Text(d.address),
                  onTap: () => Navigator.pop(dialogContext, d),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(L10n.t('common.cancel')),
          ),
        ],
      ),
    );
  }

  Future<void> _scanAndChoose() async {
    final devices = await _scan();
    if (devices == null) return;
    final selected = await _pickDevice(devices);
    if (selected == null || !mounted) return;
    final ctl = context.read<SettingsController>();
    if (selected.transport == PrintTransport.windows) {
      ctl.setWindowsPrinter(selected.address);
    } else {
      ctl.setBluetoothPrinter(selected.name, selected.address);
    }
    _toast(L10n.t('settings.connected'));
  }

  Future<void> _chooseWindowsPrinter() async {
    final devices = await _scan();
    if (devices == null) return;
    final selected = await _pickDevice(devices);
    if (selected == null || !mounted) return;
    context.read<SettingsController>().setWindowsPrinter(selected.address);
    _toast(L10n.t('settings.connected'));
  }

  Future<void> _printTest(Settings s) async {
    final service = context.read<ReceiptPrintService>();
    final res = await service.printTestPage(s);
    if (!mounted) return;
    _toast(res == null
        ? L10n.t('dialog.print.success')
        : '${L10n.t('dialog.print.failed')} $res');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
