# troubleshooting.md — 报错与修复记录

> 用来记录**每一次踩到的坑 + 为什么会报错 + 怎么修**。
> 以后遇到问题，先来这里搜；新问题就按下面的格式往末尾追加。

格式模板：

```
## 问题 N：一句话标题
- 现象 / 报错原文：...
- 原因：...
- 处理：...
- 涉及文件：...
- 状态：已修复 ✅ / 待验证 ⏳
```

---

## 问题 1：`Category` 名字冲突（Flutter 自带 vs 我们的分类模型）

- **现象 / 报错原文**（`flutter test`）：
  ```
  Error: 'Category' is imported from both 'package:big_boss_bro/models/category.dart'
  and 'package:flutter/src/foundation/annotations.dart'.
  ...
  The getter 'id' isn't defined for the type 'Object?'.
  ```
  （凡是用到分类 `.id`/`.name` 的地方一并报错，最典型在 `pos_controller`。）

- **原因**：
  Flutter 自带的 `flutter/material.dart`（底层 `flutter/foundation.dart`）里有一个**名叫 `Category` 的类**
  （是给文档/注解用的）。我们的菜品分类模型也叫 `Category`。同一个文件里同时 `import 'package:flutter/material.dart'`
  和 `import '../models/category.dart'` 时，两个 `Category` **重名**，编译器无法区分，
  于是把你的分类列表里元素的类型推断成了 `Object?`，导致取 `.id`/`.name` 失败。

- **处理**：让 Flutter 自带的 `Category` 不参与作用域，用了两种写法：
  - `lib/state/pos_controller.dart`：`import 'package:flutter/foundation.dart' show ChangeNotifier;`
    （只导入需要的 `ChangeNotifier`，不把其它名字带进来）
  - `lib/widgets/category_chips.dart`、`lib/screens/menu_manage_screen.dart`：
    `import 'package:flutter/material.dart' hide Category;`（隐藏 Flutter 的 `Category`）

- **涉及文件**：`state/pos_controller.dart`、`widgets/category_chips.dart`、`screens/menu_manage_screen.dart`

- **状态**：已修复 ✅（`flutter test` 全部通过）

- **以后注意**：新文件若既 `import 'package:flutter/material.dart'` 又用我们的 `Category`，
  记得在 flutter import 加 `hide Category`。

---

## 问题 2：`flutter run -d windows` 编译失败（蓝牙打印类型对不上）

- **现象 / 报错原文**（Windows 构建）：
  ```
  lib/services/bluetooth_print_service.dart(138,31): error: The argument type 'List<int>'
    can't be assigned to the parameter type 'Uint8List'.
  lib/services/bluetooth_print_service.dart(139,33): error: The method 'flush' isn't
    defined for the type '_BluetoothStreamSink<Uint8List>'.
  ```

- **原因**：
  1. **Windows 也会编译 `bluetooth_print_service.dart`**（因为 `main.dart` 无条件 `import` 了它），
     即使 Windows 实际用的是“暂不支持”的占位打印服务，Android 蓝牙文件的代码仍会被编译。
  2. 你解析到的 `flutter_bluetooth_serial` 0.4.0 里，
     `BluetoothConnection.output` 的类型是 **`_BluetoothStreamSink<Uint8List>`（继承自 `StreamSink<Uint8List>`）**：
     - `add(...)` 需要的是 **`Uint8List`**（不是 `List<int>`）；
     - 它**没有 `flush()`**；等数据发完用的字段是 **`allSent`**（一个 Future）。

- **处理**：
  - `import 'dart:typed_data';`（用 `Uint8List`）
  - `_connection!.output.add(Uint8List.fromList(bytes));`
  - `await _connection!.output.allSent;`（替代 `output.flush()`）

- **涉及文件**：`services/bluetooth_print_service.dart`

- **状态**：已修复 ✅（等待 `flutter run -d windows` 重新验证）

- **以后注意**：用某个插件时，先看它**当前解析版本的源码/API**（别凭旧记忆）。
  在这里我去 `C:\Users\renha\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_bluetooth_serial-0.4.0\lib\BluetoothConnection.dart`
  看了 `output` 的真实类型。

---

## 问题 3：`flutter test` 报 `BoxConstraints forces an infinite width`（按钮宽度 = 无限大）

- **现象 / 报错原文**（`flutter test`，`widget_test.dart` 启动 App 时）：
  ```
  EXCEPTION CAUGHT BY RENDERING LIBRARY
  The following assertion was thrown during performLayout():
  BoxConstraints forces an infinite width.
  The offending constraints were: BoxConstraints(w=Infinity, 52.0<=h<=Infinity)
  The relevant error-causing widget was: FilledButton
    FilledButton:.../lib/screens/settings_screen.dart:125:34
  ```

