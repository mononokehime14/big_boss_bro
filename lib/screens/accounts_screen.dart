import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/account.dart';
import '../state/auth_controller.dart';

/// 账号管理（**只有管理员能进**）：
/// 加收银员、改密码、改角色、删账号。
///
/// 规则（写在 [AuthController] 里，这里只是提示）：不能删自己，也不能删掉最后一个管理员。
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final accounts = auth.accounts;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.t('auth.manage'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.white,
            child: Column(
              children: [
                for (final a in accounts)
                  ListTile(
                    leading: Icon(
                      a.isAdmin ? Icons.admin_panel_settings : Icons.person,
                      color: a.isAdmin
                          ? const Color(0xFF1FA85A)
                          : Colors.grey.shade600,
                    ),
                    title: Text('${a.name}  (${a.id})'),
                    subtitle: Text(
                      '${a.isAdmin ? L10n.t('auth.admin') : L10n.t('auth.cashier')}'
                      '${auth.current?.id == a.id ? ' · ${L10n.t('auth.thisIsYou')}' : ''}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: L10n.t('common.edit'),
                      onPressed: () => _edit(context, a),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _add(context),
            icon: const Icon(Icons.person_add_alt),
            label: Text(L10n.t('auth.add')),
          ),
          const SizedBox(height: 8),
          Text(
            L10n.t('auth.hint'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final result = await showDialog<_AccountForm>(
      context: context,
      builder: (_) => const _AccountDialog(),
    );
    if (result == null || !context.mounted) return;
    final auth = context.read<AuthController>();
    final ok = await auth.addAccount(
      id: result.id,
      name: result.name,
      pin: result.pin,
      role: result.role,
    );
    if (!context.mounted) return;
    _toast(context, ok ? L10n.t('settings.saved') : L10n.t('auth.exists'));
  }

  Future<void> _edit(BuildContext context, Account account) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${account.name} (${account.id})'),
        content: Text(L10n.t('auth.editHint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'pin'),
            child: Text(L10n.t('auth.changePin')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'role'),
            child: Text(account.isAdmin
                ? L10n.t('auth.makeCashier')
                : L10n.t('auth.makeAdmin')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            child: Text(L10n.t('common.delete'),
                style: const TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(L10n.t('common.cancel')),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    final auth = context.read<AuthController>();

    switch (action) {
      // 每个 case 用花括号包起来：Dart 的 switch 各 case **共用同一个作用域**，
      // 不包的话两个 case 里都声明 `ok` 会直接编译报「名字已定义」。
      case 'pin': {
        final pin = await _askPin(context);
        if (pin == null || !context.mounted) return;
        final ok = await auth.updateAccount(account.copyWith(pin: pin));
        if (!context.mounted) return;
        _toast(context, ok ? L10n.t('settings.saved') : L10n.t('auth.lastAdmin'));
        break;
      }
      case 'role': {
        final updated = account.copyWith(
          role: account.isAdmin ? AccountRole.cashier : AccountRole.admin,
        );
        final ok = await auth.updateAccount(updated);
        if (!context.mounted) return;
        _toast(context, ok ? L10n.t('settings.saved') : L10n.t('auth.lastAdmin'));
        break;
      }
      case 'delete': {
        final yes = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(L10n.t('auth.deleteConfirm')),
            content: Text('${account.name} (${account.id})'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(L10n.t('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(L10n.t('common.delete')),
              ),
            ],
          ),
        );
        if (yes != true || !context.mounted) return;
        final ok = await auth.deleteAccount(account.id);
        if (!context.mounted) return;
        _toast(context,
            ok ? L10n.t('settings.saved') : L10n.t('auth.cantDelete'));
        break;
      }
    }
  }

  Future<String?> _askPin(BuildContext context) async {
    final ctl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.t('auth.newPin')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(L10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, ctl.text.trim()),
            child: Text(L10n.t('common.ok')),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (pin == null || pin.isEmpty) return null;
    return pin;
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 新增账号的表单数据。
class _AccountForm {
  final String id;
  final String name;
  final String pin;
  final AccountRole role;

  const _AccountForm(this.id, this.name, this.pin, this.role);
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog();

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _idCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _pinCtl = TextEditingController();
  AccountRole _role = AccountRole.cashier;

  @override
  void dispose() {
    _idCtl.dispose();
    _nameCtl.dispose();
    _pinCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.t('auth.add')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _idCtl,
              decoration: InputDecoration(
                labelText: L10n.t('auth.loginId'),
                helperText: L10n.t('auth.loginIdHint'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtl,
              decoration: InputDecoration(
                labelText: L10n.t('auth.displayName'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinCtl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: L10n.t('auth.pin'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(L10n.t('auth.role'),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(width: 8),
                ChoiceChip(
                  selected: _role == AccountRole.cashier,
                  onSelected: (_) =>
                      setState(() => _role = AccountRole.cashier),
                  label: Text(L10n.t('auth.cashier')),
                  showCheckmark: false,
                  selectedColor: const Color(0xFF1FA85A),
                  labelStyle: TextStyle(
                    color: _role == AccountRole.cashier
                        ? Colors.white
                        : const Color(0xFF232829),
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  selected: _role == AccountRole.admin,
                  onSelected: (_) => setState(() => _role = AccountRole.admin),
                  label: Text(L10n.t('auth.admin')),
                  showCheckmark: false,
                  selectedColor: const Color(0xFF1FA85A),
                  labelStyle: TextStyle(
                    color: _role == AccountRole.admin
                        ? Colors.white
                        : const Color(0xFF232829),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.t('common.cancel')),
        ),
        FilledButton(
          onPressed: () {
            final id = _idCtl.text.trim();
            final pin = _pinCtl.text.trim();
            if (id.isEmpty || pin.isEmpty) return;
            Navigator.pop(
              context,
              _AccountForm(id, _nameCtl.text.trim(), pin, _role),
            );
          },
          child: Text(L10n.t('common.ok')),
        ),
      ],
    );
  }
}
