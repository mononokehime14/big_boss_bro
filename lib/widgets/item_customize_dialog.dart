import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/menu_item.dart';
import '../models/menu_option_group.dart';
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
  late final List<String> _notes =
      List.of(widget.initial?.notes ?? const <String>[]);

  /// 每条备注的**加价**（跟 [_notes] 一一对应；「换炒饭 +70」就是 70，可以为负）。
  ///
  /// 编辑老单进来时**原样带过来**（已经有的备注默认不变金额）。
  late final List<double> _notePrices = [
    for (var i = 0; i < _notes.length; i++)
      (i < (widget.initial?.notePrices.length ?? 0))
          ? widget.initial!.notePrices[i]
          : 0.0,
  ];

  /// 第 [i] 条备注的加价（越界 = 0）。
  double _priceAt(int i) => i < _notePrices.length ? _notePrices[i] : 0;

  /// **最后动过的是第几条备注**（点常用备注标签 / 「加进备注」时更新；-1 = 没动过）。
  ///
  /// 用途：**备注文字框空着、只有右边加价框填了数** 的时候，这个数归这条备注
  /// （最常见的一步操作：点常用备注标签 → 在加价框打 70 → 直接点「加入购物车」）。
  /// 没有它，这一步填的 70 会被**默默丢掉** —— 看着就是"金额没生效"。
  int _lastTouched = -1;

  /// 备注文字后面跟的价签（` +70` / ` -60`；0 就不显示）。
  String _priceTag(double price) =>
      price == 0 ? '' : ' ${signedAmount(price)}';

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
  bool _saveAsTag = false;

  @override
  void initState() {
    super.initState();
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
  /// - 文字**已经在列表里了** → 以加价框为准（填了数才是改价，没填就还是原价）；
  /// - 文字框**空着**但加价框里有数 → 这个数是给**最后动过的那条**备注的
  ///   （典型操作：点常用备注标签 → 在加价框打 70 → 直接确认）。
  double get _noteTotal {
    var sum = 0.0;
    for (var i = 0; i < _notes.length; i++) {
      sum += _priceAt(i);
    }
    final box = _notePriceCtl.text.trim();
    final typed = _noteCtl.text.trim();
    if (typed.isEmpty) {
      final i = _lastTouched;
      if (box.isEmpty || i < 0 || i >= _notes.length) return sum;
      return sum - _priceAt(i) + _typedPrice;
    }
    final typedPrice = _typedPrice;
    final i = _notes.indexOf(typed);
    if (i < 0) return sum + typedPrice;
    // 已经在列表里：加价框**填了数**才当成改价，否则这条仍按原来的加价算
    if (box.isEmpty) return sum;
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

  /// 点「常用备注」标签：选中 = 加进备注，再点 = 去掉。
  ///
  /// **加价从哪来**（这是"金额好像没生效"的关键）：
  /// 1. 优先用**设置里给这条常用备注存的加价**（设置 → 常用备注 那个小金额框，
  ///    标签上会写成 `换炒饭 +70`）；
  /// 2. 没存过（老数据，或者老板当初没填）→ **用右边加价框里现在填的数**。
  ///    所以「先在加价框打 70，再点常用备注标签」也能把这 70 带上去；
  /// 3. 两个都没有 → 0（就是一条不改钱的备注，跟以前一样）。
  ///
  /// 带上加价之后还会把它填进右边那个框：让人**看得见**这条备注加了多少钱，
  /// 想改就直接改那个数再点「加进备注」。
  void _toggleSavedNote(String n, bool on, double savedPrice) {
    if (!on) {
      final i = _notes.indexOf(n);
      if (i >= 0) {
        setState(() {
          _notes.removeAt(i);
          if (i < _notePrices.length) _notePrices.removeAt(i);
          if (_lastTouched == i) _lastTouched = -1;
        });
      }
      return;
    }
    if (_notes.contains(n)) return;
    final price = savedPrice != 0 ? savedPrice : _typedPrice;
    setState(() {
      _notes.add(n);
      _notePrices.add(price);
      _lastTouched = _notes.length - 1;
      if (price != 0) _notePriceCtl.text = _fmtPrice(price);
    });
  }

  /// 加价框里显示用：整数不带小数尾巴（`70` 而不是 `70.00`）。
  String _fmtPrice(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// 「加进备注」：把输入框里的文字（+ 右边那个小框里的加价）存成一条备注，
  /// 清空两个输入框准备填下一条。
  void _addNote() {
    final text = _noteCtl.text.trim();
    if (text.isEmpty) return;
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
        // 同一条备注再加一次 = 改它的加价
        _notePrices[i] = price;
        _lastTouched = i;
      } else {
        _notes.add(text);
        _notePrices.add(price);
        _lastTouched = _notes.length - 1;
      }
      _noteCtl.clear();
      _notePriceCtl.clear();
    });
    // 光标留在输入框里，方便接着填下一条
    _noteFocus.requestFocus();
  }

  /// 去掉第 [i] 条备注（文字和加价一起删）。
  void _removeNote(int i) => setState(() {
        _notes.removeAt(i);
        if (i < _notePrices.length) _notePrices.removeAt(i);
        // 下标会往前挪，干脆忘掉"最后动过的那条"，免得加价框里的数记到错的备注上
        if (_lastTouched == i) _lastTouched = -1;
      });

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
        // 这条已经在列表里（多半是刚点的常用备注标签）：
        // **加价框里填了数就改成这个数** —— 否则"点标签带进来 0、再填 70 确认"
        // 会把 70 默默丢掉，看着就是"金额没生效"。
        if (_notePriceCtl.text.trim().isNotEmpty) prices[i] = _typedPrice;
      } else {
        notes.add(typed);
        prices.add(_typedPrice);
      }
    } else if (_notePriceCtl.text.trim().isNotEmpty &&
        _lastTouched >= 0 &&
        _lastTouched < prices.length) {
      // 备注框空着、只有加价框填了数 → 这个数归**最后动过的那条**备注
      // （最常见的一步操作：点常用备注标签 → 加价框打 70 → 直接点「加入购物车」）
      prices[_lastTouched] = _typedPrice;
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
    // 常用备注按**种类**给：通用('' 键) + 这个菜品所属分类的
    final savedNotes = settings.notesFor(_categoryId);
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
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
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
                    // 常用备注标签：点一下**加进备注**（不是填进输入框）
                    if (savedNotes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final n in savedNotes)
                            FilterChip(
                              selected: _notes.contains(n),
                              onSelected: (v) => _toggleSavedNote(
                                  n, v, settings.notePriceFor(_categoryId, n)),
                              // 标签上也把加价写出来，免得点了才知道加钱
                              label: Text(
                                '$n${_priceTag(settings.notePriceFor(_categoryId, n))}',
                              ),
                              showCheckmark: true,
                              selectedColor: const Color(0xFF1FA85A),
                              checkmarkColor: Colors.white,
                              labelStyle: TextStyle(
                                color: _notes.contains(n)
                                    ? Colors.white
                                    : const Color(0xFF232829),
                                fontWeight: FontWeight.w600,
                              ),
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
