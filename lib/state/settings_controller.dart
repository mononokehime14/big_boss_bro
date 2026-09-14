import 'package:flutter/foundation.dart';

import '../data/settings_store.dart';

/// 设置状态：什么设置改了，通过 Provider 通知界面。
class SettingsController extends ChangeNotifier {
  final SettingsStore _store = SettingsStore();

  Settings _settings = Settings();
  Settings get settings => _settings;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    _settings = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(void Function(Settings) mutate) async {
    mutate(_settings);
    notifyListeners();
    await _store.save(_settings);
  }

  void setStoreName(String v) => _settings.storeName = v;
  void setCurrencySymbol(String v) => _settings.currencySymbol = v;
  void setPaperWidth(String v) => _settings.paperWidth = v;

  /// 小票编码（gbk / utf8 / latin1 / cp850）。
  void setReceiptCodec(String v) {
    _settings.receiptCodec = v;
    notifyListeners();
    _store.save(_settings);
  }

  /// 是否用 Font A（铺满 80mm 纸宽）。
  void setUseFontA(bool v) {
    _settings.useFontA = v;
    notifyListeners();
    _store.save(_settings);
  }

  /// 小票语言：''=跟随界面语言；'zh'/'es'/'en'。
  void setReceiptLang(String v) {
    _settings.receiptLang = v;
    notifyListeners();
    _store.save(_settings);
  }

  // ---- 打印方式与打印机 ----

  void setTransport(PrintTransport t) {
    _settings.transport = t;
    notifyListeners();
    _store.save(_settings);
  }

  /// 蓝牙：name + MAC 地址。
  void setBluetoothPrinter(String name, String address) {
    _settings.printerName = name;
    _settings.printerAddress = address;
    notifyListeners();
    _store.save(_settings);
  }

  /// 网络/以太网打印机：IP + 端口。
  void setNetworkPrinter(String ip, int port) {
    _settings.printerAddress = ip.trim();
    _settings.printerPort = port;
    _settings.printerName = _settings.printerAddress.isEmpty
        ? ''
        : '${_settings.printerAddress}:$port';
    notifyListeners();
    _store.save(_settings);
  }

  /// Windows 系统打印机（USB 等）：打印机名。
  void setWindowsPrinter(String printerName) {
    _settings.windowsPrinterName = printerName;
    _settings.printerName = printerName;
    notifyListeners();
    _store.save(_settings);
  }

  // ---- 常用「其他备注」标签 ----

  void addSavedNote(String note) {
    final v = note.trim();
    if (v.isEmpty || _settings.savedNotes.contains(v)) return;
    _settings.savedNotes.add(v);
    notifyListeners();
    _store.save(_settings);
  }

  void removeSavedNote(String note) {
    _settings.savedNotes.remove(note);
    notifyListeners();
    _store.save(_settings);
  }

  // ---- 桌号管理 ----

  void addTable(String table) {
    final v = table.trim();
    if (v.isEmpty || _settings.tables.contains(v)) return;
    _settings.tables.add(v);
    notifyListeners();
    _store.save(_settings);
  }

  void removeTable(String table) {
    _settings.tables.remove(table);
    notifyListeners();
    _store.save(_settings);
  }
}
