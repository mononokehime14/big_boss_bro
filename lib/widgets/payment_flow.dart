import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../services/receipt_print_service.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';

/// 选择支付方式底部弹窗，返回 null 表示取消。
Future<PaymentMethod?> showPaymentMethodSheet(
    BuildContext context, double total) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _PaymentSheet(total: total),
  );
}

class _PaymentSheet extends StatefulWidget {
  final double total;
  const _PaymentSheet({required this.total});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  PaymentMethod _selected = PaymentMethod.cash;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(L10n.t('dialog.payment.title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              money(widget.total, settings.currencySymbol),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1FA85A)),
            ),
            const SizedBox(height: 16),
            _methodTile(
              label: L10n.t('payment.cash'),
              icon: Icons.payments_outlined,
              value: PaymentMethod.cash,
            ),
            _methodTile(
              label: L10n.t('payment.card'),
              icon: Icons.credit_card,
              value: PaymentMethod.card,
            ),
            _methodTile(
              label: L10n.t('payment.qr'),
              icon: Icons.qr_code,
              value: PaymentMethod.qr,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _selected),
              child: Text(L10n.t('dialog.confirm.ok')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodTile({
    required String label,
    required IconData icon,
    required PaymentMethod value,
  }) {
    final selected = _selected == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selected = value),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF1FA85A) : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? const Color(0xFF1FA85A) : null),
              const SizedBox(width: 12),
              Text(label, style: const TextStyle(fontSize: 16)),
              const Spacer(),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? const Color(0xFF1FA85A) : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 下单 / 追单 流程：把购物车变成（或追加进）进行中的单 → 打「厨房单」。
Future<void> placeOrAppendFlow(
  BuildContext context, {
  required bool isAppend,
  required String table,
  String? appendOrderId,
}) async {
  final pos = context.read<PosController>();
  final settingsCtl = context.read<SettingsController>();
  final service = context.read<ReceiptPrintService>();

  if (pos.cartEmpty) return;

  // 追加前先快照本次新增的菜（厨房单只打这次新增的）
  final addedLines = pos.cartItems
      .map((c) => OrderLine(
            name: c.menuItem.name,
            quantity: c.quantity,
            unitPrice: c.menuItem.price,
          ))
      .toList();

  late final Order ticket;
  if (isAppend && appendOrderId != null) {
    final updated = pos.appendToOrder(appendOrderId);
    if (updated == null) return;
    ticket = Order(
      id: updated.id,
      createdAt: DateTime.now(),
      lines: addedLines,
      total: 0,
      table: updated.table,
      status: OrderStatus.inProgress,
    );
  } else {
    final created = pos.placeOrder(table: table);
    if (created == null) return;
    ticket = created;
  }

  final PrintError? err = await service.printKitchenTicket(
    ticket,
    settingsCtl.settings,
    isAppend: isAppend,
  );
  if (!context.mounted) return;

  if (err == null) {
    _snack(context, L10n.t('dialog.print.success'));
  } else {
    await showPrintFailureSheet(
      context,
      err,
      () => service.printKitchenTicket(ticket, settingsCtl.settings,
          isAppend: isAppend),
    );
  }
}

/// 结账流程：选支付方式 → 把订单改成已结单 → 打「顾客小票」。
Future<void> settleOrderFlow(BuildContext context, Order order) async {
  final pos = context.read<PosController>();
  final settingsCtl = context.read<SettingsController>();
  final service = context.read<ReceiptPrintService>();

  final method = await showPaymentMethodSheet(context, order.total);
  if (method == null) return;
  if (!context.mounted) return;

  final closed = pos.closeOrder(order.id, method);
  if (closed == null) return;

  final PrintError? err =
      await service.printReceipt(closed, settingsCtl.settings);
  if (!context.mounted) return;

  if (err == null) {
    _snack(context, L10n.t('dialog.print.success'));
  } else {
    await showPrintFailureSheet(
      context,
      err,
      () => service.printReceipt(closed, settingsCtl.settings),
    );
  }
}

/// 打印失败弹窗：重试 / 跳过并继续。
Future<void> showPrintFailureSheet(
  BuildContext context,
  PrintError error,
  Future<PrintError?> Function() retry,
) async {
  bool retrying = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(L10n.t('dialog.print.failed')),
            content: Text(
              _errorMessage(error),
              style: const TextStyle(color: Colors.redAccent),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(L10n.t('dialog.print.skip')),
              ),
              FilledButton(
                onPressed: () async {
                  if (retrying) return;
                  setState(() => retrying = true);
                  final res = await retry();
                  if (!dialogContext.mounted) return;
                  if (res == null) {
                    Navigator.pop(dialogContext);
                    _snack(context, L10n.t('dialog.print.success'));
                  } else {
                    setState(() => retrying = false);
                  }
                },
                child: Text(retrying
                    ? L10n.t('settings.scanning')
                    : L10n.t('dialog.print.retry')),
              ),
            ],
          );
        },
      );
    },
  );
}

String _errorMessage(PrintError error) {
  if (L10n.isChinese) {
    switch (error) {
      case PrintError.noPrinter:
        return '未选择打印机，请到「设置」里连接。';
      case PrintError.notConnected:
        return '打印机未连接，请检查连接。';
      case PrintError.ioError:
        return '写入打印机失败，请确认打印机已开机并有纸。';
      case PrintError.unsupported:
        return '当前平台暂不支持该打印机。';
    }
  } else {
    switch (error) {
      case PrintError.noPrinter:
        return 'No printer selected. Connect one in Settings.';
      case PrintError.notConnected:
        return 'Printer is not connected.';
      case PrintError.ioError:
        return 'Failed to write to printer. Check it is on and has paper.';
      case PrintError.unsupported:
        return 'This printer is not supported on this platform yet.';
    }
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
