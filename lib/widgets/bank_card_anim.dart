import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 刷卡时的**银行卡动画**：一张会轻轻摇晃的卡 + 一圈扩散的波纹，
/// 表示「请在刷卡机上刷卡 / 插卡」。
///
/// 纯装饰（不连刷卡机）：卡是画出来的，不动图片资源，
/// 所以不挑机器、也不占安装包体积。
class BankCardAnim extends StatefulWidget {
  /// 卡片大小（按收款框宽度自适应传进来）。
  final double width;

  /// 卡下面的说明文字（例如「请刷卡 / 插卡」）。
  final String hint;

  const BankCardAnim({
    super.key,
    this.width = 220,
    this.hint = '',
  });

  @override
  State<BankCardAnim> createState() => _BankCardAnimState();
}

class _BankCardAnimState extends State<BankCardAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardW = widget.width;
    final cardH = cardW * 0.62;

    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, _) {
        final t = _ctl.value;
        // 0..1 往返：卡片左右轻摆 + 上下轻浮
        final wave = math.sin(t * 2 * math.pi);
        final angle = wave * 0.045; // 弧度
        final dy = wave * 3.0;
        // 波纹：0 → 1 循环放大并淡出
        final ringT = (t * 2) % 1.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: cardW + 24,
              height: cardH + 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 扩散波纹（提示「把卡靠近 / 插进去」）
                  Opacity(
                    opacity: (1 - ringT) * 0.35,
                    child: Container(
                      width: cardW * (0.85 + ringT * 0.35),
                      height: cardH * (0.85 + ringT * 0.35),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF1FA85A),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform.rotate(
                      angle: angle,
                      child: _card(cardW, cardH),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.hint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.hint,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1FA85A),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 画一张卡：渐变卡面 + 芯片 + 卡号点 + 卡组织圆标。
  Widget _card(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1FA85A), Color(0xFF0E6B39)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(w * 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 芯片
          Container(
            width: w * 0.16,
            height: w * 0.12,
            decoration: BoxDecoration(
              color: const Color(0xFFF2C94C),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const Spacer(),
          // 卡号（点点点）
          Row(
            children: [
              for (var g = 0; g < 4; g++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: w * 0.02),
                    child: Row(
                      children: [
                        for (var d = 0; d < 4; d++)
                          Container(
                            width: w * 0.018,
                            height: w * 0.018,
                            margin: EdgeInsets.only(right: w * 0.012),
                            decoration: const BoxDecoration(
                              color: Colors.white70,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: h * 0.1),
          // 右下角的两个圆（模仿卡组织标志）
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: w * 0.1,
                height: w * 0.1,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                ),
              ),
              Transform.translate(
                offset: Offset(-w * 0.04, 0),
                child: Container(
                  width: w * 0.1,
                  height: w * 0.1,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
