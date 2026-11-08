import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/custom_menu_entry.dart';
import '../l10n/app_strings.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';

/// 「自定义」菜的输入结果：**金额 + 特别备注**（备注会当菜名打出去）。
class CustomItemResult {
  final String note;
  final double amount;

  const CustomItemResult({required this.note, required this.amount});
}

/// 弹「自定义」框：金额 + 特别备注。
///
/// 用途：客人点了菜单上没有的东西（临时加菜、按重量算的菜…）——
/// 备注会**当菜名**打在小票/厨房单上（用户选的做法），金额就是单价。
///
/// - [initialNote] / [initialAmount]：编辑购物车里**已有的自定义行**时带上原值；
/// - 返回 null = 取消。
Future<CustomItemResult?> showCustomItemDialog(
  BuildContext context, {
  String initialNote = '',
  double initialAmount = 0,
}) =>
    showDialog<CustomItemResult>(
      context: context,
      builder: (_) => CustomItemDialog(
        initialNote: initialNote,
        initialAmount: initialAmount,
      ),
    );

/// 「自定义」输入框，版式和正常菜品弹窗一致：
/// 标题栏（名字 + 金额 + 关闭）→ 特别备注 → 输入框 / 金额 → 5 行备注 chip
/// → 存为常用备注 → 底部取消 / 加入单子。
///
/// 正常菜品弹窗显示 **3 行**备注；自定义没有规格/份数，空间更宽裕，显示 **5 行**。
class CustomItemDialog extends StatefulWidget {
  final String initialNote;
  final double initialAmount;

  const CustomItemDialog({
    super.key,
    this.initialNote = '',
    this.initialAmount = 0,
  });

  @override
  State<CustomItemDialog> createState() => _CustomItemDialogState();
}

class _CustomItemDialogState extends State<CustomItemDialog> {
  late final TextEditingController _amountCtl;
  late final TextEditingController _noteCtl;
  final FocusNode _noteFocus = FocusNode();
  final FocusNode _amountFocus = FocusNode();

  /// 5 行备注 chip 的滚动条。
  final ScrollController _noteListScroll = ScrollController();

  /// 「把这条备注也存成常用备注」——默认**开**：
  /// 自定义菜的备注本来就是反复用的（「生日蛋糕」「加急」…），
  /// 存下来的会跟着店级配置**云同步**（`notesByCategory['__custom__']`），
  /// 并且**连金额一起存**（选中时金额直接回填）。
  bool _saveAsTag = true;

  String? _error;

  @override
  void initState() {
    super.initState();
    _amountCtl = TextEditingController(
      text: widget.initialAmount.abs() < 0.005
          ? ''
          : widget.initialAmount.toStringAsFixed(2),
    );
    _noteCtl = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _noteCtl.dispose();
    _noteFocus.dispose();
    _amountFocus.dispose();
    _noteListScroll.dispose();
    super.dispose();
  }

