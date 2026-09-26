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

  /// 直接落盘：同步服务改了 `lastSyncAt` / `syncRefreshToken` / `menuVersion`
  /// 这类字段后调用（它们不是用户手动改的，不用重建界面）。
  Future<void> persist() => _store.save(_settings);

  // ---- 后台同步（Supabase）----

  /// 改一个同步配置项（地址 / key / 账号 / 设备名 / 开关）+ 通知界面 + 落盘。
  Future<void> updateSync(void Function(Settings) mutate) async {
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

  /// 店头信息（小票上店名下面居中打的几行：地址 / 电话 / RFC …）。
  void setStoreHeader(String v) {
    _settings.storeHeader = v;
    notifyListeners();
    _store.save(_settings);
  }

  /// 厨师单字体大小：1 = 正常，2 = 大（双倍高），3 = 特大（双倍宽 + 双倍高）。
  void setKitchenFontSize(int v) {
    _settings.kitchenFontSize = (v < 1 || v > 3) ? 1 : v;
    notifyListeners();
    _store.save(_settings);
  }

  /// 小票语言：''=跟随界面语言；'zh'/'es'/'en'。
  void setReceiptLang(String v) {
    _settings.receiptLang = v;
    notifyListeners();
    _store.save(_settings);
  }

  /// 点单区的排序方式：'default' / 'name'（首字母）/ 'popular'（流行度）。
  /// 见 `utils/menu_sort.dart` 的 `MenuSort`。
  void setMenuSort(String id) {
    _settings.menuSort = id;
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

  // ---- 常用「其他备注」标签（按菜品分类分组）----

  /// [categoryId] 为 '' 表示「通用」（所有菜都能用）。
  void addSavedNote(String categoryId, String note) {
    _settings.addNote(categoryId, note);
    notifyListeners();
    _store.save(_settings);
  }

  void removeSavedNote(String categoryId, String note) {
    _settings.removeNote(categoryId, note);
    notifyListeners();
    _store.save(_settings);
  }

  // ---- 日结：支出 ----

  void setDailyExpense(String dateKey, double value) {
    _settings.setExpense(dateKey, value);
    notifyListeners();
    _store.save(_settings);
  }

  // ---- 菜品管理密码 ----

  void setMenuPassword(String password) {
    final v = password.trim();
    if (v.isEmpty) return;
    _settings.menuPassword = v;
    notifyListeners();
    _store.save(_settings);
  }

  // ---- 税 ----

  /// 税率（百分比，0 = 不收税）。
  void setTaxRate(double rate) {
    final v = rate < 0 ? 0.0 : rate;
    _settings.taxRate = v;
    notifyListeners();
    _store.save(_settings);
  }

  /// 价格是否已含税。
  void setTaxIncluded(bool v) {
    _settings.taxIncluded = v;
    notifyListeners();
    _store.save(_settings);
  }

  // ---- 币种与汇率 ----

  /// 店里收钱的货币（本位币）：MXN / USD / RMB。
  void setBaseCurrency(String code) {
    final v = code.trim();
    if (v.isEmpty) return;
    _settings.baseCurrency = v;
    notifyListeners();
    _store.save(_settings);
  }

  /// 某个币种的汇率（**1 个该币种 = 多少本位币**）；填 0 = 清除。
  void setExchangeRate(String code, double rate) {
    _settings.setRate(code, rate);
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
