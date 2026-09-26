import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/auth_controller.dart';

/// 登录页：选账号 + 输密码。
///
/// 首次启动只有默认管理员：**账号 `admin` / 密码 `8888`**
/// （进「设置 → 账号管理」可以改密码、加收银员账号）。
///
/// 这里还放了语言切换：万一界面语言被切成看不懂的语言，也不会被锁在外面。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pinCtl = TextEditingController();
  String? _selectedId;
  String? _error;

  @override
  void dispose() {
    _pinCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final accounts = auth.accounts;
    // 账号列表可能异步才读回来；默认选中第一个
    _selectedId ??= accounts.isEmpty ? null : accounts.first.id;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.point_of_sale,
                        size: 48, color: Color(0xFF1FA85A)),
                    const SizedBox(height: 8),
                    Text(
                      L10n.t('app.title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      L10n.t('auth.account'),
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: accounts.any((a) => a.id == _selectedId)
                          ? _selectedId
                          : (accounts.isEmpty ? null : accounts.first.id),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              '${a.name}${a.isAdmin ? ' (${L10n.t('auth.admin')})' : ''}',
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _selectedId = v;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pinCtl,
                      autofocus: true,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: L10n.t('auth.pin'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: _error,
                      ),
                      onSubmitted: (_) => _signIn(auth),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: accounts.isEmpty
                          ? null
                          : () => _signIn(auth),
                      child: Text(L10n.t('auth.signIn')),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.t('auth.defaultHint'),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const Divider(height: 28),
                    // 语言（被切成看不懂的语言时的救命按钮）
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        for (final code in L10n.supported)
                          ChoiceChip(
                            selected: L10n.currentLang == code,
                            onSelected: (_) => L10n.lang.value = code,
                            label: Text(L10n.languageNames[code] ?? code),
                            showCheckmark: false,
                            selectedColor: const Color(0xFF1FA85A),
                            labelStyle: TextStyle(
                              color: L10n.currentLang == code
                                  ? Colors.white
                                  : const Color(0xFF232829),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _signIn(AuthController auth) {
    final id = _selectedId;
    if (id == null) return;
    final ok = auth.signIn(id, _pinCtl.text.trim());
    if (!ok) {
      setState(() {
        _error = L10n.t('auth.wrongPin');
        _pinCtl.clear();
      });
    }
  }
}
