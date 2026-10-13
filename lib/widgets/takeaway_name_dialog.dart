import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/order.dart';
import '../state/pos_controller.dart';
import '../state/settings_controller.dart';

/// 「保存外卖单」弹窗的结果。
class TakeawayNameResult {
  /// 外卖单名字（`''` = 用户选了「不用名字」）。
  final String label;

  /// 要等几分钟（**电话外卖**才有这个选项；`0` = 没填）。
  final int waitMinutes;

  const TakeawayNameResult({required this.label, this.waitMinutes = 0});
}

/// 给外卖单**起名 / 改名** —— 起名就等于"把这张外卖单保存起来"。
///
/// 起过名的外卖单会出现在**桌号下拉列表**里（`PosController.openTakeawayOrders`），
/// 随时能选回来接着加菜、改单；**结账确认之后它就不再是"进行中"，自动从列表消失**。
///
/// 电话外卖（`order.isPhoneTakeaway`）会**多一个「等待时间（分钟）」**输入框：
/// 客人在电话里说"20 分钟后来拿"就填 20，**厨房单会跟着打出来**。
/// 只想填等待时间、不想起名也可以（点「不用名字」或直接点保存）。
///
/// 返回值：
/// - [TakeawayNameResult]：用户确认了（名字和/或等待时间，由调用方写进订单）；
/// - **`null`**：直接关掉了（调用方什么都不做）。
///
/// 重名规则见 [PosController.canUseTakeawayLabel]：不能和**桌号**或**别的外卖单**重名。
Future<TakeawayNameResult?> showTakeawayNameDialog(
  BuildContext context,
  Order order,
) =>
    showDialog<TakeawayNameResult>(
      context: context,
      builder: (_) => _TakeawayNameDialog(order: order),
    );

class _TakeawayNameDialog extends StatefulWidget {
  final Order order;

  const _TakeawayNameDialog({required this.order});

  @override
  State<_TakeawayNameDialog> createState() => _TakeawayNameDialogState();
}

class _TakeawayNameDialogState extends State<_TakeawayNameDialog> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _waitCtl;
  final FocusNode _waitFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.order.label);
    _nameCtl.addListener(() => setState(() {}));
    _waitCtl = TextEditingController(
      text: widget.order.waitMinutes > 0 ? '${widget.order.waitMinutes}' : '',
    );
    _waitCtl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _waitCtl.dispose();
    _waitFocus.dispose();
    super.dispose();
  }

  /// 电话外卖才问"等多久"。
  bool get _askWait => widget.order.isPhoneTakeaway;

  /// 输入框里的等待时间（空的 = 0）。
  int get _waitMinutes => int.tryParse(_waitCtl.text.trim()) ?? 0;

  /// 等待时间填得不合法（填了东西但不是数字 / 是负数）。
  bool get _waitInvalid =>
      _waitCtl.text.trim().isNotEmpty &&
      (int.tryParse(_waitCtl.text.trim()) == null || _waitMinutes < 0);

  /// 名字能不能用（空 = 没起名，也返回 false）。
  bool get _nameOk {
    final pos = context.read<PosController>();
    final tables = context.read<SettingsController>().settings.tables;
    return pos.canUseTakeawayLabel(
      _nameCtl.text,
      tables: tables,
      exceptOrderId: widget.order.id,
    );
  }

  /// 名字被占了（非空但不可用）时才提示，别一打开就红着。
  bool get _nameTaken => _nameCtl.text.trim().isNotEmpty && !_nameOk;

  /// 能不能按「保存」：
  /// - 电话外卖：**起了名** 或 **填了等待时间** 都行（只填等待时间也是合法的保存）；
  /// - 其它外卖：必须起名。
  bool get _canSave {
    if (_waitInvalid) return false;
    if (_askWait) return _nameOk || _waitMinutes > 0;
    return _nameOk;
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(
      context,
      TakeawayNameResult(
        label: _nameOk ? _nameCtl.text.trim() : '',
        waitMinutes: _askWait ? _waitMinutes : 0,
      ),
    );
  }

  /// 「不用名字」：名字留空，但**等待时间照存**
  /// （电话外卖常见：不想给单子起名，只想告诉厨房"等 20 分钟"）。
  void _skipName() {
    Navigator.pop(
      context,
      TakeawayNameResult(
        label: '',
        waitMinutes: (_askWait && !_waitInvalid) ? _waitMinutes : 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_askWait
          ? L10n.t('takeaway.name.titlePhone')
          : L10n.t('takeaway.name.title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtl,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: L10n.t('takeaway.name'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) {
                if (_askWait) {
                  _waitFocus.requestFocus();
                } else {
                  _save();
                }
              },
            ),
            if (_nameTaken) ...[
              const SizedBox(height: 8),
              Text(
                L10n.t('takeaway.name.taken'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ],
            // ---- 电话外卖：等待时间（分钟）----
            if (_askWait) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _waitCtl,
                focusNode: _waitFocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: L10n.t('takeaway.wait'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_waitInvalid) ...[
                const SizedBox(height: 8),
                Text(
                  L10n.t('takeaway.wait.invalid'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _skipName,
          child: Text(L10n.t('takeaway.name.skip')),
        ),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(L10n.t('takeaway.name.save')),
        ),
      ],
    );
  }
}