  /// 备注搜索归一化：转小写 + 去空格（「不要 米饭」也能搜到「不要米饭」）。
  static String _normNote(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// 相近备注打分：完全一样 4 → 前缀 3 → 包含 2 → 按顺序出现 1 → 不相关 -1。
  static int _noteMatchScore(String note, String query) {
    final n = _normNote(note);
    final q = _normNote(query);
    if (q.isEmpty) return 0;
    if (n == q) return 4;
    if (n.startsWith(q)) return 3;
    if (n.contains(q)) return 2;
    final nr = n.runes.toList();
    final qr = q.runes.toList();
    var qi = 0;
    for (var i = 0; i < nr.length && qi < qr.length; i++) {
      if (nr[i] == qr[qi]) qi++;
    }
    return qi == qr.length ? 1 : -1;
  }

  /// 备注文字后面跟的价签（` +70` / ` -60`；0 不显示）。
  String _priceTag(double price) =>
      price == 0 ? '' : ' ${signedAmount(price)}';

  /// 标题上的金额：负数带 `-`，正数按正常价格的写法（不加 `+`）。
  String _titleMoney(double value, String currency) {
    if (value.abs() < 0.005) return '';
    return value < 0 ? '-${money(-value, currency)}' : money(value, currency);
  }

  /// 点一条常用备注：**只能选一条**，点另一条就替换。
  /// 备注文字和金额一起回填。
  void _pickNote(String note, double price) {
    setState(() {
      _noteCtl.text = note;
      _noteCtl.selection =
          TextSelection.collapsed(offset: _noteCtl.text.length);
      _amountCtl.text =
          price.abs() < 0.005 ? '' : price.toStringAsFixed(2);
      _error = null;
    });
    _amountFocus.requestFocus();
  }

  void _submit() {
    final note = _noteCtl.text.trim();
    final rawAmount = _amountCtl.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(rawAmount);
    if (note.isEmpty) {
      setState(() => _error = L10n.t('custom.dialog.needNote'));
      _noteFocus.requestFocus();
      return;
    }
    // 金额可以是正数、负数，也可以是 0；但必须是一个有效数字。
    if (rawAmount.isEmpty || amount == null) {
      setState(() => _error = L10n.t('custom.dialog.needAmount'));
      _amountFocus.requestFocus();
      return;
    }
    // 存成常用备注（跟着「店级配置」云同步，别的设备也能用）。
    // **金额一起存**：下次在 5 行 chip 里点它，金额直接回填。
    if (_saveAsTag) {
      context
          .read<SettingsController>()
          .addSavedNote(kCustomCategoryId, note, price: amount!);
    }
    Navigator.pop(context, CustomItemResult(note: note, amount: amount!));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final currency = settings.currencySymbol;
    final noteQuery = _noteCtl.text.trim();

    // 通用（''）+ 自定义分类，去重；通用组里的备注也会出现在这里，
    // 但保存时统一存回「自定义」组（不会污染每个菜品的备注）。
    final allNotes = <String>[];
    final seen = <String>{};
    for (final n in settings.notesFor(kCustomCategoryId)) {
      if (seen.add(n)) allNotes.add(n);
    }

    // 输入框本身就是搜索框：空 = 全部常用备注；打字 = 相近的排前面。
    final matches = <({String note, int score, int index})>[];
    for (var i = 0; i < allNotes.length; i++) {
      final score =
          noteQuery.isEmpty ? 0 : _noteMatchScore(allNotes[i], noteQuery);
      if (score < 0) continue;
      matches.add((note: allNotes[i], score: score, index: i));
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.index.compareTo(b.index);
    });
    final visibleNotes = [for (final m in matches) m.note];
    final selectedNote = allNotes.contains(noteQuery) ? noteQuery : null;

    final amount =
        double.tryParse(_amountCtl.text.trim().replaceAll(',', '.')) ?? 0;
    final titleAmount = _titleMoney(amount, currency);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // 和正常菜品弹窗一样宽（见 item_customize_dialog.dart）
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- 标题：名字 + 当前金额 + 关闭（跟正常菜品一样）----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      L10n.t('custom.dialog.title'),
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (titleAmount.isNotEmpty)
                    Text(
                      titleAmount,
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
                    // 特别备注标题（和正常菜品一样）
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

                    // 输入框 + 金额（版式同正常菜品的「备注 + 加价」）
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _noteCtl,
                            focusNode: _noteFocus,
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: L10n.t('custom.note.hint'),
                            ),
                            onChanged: (_) =>
                                setState(() => _error = null),
                            onSubmitted: (_) =>
                                _amountFocus.requestFocus(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 84,
                          child: TextField(
                            controller: _amountCtl,
                            focusNode: _amountFocus,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true, signed: true),
                            textAlign: TextAlign.right,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              isDense: true,
                              hintText: L10n.t('custom.dialog.amount'),
                              hintStyle: const TextStyle(fontSize: 12),
                            ),
                            onChanged: (_) =>
                                setState(() => _error = null),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                      ],
                    ),

                    // 搜索时的提示（跟正常菜品一致）
                    if (noteQuery.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        visibleNotes.isNotEmpty
                            ? L10n.t('custom.note.matches')
                            : L10n.t('custom.note.noMatch'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],

                    // 5 行常用备注 chip（和正常菜品同一套 chip，只是行数不同）
                    if (visibleNotes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: Scrollbar(
                          controller: _noteListScroll,
                          thumbVisibility: true,
                          interactive: true,
                          thickness: 6,
                          radius: const Radius.circular(3),
                          child: ConstrainedBox(
                            // 5 行：32 × 5 + 4 × 4 = 176
                            constraints:
                                const BoxConstraints(maxHeight: 176),
                            child: SingleChildScrollView(
                              controller: _noteListScroll,
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.only(right: 12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  for (final n in visibleNotes)
                                    FilterChip(
                                      selected: n == selectedNote,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onSelected: (_) => _pickNote(
                                        n,
                                        settings.notePriceFor(
                                            kCustomCategoryId, n),
                                      ),
                                      label: Text(
                                        '$n${_priceTag(settings.notePriceFor(kCustomCategoryId, n))}',
                                      ),
                                      showCheckmark: false,
                                      labelStyle: const TextStyle(
                                        color: Color(0xFF232829),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else if (noteQuery.isEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        L10n.t('settings.notes.none'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],

                    // 存为常用备注
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
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1),
            // ---- 操作（跟正常菜品一样）----
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
                      onPressed: _submit,
                      child: Text(L10n.t('custom.dialog.add')),
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
