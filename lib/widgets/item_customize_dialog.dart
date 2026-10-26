import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/menu_item.dart';
import '../models/menu_option_group.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';

/// 点菜 / 改菜对话框的结果：选中的定制项 + **特别备注（可以多条）** + 份数。
class ItemEditResult {
  final List<String> selections;
  final List<String> notes;

  /// 每条备注对应的**加价**（跟 [notes] 一一对应；短了按 0 算）。
  final List<double> notePrices;

  final int quantity;

  const ItemEditResult({
    required this.selections,
    required this.notes,
    this.notePrices = const [],
    required this.quantity,
  });
}

/// 打开「点菜 / 改菜」对话框（**屏幕中间**）。
///
/// 每道菜**都**会开这个框（不管 Excel 里有没有定制项），因为要能填特别备注：
/// - **定制项**：Excel 里有才显示；
/// - **特别备注**：**可以好几条** —— 填一条 → 点「加进备注」→ 输入框清空，接着填下一条；
///   已经加进去的备注会变成小标签，点 ✕ 可以去掉；
/// - **份数**：默认 1，可以按 +/- 或**直接输数字**。
///
/// [item] 为空 = 这道菜已经不在菜单里了（换过菜单 / 老单）：只让改备注和份数。
/// [initial] 不为空 = 编辑已有的一行（购物车里点它进来的），按钮写「保存修改」。
/// 返回 null = 用户点了取消。
Future<ItemEditResult?> showItemCustomizeDialog(
  BuildContext context,
  MenuItem? item, {
  ItemEditResult? initial,
  String? title,
}) {
  return showDialog<ItemEditResult>(
    context: context,
    builder: (_) => ItemCustomizeDialog(
      item: item,
      initial: initial,
      title: title,
    ),
  );
}

class ItemCustomizeDialog extends StatefulWidget {
  final MenuItem? item;
  final ItemEditResult? initial;
  final String? title;

  const ItemCustomizeDialog({
    super.key,
    required this.item,
    this.initial,
    this.title,
  });

  @override
  State<ItemCustomizeDialog> createState() => _ItemCustomizeDialogState();
}

class _ItemCustomizeDialogState extends State<ItemCustomizeDialog> {
  /// 定制项名 → 选中的选项（每组单选）。
  final Map<String, String> _selected = {};

  /// 已经加进这一行的**特别备注**（可以多条）。
  ///
  /// ⚠️ 这两个列表都在 [initState] 里**先按 initial 建好**，不能用
  /// `late final _notePrices = [for (i < _notes.length) ...]`：
  /// 第一次加备注时 `_notes.add` 已经先执行，`_notePrices` 的 lazy 初始化
  /// 会看到多出来的那一条，先建出一个 0 —— 结果所有价格整体错位一位
  /// （真实 bug：第一条备注 0，第二条拿到第一条的价）。
  late final List<String> _notes;

  /// 每条备注的**加价**（跟 [_notes] 一一对应；「换炒饭 +70」就是 70，可以为负）。
  ///
  /// 编辑老单进来时**原样带过来**（已经有的备注默认不变金额）。
  late final List<double> _notePrices;

  /// 第 [i] 条备注的加价（越界 = 0）。
  double _priceAt(int i) => i < _notePrices.length ? _notePrices[i] : 0;

  /// 备注文字后面跟的价签（` +70` / ` -60`；0 就不显示）。
  String _priceTag(double price) =>
      price == 0 ? '' : ' ${signedAmount(price)}';

