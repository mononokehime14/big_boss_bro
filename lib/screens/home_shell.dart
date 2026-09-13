import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'orders_screen.dart';
import 'pos_screen.dart';
import 'settings_screen.dart';

/// 主页外壳：底部 3 个标签（点单 / 订单 / 设置）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        // 不写 const：语言切换时需要整棵界面重建，让 L10n.t 重新取文案
        children: [PosScreen(), OrdersScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.restaurant_menu),
            label: L10n.t('nav.menu'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long),
            label: L10n.t('nav.orders'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.print),
            label: L10n.t('nav.settings'),
          ),
        ],
      ),
    );
  }
}
