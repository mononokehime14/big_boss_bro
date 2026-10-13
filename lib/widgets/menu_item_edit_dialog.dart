import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/menu_item.dart';
import '../models/menu_option_group.dart';

/// 新增 / 编辑一道菜：**名称、基础价格、单位、基础数量、定制项**。
///
/// 「定制项」= Excel 里那几列（`定制项1 | 选项 | 选项价格`）：
/// 一个定制项 = **组名 + 若干选项**，每个选项可以有自己的**加价**
/// （例如 `Size: Mediano +140 / Grande +185`）。
/// 这里能加/删组、改组名、加/删选项、改选项名和加价 —— 不用回 Excel 改。
///
/// 返回 null = 用户取消了。
Future<MenuItem?> showMenuItemEditDialog(
  BuildContext context, {
  required String categoryId,

  /// 传了就是**编辑**那道菜，不传就是**新增**。
  MenuItem? existing,

  /// 新菜的 id 从哪来（新增时用，通常是 `PosController.nextId()`）。
  required String Function() nextId,
}) {
  return showDialog<MenuItem>(
    context: context,
    builder: (_) => _MenuItemDialog(
      categoryId: categoryId,
      existing: existing,
      nextId: nextId,
    ),
  );
}

/// 定制项里**一个选项**的编辑状态（名字 + 加价）。
class _OptionDraft {
  final TextEditingController name;
  final TextEditingController price;

  _OptionDraft(String name, double price)
      : name = TextEditingController(text: name),
        price = TextEditingController(
          text: price == 0
              ? ''
              : (price == price.roundToDouble()
                  ? price.toStringAsFixed(0)
                  : price.toStringAsFixed(2)),
        );

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

/// 一个**定制项**（组）的编辑状态。
class _GroupDraft {
  final TextEditingController name;
  final List<_OptionDraft> options = [];

  _GroupDraft(String groupName, {bool withOneEmptyOption = false})
      : name = TextEditingController(text: groupName) {
    if (withOneEmptyOption) options.add(_OptionDraft('', 0));
  }

  void dispose() {
    name.dispose();
    for (final o in options) {
      o.dispose();
    }
  }
}

class _MenuItemDialog extends StatefulWidget {
  final String categoryId;
  final MenuItem? existing;
  final String Function() nextId;

  const _MenuItemDialog({
    required this.categoryId,
    required this.nextId,
    this.existing,
  });

  @override
  State<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends State<_MenuItemDialog> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _nickCtl;
  late final TextEditingController _priceCtl;
  late final TextEditingController _unitCtl;
  late final TextEditingController _minQtyCtl;
  final List<_GroupDraft> _groups = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtl = TextEditingController(text: e?.name ?? '');
    _nickCtl = TextEditingController(text: e?.nickName ?? '');
    _priceCtl = TextEditingController(
      text: e == null
          ? ''
          : (e.price == e.price.roundToDouble()
              ? e.price.toStringAsFixed(0)
              : e.price.toStringAsFixed(2)),
    );
    _unitCtl = TextEditingController(text: e?.unit ?? '');
    _minQtyCtl = TextEditingController(
        text: (e == null || e.minQuantity <= 1) ? '' : '${e.minQuantity}');
    for (final g in e?.options ?? const <MenuOptionGroup>[]) {
      final draft = _GroupDraft(g.name);
      for (var i = 0; i < g.options.length; i++) {
        draft.options.add(_OptionDraft(
          g.options[i],
          i < g.prices.length ? g.prices[i] : 0,
        ));
      }
      _groups.add(draft);
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _nickCtl.dispose();
    _priceCtl.dispose();
    _unitCtl.dispose();
    _minQtyCtl.dispose();
    for (final g in _groups) {
      g.dispose();
    }
    super.dispose();
  }

