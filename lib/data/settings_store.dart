import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 打印连接方式。
enum PrintTransport {
  bluetooth('bluetooth'), // 经典蓝牙 SPP（安卓）
  network('network'), // 网络/以太网/局域网（TCP，通常是 9100 端口）
  windows('windows'); // Windows 已安装的打印机（USB 等，走系统后台打印）

  final String id;
  const PrintTransport(this.id);

  static PrintTransport fromId(String id) => PrintTransport.values.firstWhere(
        (e) => e.id == id,
        orElse: () => PrintTransport.bluetooth,
      );
}

/// 应用设置（店名、货币符号、纸宽、打印方式、打印机、桌号列表、常用备注）。
class Settings {
  String storeName;
  String currencySymbol;
  String paperWidth; // '58' 或 '80'

  /// 打印方式：蓝牙 / 网络 / Windows 系统打印机。
  PrintTransport transport;

  /// 蓝牙 MAC 地址 或 网络打印机的 IP（按 [transport] 解释）。
  String printerAddress;

  /// 网络打印机的端口（默认 9100）。
  int printerPort;

  /// Windows 系统打印机名（[PrintTransport.windows] 时使用）。
  String windowsPrinterName;

  /// 人类可读的“当前打印机”名称（用于设置页显示）。
  String printerName;

  /// 餐厅自己的桌号清单（可在设置里增删）。
  List<String> tables;

  /// 常用「其他备注」标签（点菜时可一键选）。
  List<String> savedNotes;

  Settings({
    this.storeName = '我的餐厅',
    this.currencySymbol = '¥',
    this.paperWidth = '58',
    this.transport = PrintTransport.bluetooth,
    this.printerAddress = '',
    this.printerPort = 9100,
    this.windowsPrinterName = '',
    this.printerName = '',
    List<String>? tables,
    List<String>? savedNotes,
  })  : tables = tables ?? List.of(_defaultTables),
        savedNotes = savedNotes ?? <String>[];

  static const List<String> _defaultTables = ['1', '2', '3', '4', '5'];
}

/// 用 shared_preferences 把设置存到本机（不用数据库，简单可靠）。
class SettingsStore {
  static const _kStoreName = 'store_name';
  static const _kCurrency = 'currency_symbol';
  static const _kPaperWidth = 'paper_width';
  static const _kPrinterName = 'printer_name';
  static const _kPrinterAddr = 'printer_address';
  static const _kTransport = 'print_transport';
  static const _kPrinterPort = 'printer_port';
  static const _kWindowsPrinter = 'windows_printer';
  static const _kTables = 'tables';
  static const _kSavedNotes = 'saved_notes';

  static List<String> _decodeList(String? raw, List<String> fallback) {
    if (raw == null) return List.of(fallback);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return List.of(fallback);
  }

  Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var tables = _decodeList(prefs.getString(_kTables), Settings._defaultTables);
    if (tables.isEmpty) tables = List.of(Settings._defaultTables);

    return Settings(
      storeName: prefs.getString(_kStoreName) ?? '我的餐厅',
      currencySymbol: prefs.getString(_kCurrency) ?? '¥',
      paperWidth: prefs.getString(_kPaperWidth) ?? '58',
      transport: PrintTransport.fromId(prefs.getString(_kTransport) ?? ''),
      printerAddress: prefs.getString(_kPrinterAddr) ?? '',
      printerPort: prefs.getInt(_kPrinterPort) ?? 9100,
      windowsPrinterName: prefs.getString(_kWindowsPrinter) ?? '',
      printerName: prefs.getString(_kPrinterName) ?? '',
      tables: tables,
      savedNotes: _decodeList(prefs.getString(_kSavedNotes), const []),
    );
  }

  Future<void> save(Settings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStoreName, settings.storeName);
    await prefs.setString(_kCurrency, settings.currencySymbol);
    await prefs.setString(_kPaperWidth, settings.paperWidth);
    await prefs.setString(_kTransport, settings.transport.id);
    await prefs.setString(_kPrinterAddr, settings.printerAddress);
    await prefs.setInt(_kPrinterPort, settings.printerPort);
    await prefs.setString(_kWindowsPrinter, settings.windowsPrinterName);
    await prefs.setString(_kPrinterName, settings.printerName);
    await prefs.setString(_kTables, jsonEncode(settings.tables));
    await prefs.setString(_kSavedNotes, jsonEncode(settings.savedNotes));
  }
}