  /// 备注搜索用的归一化：转小写 + 去掉空格（「不要 炒饭」也能搜到「不要炒饭」）。
  static String _normNote(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// **相近备注**的打分：
  /// 完全一样 4 → 前缀 3 → 包含 2 → 按顺序出现（「不要饭」也能找到「不要炒饭」）1
  /// → 不相关 -1。
  static int _noteMatchScore(String note, String query) {
    final n = _normNote(note);
    final q = _normNote(query);
    if (q.isEmpty) return 0;
    if (n == q) return 4;
    if (n.startsWith(q)) return 3;
    if (n.contains(q)) return 2;
    // 简单的"字按顺序出现"：足够处理「不要饭」→「不要炒饭」这种少打一个字的输入
    final nr = n.runes.toList();
    final qr = q.runes.toList();
    var qi = 0;
    for (var i = 0; i < nr.length && qi < qr.length; i++) {
      if (nr[i] == qr[qi]) qi++;
    }
    return qi == qr.length ? 1 : -1;
  }

  /// 备注输入框右边那个小金额框里填的数。
  ///
  /// **空着的时候不是 0**：如果打的这条文字正好是一条**常用备注**
  /// （设置 → 常用备注，标签上写着 `换炒饭 +70`），就用它存的加价 ——
  /// 这样"直接把常用备注的名字打进去"和"点那个标签"是同一个效果。
  /// 想这一次不加钱就把金额框填 `0`（显式 0 就是 0）。
  double get _typedPrice {
    final raw = _notePriceCtl.text.trim().replaceAll(',', '.');
    if (raw.isNotEmpty) return double.tryParse(raw) ?? 0;
    final text = _noteCtl.text.trim();
    if (text.isEmpty) return 0;
    return context
        .read<SettingsController>()
        .settings
        .notePriceFor(_categoryId, text);
  }

  /// 份数（编辑时用原来的，但不低于最少份数；新加时**从最少份数开始**）。
  ///
  /// ⚠️ 这里只能在 initState 里赋值：字段初始化器跑在 `widget` 被赋值之前，
  /// 直接写 `widget.item?.minQuantity` 会崩。
  late int _qty;

  /// 这道菜的**最少份数**（Excel 的「基础数量」列；没这列 = 1）。
  int get _minQty => widget.item?.minQuantity ?? 1;

  /// **真正会下单的份数**：输入框里手打了一个比最少份数还小的数时，按最少份数算。
  int get _effectiveQty => _qty < _minQty ? _minQty : _qty;

  final _noteCtl = TextEditingController();

  /// 备注右边那个**小金额框**（这条备注要加多少钱；**空 = 看它是不是常用备注**，
  /// 是的话自动用那条常用备注存的加价 —— 见 [_typedPrice]）。
  final _notePriceCtl = TextEditingController();
  final _qtyCtl = TextEditingController();
  final _noteFocus = FocusNode();

  /// 新备注**默认存进常用备注**（用户可以在下面取消勾选）。
  bool _saveAsTag = true;

  /// **常用备注使用次数**（只算已结账单）：打开框时从 PosController 取一次。
  ///
  /// 测试 / 没有 PosController 的环境取不到 → 空 map（就按设置里原来的顺序）。
  late final Map<String, int> _noteUsage;

  @override
  void initState() {
    super.initState();
    // 先按初始备注建好两个列表，再让用户往里加：
    // 这样 `_notes` 和 `_notePrices` 从第一帧起就严格一一对应。
    _notes = List.of(widget.initial?.notes ?? const <String>[]);
    _notePrices = [
      for (var i = 0; i < _notes.length; i++)
        (i < (widget.initial?.notePrices.length ?? 0))
            ? widget.initial!.notePrices[i]
            : 0.0,
    ];
    // 常用备注排序用的使用次数：打开框时算一次（测试里没 PosController → 空）
    try {
      _noteUsage = context.read<PosController>().noteUsageCounts();
    } catch (_) {
      _noteUsage = const <String, int>{};
    }
    final initial = widget.initial?.selections ?? const <String>[];
    // ⚠️ 兜底一定要写 `const <MenuOptionGroup>[]`（不能只写 `const []`）：
    // 只写 `const []` 时这个表达式的类型会变成 `List<dynamic>`，循环变量 g 就变 dynamic，
    // 下面 `g.options.firstWhere(orElse: ...)` 会在运行时因为
    // 「() => dynamic 不是 (() => String)?」直接崩（踩过一次）。
    for (final g in widget.item?.options ?? const <MenuOptionGroup>[]) {
      if (g.isEmpty) continue;
      // 编辑时优先用**原来选的那个**；没选过就按默认规则来。
      // 加料开关在单子上存的是**组名**，所以这里要单独认一下，并且选中
      // 「要加钱」的那个（Excel 里写成 `No/Yes` 的情况也能对上）。
      final kept = g.options.firstWhere(
        (o) => initial.contains(o),
        orElse: () {
          if (g.isToggle && initial.contains(g.name)) {
            return g.options.firstWhere(
              (opt) => g.priceOf(opt) != 0,
              orElse: () => g.options.first,
            );
          }
          return _defaultOption(g);
        },
      );
      if (kept.isEmpty) continue; // 默认「不选」（加料开关就是这种）
      _selected[g.name] = kept;
    }
    // 份数：最少份数（「基础数量」列）→ 新加时从它开始；编辑老行时不低于它
    final minQty = _minQty;
    final initialQty = widget.initial?.quantity ?? minQty;
    _qty = initialQty < minQty ? minQty : initialQty;
    _qtyCtl.text = '$_qty';

    // ⚠️ 备注框 / 加价框**每敲一个字都要重算**（标题的菜价、底下的合计、备注价签）。
    //    以前这两个框没有监听：填了「换炒饭 +70」之后框里的价格一动不动，
    //    看着就像"备注加价没生效"（其实只是没刷新）—— 真实踩过。
    _noteCtl.addListener(_refreshPrice);
    _notePriceCtl.addListener(_refreshPrice);
  }

  /// 备注 / 加价输入框变了 → 重算价格并刷新界面。
  void _refreshPrice() {
    if (!mounted) return;
    setState(() {});
  }

  /// 这个定制项**默认选哪个**（返回空串 = 默认不选）：
  ///
  /// - **加料开关**（只有一个选项 / 一对 Yes-No，例如 `EXTRA BOBA`、`JARRA`）
  ///   → **默认不选**：客人要就点一下，不要就不加钱；
  /// - **普通多选项**（例如 Size: Mediano/Grande）→ 默认选**最便宜**的那个
  ///   （通常就是不加钱的那个），这样框里显示的价 = 菜单格子上写的「起价」，
  ///   不会一点开就贵一档。
  static String _defaultOption(MenuOptionGroup g) {
    if (g.isToggle) return '';
    var best = g.options.first;
    for (final o in g.options) {
      if (g.priceOf(o) < g.priceOf(best)) best = o;
    }
    return best;
  }

  @override
  void dispose() {
    _noteCtl.removeListener(_refreshPrice);
    _notePriceCtl.removeListener(_refreshPrice);
    _noteCtl.dispose();
    _notePriceCtl.dispose();
    _qtyCtl.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// 当前选中的项（每组一个）—— **要存进订单/购物车的那份**：
  ///
  /// - 普通多选项（Size: Grande）→ 存**选项值** `Grande`；
  /// - **加料开关**（`EXTRA BOBA: Yes`、`JARRA: Yes/No`）→ 存**组名**（`EXTRA BOBA` / `JARRA`），
  ///   因为小票/厨房单上写「Yes」谁也看不懂；
  ///   而且**不加钱的那个（No / +0）等于没加**，直接不存。
  List<String> get _selections {
    final out = <String>[];
    for (final g in widget.item?.options ?? const <MenuOptionGroup>[]) {
      final v = _selected[g.name];
      if (v == null || v.trim().isEmpty) continue;
      if (g.isToggle) {
        if (g.priceOf(v) != 0) out.add(g.name); // 加了钱的才算「加了」
        continue;
      }
      out.add(v);
    }
    return out;
  }

  /// 按当前选择算出的单价（基础价 + 各选中项加价，**不含备注加价**）。
  double get _unitPrice {
    final item = widget.item;
    if (item == null) return 0;
    return item.unitPriceFor(_selections);
  }

  /// **备注加价合计（每份）**：已经加进去的 + 输入框里正在填的那条。
  ///
  /// 跟 `_confirm()` 一个口径：
  /// - 输入框里的文字**还没加进列表** → 加上它的加价；
  /// - 文字**已经在列表里了** → 加价框填了数才当成改价，否则仍按原价；
  /// - 文字框**空着**时，加价框里的数**不算**（它只服务于旁边正在填的这条备注）。
  double get _noteTotal {
    var sum = 0.0;
    for (var i = 0; i < _notes.length; i++) {
      sum += _priceAt(i);
    }
    final typed = _noteCtl.text.trim();
    if (typed.isEmpty) return sum;
    final typedPrice = _typedPrice;
    final i = _notes.indexOf(typed);
    if (i < 0) return sum + typedPrice;
    // 已经在列表里：加价框**填了数**才当成改价，否则这条仍按原来的加价算
    if (_notePriceCtl.text.trim().isEmpty) return sum;
    return sum - _priceAt(i) + typedPrice;
  }

  /// **加上备注加价之后**的单价（「换炒饭 +70」算在这里）。
  ///
  /// ⚠️ 标题上写的「菜价」用的就是它 —— 以前标题写的是不含备注加价的 `_unitPrice`，
  /// 于是填了 +70 之后**标题价格一动不动**，看着像"加价没生效"（其实就是没显示）。
  double get _unitPriceWithNotes => _unitPrice + _noteTotal;

  /// 标题上显示的名字：外面传了就用传的，否则用**昵称优先**的名字
  /// （点单界面看昵称，见 `MenuItem.displayName`）。
  String get _displayName =>
      widget.title ?? widget.item?.displayName ?? '';

  /// 改份数（+/- 按钮和输入框都走这里，两边永远同步）。
  ///
  /// 不会低于这道菜的**最少份数**（「基础数量」列，例如套餐 2 份起）。
  void _setQty(int v) {
    final min = _minQty;
    final q = v < min ? min : v;
    setState(() {
      _qty = q;
      _qtyCtl.text = '$q';
    });
  }

  /// 加价框里显示用：整数不带小数尾巴（`70` 而不是 `70.00`）。
  String _fmtPrice(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// 点已经加进去的备注 chip：把它**填回输入框**，方便改加价。
  ///
  /// 改完按「加进备注」（同一条会更新）或直接「加入购物车」。
  /// 要改备注文字就删掉 chip 重新加。
  /// 这样加价框永远只服务于**输入框里这条**，不会变成跨备注的隐式暂存价。
  void _editNote(int i) {
    _noteCtl.text = _notes[i];
    final p = _priceAt(i);
    _notePriceCtl.text = p == 0 ? '' : _fmtPrice(p);
    _noteFocus.requestFocus();
  }

  /// 一条常用备注的 chip（标签带价签，点击按自己存的价格加入）。
  ///
  /// 用方法参数把 [note] / [price] 固定住，避免在集合 `for` 的闭包里
  /// 引用循环变量造成歧义。
  Widget _savedNoteChip(String note, double price) => FilterChip(
        selected: false,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => _toggleSavedNote(note, true, price),
        // 标签上也把加价写出来，免得点了才知道加钱
        label: Text('$note${_priceTag(price)}'),
        showCheckmark: false,
        labelStyle: const TextStyle(
          color: Color(0xFF232829),
          fontWeight: FontWeight.w600,
        ),
      );

  /// 点「常用备注」标签：选中 = 加进备注，再点 = 去掉。
  ///
  /// **加价只认这条常用备注在设置里存的价格**（没存 = 0，不改价）。
  /// 不拿右边加价框里的数来兜底 —— 那个框是给旁边**正在输入的新备注**用的，
  /// 拿它兜底会把上一条残留的 50 悄悄算到下一条免费备注上（真实 bug）。
  ///
  /// 加完**马上清空文字框和加价框**，接着加下一条。
  void _toggleSavedNote(String n, bool on, double savedPrice) {
    if (!on) {
      final i = _notes.indexOf(n);
      if (i >= 0) {
        setState(() {
          _notes.removeAt(i);
          if (i < _notePrices.length) _notePrices.removeAt(i);
        });
        // 删掉这条之后，加价框里可能还留着它的价格；清掉，别影响下一条
        _notePriceCtl.clear();
      }
      return;
    }
    if (_notes.contains(n)) return;
    setState(() {
      _notes.add(n);
      _notePrices.add(savedPrice);
    });
    // 这条已经是一条 chip 了：清空输入，接着加下一条
    _noteCtl.clear();
    _notePriceCtl.clear();
  }

  /// 「加进备注」：把输入框里的文字（+ 右边那个小框里的加价）存成一条备注，
  /// 清空两个输入框准备填下一条。
  void _addNote() {
    final text = _noteCtl.text.trim();
    if (text.isEmpty) return;
    final box = _notePriceCtl.text.trim();
    final price = _typedPrice;
    if (_saveAsTag) {
      // 存成常用标签时**连加价一起存**（下次点这个标签，加价自动跟着来）
      context
          .read<SettingsController>()
          .addSavedNote(_categoryId, text, price: price);
    }
    setState(() {
      final i = _notes.indexOf(text);
      if (i >= 0) {
        // 同一条备注再加一次：**加价框明确填了数**才改价；
        // 空着就保留原来这条的价格（不拿自动单价把它覆盖掉）。
        if (box.isNotEmpty) _notePrices[i] = price;
      } else {
        _notes.add(text);
        _notePrices.add(price);
      }
    });
    _noteCtl.clear();
    _notePriceCtl.clear();
    // 光标留在输入框里，方便接着填下一条
    _noteFocus.requestFocus();
  }

  /// 去掉第 [i] 条备注（文字和加价一起删）。
  void _removeNote(int i) {
    setState(() {
      _notes.removeAt(i);
      if (i < _notePrices.length) _notePrices.removeAt(i);
    });
    // 框里可能还留着这条的价格；清掉，别让下一条备注捡走
    _notePriceCtl.clear();
  }

  /// 备注要存到哪个种类下（编辑老单时可能没有对应菜单项 → 存到「通用」）。
  String get _categoryId => widget.item?.categoryId ?? '';

  void _confirm() {
    final settingsCtl = context.read<SettingsController>();
    // 输入框里还没点「加进备注」的那条也算上，别让收银员白填
    final typed = _noteCtl.text.trim();
    if (typed.isNotEmpty && _saveAsTag) {
      settingsCtl.addSavedNote(_categoryId, typed, price: _typedPrice);
    }
    final notes = List<String>.of(_notes);
    final prices = [
      for (var i = 0; i < _notes.length; i++) _priceAt(i),
    ];
    if (typed.isNotEmpty) {
      final i = notes.indexOf(typed);
      if (i >= 0) {
        // 这条已经在列表里：**加价框明确填了数**才改价；空着就保留原价。
        if (_notePriceCtl.text.trim().isNotEmpty) prices[i] = _typedPrice;
      } else {
        notes.add(typed);
        prices.add(_typedPrice);
      }
    }

    Navigator.pop(
      context,
      ItemEditResult(
        selections: _selections,
        notes: notes,
        notePrices: prices,
        // 比最少份数小的话按最少份数下单（「基础数量」列，例如 2 份起）
        quantity: _effectiveQty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final item = widget.item;
    final symbol = settings.currencySymbol;

    // ---- 常用备注：搜索 / 按已结账单的使用次数排序 / 最多显示两行 ----
    final noteQuery = _noteCtl.text.trim();
    // 通用（''）+ 这个分类的；**已经加进这一行的**不重复显示（上面有 InputChip）。
    final seen = <String>{};
    final available = <String>[
      for (final n in settings.notesFor(_categoryId))
        if (!_notes.contains(n) && seen.add(n)) n,
    ];
    final matches = <({String note, int score, int index})>[];
    for (var i = 0; i < available.length; i++) {
      final score =
          noteQuery.isEmpty ? 0 : _noteMatchScore(available[i], noteQuery);
      if (score < 0) continue;
      matches.add((note: available[i], score: score, index: i));
    }
    matches.sort((a, b) {
      // 输入了搜索词：先按"相近程度"，再按使用次数
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byUsage =
          (_noteUsage[b.note] ?? 0).compareTo(_noteUsage[a.note] ?? 0);
      if (byUsage != 0) return byUsage;
      return a.index.compareTo(b.index);
    });
    final visibleNotes = [for (final m in matches) m.note];
    final exactNoteAlreadyAdded =
        noteQuery.isNotEmpty && _notes.contains(noteQuery);

    final isEdit = widget.initial != null;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- 标题：菜名 + **这一行现在的单价**（选了规格 / 加了备注都会变）----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _displayName,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (item != null)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          // ⚠️ 用**含备注加价**的单价：填了「换炒饭 +70」这里就该是 98，
                          //    不是 28 —— 以前这里写的是基础价，看着像加价没生效
                          item.hasUnit
                              ? '${money(_unitPriceWithNotes, symbol)} / ${item.unit}'
                              : money(_unitPriceWithNotes, symbol),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1FA85A),
                          ),
                        ),
                        // 备注加了钱就把账拆开写一行小字：`28.00 +70`（一眼看出多在哪）
                        if (_noteTotal.abs() >= 0.005)
                          Text(
                            '${money(_unitPrice, symbol)} ${signedAmount(_noteTotal)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ---- 内容（可滚动）----
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 这道菜已经不在菜单里了（老单 / 换过菜单）
                    if (item == null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF6E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          L10n.t('custom.notInMenu'),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF8D6E00)),
                        ),
                      ),

                    // ---- 定制项（Excel 里有才显示）----
                    for (final g in item?.options ?? const <MenuOptionGroup>[])
                      if (!g.isEmpty) ...[
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                g.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                            // 加料开关（单选项 / Yes-No）= 点一下才加钱（默认不选）
                            if (g.isToggle) ...[
                              const SizedBox(width: 6),
                              Text(
                                L10n.t('custom.optional'),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final o in g.options)
                              ChoiceChip(
                                selected: _selected[g.name] == o,
                                // 点一下选上；**加料开关**再点一下可以取消
                                // （普通多选项必须留一个，不能取消）
                                onSelected: (v) => setState(() {
                                  if (v) {
                                    _selected[g.name] = o;
                                  } else if (g.isToggle &&
                                      _selected[g.name] == o) {
                                    _selected.remove(g.name);
                                  }
                                }),
                                // 选项有加价时标出来，例如 "Grande +185"；
                                // 加价是 0 的（例如 Size 的 Mediano）就不写 +0，免得看花眼
                                label: Text(
                                    g.hasPrices && g.priceOf(o) != 0
                                        ? '$o  +${money(g.priceOf(o), symbol)}'
                                        : o),
                                showCheckmark: false,
                                selectedColor: const Color(0xFF1FA85A),
                                labelStyle: TextStyle(
                                  color: _selected[g.name] == o
                                      ? Colors.white
                                      : const Color(0xFF232829),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                    // ---- 特别备注（每道菜都有，可以好几条）----
                    Row(
                      children: [
                        const Icon(Icons.edit_note, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          L10n.t('custom.note'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 已经加进去的备注（点 ✕ 去掉；带加价的一起显示成 `换炒饭 +70`）
                    if (_notes.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (var i = 0; i < _notes.length; i++)
                            InputChip(
                              label: Text(
                                '${_notes[i]}${_priceTag(_priceAt(i))}',
                              ),
                              // 点 chip 本体 = 填回输入框改价；✕ 才是删除
                              onPressed: () => _editNote(i),
                              onDeleted: () => _removeNote(i),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    // 输入框 + 小金额框 + 「加进备注」：
                    // 填一条 → 保存 → 接着填下一条。金额不填 = 这条备注不改价。
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('itemNoteField'),
                            controller: _noteCtl,
                            focusNode: _noteFocus,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: L10n.t('custom.note.hint'),
                            ),
                            // 回车 = 跳到右边那个「加价」小框（填完再回车就存）
                            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 备注的加价（右边这个小框，「换炒饭 +70」就填 70）
                        SizedBox(
                          width: 84,
                          child: TextField(
                            key: const ValueKey('itemNotePriceField'),
                            controller: _notePriceCtl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            textAlign: TextAlign.right,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: L10n.t('custom.note.price'),
                              hintStyle: const TextStyle(fontSize: 12),
                            ),
                            onSubmitted: (_) => _addNote(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton.tonal(
                          onPressed: _addNote,
                          child: Text(L10n.t('custom.note.add')),
                        ),
                      ],
                    ),
                    // 常用备注：输入时就是**搜索结果**；没输入时按「已结账单使用次数」
                    // 从多到少排。最多显示**两行**，剩下的用「…」省略（继续打字可搜出来）。
                    if (visibleNotes.isNotEmpty || noteQuery.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      if (noteQuery.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            visibleNotes.isNotEmpty
                                ? L10n.t('custom.note.matches')
                                : (exactNoteAlreadyAdded
                                    ? L10n.t('custom.note.alreadyAdded')
                                    : L10n.t('custom.note.noMatch')),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      if (visibleNotes.isNotEmpty)
                        _LimitedWrap(
                          children: [
                            for (final n in visibleNotes)
                              // 用方法传参，避免闭包捕获循环变量导致
                              // "点第一条却加了最后一条"的歧义。
                              _savedNoteChip(
                                n,
                                settings.notePriceFor(_categoryId, n),
                              ),
                          ],
                        ),
                    ],
                    Row(
                      children: [
                        Checkbox(
                          value: _saveAsTag,
                          onChanged: (v) =>
                              setState(() => _saveAsTag = v ?? false),
                        ),
                        Expanded(
                          child: Text(
                            L10n.t('custom.note.saveTag'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 18),

                    // ---- 份数（默认 1，可以 +/- 或直接输数字）----
                    Row(
                      children: [
                        const Icon(Icons.numbers, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          L10n.t('custom.qty'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        // 「2 份起」提示（Excel 的「基础数量」列 > 1 时才显示）
                        if (_minQty > 1) ...[
                          const SizedBox(width: 4),
                          Text(
                            '$_minQty ${L10n.t('custom.qty.min')}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF6C00),
                            ),
                          ),
                        ],
                        const SizedBox(width: 12),
                        IconButton(
                          // 减到最少份数就停住（要整行删掉用购物车里的 ✕）
                          onPressed:
                              _qty > _minQty ? () => _setQty(_qty - 1) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: L10n.t('custom.qty.minus'),
                        ),
                        SizedBox(
                          width: 72,
                          child: TextField(
                            controller: _qtyCtl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              final n = int.tryParse(v.trim());
                              if (n != null && n > 0) setState(() => _qty = n);
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: () => _setQty(_qty + 1),
                          icon: const Icon(Icons.add_circle_outline,
                              color: Color(0xFF1FA85A)),
                          tooltip: L10n.t('custom.qty.plus'),
                        ),
                        const Spacer(),
                        if (item != null)
                          Text(
                            '${L10n.t('cart.total')} '
                            '${money(_unitPriceWithNotes * _effectiveQty, symbol)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1FA85A),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            // ---- 操作 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(L10n.t('common.cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _confirm,
                      child: Text(isEdit
                          ? L10n.t('custom.saveEdit')
                          : L10n.t('custom.add')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// **两行高的可滚动框**：常用备注太多时，框本身还是两行，
/// 右边出现一个**可拖动的滚动条**（就像网页右侧那条），用户往下拖看更多。
///
/// 不用省略号：备注仍然都在，只是藏在框里，滚一下就能看到；
/// 另外在输入框打字会直接搜索，不用滚。
class _LimitedWrap extends StatefulWidget {
  final List<Widget> children;

  const _LimitedWrap({required this.children});

  @override
  State<_LimitedWrap> createState() => _LimitedWrapState();
}

class _LimitedWrapState extends State<_LimitedWrap> {
  /// 两行的高度：FilterChip 用了 `shrinkWrap`，一行 32；两行 + 4 行距 = 68。
  static const double _maxHeight = 68;

  /// 滚动条和滚动内容**共用**这个 controller，拖动条才能控制内容。
  final ScrollController _scrollCtl = ScrollController();

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Scrollbar(
        controller: _scrollCtl,
        // 一直显示那条滚动条（内容不够高时 Flutter 自己不会画）
        thumbVisibility: true,
        // Windows / 安卓都能**直接拖这条 bar**
        interactive: true,
        thickness: 6,
        radius: const Radius.circular(3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _maxHeight),
          child: SingleChildScrollView(
            controller: _scrollCtl,
            physics: const ClampingScrollPhysics(),
            // 右边留一点，别让 chip 压在滚动条下面
            padding: const EdgeInsets.only(right: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.children,
            ),
          ),
        ),
      ),
    );
  }
}
