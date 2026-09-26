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

/// 应用设置。
class Settings {
  String storeName;

  /// 店头信息：店名**下面**居中打在小票上的几行（地址 / 电话 / RFC …），
  /// 一行一条（`\n` 分隔）。参考小票 `assets/receipt_print.jpg` 的头部就是这样。
  String storeHeader;

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

  /// 小票编码（内码）：gbk / utf8 / latin1 / cp850。
  String receiptCodec;

  /// 是否用 Font A（12×24）打印 —— 让 80mm 的 48 列正好铺满纸宽。
  bool useFontA;

  /// **厨师单字体大小**：1 = 正常，2 = 大（双倍高），3 = 特大（双倍宽 + 双倍高）。
  ///
  /// 实现方式：`escpos.dart` 的 `TicketScale` 会把这一行包上 ESC/POS 的
  /// `GS ! n`（0x1D 0x21 n）放大指令；**双倍宽时每行列数减半**，
  /// 所以 `receipt_layout.dart` 的 `kitchenColumns()` 会同步把列数缩掉，
  /// 否则菜名右边的字会被切出纸外。
  int kitchenFontSize;

  /// 小票上的表头语言：''=跟随界面语言；'zh'/'es'/'en' 可单独指定。
  String receiptLang;

  /// 点单区的排序方式：'default'（菜单顺序）/'name'（首字母）/'popular'（流行度）。
  /// 见 `utils/menu_sort.dart` 的 `MenuSort`。
  String menuSort;

  /// 餐厅自己的桌号清单（可在设置里增删）。
  List<String> tables;

  /// 常用「其他备注」标签，**按菜品分类分组**：`分类id → 标签列表`。
  /// 键 `''` 表示「通用」（所有菜都能用）。例如 Bebida 分类下有「加冰」。
  Map<String, List<String>> notesByCategory;

  /// 进入「菜品管理」需要的密码（开发默认 8888）。
  /// 说明：现在主要用「账号 + 权限」（见 `models/account.dart`），
  /// 这个密码保留作为**兼容/兜底**（没有管理员账号时用）。
  String menuPassword;

  /// 税率（百分比，例如 16 表示 16%）。0 = 不收税。
  double taxRate;

  /// 价格是否**已经含税**：
  /// - true（默认）：菜单上写的价就是客人付的价，税只是从里面拆出来展示；
  /// - false：**价外税**，菜单价 + 税才是客人要付的钱。
  bool taxIncluded;

  /// 店里收钱的货币（本位币）：MXN / USD / RMB。
  /// 菜价、订单金额、日结都用它。
  String baseCurrency;

  /// 汇率：**1 个该币种 = 多少本位币**。
  /// 例：本位币 MXN、`{'USD': 18.5, 'RMB': 2.6}`（本位币不用存，恒为 1）。
  /// 缺项或 <= 0 表示**没设汇率**：界面不换算，也不能用那个币种收款。
  Map<String, double> exchangeRates;

  /// 日结：每天填的「支出」，键是日期 `yyyy-MM-dd`。
  Map<String, double> dailyExpenses;

  // ---------------- 后台同步（Supabase）----------------
  //
  // 说明：收银**永远先写本机**，这些只是「怎么连后台」的配置；
  // 断网 / 没配好都不影响点单、打单、结账。

  /// 是否启用后台同步。
  bool syncEnabled;

  /// Supabase 项目地址，例如 `https://abcdefg.supabase.co`。
  String supabaseUrl;

  /// Supabase 的 **anon public** key（公开的，可以放在设备上；
  /// 千万别用 service_role key）。
  String supabaseAnonKey;

  /// 这台设备用来登录后台的账号（Supabase Auth 里建的「设备账号」）。
  String syncEmail;
  String syncPassword;

  /// 这台设备的名字（例如「收银台A」）：打在同步记录里，用来区分「谁改的单」。
  String deviceName;

  /// 上次同步成功的时间（ISO 字符串；空 = 还没成功过）。
  String lastSyncAt;

