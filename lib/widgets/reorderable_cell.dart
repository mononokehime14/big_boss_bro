import 'package:flutter/material.dart';

/// 「自定义排序」用的**可拖动格子**：长按拖起来，放到另一个格子上就换位置。
///
/// 只在 [enabled]（= 排序方式选了「自定义」）时才有拖拽行为；其它排序方式下
/// **原样返回 [child]**，一个字都不动（点、长按快速加一份都跟以前一样）。
///
/// 用法（`category_grid.dart` / `menu_grid.dart` 都是这么用的）：
/// ```dart
/// ReorderableCell(
///   id: cat.id,
///   enabled: custom,
///   draggable: cat.id != kCustomCategoryId, // 内置「自定义」永远排最后，不给拖
///   onReorder: (movedId, targetId) => ...,
///   child: cell,
/// )
/// ```
///
/// 为什么用 `LongPressDraggable` 而不是点住就拖：格子还要能**点一下**（进种类 / 点菜），
/// 一按就拖会把"点"也抢走。长按开始拖，和列表拖拽的手感也一致。
class ReorderableCell extends StatelessWidget {
  /// 这一格的 id（种类 id / 菜品 id）—— 拖动时传的就是它。
  final String id;

  /// 开着才可拖（排序方式 = 自定义）。
  final bool enabled;

  /// 这一格**能不能被拖走**（内置的「自定义」种类不给拖：它永远排最后）。
  final bool draggable;

  /// 拖到这一格上时回调：`(被拖的 id, 落点的 id)`。
  final void Function(String movedId, String targetId) onReorder;

  final Widget child;

  const ReorderableCell({
    super.key,
    required this.id,
    required this.enabled,
    required this.onReorder,
    required this.child,
    this.draggable = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final cell = DragTarget<String>(
      // 拖到自己头上不算
      onWillAcceptWithDetails: (d) => d.data != id,
      onAcceptWithDetails: (d) => onReorder(d.data, id),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        // 有格子悬在上面：描一圈白边，让用户看清"会落到这里"
        final body = hovering
            ? DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: child,
              )
            : child;

        if (!draggable) return body;
        return LayoutBuilder(
          builder: (context, constraints) => LongPressDraggable<String>(
            data: id,
            // 拖起来的"影子"：就是这一格本身，半透明、大小一致
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.85,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: child,
                ),
              ),
            ),
            // 原来那一格变淡，作为"它正在被搬走"的提示
            childWhenDragging: Opacity(opacity: 0.3, child: child),
            child: body,
          ),
        );
      },
    );

    return cell;
  }
}
