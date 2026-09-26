import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import '../utils/pricing.dart';
import 'cart_sheet.dart';

/// 点单页底部的购物车栏（窄屏用）。显示**整桌**件数与合计，点开就是购物车明细，
/// 里面才是「保存 / 厨房」两个按钮。
class CartBottomBar extends StatelessWidget {
  const CartBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;

    final open = pos.openOrderForSelectedTable();
    final placed = open?.lines ?? const <OrderLine>[];
    final hasAnything = placed.isNotEmpty || !pos.cartEmpty;

    // 整桌合计（已在单上 + 本次新增），跟购物车面板里显示的是同一个数
    final price = PriceBreakdown.of(
      subtotal: (open?.subtotal ?? 0) + pos.cartSubtotal,
      discountType: open?.discountType ?? DiscountType.none,
      discountValue: open?.discountValue ?? 0,
      taxRate: open?.taxRate ?? settings.taxRate,
      taxIncluded: open?.taxIncluded ?? settings.taxIncluded,
    );
    final count = (open?.itemCount ?? 0) + pos.cartCount;

    return Material(
      color: Colors.white,
      elevation: 10,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: hasAnything ? () => showCartSheet(context) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.shopping_cart_outlined,
                            color: Color(0xFF232829)),
                        const SizedBox(width: 8),
                        Text(
                          '$count ${L10n.t('cart.items')}',
                          style: const TextStyle(
                              fontSize: 15, color: Color(0xFF232829)),
                        ),
                        const Spacer(),
                        Text(
                          money(price.total, settings.currencySymbol),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1FA85A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed:
                      hasAnything ? () => showCartSheet(context) : null,
                  child: Text(L10n.t('cart.actions')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