- **原因**：
  全局主题里给按钮设了最小尺寸：
  ```dart
  minimumSize: const Size.fromHeight(52)   // == Size(double.infinity, 52)
  ```
  `Size.fromHeight(52)` 的**宽度是 `double.infinity`（无限大）**。
  在纵向布局（`ListView` / `Column` / `Expanded`）里宽度有界，没事；
  但我新加的「桌号管理」把按钮放进了**横向的 `Row`**——`Row` 给子项的是**无界宽度**，
  于是“最小宽度 = 无限大”直接非法 → 崩溃。
  （`IndexedStack` 会在启动时就构建“设置页”，所以这个错误一启动就炸，`widget_test` 才会抓到。）

- **处理**：
  1. `lib/app.dart`：`minimumSize: const Size(0, 52)` —— 只保留高度，不给宽度设下限。
  2. 需要满宽的按钮单独撑满：`lib/widgets/cart_sheet.dart` 的主按钮包一层
     `SizedBox(width: double.infinity, child: FilledButton(...))`。
  （其它满宽按钮不用改：`ListView` 的子项、`Column(crossAxisAlignment: stretch)`、`Expanded` 本身就会给满宽。）

- **涉及文件**：`lib/app.dart`、`lib/widgets/cart_sheet.dart`

- **状态**：已修复 ✅（待重跑 `flutter test` 验证）

- **以后注意**：`Size.fromHeight(h)` / `Size.fromWidth(w)` 会把**另一维设成 `infinity`**，
  只在“另一维确定有界”的父级里才安全。放进 `Row`/`Column` 的主轴方向、`Wrap`、`SingleChildScrollView` 里要小心。

---

## 附：不算错误的提示

- `flutter run -d windows` 里出现
  ```
  Nuget.exe not found, trying to download or use cached version.
  ```
  这是 Windows 桌面构建在准备 NuGet 工具，**属于正常提示**，不是错误；只要后面能编译出窗口就没事。

---

## 问题 4：`RenderFlex overflowed by 17 pixels`（菜品格子内容比格子高）

- **现象 / 报错原文**（`flutter test`，`widget_test.dart` 启动 App 时）：
  ```
  EXCEPTION CAUGHT BY RENDERING LIBRARY
  The following assertion was thrown during layout:
  A RenderFlex overflowed by 17 pixels on the bottom.
  The relevant error-causing widget was:
    Column
    Column:.../lib/widgets/menu_grid.dart:63:18
  ```

- **原因**：
  改成「宽屏 60/40」之后，左侧菜单列变窄 → 菜品格子（`SliverGridDelegateWithMaxCrossAxisExtent`
  按 `childAspectRatio` 算高度）也跟着变矮。而格子里 `Column`（emoji 40px + 菜名 + 价格 + 间距）
  是**固定尺寸**，比格子高出 17px，于是溢出（黄黑条纹）。
  `flutter test` 的默认窗口正好是 800×600，会走到宽屏分支，所以被它抓到了。

- **处理**：
  `lib/widgets/menu_grid.dart` 的 `_MenuCell`：给内容套一层
  **`FittedBox(fit: BoxFit.scaleDown)`**（并给内部一个固定宽度的 `SizedBox(width: 108)`），
  格子变小/变矮时**整体等比缩小**，任何窗口尺寸都不再溢出；格子足够大时按原尺寸显示（scaleDown 不会放大）。

- **涉及文件**：`lib/widgets/menu_grid.dart`

- **状态**：已修复 ✅

- **以后注意**：凡是「固定尺寸内容放进由 `childAspectRatio` 决定高度的网格格子」，
  都要考虑格子会随窗口变化；用 `FittedBox(scaleDown)`、`Flexible`/`Expanded` 或
  把 `childAspectRatio` 调小（更高）来兜底。

---

## 问题 5：`Method not found: 'free'`（`package:ffi` 里已没有顶层 `free()`）

- **现象 / 报错原文**（`flutter run -d windows`）：
  ```
  lib/services/windows_print_service.dart(106,9): error: Method not found: 'free'.
  ...（多处）
  ```

- **原因**：
  `package:ffi` **移除了顶层的 `free()` 函数**。现在释放内存要用**分配器自己的方法**：
  - `calloc<T>(...)` 分配的 → `calloc.free(ptr)`
  - `malloc<T>(...)` / `toNativeUtf16()` 分配的（默认用 `malloc`）→ `malloc.free(ptr)`

- **处理**：
  `lib/services/windows_print_service.dart` 全文改掉：所有 `free(x)` → `calloc.free(x)` 或 `malloc.free(x)`。
  顺便把内存分配**提到 try 之前一次分配完**、在 `finally` 里统一释放，避免某条分支漏掉释放。

- **涉及文件**：`lib/services/windows_print_service.dart`

- **状态**：已修复 ✅

- **以后注意**：写 FFI 时，**谁分配的就用谁的 free**（`calloc.free` / `malloc.free`）；
  `String.toNativeUtf16()` 默认走 `malloc`，所以要用 `malloc.free` 释放。

---

## 问题 6：（预留）下一个报错

> 遇到就照模板填（现象/原因/处理/文件/状态），并同步更新 `log.md` 变更记录。
