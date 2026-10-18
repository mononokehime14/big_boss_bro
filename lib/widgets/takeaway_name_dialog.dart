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

/// 给外卖单**起名 / 改名** —— 起名 = 给它一个人看得懂的名字（不起名也能认）。
///
/// 外卖单**有没有名字都会**出现在**桌号下拉列表**里（`PosController.openTakeawayOrders`）：
/// 有名字显示 `张三 #3`，没名字显示单号 `#3`，随时能选回来接着加菜、改单；
/// **结账确认之后它就不再是"进行中"，自动从列表消失**。
///
/// **每次「保存」都会弹这个框**（保存不限次数）：没名字的可以补上、有名字的可以改，
/// 名字框里预先填着现在的名字（直接按「保存」就是不改）。
/// 点「不用名字」= **清掉名字**（这张单继续用 `#号` 认，不会丢）。
///
/// **等待时间（分钟）**：外卖单都有这一栏 —— 客人说"20 分钟后来拿"就填 20，
/// **厨房单会跟着打出来**（`等待 20 分钟`）。只填等待时间、不起名也可以。
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

  /// 要不要问「等多久」：**所有外卖单都问**（普通外卖也常有"20 分钟后来拿"）。
  bool get _showWait => widget.order.isTakeaway;

  /// 标题用哪种叫法（电话外卖 / 普通外卖）—— 跟"要不要问等待时间"是两件事。
  bool get _isPhone => widget.order.isPhoneTakeaway;

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

  /// 能不能按「保存」：**起了名** 或 **填了等待时间** 都行
  /// （只填等待时间也是合法的保存；两个都没有就没意义了）。
  bool get _canSave {
    if (_waitInvalid) return false;
    return _nameOk || _waitMinutes > 0;
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(
      context,
      TakeawayNameResult(
        label: _nameOk ? _nameCtl.text.trim() : '',
        waitMinutes: _showWait ? _waitMinutes : 0,
      ),
    );
  }

  /// 「不用名字」：名字留空（**原来有名字的会被清掉**），但**等待时间照存**
  /// （常见：不想给单子起名，只想告诉厨房"等 20 分钟"）。
  void _skipName() {
    Navigator.pop(
      context,
      TakeawayNameResult(
        label: '',
        waitMinutes: (_showWait && !_waitInvalid) ? _waitMinutes : 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isPhone
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
                if (_showWait) {
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
            // ---- 等待时间（分钟）：外卖单都有（厨房单上会打「等待 N 分钟」）----
            if (_showWait) ...[
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