  /// 存下来的 refresh token：下次启动直接续上，不用重新输密码。
  String syncRefreshToken;

  /// 本地菜单的版本号（跟服务器上的比大小，决定要不要拉新版）。
  int menuVersion;

  /// 本地菜单有没有改过、要推给后台。
  bool menuDirty;

  Settings({
    this.storeName = '我的餐厅',
    this.storeHeader = '',
    this.currencySymbol = '¥',
    this.paperWidth = '58',
    this.transport = PrintTransport.bluetooth,
    this.printerAddress = '',
    this.printerPort = 9100,
    this.windowsPrinterName = '',
    this.printerName = '',
    this.receiptCodec = 'gbk',
    this.useFontA = true,
    this.kitchenFontSize = 1,
    this.receiptLang = '',
    this.menuSort = 'default',
    this.syncEnabled = false,
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
    this.syncEmail = '',
    this.syncPassword = '',
    this.deviceName = '',
    this.lastSyncAt = '',
    this.syncRefreshToken = '',
    this.menuVersion = 0,
    this.menuDirty = false,
    List<String>? tables,
    Map<String, List<String>>? notesByCategory,
    this.menuPassword = kDefaultMenuPassword,
    this.taxRate = 0,
    this.taxIncluded = true,
    this.baseCurrency = kDefaultBaseCurrency,
    Map<String, double>? exchangeRates,
    Map<String, double>? dailyExpenses,
  })  : tables = tables ?? List.of(_defaultTables),
        notesByCategory = notesByCategory ?? <String, List<String>>{},
        exchangeRates = exchangeRates ?? <String, double>{},
        dailyExpenses = dailyExpenses ?? <String, double>{};

  /// 某个币种的汇率（1 个该币种 = 多少本位币）。
  /// 本位币恒为 1；没设过返回 0（= 不能用它收款）。
  double rateFor(String code) {
    if (code.isEmpty) return 1;
    if (code == baseCurrency) return 1;
    return exchangeRates[code] ?? 0;
  }

  /// 这个币种能不能用来收款（本位币，或设过汇率）。
  bool canPayWith(String code) => rateFor(code) > 0;

  void setRate(String code, double rate) {
    if (code.isEmpty) return;
    if (rate <= 0) {
      exchangeRates.remove(code);
    } else {
      exchangeRates[code] = rate;
    }
  }

  static const List<String> _defaultTables = ['1', '2', '3', '4', '5'];

  /// 该菜品分类能用哪些备注：通用（'' 键） + 这个分类自己的。
  List<String> notesFor(String categoryId) => <String>[
        ...(notesByCategory[''] ?? const <String>[]),
        ...(notesByCategory[categoryId] ?? const <String>[]),
      ];

  void addNote(String categoryId, String note) {
    final v = note.trim();
    if (v.isEmpty) return;
    final list = notesByCategory.putIfAbsent(categoryId, () => <String>[]);
    if (!list.contains(v)) list.add(v);
  }

  void removeNote(String categoryId, String note) {
    notesByCategory[categoryId]?.remove(note);
  }

  double expenseFor(String dateKey) => dailyExpenses[dateKey] ?? 0;

  void setExpense(String dateKey, double value) {
    if (value == 0) {
      dailyExpenses.remove(dateKey);
    } else {
      dailyExpenses[dateKey] = value;
    }
  }
}

/// 「菜品管理」的默认密码（开发默认 8888）。
const String kDefaultMenuPassword = '8888';

/// 默认本位币（店里收钱的货币）。
/// 你在墨西哥开店 → 默认 MXN；其他币种的汇率在「菜品管理 → 汇率」里填。
const String kDefaultBaseCurrency = 'MXN';

