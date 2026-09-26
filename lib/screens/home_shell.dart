import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/sync_service.dart';
import '../state/settings_controller.dart';
import '../widgets/admin_gate.dart';
import 'orders_screen.dart';
import 'pos_screen.dart';
import 'settings_screen.dart';

/// 主页外壳：底部 3 个标签（点单 / 订单 / 设置）。
///
/// **权限**：「设置」是管理员的地方（打印机、税、桌号、菜单、账号…），
/// 收银员点它会要求输**管理员密码**（输对后本次会话临时提权）。
/// 点单和订单页收银员可以随便用（删历史订单另有单独的门禁）。
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
        onDestinationSelected: _onSelect,
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

  Future<void> _onSelect(int index) async {
    // 设置页 = 管理员专区
    if (index == 2) {
      final ok = await requireAdmin(
        context,
        reason: L10n.t('auth.settingsNeeded'),
      );
      if (!ok || !mounted) return;
    }
    setState(() => _index = index);
    // 切到「订单」就顺手同步一次：多设备共用一个单池时，收银员切过来看到的
    // 就是最新的（不用干等 25 秒那一趟定时同步）。syncNow 自己会判断
    // 「没启用 / 正在同步中」，所以重复切也不会发多余请求。
    if (index == 1 && mounted) {
      final settings = context.read<SettingsController>().settings;
      if (settings.syncEnabled) {
        unawaited(context.read<SyncService>().syncNow());
      }
    }
  }
}
