import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/employee.dart';
import '../utils/format.dart';

/// **打卡对话框**（上班 / 下班都用它）：4 位数字键盘 + 结果提示。
///
/// 为什么不用 `TextField`：
/// - 收银台/门口的平板，弹系统键盘又慢又占地方；
/// - 员工只要点 4 下数字，比打字快得多，也不会打错输入法。
///
/// [onSubmit] 由调用方提供（它去 `AttendanceController.punch()` 打卡）。
/// 结果处理：
/// - 成功 → 大 ✓ + 姓名 + 时间（下班还显示「今天工作了多久」），**1.8 秒后自己关掉**；
/// - 今天这一次已经打过 → 同样的界面但换成 ℹ 图标 + 第一次/那一次的时间；
/// - PIN 不对 / 还没签到 → **就地提示**、清空重输（不用重新点一次大按钮）。
class ClockInDialog extends StatefulWidget {
  const ClockInDialog({
    super.key,
    required this.onSubmit,
    this.kind = PunchKind.clockIn,
  });

  final Future<PunchResult> Function(String pin) onSubmit;

  /// 这次打的是上班还是下班（只影响文案）。
  final PunchKind kind;

  @override
  State<ClockInDialog> createState() => _ClockInDialogState();
}

class _ClockInDialogState extends State<ClockInDialog> {
  static const int digits = 4;

  String _pin = '';
  String? _error;

  /// 提示是不是「提醒」（不是错）—— 比如「今天还没签到」，用橙色而不是红色。
  bool _errorIsHint = false;
  bool _busy = false;
  PunchResult? _done;
  Timer? _closeTimer;

  bool get _isOut => widget.kind == PunchKind.clockOut;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _tap(String d) {
    if (_busy || _done != null || _pin.length >= digits) return;
    setState(() {
      _error = null;
      _errorIsHint = false;
      _pin += d;
    });
    // 满 4 位自动提交（少点一次「确定」）
    if (_pin.length == digits) unawaited(_submit());
  }

  void _backspace() {
    if (_busy || _done != null || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _done != null || _pin.length < digits) return;
    setState(() => _busy = true);
    final res = await widget.onSubmit(_pin);
    if (!mounted) return;
    if (res.outcome != PunchOutcome.ok &&
        res.outcome != PunchOutcome.alreadyToday) {
      setState(() {
        _busy = false;
        _error = _errorText(res.outcome);
        _errorIsHint = res.outcome == PunchOutcome.needClockIn;
        _pin = '';
      });
      return;
    }
    setState(() {
      _busy = false;
      _done = res;
    });
    // 让他看清「谁、几点」再自动关掉
    _closeTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) Navigator.pop(context, res);
    });
  }

  String _errorText(PunchOutcome o) => switch (o) {
        PunchOutcome.wrongPin => L10n.t('attendance.wrongPin'),
        PunchOutcome.needClockIn => L10n.t('attendance.needClockIn'),
        _ => L10n.t('attendance.wrongPin'),
      };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 先写清楚这次是「上班」还是「下班」，员工不会点错
              Text(
                _isOut ? L10n.t('attendance.clockOut') : L10n.t('attendance.clockIn'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _isOut
                      ? const Color(0xFF1565C0)
                      : const Color(0xFF1FA85A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                L10n.t('attendance.enterPin'),
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 14),
              if (_done != null)
                _doneView(_done!)
              else ...[
                _dots(),
                const SizedBox(height: 8),
                SizedBox(
                  height: 22,
                  child: _error == null
                      ? null
                      : Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: _errorIsHint
                                ? Colors.orange.shade900
                                : Colors.redAccent,
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                _keypad(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 4 个点：填了几个就亮几个。
  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          digits,
          (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _pin.length
                  ? (_isOut ? const Color(0xFF1565C0) : const Color(0xFF1FA85A))
                  : Colors.grey.shade300,
            ),
          ),
        ),
      );

  Widget _keypad() {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => SizedBox(
          width: 88,
          height: 62,
          child: OutlinedButton(
            onPressed: _busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: icon != null
                ? Icon(icon, size: 24)
                : Text(label,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w600)),
          ),
        );

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in row) ...[
                  key(d, onTap: () => _tap(d)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key('', onTap: _backspace, icon: Icons.backspace_outlined),
            const SizedBox(width: 8),
            key('0', onTap: () => _tap('0')),
            const SizedBox(width: 8),
            key('', onTap: _submit, icon: Icons.check),
          ],
        ),
      ],
    );
  }

  /// 成功 / 今天已经打过：大图标 + 姓名 + 时间（下班再加「今天工作了多久」）。
  Widget _doneView(PunchResult res) {
    final ok = res.outcome == PunchOutcome.ok;
    final out = res.kind == PunchKind.clockOut;
    final color = ok
        ? (out ? const Color(0xFF1565C0) : const Color(0xFF1FA85A))
        : Colors.orange.shade800;
    return Column(
      key: const Key('clockin-done'),
      children: [
        Icon(ok ? Icons.check_circle : Icons.info_outline,
            size: 64, color: color),
        const SizedBox(height: 10),
        Text(
          ok
              ? (out
                  ? L10n.t('attendance.doneOut')
                  : L10n.t('attendance.done'))
              : (out
                  ? L10n.t('attendance.alreadyOut')
                  : L10n.t('attendance.already')),
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: 6),
        Text(
          '${res.employee?.name ?? ''}  ${res.at == null ? '' : timeHm(res.at!)}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        if (res.worked != null) ...[
          const SizedBox(height: 4),
          Text(
            '${L10n.t('attendance.worked')} ${durationHm(res.worked!)}',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
          ),
        ],
      ],
    );
  }
}

/// 弹出打卡框：[onSubmit] 里打卡。返回打卡结果（取消返回 null）。
Future<PunchResult?> showClockInDialog(
  BuildContext context, {
  required PunchKind kind,
  required Future<PunchResult> Function(String pin) onSubmit,
}) =>
    showDialog<PunchResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ClockInDialog(kind: kind, onSubmit: onSubmit),
    );
