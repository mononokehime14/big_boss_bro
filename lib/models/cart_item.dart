import '../utils/format.dart';
import 'menu_item.dart';

/// 购物车里的一行：某道菜 + 份数 + 所选的定制选项 + **特别备注**（可以好几条，可以带加价）。
///
/// 同一道菜**选项/备注（含加价）的组合不同算不同的行**
/// （例如"大份"和"中份"分开显示，「换炒饭 +70」和「换炒饭」也分开）。
class CartItem {
  final MenuItem menuItem;

  /// 份数（点菜对话框里默认 1，可以加减或直接输）。
  int quantity;

  /// 所选的定制项值，例如 ['Grande'] 或 ['中辣']。
  final List<String> selections;

  /// **特别备注**：可以填好几条（在点菜对话框里一条一条存进去）。
  final List<String> notes;

  /// 每条备注对应的**加价**（跟 [notes] 一一对应；短了按 0 算）。
  ///
  /// 「换炒饭 +70」这种备注是要改钱的，按**每份**加（跟单价一个口径）。
  final List<double> notePrices;

  CartItem({
    required this.menuItem,
    this.quantity = 1,
    List<String>? selections,
    List<String>? notes,
    List<double>? notePrices,
  })  : selections = selections ?? <String>[],
        notes = notes ?? <String>[],
        notePrices = notePrices ?? <double>[];

  /// 所有备注拼成一行（**不带价格**；给厨房看）。
  String get note => notes.join(' · ');

  /// 第 [i] 条备注的加价（越界 = 0）。
  double notePriceAt(int i) => i < notePrices.length ? notePrices[i] : 0;

  /// 备注加价合计（每份）。
  double get notePriceTotal {
    var sum = 0.0;
    for (var i = 0; i < notes.length; i++) {
      sum += notePriceAt(i);
    }
    return sum;
  }

  /// 所有备注的**带价签**文字：`换炒饭 +70 · 少辣`（界面 / 小票用）。
  String get noteLabels {
    final out = <String>[];
    for (var i = 0; i < notes.length; i++) {
      final p = notePriceAt(i);
      out.add(p == 0 ? notes[i] : '${notes[i]} ${signedAmount(p)}');
    }
    return out.join(' · ');
  }

  /// 购物车里的唯一键：同菜 + **同单价** + 同选项 + 同备注 + **同备注加价** 才算同一行。
  ///
  /// 备注之间用 `\u0001` 分隔：否则「一条备注 a/b」和「两条备注 a、b」会撞成同一行。
  ///
  /// ⚠️ 为什么还要带上**名字 + 单价**：内置的「自定义」菜所有行的 `id` 都是
  /// `__custom__`（见 `data/custom_menu_entry.dart`），只按 id 算键的话
  /// 「生日蛋糕 ¥80」和「加急 ¥20」会**并成同一行**（显示的是先加进去那份的名字/价格）。
  /// 普通菜的名字/单价由 id 唯一决定，所以这里加上它们不影响原来的行为。
  String get key => '${menuItem.id}|${menuItem.name}|${menuItem.price}|'
      '${selections.join('/')}|${notes.join('\u0001')}|'
      '${[for (var i = 0; i < notes.length; i++) notePriceAt(i)].join('/')}';

  /// 单价 = 基础价 + 所选项的加价（见 `MenuItem.unitPriceFor`）。
  double get unitPrice => menuItem.unitPriceFor(selections);

  /// **实收单价** = 单价 + 备注加价（「换炒饭 +70」加在这里）。
  double get effectiveUnitPrice => unitPrice + notePriceTotal;

  /// 这一行实收 = 实收单价 × 份数。
  double get lineTotal => effectiveUnitPrice * quantity;

  /// 选项 + 备注（带价签）的简短描述（显示在购物车 / 小票里）。
  String get detail {
    final parts = <String>[];
    if (selections.isNotEmpty) parts.add(selections.join(' / '));
    if (noteLabels.trim().isNotEmpty) parts.add(noteLabels.trim());
    return parts.join(' · ');
  }
}
