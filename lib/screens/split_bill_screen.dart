import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import '../utils/order_label.dart';

/// 打开「**分单**」界面（客人分开付钱时用）。
///
/// 入口在购物车右上角「⋮」→「分单」。
Future<void> showSplitBillScreen(BuildContext context, String orderId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SplitBillScreen(orderId: orderId),
      ),
    );

/// **分单界面**（一单一条线：母单 + 若干分单，横向排开）。
///
/// ```
/// ┌── 母单 ──────┐ ┌── 桌号1-分单1 ─┐ ┌── 桌号1-分单2 ─┐
/// │ 合计 ¥52     │ │ 合计 ¥30       │ │ 合计 ¥22       │
/// │ ☑ ×2 牛肉炒饭│ │ ☐ ×1 宫保鸡丁  │ │ ☐ ×1 可乐      │
/// │ ☐ ×1 可乐    │ │                │ │                │
/// │ [移动]       │ │ [移动]         │ │ [移动]         │
/// └──────────────┘ └────────────────┘ └────────────────┘
/// ```
///
/// - **一开始只有母单这一栏**；分出去之后右边多一栏分单；
/// - **每一栏下面都有「移动」**：母单能分，分单**也能继续往下分**
///   （新分单永远挂在同一个母单下、分单号接着排，所以是一排并列的卡片）；
/// - 分单多了**横向滑动**；
/// - 每栏都显示**自己的合计**（客人分开付钱，各自结账）。
///
/// 规则（`PosController.splitOrderLines`）：菜是**挪走**的（合计加起来不变）、
/// 出手的那一栏至少留一道菜、分单单独结账。
class SplitBillScreen extends StatefulWidget {
  /// 从哪张单进来的（母单或分单都行 —— 会显示它所属的**整条线**）。
  final String orderId;

  const SplitBillScreen({super.key, required this.orderId});

