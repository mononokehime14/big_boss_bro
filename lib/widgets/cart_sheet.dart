import 'package:flutter/material.dart';

import 'cart_panel.dart';
import 'payment_flow.dart';

/// 打开购物车明细底部弹窗（窄屏/手机用；宽屏是右侧常驻面板）。
///
/// 弹窗里就是同一个 [CartPanel]：上面「已在单上 / 本次新增」两个分区，
/// 下面两个按钮 **保存 / 厨房** —— 点完先关弹窗，再用点单页的 context 跑流程
/// （弹窗自己的 context 已经关闭，不能再用）。
Future<void> showCartSheet(BuildContext context) {
  void runAfterClose(Future<void> Function(BuildContext) flow) {
    // 用点单页的 context（弹窗的 context 已经关闭）
    WidgetsBinding.instance.addPostFrameCallback((_) => flow(context));
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: CartPanel(
        showHandle: true,
        onSave: () {
          Navigator.of(sheetContext).pop();
          runAfterClose(saveOrderFlow);
        },
        onKitchen: () {
          Navigator.of(sheetContext).pop();
          runAfterClose(kitchenOrderFlow);
        },
      ),
    ),
  );
}
