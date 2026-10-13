import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/custom_menu_entry.dart' show kCustomCategoryId;
import '../data/settings_store.dart';
import '../l10n/app_strings.dart';
import '../models/order.dart' show kCashCurrencies; // 币种与汇率
import '../services/escpos.dart';
import '../services/receipt_print_service.dart';
import '../services/sync_service.dart';
import '../state/auth_controller.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import '../utils/menu_sort.dart'; // sortedTables()：桌号按自然顺序显示
import '../widgets/account_menu.dart';
import '../widgets/admin_gate.dart';
import 'accounts_screen.dart';
import 'menu_import_screen.dart';
import 'menu_manage_screen.dart';

/// 设置页：账号、店名、货币、税、纸宽、界面语言、打印机、桌号、备注、菜单管理。
///
/// **整页是管理员专区**（`home_shell.dart` 里点「设置」标签就会要求管理员密码）；
/// 菜单管理和 Excel 导入再单独要一次管理员权限（防止误清空菜单）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storeCtl = TextEditingController();
  final _headerCtl = TextEditingController();
  final _currencyCtl = TextEditingController();
  final _tableCtl = TextEditingController();
  final _ipCtl = TextEditingController();
  final _portCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  final _taxCtl = TextEditingController();
  // 后台同步（Supabase）
  final _supabaseUrlCtl = TextEditingController();
  final _anonKeyCtl = TextEditingController();
  final _deviceNameCtl = TextEditingController();
  final _syncEmailCtl = TextEditingController();
  final _syncPasswordCtl = TextEditingController();
  /// 上一次「从设置填进输入框」的值（键 = 字段名）。
  ///
  /// 用途：店级配置可能被**后台同步**改掉（比如新设备第一次同步，把云端的店名/地址/
  /// 税率/货币拉下来了）—— 那时输入框里还显示旧值，用户一按「保存」就会把刚拉下来的
  /// 值又写回成旧的。所以这里要知道"框里的内容是不是我们填进去的"：
  /// **只有用户没动过的框**才允许被刷新（见 [_setIfIdle]）。
  final Map<String, String> _filled = {};

  /// 正在管理哪个种类的备注：**null = 还没选**（一开始不选任何种类），
  /// `''` = 通用（所有种类都能用），其它 = 某个种类 id。
  String? _noteCatId;
  bool _scanning = false;

  /// 汇率输入框（按币种各一个；第一次 build 时懒创建）。
  final Map<String, TextEditingController> _rateCtls = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<SettingsController>().settings;
    _fillFields(settings);
  }

  /// 把设置里的值填进输入框（第一次是初始化；之后只刷新"用户没动过"的框）。
  void _fillFields(Settings settings) {
    _setIfIdle('storeName', _storeCtl, settings.storeName);
    _setIfIdle('storeHeader', _headerCtl, settings.storeHeader);
    _setIfIdle('currency', _currencyCtl, settings.currencySymbol);
    _setIfIdle('ip', _ipCtl, settings.printerAddress);
    _setIfIdle('port', _portCtl, settings.printerPort.toString());
    _setIfIdle('tax', _taxCtl, settings.taxRate == 0 ? '' : _fmtRate(settings.taxRate));
    _setIfIdle('supabaseUrl', _supabaseUrlCtl, settings.supabaseUrl);
    _setIfIdle('anonKey', _anonKeyCtl, settings.supabaseAnonKey);
    _setIfIdle('deviceName', _deviceNameCtl, settings.deviceName);
    _setIfIdle('syncEmail', _syncEmailCtl, settings.syncEmail);
    _setIfIdle('syncPassword', _syncPasswordCtl, settings.syncPassword);
  }

  /// 刷新一个输入框，但**只在用户没改过它的时候**。
  ///
  /// 判断：框里的内容 == 上次我们填进去的值（没动过）→ 可以刷新；
  /// 或者框里的内容 == 现在设置里的值（用户自己改的已经存进去了）→ 记一笔，以后也能刷新。
  void _setIfIdle(String key, TextEditingController c, String value) {
    final last = _filled[key];
    final idle = last == null || c.text == last || c.text == value;
    if (!idle) return; // 用户正在改这个框 → 不打扰
    if (c.text != value) c.text = value;
    _filled[key] = value;
  }

  @override
  void dispose() {
    _storeCtl.dispose();
    _headerCtl.dispose();
    _currencyCtl.dispose();
    _tableCtl.dispose();
    _ipCtl.dispose();
    _portCtl.dispose();
    _noteCtl.dispose();
    _taxCtl.dispose();
    _supabaseUrlCtl.dispose();
    _anonKeyCtl.dispose();
    _deviceNameCtl.dispose();
    _syncEmailCtl.dispose();
    _syncPasswordCtl.dispose();
    for (final c in _rateCtls.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmtRate(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// 汇率的输入框（没设过就是空的）。
  TextEditingController _rateCtl(String code, double rate) =>
      _rateCtls.putIfAbsent(
        code,
        () => TextEditingController(text: rate <= 0 ? '' : _fmtRate(rate)),
      );

  /// 一行汇率：`1 USD = [ 18.50 ]`。
  ///
  /// **改完立刻保存**（不用点按钮）；清空 = 没设汇率 → 收款时那个币种是灰的。
  Widget _rateRow(
    SettingsController ctl,
    String code,
    double rate,
    String baseSymbol,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '1 $code =',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _rateCtl(code, rate),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                prefixText: '$baseSymbol ',
                hintText: '0',
              ),
              onChanged: (v) => ctl.setExchangeRate(
                code,
                double.tryParse(v.trim().replaceAll(',', '.')) ?? 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsCtl = context.watch<SettingsController>();
    final settings = settingsCtl.settings;
    final auth = context.watch<AuthController>();
    final currency = settings.currencySymbol;

    // 语言切换：改了 L10n.lang 会自动刷新整个 App。
    String lang = L10n.currentLang;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t('settings.title')),
        actions: const [AccountMenuButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- 账号 ----
          _sectionTitle(L10n.t('auth.account')),
          _card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    auth.isAdmin
                        ? Icons.admin_panel_settings
                        : Icons.person_outline,
                    color: const Color(0xFF1FA85A),
                  ),
                  title: Text(auth.currentName),
                  subtitle: Text(
                    '${auth.isAdmin ? L10n.t('auth.admin') : L10n.t('auth.cashier')}'
                    '${auth.isElevated ? ' · ${L10n.t('auth.elevated')}' : ''}',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.manage_accounts,
                      color: Color(0xFF1FA85A)),
                  title: Text(L10n.t('auth.manage')),
                  subtitle: Text(
                    L10n.t('auth.manageHint'),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final ok = await requireAdmin(context);
                    if (!ok || !context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AccountsScreen()),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_outline,
                      color: Color(0xFF1FA85A)),
                  title: Text(L10n.t('auth.lock')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.read<AuthController>().signOut(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

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

          // ---- 菜品管理（需要密码；开发默认 8888）----
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
                  onTap: () => _openMenuManage(),
                ),
                // 从 Excel 导入菜单（同样要密码，防止员工误清空菜单）
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
                  onTap: () => _openMenuImport(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- 税（和「菜品管理」挨着：菜单价格与税、汇率是一件事）----
          _sectionTitle(L10n.t('settings.tax')),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _taxCtl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: L10n.t('settings.taxRate'),
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixText: '%',
                  ),
                  onChanged: (v) => settingsCtl.setTaxRate(
                    double.tryParse(v.trim().replaceAll(',', '.')) ?? 0,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.taxIncluded,
                  onChanged: settingsCtl.setTaxIncluded,
                  title: Text(L10n.t('settings.taxIncluded')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- 币种与汇率（收款框里的三个币种按它换算）----
          // 这套原来在「菜品管理」里，按你的要求搬到设置页（和税率挨着，都是钱的事）
          _sectionTitle(L10n.t('menu.rates')),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 本位币 = 店里收钱的货币
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        L10n.t('menu.baseCurrency'),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    DropdownButton<String>(
                      value: settings.baseCurrency,
                      items: [
                        for (final c in kCashCurrencies)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) {
                        if (v != null) settingsCtl.setBaseCurrency(v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  L10n.t('menu.rates.hint'),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const Divider(height: 18),
                // 其它币种的汇率：改完立刻保存；清空 = 没设汇率（收款时那个币种是灰的）
                for (final code in kCashCurrencies)
                  if (code != settings.baseCurrency)
                    _rateRow(
                        settingsCtl, code, settings.rateFor(code), currency),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- 常用备注（按种类分组的「其他备注」标签）----
          // 用法：**先在上面选一个种类**，下面才显示这个种类的备注（每条后面的 ✕ 直接删），
          // 最下面的输入框加一条新的。一开始什么都不选，避免"到底在看哪个种类"看错。
          _sectionTitle(L10n.t('settings.notes')),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                DropdownButton<String>(
                  value: _noteCatId,
                  isExpanded: true,
                  hint: Text(L10n.t('settings.notes.pickCategory')),
                  items: [
                    DropdownMenuItem(
                        value: '', child: Text(L10n.t('settings.notes.general'))),
                    for (final c in context.watch<PosController>().categories)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                    // 内置的「自定义」那一类也要能管（点「自定义」时那个框会用它）
                    DropdownMenuItem(
                      value: kCustomCategoryId,
                      child: Text(L10n.t('custom.category')),
                    ),
                  ],
                  onChanged: (v) => setState(() => _noteCatId = v),
                ),
                const SizedBox(height: 8),
                // ① 还没选种类 → 空；② 选了但没有备注 → 也说一句；
                // ③ 有备注 → 一条一个标签，点 ✕ 就删掉
                if (_noteCatId != null)
                  Builder(builder: (context) {
                    final catId = _noteCatId!;
                    final list =
                        settings.notesByCategory[catId] ?? const <String>[];
                    if (list.isEmpty) {
                      return Text(
                        L10n.t('settings.notes.none'),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final n in list)
                          InputChip(
                            label: Text(n),
                            // 把叉叉放大一点、加上提示：一眼看得出"点这里删"
                            deleteIcon: const Icon(Icons.close, size: 18),
                            deleteButtonTooltipMessage:
                                '${L10n.t('common.delete')}：$n',
                            onDeleted: () => settingsCtl.removeSavedNote(catId, n),
                          ),
                      ],
                    );
                  }),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _noteCtl,
                        enabled: _noteCatId != null,
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
                      // 没选种类不能加（不然这条备注会存到"不知道哪个种类"下）
                      onPressed:
                          _noteCatId == null ? null : () => _addNote(settingsCtl),
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
                // 这里也用自然顺序（数字 → 字母），跟点单页的桌号下拉保持一致
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in sortedTables(settings.tables))
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

          // ---- 店名 & 店头信息 & 货币 ----
          _sectionTitle(L10n.t('settings.storeName')),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _storeCtl,
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
                const Divider(height: 10),
                // 小票上店名下面居中打的几行（地址 / 电话 / RFC …）
                TextField(
                  controller: _headerCtl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: L10n.t('settings.storeHeader'),
                    helperText: L10n.t('settings.storeHeader.hint'),
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
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

          const SizedBox(height: 16),

          // ---- 后台同步（Supabase）----
          _sectionTitle(L10n.t('settings.sync')),
          _card(child: _syncSection(settingsCtl, settings)),

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

  /// **后台同步**设置区：连 Supabase（云端），多台设备共用一个单池。
  ///
  /// 说明都写在界面上：收银永远先写本机，这里只是「怎么连后台」。
  Widget _syncSection(SettingsController ctl, Settings settings) {
    final sync = context.watch<SyncService>();
    final status = sync.status;
    // 现在同步不了的原因（开关没开 / 哪个字段没填）→ 直接显示出来，
    // 不然点了「立即同步」什么都不发生，看着像「同步成功但 0 张」。
    final blocked = sync.syncBlockedReason;
    // 菜单改过还没推上去 → 状态行上加一段（橙色提示）
    final menuPending =
        sync.menuPending ? '   ·   ${L10n.t('sync.menuPending')}' : '';
    // 店级配置那一行：本机改过还没推上去 / 这一趟对它做了什么
    // （从云端恢复、已上传、表还没建好…）。都没事就是空字符串，不占地方。
    final settingsLine = <String>[
      if (sync.settingsPending) L10n.t('sync.settingsPending'),
      if (sync.settingsNote != null) L10n.t(sync.settingsNote!),
    ].join('   ·   ');

    // 菜品（菜单）那一行：**本机 vs 云端** 各有多少道菜、有几道是「几份起」。
    // 「几份起」那道数是关键 —— 菜单没同步过来时它是 0，一眼就能看出来。
    final local = sync.localMenuSummary;
    final cloud = sync.cloudMenu;
    final cloudPart = cloud == null
        ? '${L10n.t('sync.menuCloud')}: ${L10n.t('sync.menuUnknown')}'
        : '${L10n.t('sync.menuCloud')}: v${cloud.version} · '
            '${cloud.itemCount} ${L10n.t('sync.menuItems')} · '
            '${cloud.minQtyCount} ${L10n.t('sync.menuMinQty')}';
    final menuLine = '${L10n.t('sync.menuLocal')}: '
        '${local.items} ${L10n.t('sync.menuItems')} · '
        '${local.minQty} ${L10n.t('sync.menuMinQty')}$menuPending\n'
        '$cloudPart';
    // 两边「几份起」的道数不一样 → 橙色（多半就是「这台设备的菜单还是旧的」）
    final menuDiffers = cloud != null && cloud.minQtyCount != local.minQty;
    final menuNoteLine = sync.menuNote == null ? '' : L10n.t(sync.menuNote!);
    // 成功那两句用灰字；「表没建 / 云端还没有 / 数据不完整」用橙色（要人处理）
    final menuNoteWarn = sync.menuNote != null &&
        sync.menuNote != 'sync.menuPulled' &&
        sync.menuNote != 'sync.menuPushed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.syncEnabled,
          onChanged: (v) => ctl.updateSync((s) => s.syncEnabled = v),
          title: Text(L10n.t('sync.enable')),
          subtitle: Text(
            L10n.t('sync.enableHint'),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        const Divider(),
        TextField(
          controller: _supabaseUrlCtl,
          decoration: InputDecoration(
            labelText: L10n.t('sync.url'),
            hintText: 'https://xxxxxxxx.supabase.co',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => ctl.updateSync((s) => s.supabaseUrl = v.trim()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _anonKeyCtl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: L10n.t('sync.anonKey'),
            helperText: L10n.t('sync.anonKeyHint'),
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => ctl.updateSync((s) => s.supabaseAnonKey = v.trim()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _deviceNameCtl,
                decoration: InputDecoration(
                  labelText: L10n.t('sync.deviceName'),
                  hintText: '收银台A',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) =>
                    ctl.updateSync((s) => s.deviceName = v.trim()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _syncEmailCtl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: L10n.t('sync.email'),
            hintText: 'device1@bossbro.local',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => ctl.updateSync((s) => s.syncEmail = v.trim()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _syncPasswordCtl,
          obscureText: true,
          decoration: InputDecoration(
            labelText: L10n.t('sync.password'),
            helperText: L10n.t('sync.passwordHint'),
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => ctl.updateSync((s) => s.syncPassword = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: sync.busy ? null : _testSync,
              icon: const Icon(Icons.wifi_tethering, size: 18),
              label: Text(L10n.t('sync.test')),
            ),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              // 没开开关 / 没填全 → 按钮直接灰掉（原因就写在上面那行）
              onPressed: (sync.busy || blocked != null) ? null : _syncNow,
              icon: const Icon(Icons.sync, size: 18),
              label: Text(sync.busy ? L10n.t('sync.syncing') : L10n.t('sync.now')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 一键把「临时预设的后台配置」填进来（URL / anon key / 邮箱）。
        // 为什么要它：预设值只在"本机从没填过"时自动生效；以前手打过（哪怕半截）的话，
        // 本机存的那份会优先 —— 这颗按钮就是"以预设为准"的入口（不用手打/不用清空重启）。
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: sync.busy ? null : _fillPresetSyncConfig,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: Text(L10n.t('sync.prefill')),
          ),
        ),
        // 同步没在跑的话，把原因直接写在这儿 ——
        // 不然后面那些状态数字全是 0，看着像「同步成功但一张都没上传」。
        if (blocked != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.report_gmailerrorred,
                    size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    L10n.t(blocked),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
        // 状态：上次同步 / 待上传 / 菜单待上传 / 出错
        Text(
          status.error != null
              ? '${L10n.t('sync.error')}: ${status.error}'
              : '${L10n.t('sync.lastAt')}: '
                  '${status.lastSyncAt == null ? L10n.t('sync.never') : _fmtTime(status.lastSyncAt!)}'
                  '   ·   ${L10n.t('sync.pending')}: ${status.pendingOrders}'
                  '$menuPending',
          style: TextStyle(
            fontSize: 12,
            color: status.error != null
                ? Colors.red.shade700
                : (sync.menuPending ? Colors.orange.shade800 : Colors.grey.shade700),
          ),
        ),
        const SizedBox(height: 12),
        // ---- 店级配置（店名 / 地址 / 税 / 货币 / 桌号 / 备注 / 日结支出）----
        //
        // 它是**自动同步**的：改动会在 2 秒后推上去，新设备登录后自动拿回来。
        // 这两颗按钮是"强制指定以哪一头为准"，用来处理"云端被先跑的那台设备占了"
        // 这种顺序问题（先跑平板、后跑收银机就会出现）。
        const SizedBox(height: 6),
        // 用 Wrap 而不是 Row：窄屏（手机）上两个按钮放不下时会自动换行，不会溢出
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: (sync.busy || blocked != null)
                  ? null
                  : _restoreStoreSettings,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(L10n.t('sync.settingsPull')),
            ),
            OutlinedButton.icon(
              onPressed:
                  (sync.busy || blocked != null) ? null : _uploadStoreSettings,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(L10n.t('sync.settingsPush')),
            ),
          ],
        ),
        if (settingsLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              settingsLine,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sync.settingsPending
                    ? Colors.orange.shade800
                    : Colors.grey.shade700,
              ),
            ),
          ),
        const SizedBox(height: 12),
        // ---- 菜品（菜单）----
        //
        // 为什么单独一块：**店级配置里不含菜品** —— 菜单是另一条同步线（按版本号走）。
        // 真实踩过：收银机上重新导入 Excel（带了「基础数量」）→ 点「上传本机配置」→
        // 以为平板拿到了，结果平板上还是旧菜单，「2 份起」不生效。所以这里
        // ① 摆出「本机 / 云端」两边的道菜数和「几份起」的道数（一眼能比出来）；
        // ② 给两颗**强制**按钮（不看版本号），用来把菜单掰到指定的那一头。
        const SizedBox(height: 6),
        Text(
          menuLine,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: (sync.menuPending || menuDiffers)
                ? Colors.orange.shade800
                : Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed:
                  (sync.busy || blocked != null) ? null : _downloadMenu,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(L10n.t('sync.menuPull')),
            ),
            OutlinedButton.icon(
              onPressed: (sync.busy || blocked != null) ? null : _uploadMenu,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(L10n.t('sync.menuPush')),
            ),
          ],
        ),
        if (menuNoteLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              menuNoteLine,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: menuNoteWarn
                    ? Colors.orange.shade800
                    : Colors.grey.shade700,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: sync.busy ? null : _resetSync,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: Text(L10n.t('sync.reset')),
          ),
        ),
      ],
    );
  }

  /// 重置同步状态：忘掉登录态 + 所有单子和菜单重新推一遍（**不删单子**）。
  Future<void> _resetSync() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.t('sync.reset')),
        content: Text(L10n.t('sync.resetConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.t('common.ok')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final sync = context.read<SyncService>();
    await sync.resetSyncState();
    if (!mounted) return;
    _toast(sync.status.error == null
        ? L10n.t('sync.done')
        : '${L10n.t('sync.error')}: ${sync.status.error}');
  }

  static String _fmtTime(DateTime t) => timeShort(t);

  /// **从云端恢复店级配置**（覆盖本机）。
  ///
  /// 用途：新设备第一次接入后想强制"以云端为准"，或云端那份才是对的配置。
  Future<void> _restoreStoreSettings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.t('sync.settingsPull')),
        content: Text(L10n.t('sync.settingsPullConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.t('common.ok')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final sync = context.read<SyncService>();
    final done = await sync.pullStoreSettings();
    if (!mounted) return;
    if (done) {
      _toast(L10n.t('sync.settingsPulled'));
      return;
    }
    final err = sync.status.error;
    _toast(err != null
        ? '${L10n.t('sync.error')}: $err'
        : L10n.t(sync.settingsNote ?? 'sync.settingsBadData'));
  }

  /// **把本机店级配置上传到云端**（覆盖服务器那份）。
  ///
  /// 用途：云端被"先跑的那台设备"的配置占了（例如新装的平板抢先把默认配置传上去了），
  /// 而本机（收银电脑）这份才是全店该用的配置。
  Future<void> _uploadStoreSettings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.t('sync.settingsPush')),
        content: Text(L10n.t('sync.settingsPushConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.t('common.ok')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final sync = context.read<SyncService>();
    final done = await sync.pushStoreSettings();
    if (!mounted) return;
    if (done) {
      _toast(L10n.t('sync.settingsPushed'));
      return;
    }
    final err = sync.status.error;
    _toast(err != null
        ? '${L10n.t('sync.error')}: $err'
        : L10n.t(sync.settingsNote ?? 'sync.settingsBadData'));
  }

  /// **从云端下载菜单**（覆盖本机那份，不看版本号）。
  ///
  /// 用途：这台设备的菜单是旧的（换设备 / 新装的平板），或者两边菜单不一样、
  /// 想一刀切以云端为准。**店级配置那颗按钮不管菜品** —— 菜单是另一条同步线。
  Future<void> _downloadMenu() async {
    final ok = await _confirmSyncAction('sync.menuPull', 'sync.menuPullConfirm');
    if (ok != true || !mounted) return;
    final sync = context.read<SyncService>();
    final done = await sync.pullMenu();
    if (!mounted) return;
    if (done) {
      _toast(L10n.t('sync.menuPulled'));
      return;
    }
    final err = sync.status.error;
    _toast(err != null
        ? '${L10n.t('sync.error')}: $err'
        : L10n.t(sync.menuNote ?? 'sync.menuBadData'));
  }

  /// **把本机菜单上传到云端**（覆盖服务器那份，不看版本号）。
  ///
  /// 用途：本机这份才是对的（例如刚重新导入过 Excel，菜里带了「基础数量」），
  /// 但云端被别的设备的旧菜单占着。
  Future<void> _uploadMenu() async {
    final ok = await _confirmSyncAction('sync.menuPush', 'sync.menuPushConfirm');
    if (ok != true || !mounted) return;
    final sync = context.read<SyncService>();
    final done = await sync.pushMenu();
    if (!mounted) return;
    if (done) {
      _toast(L10n.t('sync.menuPushed'));
      return;
    }
    final err = sync.status.error;
    _toast(err != null
        ? '${L10n.t('sync.error')}: $err'
        : L10n.t(sync.menuNote ?? 'sync.menuBadData'));
  }

  /// 「确定 / 取消」确认框（标题 + 说明都是文案 key）。
  Future<bool?> _confirmSyncAction(String titleKey, String bodyKey) =>
      showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(L10n.t(titleKey)),
          content: Text(L10n.t(bodyKey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(L10n.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(L10n.t('common.ok')),
            ),
          ],
        ),
      );

  /// **一键填入预设的后台配置**（URL / anon key / 邮箱）。
  ///
  /// 为什么要这颗按钮：那三个预设值只在"本机从没填过"时自动生效；
  /// 如果你以前手打过（哪怕是半截），**本机存的那份会优先** ——
  /// 这颗按钮就是"以预设为准"的入口（不用手打，也不用先清空再重启）。
  Future<void> _fillPresetSyncConfig() async {
    final ctl = context.read<SettingsController>();
    await ctl.updateSync((s) {
      s.supabaseUrl = kDefaultSupabaseUrl;
      s.supabaseAnonKey = kDefaultSupabaseAnonKey;
      s.syncEmail = kDefaultSyncEmail;
    });
    // 顺手把输入框也刷成预设值，并更新"已填充基线"（否则下一帧会被判成"用户改过"而不刷新）
    _supabaseUrlCtl.text = kDefaultSupabaseUrl;
    _anonKeyCtl.text = kDefaultSupabaseAnonKey;
    _syncEmailCtl.text = kDefaultSyncEmail;
    _filled['supabaseUrl'] = kDefaultSupabaseUrl;
    _filled['anonKey'] = kDefaultSupabaseAnonKey;
    _filled['syncEmail'] = kDefaultSyncEmail;
    if (!mounted) return;
    _toast(L10n.t('sync.prefillDone'));
  }

  Future<void> _testSync() async {
    final sync = context.read<SyncService>();
    final ok = await sync.testConnection();
    if (!mounted) return;
    _toast(ok ? L10n.t('sync.test.ok') : L10n.t('sync.test.fail'));
  }

  Future<void> _syncNow() async {
    final sync = context.read<SyncService>();
    // 开关没开 / 没填全的时候 syncNow() 是**静默**什么都不做的
    // （点了会看到数字没变，像「同步成功但 0 张」）→ 这里明确告诉用户原因。
    final blocked = sync.syncBlockedReason;
    if (blocked != null) {
      _toast(L10n.t(blocked));
      return;
    }
    await sync.syncNow();
    if (!mounted) return;
    final err = sync.status.error;
    if (err == null) {
      // 顺带把「还剩几张没上传」也说出来：如果 ↑0 但待上传 >0，就是没推成功，一目了然
      _toast('${L10n.t('sync.done')}: '
          '↑${sync.status.pushed} ↓${sync.status.pulled}   ·   '
          '${L10n.t('sync.pending')}: ${sync.status.pendingOrders}');
    } else {
      _toast('${L10n.t('sync.error')}: $err');
    }
  }

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
    final catId = _noteCatId;
    if (v.isEmpty || catId == null) return; // 没选种类就不给加（按钮本来就是灰的）
    ctl.addSavedNote(catId, v); // 存到当前选中的种类下
    _noteCtl.clear();
  }

  // ---- 菜品管理 / Excel 导入：都要管理员权限 ----

  Future<void> _openMenuManage() async {
    if (!await requireAdmin(context, reason: L10n.t('auth.menuNeeded'))) return;
    if (!mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const MenuManageScreen()));
  }

  Future<void> _openMenuImport() async {
    if (!await requireAdmin(context, reason: L10n.t('auth.menuNeeded'))) return;
    if (!mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const MenuImportScreen()));
  }

  void _save(SettingsController ctl) {
    ctl.update((s) {
      s.storeName = _storeCtl.text.trim().isEmpty
          ? '餐厅'
          : _storeCtl.text.trim();
      s.storeHeader = _headerCtl.text.trim();
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
            // 「Windows 系统打印机」只在 Windows 上有意义：
            // 安卓上选了也只会得到「不支持」，所以干脆不显示（免得收银员选错）。
            if (Platform.isWindows)
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
        // ---- 厨师单打印份数（默认 2：一张厨师、一张出餐服务员）----
        Text(L10n.t('settings.kitchenCopies'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        DropdownButton<int>(
          value: settings.kitchenCopies.clamp(1, 3).toInt(),
          isExpanded: true,
          items: [
            for (final n in const [1, 2, 3])
              DropdownMenuItem(
                value: n,
                child: Text(L10n.t('settings.kitchenCopies.$n')),
              ),
          ],
          onChanged: (v) {
            if (v != null) ctl.setKitchenCopies(v);
          },
        ),
        Text(
          L10n.t('settings.kitchenCopies.hint'),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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

  /// 打印测试页：**成功不提示**（纸出来了就是成功），失败才提示。
  Future<void> _printTest(Settings s) async {
    final service = context.read<ReceiptPrintService>();
    final res = await service.printTestPage(s);
    if (!mounted) return;
    if (res != null) {
      _toast('${L10n.t('dialog.print.failed')} $res');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
