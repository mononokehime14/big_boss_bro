import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/auth_controller.dart';

/// AppBar 右上角的账号按钮：显示当前账号，可以「锁定/退出登录」。
///
/// 放在每个页面的 AppBar actions 里，收银员随时能换人。
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final name = auth.currentName;

    return PopupMenuButton<String>(
      tooltip: L10n.t('auth.account'),
      icon: Row(
        children: [
          const Icon(Icons.person_outline, size: 20),
          const SizedBox(width: 4),
          if (name.isNotEmpty)
            Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
        ],
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '${L10n.t('auth.account')}: $name'
            '${auth.isAdmin ? ' (${L10n.t('auth.admin')})' : ' (${L10n.t('auth.cashier')})'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (auth.isElevated)
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              L10n.t('auth.elevated'),
              style: const TextStyle(fontSize: 12, color: Color(0xFFEF6C00)),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'lock',
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: 8),
              Text(L10n.t('auth.lock')),
            ],
          ),
        ),
      ],
      onSelected: (v) {
        if (v == 'lock') context.read<AuthController>().signOut();
      },
    );
  }
}