  static double _num(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;

  /// 保存：把草稿翻成 [MenuItem]。**空组、空选项会被丢掉**（不留空壳）。
  MenuItem? _build() {
    final name = _nameCtl.text.trim();
    final price = double.tryParse(_priceCtl.text.trim().replaceAll(',', '.'));
    if (name.isEmpty || price == null || price < 0) return null;

    final options = <MenuOptionGroup>[];
    for (final g in _groups) {
      final gName = g.name.text.trim();
      final opts = <String>[];
      final prices = <double>[];
      for (final o in g.options) {
        final oName = o.name.text.trim();
        if (oName.isEmpty) continue; // 名字空着的选项直接不要
        opts.add(oName);
        prices.add(_num(o.price.text));
      }
      if (gName.isEmpty || opts.isEmpty) continue; // 空组不要
      options.add(MenuOptionGroup(name: gName, options: opts, prices: prices));
    }

    final minQty = int.tryParse(_minQtyCtl.text.trim()) ?? 1;
    return MenuItem(
      id: widget.existing?.id ?? widget.nextId(),
      name: name,
      price: price,
      emoji: widget.existing?.emoji ?? '',
      categoryId: widget.categoryId,
      options: options,
      unit: _unitCtl.text.trim(),
      nickName: _nickCtl.text.trim(),
      minQuantity: minQty < 1 ? 1 : minQty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(
          isNew ? L10n.t('menu.addItem') : L10n.t('menu.editItem')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: L10n.t('menu.itemName'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nickCtl,
                decoration: InputDecoration(
                  labelText: L10n.t('menu.itemNick'),
                  helperText: L10n.t('menu.itemNickHint'),
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: L10n.t('menu.itemPrice'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _unitCtl,
                      decoration: InputDecoration(
                        labelText: L10n.t('menu.itemUnit'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _minQtyCtl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: L10n.t('menu.itemMinQty'),
                        hintText: '1',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ---------------- 定制项 ----------------
              Row(
                children: [
                  Expanded(
                    child: Text(
                      L10n.t('menu.itemOptions'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() =>
                        _groups.add(_GroupDraft('', withOneEmptyOption: true))),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(L10n.t('menu.addOptionGroup')),
                  ),
                ],
              ),
              if (_groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    L10n.t('menu.noOptions'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              for (var gi = 0; gi < _groups.length; gi++)
                _groupCard(gi),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.t('common.cancel')),
        ),
        FilledButton(
          onPressed: () {
            final item = _build();
            if (item == null) return; // 名字/价格没填好就什么都不做
            Navigator.pop(context, item);
          },
          child: Text(isNew
              ? L10n.t('menu.confirmItem')
              : L10n.t('common.ok')),
        ),
      ],
    );
  }

  /// 一个定制项的小卡片：组名 + 每个选项（名字 + 加价）+ 加选项 + 删组。
  Widget _groupCard(int gi) {
    final g = _groups[gi];
    return Card(
      color: const Color(0xFFF7F9F8),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: g.name,
                    decoration: InputDecoration(
                      labelText: L10n.t('menu.optionGroupName'),
                      hintText: L10n.t('menu.optionGroupHint'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: L10n.t('common.delete'),
                  onPressed: () => setState(() {
                    _groups.removeAt(gi).dispose();
                  }),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 每个选项一行：名字 + 加价 + 删
            for (var oi = 0; oi < g.options.length; oi++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: g.options[oi].name,
                        decoration: InputDecoration(
                          labelText: L10n.t('menu.optionName'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: g.options[oi].price,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: L10n.t('menu.optionPrice'),
                          hintText: '0',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: L10n.t('common.delete'),
                      onPressed: () => setState(() {
                        g.options.removeAt(oi).dispose();
                      }),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => g.options.add(_OptionDraft('', 0))),
              icon: const Icon(Icons.add, size: 18),
              label: Text(L10n.t('menu.addOption')),
            ),
            Text(
              L10n.t('menu.optionToggleHint'),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
