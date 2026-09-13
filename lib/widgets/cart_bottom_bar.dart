import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';
import '../utils/format.dart';
import 'cart_sheet.dart';

/// 点单页底部的「购物车 / 结账」栏。点击打开购物车明细。
class CartBottomBar extends StatelessWidget {
  const CartBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosController>();
    final settings = context.watch<SettingsController>().settings;
    final empty = pos.cartEmpty;

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
                  onTap: empty ? null : () => showCartSheet(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.shopping_cart_outlined,
                            color: Color(0xFF232829)),
                        const SizedBox(width: 8),
                        Text(
                          '${pos.cartCount} ${L10n.t('cart.items')}',
                          style: const TextStyle(
                              fontSize: 15, color: Color(0xFF232829)),
                        ),
                        const Spacer(),
                        Text(
                          money(pos.cartTotal, settings.currencySymbol),
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
                  onPressed: empty ? null : () => showCartSheet(context),
                  child: Text(L10n.t('cart.placeOrder')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
