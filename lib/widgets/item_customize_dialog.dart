import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/menu_item.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';

/// 打开「个性化定制」对话框（**屏幕中间**）：选定制项 + 填「其他备注」，确认后加入购物车。
Future<void> showItemCustomizeDialog(BuildContext context, MenuItem item) {
  return showDialog<void>(
    context: context,
    builder: (_) => ItemCustomizeDialog(item: item),
  );
}

class ItemCustomizeDialog extends StatefulWidget {
  final MenuItem item;
  const ItemCustomizeDialog({super.key, required this.item});

  @override
  State<ItemCustomizeDialog> createState() => _ItemCustomizeDialogState();
}

class _ItemCustomizeDialogState extends State<ItemCustomizeDialog> {
  /// 定制项名 → 选中的选项（每组单选，默认选第一个）。
  final Map<String, String> _selected = {};

  final _noteCtl = TextEditingController();
  bool _saveAsTag = false;

  @override
  void initState() {
    super.initState();
    for (final g in widget.item.options) {
      if (!g.isEmpty) _selected[g.name] = g.options.first;
    }
  }

  @override
  void dispose() {
    _noteCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final savedNotes = settings.savedNotes;
    final item = widget.item;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- 标题：菜名 + 价格 ----
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    money(item.price, settings.currencySymbol),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 定制项（来自 Excel）
                    for (final g in item.options)
                      if (!g.isEmpty) ...[
                        Text(
                          g.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final o in g.options)
                              ChoiceChip(
                                selected: _selected[g.name] == o,
                                onSelected: (_) =>
                                    setState(() => _selected[g.name] = o),
                                label: Text(o),
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

                    // 其他备注（固定都有）
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
                    // 以前用过的常用备注，点一下直接填进输入框
                    if (savedNotes.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final n in savedNotes)
                            ActionChip(
                              label: Text(n),
                              onPressed: () =>
                                  setState(() => _noteCtl.text = n),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: _noteCtl,
                      decoration: InputDecoration(
                        hintText: L10n.t('custom.note.hint'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
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
                    child: FilledButton(
                      onPressed: _confirm,
                      child: Text(L10n.t('custom.add')),
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

  void _confirm() {
    final pos = context.read<PosController>();
    final settingsCtl = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);

    final selections = <String>[];
    for (final g in widget.item.options) {
      final v = _selected[g.name];
      if (v != null && v.trim().isNotEmpty) selections.add(v);
    }
    final note = _noteCtl.text.trim();
    if (_saveAsTag && note.isNotEmpty) settingsCtl.addSavedNote(note);

    pos.addToCart(widget.item, selections: selections, note: note);
    Navigator.pop(context);

    final detail =
        [selections.join(' / '), note].where((e) => e.isNotEmpty).join(' · ');
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(detail.isEmpty
            ? widget.item.name
            : '${widget.item.name} · $detail'),
        duration: const Duration(milliseconds: 900),
      ));
  }
}
