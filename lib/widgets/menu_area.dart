import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/menu_sort.dart';
import 'category_grid.dart';
import 'menu_grid.dart';

/// 点单区（左半边）：
/// - 最上面一条**排序条**：默认（菜单顺序）/ 首字母 A-Z / 流行度，**最右边一个放大镜**；
/// - 还没选种类 → 显示**种类**列表；
/// - 选了种类 → 显示该种类下的**菜品**，顶部条可以点回种类列表；
/// - **正在搜索**（放大镜点开、输入框里有字）→ 下面直接显示**所有种类里**搜到的菜。
///
/// 「流行度」= 卖出的份数，**结账确认**时累加（见 `PosController.closeOrder`）。
class MenuArea extends StatelessWidget {
  const MenuArea({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();

    return Column(
      children: [
        const MenuSortBar(),
        // 搜索中：不看种类，直接把搜到的菜列出来（搜不到 / 没输入时 grid 自己会说一句）
        if (pos.menuSearching)
          const Expanded(child: MenuGrid())
        else if (pos.selectedCategoryId.isEmpty)
          const Expanded(child: CategoryGrid())
        else ...[
          const CategoryHeader(),
          const Expanded(child: MenuGrid()),
        ],
      ],
    );
  }
}

/// 排序条：默认 / 首字母 / 流行度 + **最右边的搜索**。选哪个存在设置里，重启还记得。
///
/// **默认**这一档 = "本机记住的顺序"：一开始是菜单原本的顺序，用户在格子上
/// **长按拖动**之后就按拖出来的顺序（只存本机，见 `Settings.menuOrder`）。
/// 选了「默认」时右边写一句提示 —— 不然没人知道能拖。
///
/// 搜索：点右边的 🔍 → **就在这一行**露出输入框（排序按钮先让位），边打边筛；
/// 点 ✕ 关掉，搜索词清空、回到原来的种类/菜品视图。搜索词存在
/// `PosController`（`menuSearchQuery`），所以界面重建 / 切语言都不会丢。
class MenuSortBar extends StatefulWidget {
  const MenuSortBar({super.key});

  @override
  State<MenuSortBar> createState() => _MenuSortBarState();
}

class _MenuSortBarState extends State<MenuSortBar> {
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// 搜索框开没开（关掉时搜索词也清掉，下面回到种类/菜品）。
  bool _open = false;

  @override
  void initState() {
    super.initState();
    // 从别的页面回来 / 界面重建时，控制器里如果还留着搜索词，就把搜索框恢复成打开状态
    // （不然下面在显示搜索结果，上面却没有输入框，看着很怪）
    final q = context.read<PosController>().menuSearchQuery;
    if (q.isNotEmpty) {
      _open = true;
      _ctl.text = q;
    }
    // 输入框右边那个「清空」小按钮要跟着有没有字变 → 自己重建一下这一行
    _ctl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _open = true);
    // 开了就聚焦（直接能打字），光标放到最后
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _ctl.selection =
          TextSelection.collapsed(offset: _ctl.text.length);
    });
  }

  void _closeSearch() {
    _ctl.clear();
    context.read<PosController>().clearMenuSearch();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final settingsCtl = context.watch<SettingsController>();
    final current = MenuSort.fromId(settingsCtl.settings.menuSort);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          if (!_open) ...[
            Icon(Icons.sort, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              L10n.t('menu.sort'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final mode in MenuSort.values) ...[
                      _chip(settingsCtl, current, mode, _label(mode)),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
            // 关着的时候：最右边一个放大镜（图标就够，不占地方）
            IconButton(
              onPressed: _openSearch,
              tooltip: L10n.t('menu.search'),
              icon: const Icon(Icons.search, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ] else ...[
            // 开着的时候：**这一行变成搜索框**（排序按钮让位），右边一个 ✕ 关掉
            Expanded(
              child: TextField(
                controller: _ctl,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  hintText: L10n.t('menu.search'),
                  suffixIcon: _ctl.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _ctl.clear();
                            context.read<PosController>().setMenuSearchQuery('');
                            _focus.requestFocus();
                          },
                          icon: const Icon(Icons.backspace_outlined, size: 18),
                          tooltip: L10n.t('cart.clear'),
                          visualDensity: VisualDensity.compact,
                        ),
                ),
                onChanged: (v) =>
                    context.read<PosController>().setMenuSearchQuery(v),
              ),
            ),
            IconButton(
              onPressed: _closeSearch,
              tooltip: L10n.t('common.cancel'),
              icon: const Icon(Icons.close, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  /// 排序方式在界面上的名字。
  String _label(MenuSort mode) => switch (mode) {
        MenuSort.natural => L10n.t('menu.sort.natural'),
        MenuSort.name => L10n.t('menu.sort.name'),
        MenuSort.popular => L10n.t('menu.sort.popular'),
      };

  Widget _chip(
    SettingsController ctl,
    MenuSort current,
    MenuSort mode,
    String label,
  ) {
    final selected = current == mode;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => ctl.setMenuSort(mode.id),
      label: Text(label),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selectedColor: const Color(0xFF1FA85A),
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? Colors.white : const Color(0xFF232829),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