  @override
  State<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends State<SplitBillScreen> {
  /// 现在勾的是**哪一栏**（空 = 还没勾）。
  String _sourceId = '';

  /// 勾选的菜品下标（在 [_sourceId] 那张单的 `lines` 里）。
  final Set<int> _picked = <int>{};

  /// 勾 / 取消勾某一栏里的第 [index] 道菜。
  ///
  /// 换了栏就把上一栏的勾选清掉（一次只从一个单里往外挪，不然「移到哪」会说不清）。
  void _toggle(String orderId, int index) => setState(() {
        if (_sourceId != orderId) {
          _sourceId = orderId;
          _picked.clear();
        }
        if (!_picked.remove(index)) _picked.add(index);
      });

  /// 问「移到哪儿」：新分单 / 这条线里**别的**分单。
  Future<String?> _askTarget(List<Order> family, String sourceId, String symbol) {
    final others = family.where((o) => o.isSplit && o.id != sourceId).toList();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(L10n.t('split.move')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: Row(
              children: [
                const Icon(Icons.add_circle_outline,
                    size: 20, color: Color(0xFF1FA85A)),
                const SizedBox(width: 10),
                Text(L10n.t('split.newSplit')),
              ],
            ),
          ),
          if (others.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                L10n.t('split.existing'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            for (final s in others)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, s.id),
                child: Row(
                  children: [
                    Icon(Icons.call_split,
                        size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 10),
                    Expanded(child: Text(orderPlaceLabel(s))),
                    Text(
                      money(s.total, symbol),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _move(
    List<Order> family,
    String sourceId,
    String symbol,
  ) async {
    final target = await _askTarget(family, sourceId, symbol);
    if (target == null || !mounted) return;
    final pos = context.read<PosController>();
    final picked = _picked.toList()..sort();
    final r = pos.splitOrderLines(sourceId, picked, intoSplitId: target);
    if (r == null || !mounted) return;
    setState(() {
      _picked.clear();
      _sourceId = '';
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('${L10n.t('split.moved')} · ${orderPlaceLabel(r)}'),
        duration: const Duration(milliseconds: 1600),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final symbol = settings.currencySymbol;

    // 这条线：母单 + 分单（进行中的那些）
    final family = pos.familyOrders(widget.orderId);

    if (family.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.t('split.title'))),
        body: Center(child: Text(L10n.t('move.emptySource'))),
      );
    }

    // 勾的那一栏没了（被结账 / 被挪空）→ 清掉勾选
    if (_sourceId.isNotEmpty && !family.any((o) => o.id == _sourceId)) {
      _sourceId = '';
      _picked.clear();
    }

    final width = MediaQuery.of(context).size.width;
    // 一栏多宽：手机上一屏基本一栏（横滑看下一栏），平板上并排两三栏
    final colWidth = math.min(360.0, math.max(260.0, width * 0.82));

    return Scaffold(
      appBar: AppBar(
        title: Text('${L10n.t('split.title')} · ${orderPlaceLabel(family.first)}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.call_split, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    L10n.t('split.hint'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: family.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final order = family[i];
                final isSource = order.id == _sourceId;
                return SizedBox(
                  width: colWidth,
                  child: _SplitColumn(
                    order: order,
                    isMain: !order.isSplit,
                    symbol: symbol,
                    // 勾选只属于"当前这一栏"
                    picked: isSource ? _picked : const <int>{},
                    active: isSource,
                    onToggle: (index) => _toggle(order.id, index),
                    onMove: () => _move(family, order.id, symbol),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 一栏：一张单（母单或分单）—— 标题 + 合计 + 菜品（可勾选）+ 「移动」。
class _SplitColumn extends StatelessWidget {
  final Order order;

  /// 是不是母单（标题写「母单」）。
  final bool isMain;

  final String symbol;

  /// 这一栏里被勾选的行下标（不是当前栏就是空的）。
  final Set<int> picked;

  /// 当前勾的是不是这一栏（高亮边框）。
  final bool active;

  final void Function(int index) onToggle;
  final VoidCallback onMove;

  const _SplitColumn({
    required this.order,
    required this.isMain,
    required this.symbol,
    required this.picked,
    required this.active,
    required this.onToggle,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        isMain ? const Color(0xFF1FA85A) : const Color(0xFF1565C0);
    // 勾满一整栏 = 这张单会被搬空 → 不允许
    final allPicked =
        order.lines.isNotEmpty && picked.length >= order.lines.length;
    final pickedTotal = [
      for (var i = 0; i < order.lines.length; i++)
        if (picked.contains(i)) order.lines[i].subtotal,
    ].fold<double>(0, (a, b) => a + b);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: active ? accent : Colors.grey.shade300,
          width: active ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- 标题：哪一单 + 合计 ----
          Container(
            color: accent.withValues(alpha: 0.12),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // 母单那一栏写「母单 · 桌号 1」，分单直接写「桌号 1-分单1」
                  isMain
                      ? '${L10n.t('split.parent')} · ${orderPlaceLabel(order)}'
                      : orderPlaceLabel(order),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      money(order.total, symbol),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${order.itemCount} ${L10n.t('cart.items')}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ---- 菜品（点一下勾上）----
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: order.lines.length,
              itemBuilder: (context, i) {
                final line = order.lines[i];
                final checked = picked.contains(i);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (_) => onToggle(i),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: const EdgeInsets.only(right: 4),
                  title: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          '×${line.quantity}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          line.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        money(line.subtotal, symbol),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  subtitle: line.detail.trim().isEmpty
                      ? null
                      : Text(
                          line.detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // ---- 底下：已选 N 项 / 金额 + 移动 ----
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  picked.isEmpty
                      ? '—'
                      : '${L10n.t('split.selected')} ${picked.length} '
                          '${L10n.t('cart.items')} · '
                          '${money(pickedTotal, symbol)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
                if (allPicked)
                  Text(
                    L10n.t('split.keepOne'),
                    maxLines: 2,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFEF6C00)),
                  ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed:
                      picked.isEmpty || allPicked ? null : onMove,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    minimumSize: const Size(0, 40),
                  ),
                  icon: const Icon(Icons.call_split, size: 18),
                  label: Text(L10n.t('split.move')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
