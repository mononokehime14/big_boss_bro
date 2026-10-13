import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/custom_menu_entry.dart';
import '../l10n/app_strings.dart';
import '../state/settings_controller.dart';

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

/// 「自定义」输入框：**特别备注（先）+ 金额（后）**（备注会当菜名，
/// 也可以存成常用备注，跟别的种类一样云同步）。
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

  /// 「把这条备注也存成常用备注」——默认**开**：
  /// 自定义菜的备注本来就是反复用的（「生日蛋糕」「加急」…），
  /// 存下来的会跟着店级配置**云同步**（`notesByCategory['__custom__']`）。
  bool _saveAsTag = true;

  String? _error;

  @override
  void initState() {
    super.initState();
    _amountCtl = TextEditingController(
      text: widget.initialAmount > 0 ? widget.initialAmount.toStringAsFixed(2) : '',
    );
    _noteCtl = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _noteCtl.dispose();
    _noteFocus.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _noteCtl.text.trim();
    final amount = double.tryParse(_amountCtl.text.trim().replaceAll(',', '.')) ?? 0;
    if (note.isEmpty) {
      setState(() => _error = L10n.t('custom.dialog.needNote'));
      _noteFocus.requestFocus();
      return;
    }
    if (amount <= 0) {
      setState(() => _error = L10n.t('custom.dialog.needAmount'));
      return;
    }
    // 存成常用备注（跟着「店级配置」云同步，别的设备也能用）
    if (_saveAsTag) {
      context.read<SettingsController>().addSavedNote(kCustomCategoryId, note);
    }
    Navigator.pop(context, CustomItemResult(note: note, amount: amount));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final currency = settings.currencySymbol;
    final savedNotes = settings.notesFor(kCustomCategoryId);

    return AlertDialog(
      title: Row(
        children: [
          const Text('✍️', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Text(L10n.t('custom.dialog.title'))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- 特别备注（会当菜名）----
            // 顺序是**先备注、后金额**（你说的）：先把"这是什么菜"写清楚，
            // 再填金额；老板/店员习惯也是这么念的。
            TextField(
              controller: _noteCtl,
              focusNode: _noteFocus,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: L10n.t('custom.note'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _amountFocus.requestFocus(),
            ),
            // 常用备注（点一下直接填进备注框）——包括「自定义」种类自己的那些
            // （设置 → 常用备注 里选「自定义」加 / 删）
            if (savedNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final n in savedNotes)
                    ActionChip(
                      label: Text(n),
                      onPressed: () => setState(() {
                        _noteCtl.text = n;
                        _noteCtl.selection = TextSelection.collapsed(
                            offset: _noteCtl.text.length);
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Checkbox(
                  value: _saveAsTag,
                  onChanged: (v) => setState(() => _saveAsTag = v ?? false),
                ),
                Expanded(
                  child: Text(
                    L10n.t('custom.note.saveTag'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ---- 金额 ----
            TextField(
              controller: _amountCtl,
              focusNode: _amountFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: L10n.t('custom.dialog.amount'),
                prefixText: '$currency ',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.t('common.cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(L10n.t('custom.dialog.add')),
        ),
      ],
    );
  }
}
