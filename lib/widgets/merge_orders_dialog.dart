import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import '../utils/order_label.dart';

/// **合并单子**窗口。
///
/// 左边勾选要合并的进行中单子（可多选），右边再从已勾选里选一张
/// **保留**的单子；确认后会二次确认，然后调用 [PosController.mergeOrders]。
Future<void> showMergeOrdersDialog(
  BuildContext context, {
  String? orderId,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _MergeOrdersDialog(initialOrderId: orderId ?? ''),
    );

class _MergeOrdersDialog extends StatefulWidget {
  final String initialOrderId;

  const _MergeOrdersDialog({required this.initialOrderId});

  @override
  State<_MergeOrdersDialog> createState() => _MergeOrdersDialogState();
}

class _MergeOrdersDialogState extends State<_MergeOrdersDialog> {
  final Set<String> _selected = <String>{};
  String _targetId = '';

  @override
  void initState() {
    super.initState();
    final id = widget.initialOrderId.trim();
    if (id.isNotEmpty) {
      _selected.add(id);
      _targetId = id;
    }
  }

  void _toggle(String id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(id);
        if (_targetId.isEmpty) _targetId = id;
      } else {
        _selected.remove(id);
        if (_targetId == id) {
          _targetId = _selected.isEmpty ? '' : _selected.first;
        }
      }
    });
  }

  Future<void> _confirm(
    BuildContext context,
    PosController pos,
    Order target,
    Set<String> selectedIds,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('merge.confirmTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.t('merge.confirmBody')),
            const SizedBox(height: 16),
            Text(
              '${selectedIds.length} → ${orderPlaceLabel(target)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.t('common.ok')),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final merged = pos.mergeOrders(selectedIds.toList(), target.id);
    navigator.pop();
    if (merged != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(L10n.t('merge.done')),
          duration: const Duration(milliseconds: 1600),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final symbol = settings.currencySymbol;

    final orders = pos.inProgressParents;
    // 弹窗打开期间订单可能被别的操作删掉：以当前列表为准，不用在 build 里改 state。
    final alive = orders.map((e) => e.id).toSet();
    final selectedIds = _selected.where(alive.contains).toSet();
    var targetId = _targetId;
    if (!alive.contains(targetId) || !selectedIds.contains(targetId)) {
      targetId = selectedIds.isEmpty ? '' : selectedIds.first;
    }

    Order? target;
    for (final o in orders) {
      if (o.id == targetId) {
        target = o;
        break;
      }
    }
    final selectedOrders =
        orders.where((o) => selectedIds.contains(o.id)).toList(growable: false);
    final canMerge = selectedOrders.length >= 2 &&
        target != null &&
        selectedIds.contains(target!.id);

    final size = MediaQuery.of(context).size;
    final width = math.min(680.0, size.width * 0.86);
    final height = math.min(460.0, size.height * 0.66);

    final left = _Pane(
      title: L10n.t('merge.source'),
      child: ListView(
        children: [
          for (final o in orders)
            CheckboxListTile(
              dense: true,
              value: selectedIds.contains(o.id),
              onChanged: (v) => _toggle(o.id, v),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                orderPlaceLabel(o),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${o.itemCount} ${L10n.t('cart.items')} · '
                '${money(o.total, symbol)}',
              ),
            ),
        ],
      ),
    );

    final right = _Pane(
      title: L10n.t('merge.target'),
      child: selectedOrders.isEmpty
          ? Center(
              child: Text(
                L10n.t('merge.needTwo'),
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          : ListView(
              children: [
                for (final o in selectedOrders)
                  RadioListTile<String>(
                    dense: true,
                    value: o.id,
                    groupValue: targetId,
                    onChanged: (v) {
                      if (v != null) setState(() => _targetId = v);
                    },
                    title: Text(
                      orderPlaceLabel(o),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${o.itemCount} ${L10n.t('cart.items')} · '
                      '${money(o.total, symbol)}',
                    ),
                  ),
              ],
            ),
    );

    return AlertDialog(
      title: Text(L10n.t('merge.title')),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: width,
        height: height,
        child: orders.length < 2
            ? Center(
                child: Text(
                  L10n.t('merge.empty'),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Expanded(
                    child: width < 460
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: left),
                              const Divider(height: 1),
                              Expanded(child: right),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: left),
                              const VerticalDivider(width: 1),
                              Expanded(child: right),
                            ],
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        if (!canMerge)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              selectedOrders.length < 2
                  ? L10n.t('merge.needTwo')
                  : L10n.t('merge.noTarget'),
              style: const TextStyle(fontSize: 12, color: Color(0xFFEF6C00)),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.t('common.cancel')),
        ),
        FilledButton(
          onPressed: canMerge && target != null
              ? () => _confirm(context, pos, target!, selectedIds)
              : null,
          child: Text(L10n.t('common.ok')),
        ),
      ],
    );
  }
}

/// 左右两栏共用的外壳：标题 + 滚动列表。
class _Pane extends StatelessWidget {
  final String title;
  final Widget child;

  const _Pane({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
