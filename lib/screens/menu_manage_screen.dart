import 'package:flutter/material.dart' hide Category;
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/category.dart';
import '../models/menu_item.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';

/// 菜品/分类管理：增删改菜单，改动自动持久化。
class MenuManageScreen extends StatefulWidget {
  const MenuManageScreen({super.key});

  @override
  State<MenuManageScreen> createState() => _MenuManageScreenState();
}

class _MenuManageScreenState extends State<MenuManageScreen> {
  String _selectedCatId = '';

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final currency = settings.currencySymbol;

    final cats = pos.categories;
    final items = _selectedCatId.isEmpty
        ? pos.menu.toList()
        : pos.menu.where((m) => m.categoryId == _selectedCatId).toList();

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('menu.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(L10n.t('menu.categories')),
          Card(
            color: Colors.white,
            child: Column(
              children: [
                for (final c in cats)
                  _categoryTile(pos, c),
                _addTile(
                  icon: Icons.add,
                  label: L10n.t('menu.addCategory'),
                  onTap: () => _addCategory(pos),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(L10n.t('menu.items')),
          Card(
            color: Colors.white,
            child: Column(
              children: [
                for (final m in items) _itemTile(context, pos, m, currency),
                _addTile(
                  icon: Icons.add,
                  label: L10n.t('menu.addItem'),
                  onTap: () => _addItem(pos),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 恢复默认菜单（改乱后一键还原）
          OutlinedButton.icon(
            onPressed: () => _resetMenu(pos),
            icon: const Icon(Icons.refresh),
            label: Text(L10n.t('menu.reset')),
          ),
        ],
      ),
    );
  }

  Future<void> _resetMenu(PosController pos) async {
    final ok = await _confirm(L10n.t('menu.resetConfirm'));
    if (ok) {
      pos.resetMenuToDefault();
      setState(() => _selectedCatId = '');
    }
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

  Widget _categoryTile(PosController pos, Category c) {
    final selected = _selectedCatId == c.id;
    return ListTile(
      leading: Text(c.emoji, style: const TextStyle(fontSize: 24)),
      title: Text(c.name),
      selected: selected,
      onTap: () => setState(() {
        _selectedCatId = selected ? '' : c.id;
      }),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editCategory(pos, c),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteCategory(pos, c),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(BuildContext context, PosController pos, MenuItem m,
      String currency) {
    return ListTile(
      leading: Text(m.emoji, style: const TextStyle(fontSize: 24)),
      title: Text(m.name),
      subtitle: Text(money(m.price, currency)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editItem(pos, m),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteItem(pos, m),
          ),
        ],
      ),
    );
  }

  Widget _addTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1FA85A)),
      title: Text(label, style: const TextStyle(color: Color(0xFF1FA85A))),
      onTap: onTap,
    );
  }

  // ---------------- 分类的增删改 ----------------

  Future<void> _addCategory(PosController pos) async {
    final cat = await _showCategoryDialog(context);
    if (cat != null) pos.addCategory(cat);
  }

  Future<void> _editCategory(PosController pos, Category c) async {
    final cat = await _showCategoryDialog(context, existing: c);
    if (cat != null) pos.updateCategory(cat);
  }

  Future<void> _deleteCategory(PosController pos, Category c) async {
    final ok = await _confirm(L10n.t('menu.deleteCategory'));
    if (ok) {
      pos.deleteCategory(c.id);
      if (_selectedCatId == c.id) setState(() => _selectedCatId = '');
    }
  }

  Future<Category?> _showCategoryDialog(BuildContext context, {Category? existing}) {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final emojiCtl = TextEditingController(text: existing?.emoji ?? '🍽️');
    return showDialog<Category>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null
            ? L10n.t('menu.addCategory')
            : L10n.t('menu.editCategory')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: L10n.t('menu.catName'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emojiCtl,
              decoration: InputDecoration(
                labelText: L10n.t('menu.catEmoji'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              final pos = context.read<PosController>();
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              final emoji = emojiCtl.text.trim().isEmpty ? '🍽️' : emojiCtl.text.trim();
              final cat = Category(
                id: existing?.id ?? pos.nextId(),
                name: name,
                emoji: emoji,
              );
              Navigator.pop(dialogContext, cat);
            },
            child: Text(L10n.t('menu.confirmCategory')),
          ),
        ],
      ),
    );
  }

  // ---------------- 菜品的增删改 ----------------

  Future<void> _addItem(PosController pos) async {
    var catId = _selectedCatId;
    if (catId.isEmpty) {
      // 没选分类就默认用第一个分类
      if (pos.categories.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(L10n.t('menu.needCategory'))));
        return;
      }
      catId = pos.categories.first.id;
    }
    final item = await _showItemDialog(context, categoryId: catId);
    if (item != null) pos.addMenuItem(item);
  }

  Future<void> _editItem(PosController pos, MenuItem m) async {
    final item = await _showItemDialog(context, categoryId: m.categoryId, existing: m);
    if (item != null) pos.updateMenuItem(item);
  }

  Future<void> _deleteItem(PosController pos, MenuItem m) async {
    final ok = await _confirm(L10n.t('menu.deleteItem'));
    if (ok) pos.deleteMenuItem(m.id);
  }

  Future<MenuItem?> _showItemDialog(BuildContext context,
      {required String categoryId, MenuItem? existing}) {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final emojiCtl = TextEditingController(text: existing?.emoji ?? '🍛');
    final priceCtl =
        TextEditingController(text: existing?.price.toString() ?? '');
    return showDialog<MenuItem>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null
            ? L10n.t('menu.addItem')
            : L10n.t('menu.editItem')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: L10n.t('menu.itemName'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emojiCtl,
              decoration: InputDecoration(
                labelText: L10n.t('menu.itemEmoji'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: L10n.t('menu.itemPrice'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              final pos = context.read<PosController>();
              final name = nameCtl.text.trim();
              final price = double.tryParse(priceCtl.text.trim());
              if (name.isEmpty || price == null || price < 0) return;
              final emoji = emojiCtl.text.trim().isEmpty ? '🍛' : emojiCtl.text.trim();
              final item = MenuItem(
                id: existing?.id ?? pos.nextId(),
                name: name,
                price: price,
                emoji: emoji,
                categoryId: categoryId,
              );
              Navigator.pop(dialogContext, item);
            },
            child: Text(L10n.t('menu.confirmItem')),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.t('common.delete')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
