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

  /// **厨师单打印份数**（1~3，默认 2）。
  ///
  /// 默认 2：一张给厨师、一张给出餐服务员；两张的票面用「厨师单 1 / 2」区分
  /// （见 `receipt_layout.dart` 的 `buildKitchenRows`）。
  /// 两张是**一次连接、一次发出去**的（见 `print_service.dart`），中途不会掉线。
  int kitchenCopies;

  /// 小票上的表头语言：''=跟随界面语言；'zh'/'es'/'en' 可单独指定。
  String receiptLang;

  /// 点单区的排序方式：'default'（本机拖出来的顺序）/'name'（首字母）/'popular'（流行度）。
  /// 见 `utils/menu_sort.dart` 的 `MenuSort`。
  String menuSort;

  /// **「进行中」订单列表的排法**：`'position'`（默认：外卖 → 电话外卖 → 桌子，
  /// 桌子按桌号清单的顺序）/ `'time'`（最近保存/下厨房的在最上面）。
  /// 见 `utils/order_sort.dart` 的 `OrderSort`。
  ///
  /// 跟 [menuSort] 一样**只存本机**（属于"这台设备怎么看列表"，不同步到云端）。
  String orderSort;

  /// **「已结单」订单列表的排法**：`'time'`（默认：按结账确认时间，由近到远）/
  /// `'amount'`（按金额，由大到小）。见 `utils/order_sort.dart` 的 `ClosedSort`。
  ///
  /// 跟 [orderSort] 一样**只存本机**（属于"这台设备怎么看列表"）。
  String closedSort;

  /// 餐厅自己的桌号清单（可在设置里增删）。
  List<String> tables;

  /// 常用「其他备注」标签，**按菜品分类分组**：`分类id → 标签列表`。
  /// 键 `''` 表示「通用」（所有菜都能用）。例如 Bebida 分类下有「加冰」。
  Map<String, List<String>> notesByCategory;

  /// **自定义排序**的顺序表（点单页把「排序」选成「自定义」时用）：
  /// 里面是**种类 id 和菜品 id 混在一起**，按用户拖出来的先后排列。
  ///
  /// - 排序规则见 `utils/menu_sort.dart` 的 `sortByCustomOrder`；
  /// - 没在表里的（新导入的菜 / 从没拖过）一律排到最后，**保持菜单原本的先后**；
  /// - 存在本机（跟着 `menuSort` 走，属于"这台设备怎么看菜单"，不参与云端同步）。
  List<String> menuOrder;

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

  /// 本地**店级配置**的版本号（跟服务器 `store_settings` 上的比大小，决定要不要拉新版）。
  ///
  /// 「店级配置」= 整个店共用的那几项：店名、店头（地址/电话）、税率、货币与汇率、
  /// 桌号清单、各分类的常用备注、日结支出、菜品管理密码。
  /// **打印机地址 / 纸宽 / 小票编码这些是每台设备自己的**，不参与同步。
  int storeSettingsVersion;

  /// 上一次同步时「服务器上的店级配置」长什么样（JSON 字符串）。
  ///
  /// 用它判断本机有没有改过：`StoreSettingsSync.encode(当前设置) != 它` → 有本机改动要推。
  /// 空字符串 = **这台设备还没同步过店级配置**（第一次接入）→ 这时以服务器那份为准。
  String storeSettingsSyncedJson;

  /// 本地**员工名单**的版本号（跟服务器上的比大小，决定要不要拉新版）。
  int staffVersion;

  /// 本地员工名单有没有改过、要推给后台。
  bool staffDirty;

  Settings({
    this.storeName = kDefaultStoreName,
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
    this.kitchenCopies = 2,
    this.receiptLang = '',
    this.menuSort = 'default',
    this.orderSort = 'position',
    this.closedSort = 'time',
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
    this.storeSettingsVersion = 0,
    this.storeSettingsSyncedJson = '',
    this.staffVersion = 0,
    this.staffDirty = false,
    this.menuPassword = kDefaultMenuPassword,
    this.taxRate = 0,
    this.taxIncluded = true,
    this.baseCurrency = kDefaultBaseCurrency,
    List<String>? tables,
    Map<String, List<String>>? notesByCategory,
    List<String>? menuOrder,
    Map<String, double>? exchangeRates,
    Map<String, double>? dailyExpenses,
  })  : tables = tables ?? List.of(defaultTables),
        notesByCategory = notesByCategory ?? <String, List<String>>{},
        menuOrder = menuOrder ?? <String>[],
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

  static const List<String> defaultTables = ['1', '2', '3', '4', '5'];

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