/// 用 shared_preferences 把设置存到本机（不用数据库，简单可靠）。
class SettingsStore {
  static const _kStoreName = 'store_name';
  static const _kStoreHeader = 'store_header';
  static const _kCurrency = 'currency_symbol';
  static const _kPaperWidth = 'paper_width';
  static const _kPrinterName = 'printer_name';
  static const _kPrinterAddr = 'printer_address';
  static const _kTransport = 'print_transport';
  static const _kPrinterPort = 'printer_port';
  static const _kWindowsPrinter = 'windows_printer';
  static const _kTables = 'tables';
  static const _kSavedNotes = 'saved_notes'; // 旧版（扁平列表），仅用于迁移
  static const _kNotesByCategory = 'notes_by_category';
  static const _kReceiptCodec = 'receipt_codec';
  static const _kUseFontA = 'use_font_a';
  static const _kKitchenFontSize = 'kitchen_font_size';
  static const _kReceiptLang = 'receipt_lang';
  static const _kMenuSort = 'menu_sort';
  static const _kMenuPassword = 'menu_password';
  static const _kDailyExpenses = 'daily_expenses';
  static const _kTaxRate = 'tax_rate';
  static const _kTaxIncluded = 'tax_included';
  static const _kBaseCurrency = 'base_currency';
  static const _kExchangeRates = 'exchange_rates';
  // 后台同步（Supabase）
  static const _kSyncEnabled = 'sync_enabled';
  static const _kSupabaseUrl = 'supabase_url';
  static const _kSupabaseAnonKey = 'supabase_anon_key';
  static const _kSyncEmail = 'sync_email';
  static const _kSyncPassword = 'sync_password';
  static const _kDeviceName = 'device_name';
  static const _kLastSyncAt = 'last_sync_at';
  static const _kSyncRefreshToken = 'sync_refresh_token';
  static const _kMenuVersion = 'menu_version';
  static const _kMenuDirty = 'menu_dirty';

  static List<String> _decodeList(String? raw, List<String> fallback) {
    if (raw == null) return List.of(fallback);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return List.of(fallback);
  }

