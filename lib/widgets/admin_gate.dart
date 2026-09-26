import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/auth_controller.dart';

/// 需要「管理员权限」的地方统一调它。
///
/// - 当前账号是管理员（或已经提权过）→ 直接返回 true；
/// - 收银员 → 弹窗让**输管理员密码**，对了就把本次会话临时提权，
///   不用退出登录再登一次（收银台前面没人愿意折腾）。
///
/// [reason] 是给用户看的一句说明，例如「删除订单需要管理员权限」。
Future<bool> requireAdmin(BuildContext context, {String? reason}) async {
  final auth = context.read<AuthController>();
  if (auth.canManage) return true;

  final ctl = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(L10n.t('auth.adminNeeded')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  reason,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
            TextField(
              controller: ctl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.t('auth.adminPin'),
                hintText: '****',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                final good = auth.elevate(v);
                if (good) {
                  Navigator.pop(dialogContext, true);
                } else {
                  setState(() => error = L10n.t('auth.wrongPin'));
                }
              },
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              final good = auth.elevate(ctl.text);
              if (good) {
                Navigator.pop(dialogContext, true);
              } else {
                setState(() => error = L10n.t('auth.wrongPin'));
              }
            },
            child: Text(L10n.t('common.ok')),
          ),
        ],
      ),
    ),
  );
  ctl.dispose();
  return ok ?? false;
}