/// 默认店名（用来判断"本机配置还是不是出厂默认值"）。
const String kDefaultStoreName = '我的餐厅';

/// 默认本位币（店里收钱的货币）。
/// 你在墨西哥开店 → 默认 MXN；其他币种的汇率在「菜品管理 → 汇率」里填。
const String kDefaultBaseCurrency = 'MXN';

// ===========================================================================
// 【临时便利设置】预填后台（Supabase）的连接信息
// ---------------------------------------------------------------------------
// 目的：换新设备 / 重装 App 时，不用在平板上手打那一长串 anon key。
// 预填的只有 **URL + anon key + 登录邮箱**；**密码永远要自己输**（绝不写进代码）。
//
// ⚠️ 两点说明：
//   1. anon key 本来就是**公开**的（设计上就是放在客户端用的），写在这里不额外增加风险；
//      但**登录邮箱**是个人信息，这份代码别往公开仓库推。
//   2. 不想要这些默认值了：把下面三个常量删掉，并把 `SettingsStore.load()` 里那三行
//      `_textOrDefault(prefs.getString(_kXxx), kDefaultXxx)` 改回 `prefs.getString(_kXxx) ?? ''`，
//      再把 `syncEnabled: prefs.getBool(...) ?? true` 的 `?? true` 去掉即可
//      （本机已经存过的值不受影响；只有"没填过"的设备才会用到默认值）。
// ===========================================================================

/// 【临时】默认 Supabase 项目地址。
const String kDefaultSupabaseUrl = 'https://upvemnnusngcheshmvbu.supabase.co';

/// 【临时】默认 Supabase anon public key（公开 key，可以放客户端）。
const String kDefaultSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVwdmVtbm51c25nY2hlc2htdmJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA0NDc4MjMsImV4cCI6MjEwNjAyMzgyM30._cVjQz28ZYCewD0IYO5sSoKZIuQCjYONP9roUZo2Dgg';