  static Map<String, List<String>> _decodeNotes(String? raw) {
    if (raw == null) return <String, List<String>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, List<String>>{};
        decoded.forEach((k, v) {
          if (v is List) {
            out[k.toString()] = v.map((e) => e.toString()).toList();
          }
        });
        return out;
      }
    } catch (_) {}
    return <String, List<String>>{};
  }

  static Map<String, double> _decodeExpenses(String? raw) {
    if (raw == null) return <String, double>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, double>{};
        decoded.forEach((k, v) {
          if (v is num) out[k.toString()] = v.toDouble();
        });
        return out;
      }
    } catch (_) {}
    return <String, double>{};
  }

  Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var tables = _decodeList(prefs.getString(_kTables), Settings._defaultTables);
    if (tables.isEmpty) tables = List.of(Settings._defaultTables);

    // 备注：优先读「按分类」的新格式；没有就把旧版扁平列表迁到「通用」下
    var notes = _decodeNotes(prefs.getString(_kNotesByCategory));
    if (notes.isEmpty) {
      final legacy = _decodeList(prefs.getString(_kSavedNotes), const []);
      if (legacy.isNotEmpty) notes = {'': legacy};
    }

    return Settings(
      storeName: prefs.getString(_kStoreName) ?? '我的餐厅',
      storeHeader: prefs.getString(_kStoreHeader) ?? '',
      currencySymbol: prefs.getString(_kCurrency) ?? '¥',
      paperWidth: prefs.getString(_kPaperWidth) ?? '58',
      transport: PrintTransport.fromId(prefs.getString(_kTransport) ?? ''),
      printerAddress: prefs.getString(_kPrinterAddr) ?? '',
      printerPort: prefs.getInt(_kPrinterPort) ?? 9100,
      windowsPrinterName: prefs.getString(_kWindowsPrinter) ?? '',
      printerName: prefs.getString(_kPrinterName) ?? '',
      tables: tables,
      notesByCategory: notes,
      receiptCodec: prefs.getString(_kReceiptCodec) ?? 'gbk',
      useFontA: prefs.getBool(_kUseFontA) ?? true,
      kitchenFontSize: prefs.getInt(_kKitchenFontSize) ?? 1,
      receiptLang: prefs.getString(_kReceiptLang) ?? '',
      menuSort: prefs.getString(_kMenuSort) ?? 'default',
      menuPassword: prefs.getString(_kMenuPassword) ?? kDefaultMenuPassword,
      taxRate: (prefs.getDouble(_kTaxRate) ?? 0),
      taxIncluded: prefs.getBool(_kTaxIncluded) ?? true,
      baseCurrency: prefs.getString(_kBaseCurrency) ?? kDefaultBaseCurrency,
      exchangeRates: _decodeExpenses(prefs.getString(_kExchangeRates)),
      dailyExpenses: _decodeExpenses(prefs.getString(_kDailyExpenses)),
      // 后台同步
      syncEnabled: prefs.getBool(_kSyncEnabled) ?? false,
      supabaseUrl: prefs.getString(_kSupabaseUrl) ?? '',
      supabaseAnonKey: prefs.getString(_kSupabaseAnonKey) ?? '',
      syncEmail: prefs.getString(_kSyncEmail) ?? '',
      syncPassword: prefs.getString(_kSyncPassword) ?? '',
      deviceName: prefs.getString(_kDeviceName) ?? '',
      lastSyncAt: prefs.getString(_kLastSyncAt) ?? '',
      syncRefreshToken: prefs.getString(_kSyncRefreshToken) ?? '',
      menuVersion: prefs.getInt(_kMenuVersion) ?? 0,
      menuDirty: prefs.getBool(_kMenuDirty) ?? false,
    );
  }

  Future<void> save(Settings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStoreName, settings.storeName);
    await prefs.setString(_kStoreHeader, settings.storeHeader);
    await prefs.setString(_kCurrency, settings.currencySymbol);
    await prefs.setString(_kPaperWidth, settings.paperWidth);
    await prefs.setString(_kTransport, settings.transport.id);
    await prefs.setString(_kPrinterAddr, settings.printerAddress);
    await prefs.setInt(_kPrinterPort, settings.printerPort);
    await prefs.setString(_kWindowsPrinter, settings.windowsPrinterName);
    await prefs.setString(_kPrinterName, settings.printerName);
    await prefs.setString(_kTables, jsonEncode(settings.tables));
    await prefs.setString(
        _kNotesByCategory, jsonEncode(settings.notesByCategory));
    await prefs.setString(_kReceiptCodec, settings.receiptCodec);
    await prefs.setBool(_kUseFontA, settings.useFontA);
    await prefs.setInt(_kKitchenFontSize, settings.kitchenFontSize);
    await prefs.setString(_kReceiptLang, settings.receiptLang);
    await prefs.setString(_kMenuSort, settings.menuSort);
    await prefs.setString(_kMenuPassword, settings.menuPassword);
    await prefs.setDouble(_kTaxRate, settings.taxRate);
    await prefs.setBool(_kTaxIncluded, settings.taxIncluded);
    await prefs.setString(_kBaseCurrency, settings.baseCurrency);
    await prefs.setString(_kExchangeRates, jsonEncode(settings.exchangeRates));
    await prefs.setString(_kDailyExpenses, jsonEncode(settings.dailyExpenses));
    // 后台同步
    await prefs.setBool(_kSyncEnabled, settings.syncEnabled);
    await prefs.setString(_kSupabaseUrl, settings.supabaseUrl);
    await prefs.setString(_kSupabaseAnonKey, settings.supabaseAnonKey);
    await prefs.setString(_kSyncEmail, settings.syncEmail);
    await prefs.setString(_kSyncPassword, settings.syncPassword);
    await prefs.setString(_kDeviceName, settings.deviceName);
    await prefs.setString(_kLastSyncAt, settings.lastSyncAt);
    await prefs.setString(_kSyncRefreshToken, settings.syncRefreshToken);
    await prefs.setInt(_kMenuVersion, settings.menuVersion);
    await prefs.setBool(_kMenuDirty, settings.menuDirty);
  }
}
