import 'package:flutter/material.dart';

import 'cart_panel.dart';
import 'payment_flow.dart';

/// 打开购物车明细底部弹窗（窄屏/手机用；宽屏是右侧常驻面板）。
Future<void> showCartSheet(BuildContext context) {
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
        onSubmit: (isAppend, table, appendOrderId) {
          Navigator.of(sheetContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // 用点单页的 context（弹窗的 context 已经关闭）
            placeOrAppendFlow(
              context,
              isAppend: isAppend,
              table: table,
              appendOrderId: appendOrderId,
            );
          });
        },
      ),
    ),
  );
}