/// 【临时】默认的后台登录邮箱（设备账号）。
const String kDefaultSyncEmail = 'renhao19971222@gmail.com';

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
  // 旧键 `kitchen_font_size`：厨师单菜品字号以前是个设置项，现在**写死在代码里**
  // （`receipt_layout.dart` 的 `kKitchenItemScale` = 特大）。老设置留着不管，读的时候忽略。
  static const _kKitchenCopies = 'kitchen_copies';
  static const _kReceiptLang = 'receipt_lang';
  static const _kMenuSort = 'menu_sort';

  /// 「进行中」订单列表的排法（`position` / `time`，见 `Settings.orderSort`）。
  static const _kOrderSort = 'order_sort';

  /// 「已结单」订单列表的排法（`time` / `amount`，见 `Settings.closedSort`）。
  static const _kClosedSort = 'closed_sort';

  /// 自定义排序的顺序表（种类 id + 菜品 id 混排，见 `Settings.menuOrder`）。
  static const _kMenuOrder = 'menu_order';
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
  static const _kStoreSettingsVersion = 'store_settings_version';
  static const _kStoreSettingsSyncedJson = 'store_settings_synced_json';
  static const _kStaffVersion = 'staff_version';
  static const _kStaffDirty = 'staff_dirty';

  /// 读一个「字符串设置」：本机存过非空值就用本机的，否则用默认值。
  ///
  /// 为什么要判**空白也算没存**：设备第一次保存设置时会把"空字符串"也写回本机，
  /// 之后只用 `?? 默认值` 就永远轮不到默认值了（预填会失效）——
  /// 已经被这个坑绊过一次，所以这里显式判空白。
  static String _textOrDefault(String? stored, String fallback) =>
      (stored == null || stored.trim().isEmpty) ? fallback : stored;

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
    var tables = _decodeList(prefs.getString(_kTables), Settings.defaultTables);
    if (tables.isEmpty) tables = List.of(Settings.defaultTables);

    // 备注：优先读「按分类」的新格式；没有就把旧版扁平列表迁到「通用」下
    var notes = _decodeNotes(prefs.getString(_kNotesByCategory));
    if (notes.isEmpty) {
      final legacy = _decodeList(prefs.getString(_kSavedNotes), const []);
      if (legacy.isNotEmpty) notes = {'': legacy};
    }

    return Settings(
      storeName: prefs.getString(_kStoreName) ?? kDefaultStoreName,
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
      kitchenCopies: prefs.getInt(_kKitchenCopies) ?? 2,
      receiptLang: prefs.getString(_kReceiptLang) ?? '',
      menuSort: prefs.getString(_kMenuSort) ?? 'default',
      orderSort: prefs.getString(_kOrderSort) ?? 'position',
      closedSort: prefs.getString(_kClosedSort) ?? 'time',
      menuOrder: _decodeList(prefs.getString(_kMenuOrder), const <String>[]),
      menuPassword: prefs.getString(_kMenuPassword) ?? kDefaultMenuPassword,
      taxRate: (prefs.getDouble(_kTaxRate) ?? 0),
      taxIncluded: prefs.getBool(_kTaxIncluded) ?? true,
      baseCurrency: prefs.getString(_kBaseCurrency) ?? kDefaultBaseCurrency,
      exchangeRates: _decodeExpenses(prefs.getString(_kExchangeRates)),
      dailyExpenses: _decodeExpenses(prefs.getString(_kDailyExpenses)),
      // 后台同步
      // ⚠️ 开关默认 true、URL/anon key/邮箱用【临时默认值】预填（见文件上方那段说明）：
      //    新设备只要输一次密码就能用。**密码本身没有默认值**，留空。
      syncEnabled: prefs.getBool(_kSyncEnabled) ?? true,
      supabaseUrl: _textOrDefault(prefs.getString(_kSupabaseUrl), kDefaultSupabaseUrl),
      supabaseAnonKey:
          _textOrDefault(prefs.getString(_kSupabaseAnonKey), kDefaultSupabaseAnonKey),
      syncEmail: _textOrDefault(prefs.getString(_kSyncEmail), kDefaultSyncEmail),
      syncPassword: prefs.getString(_kSyncPassword) ?? '',
      deviceName: prefs.getString(_kDeviceName) ?? '',
      lastSyncAt: prefs.getString(_kLastSyncAt) ?? '',
      syncRefreshToken: prefs.getString(_kSyncRefreshToken) ?? '',
      menuVersion: prefs.getInt(_kMenuVersion) ?? 0,
      menuDirty: prefs.getBool(_kMenuDirty) ?? false,
      storeSettingsVersion: prefs.getInt(_kStoreSettingsVersion) ?? 0,
      storeSettingsSyncedJson: prefs.getString(_kStoreSettingsSyncedJson) ?? '',
      staffVersion: prefs.getInt(_kStaffVersion) ?? 0,
      staffDirty: prefs.getBool(_kStaffDirty) ?? false,
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
    await prefs.setInt(_kKitchenCopies, settings.kitchenCopies);
    await prefs.setString(_kReceiptLang, settings.receiptLang);
    await prefs.setString(_kMenuSort, settings.menuSort);
    await prefs.setString(_kOrderSort, settings.orderSort);
    await prefs.setString(_kClosedSort, settings.closedSort);
    await prefs.setString(_kMenuOrder, jsonEncode(settings.menuOrder));
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
    await prefs.setInt(_kStoreSettingsVersion, settings.storeSettingsVersion);
    await prefs.setString(
        _kStoreSettingsSyncedJson, settings.storeSettingsSyncedJson);
    await prefs.setInt(_kStaffVersion, settings.staffVersion);
    await prefs.setBool(_kStaffDirty, settings.staffDirty);
  }
}
