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
  final int quantity;

  const ItemEditResult({
    required this.selections,
    required this.notes,
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

  /// 份数（默认 1）。
  late int _qty = widget.initial?.quantity ?? 1;

  final _noteCtl = TextEditingController();
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
    _qtyCtl.text = '$_qty';
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
    _noteCtl.dispose();
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

  /// 按当前选择算出的单价（基础价 + 各选中项加价）。
  double get _unitPrice {
    final item = widget.item;
    if (item == null) return 0;
    return item.unitPriceFor(_selections);
  }

  String get _displayName => widget.title ?? widget.item?.name ?? '';

  /// 改份数（+/- 按钮和输入框都走这里，两边永远同步）。
  void _setQty(int v) {
    final q = v < 1 ? 1 : v;
    setState(() {
      _qty = q;
      _qtyCtl.text = '$q';
    });
  }

  /// 「加进备注」：把输入框里的文字存成一条备注，清空输入框准备填下一条。
  void _addNote() {
    final text = _noteCtl.text.trim();
    if (text.isEmpty) return;
    if (_saveAsTag) {
      context.read<SettingsController>().addSavedNote(_categoryId, text);
    }
    setState(() {
      if (!_notes.contains(text)) _notes.add(text);
      _noteCtl.clear();
    });
    // 光标留在输入框里，方便接着填下一条
    _noteFocus.requestFocus();
  }

  /// 备注要存到哪个种类下（编辑老单时可能没有对应菜单项 → 存到「通用」）。
  String get _categoryId => widget.item?.categoryId ?? '';

  void _confirm() {
    final settingsCtl = context.read<SettingsController>();
    // 输入框里还没点「加进备注」的那条也算上，别让收银员白填
    final typed = _noteCtl.text.trim();
    if (typed.isNotEmpty && _saveAsTag) {
      settingsCtl.addSavedNote(_categoryId, typed);
    }
    final notes = List<String>.of(_notes);
    if (typed.isNotEmpty && !notes.contains(typed)) notes.add(typed);

    Navigator.pop(
      context,
      ItemEditResult(
        selections: _selections,
        notes: notes,
        quantity: _qty,
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
            // ---- 标题：菜名 + 单价（选了不同规格会变）----
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
                    Text(
                      item.hasUnit
                          ? '${money(_unitPrice, symbol)} / ${item.unit}'
                          : money(_unitPrice, symbol),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1FA85A),
                      ),
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            L10n.t('custom.note.multi'),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 已经加进去的备注（点 ✕ 去掉）
                    if (_notes.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final n in _notes)
                            InputChip(
                              label: Text(n),
                              onDeleted: () => setState(() => _notes.remove(n)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    // 输入框 + 「加进备注」：填一条 → 保存 → 接着填下一条
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _noteCtl,
                            focusNode: _noteFocus,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: L10n.t('custom.note.hint'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _addNote(),
                          ),
                        ),
                        const SizedBox(width: 8),
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
                              onSelected: (v) => setState(() {
                                if (v) {
                                  if (!_notes.contains(n)) _notes.add(n);
                                } else {
                                  _notes.remove(n);
                                }
                              }),
                              label: Text(n),
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
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _qty > 1 ? () => _setQty(_qty - 1) : null,
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
                            '${money(_unitPrice * _qty, symbol)}',
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
