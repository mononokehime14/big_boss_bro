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

## 问题 6：小票上的文字乱码（数字/日期正常）+ 80mm 纸宽没铺满

- **现象**：
  - 打出来的小票**日期、单价、数量都正常**，但**文字全是乱码**。
  - 80mm 纸上内容只占左边一段，**没有铺满纸宽**。

- **原因**：
  1. **乱码 = 编码（内码）不匹配**。中文热敏打印机必须**先进入中文模式**（指令 `FS &` = `1C 26`）再发 **GBK** 字节；
     原来只发了 GBK 没发 `FS &`，打印机按默认单字节内码解释双字节 GBK → 乱码。
     （ASCII 数字只占 1 字节、且各内码一致，所以它们正常——这正是“数字对、文字乱”的原因。）
     另外西语重音字符（á é í ó ú ñ）在不同内码（GBK / Latin-1 / CP850 / CP437）里字节不同，也必须匹配。
  2. **纸宽没铺满**：打印机默认可能用 **Font B（9×17 点阵）**。80mm 可打 576 点，
     Font B 每字 9 点 → 48 列只有 432 点 ≈ 60mm，看起来就没铺满。
     Font A 是 12×24 点：48 列 × 12 点 = 576 点，**正好铺满**。

- **处理**：
  1. `services/escpos.dart`：字节流里加上
     `ESC M 0`（选 Font A）+ `FS &`（进中文模式，仅当编码为 gbk）。
  2. 新增设置「**小票编码**」：`gbk` / `utf8` / `latin1` / `cp850`，可逐个试。
  3. 新增设置「**铺满纸宽（Font A）**」开关（默认开）。
  4. 测试页加了**刻度尺 `----` 和 ASCII/西语重音/中文三种样例**，方便自查。
  5. **注意**：若打印机不支持中文（选 `latin1`/`cp850`），把「界面语言」切成**西语/英语**，
     小票表头就会用西语/英语输出，才不会显示成 `?`。

- **涉及文件**：`lib/services/escpos.dart`、`lib/services/ticket_builder.dart`、`lib/data/settings_store.dart`、
  `lib/state/settings_controller.dart`、`lib/services/print_service.dart`、`lib/screens/settings_screen.dart`

- **状态**：已修复 ✅（等你按 `setup.md` 第 5 节 ④ 换编码 / 开 Font A 后复测）

- **复测追加（第二次反馈）**：
  - 复测测试页显示 `Codec utf8  FontA off`，ASCII 行、西语**无重音**行、刻度尺都正常，**宽度已正确**，
    但中文仍乱码。
  - **关键**：只有「小票编码 = `gbk`」时才会发 `FS &` 进中文模式。那次用 `utf8`，打印机不在中文模式，
    所以**那次对中文是无效测试**，不能据此判定打印机不支持中文。
  - 因此测试页新增 **`[GBK强制]` 行**：`escpos.gbkProbeBytes()` 会**无视当前编码设置**，
    强制 `FS &` + GBK 中文 + `FS .`，用来给出确定结论：
    - 该行**正常** → 打印机支持中文 → 把「小票编码」设为 `gbk`。
    - 该行**乱码** → 打印机没有中文字库 → 用新加的「**小票语言**」把**小票**打成西语
      （界面仍可保持中文），编码用 `cp850` 或 `latin1`。
  - 同时新增设置「**小票语言**」（`Settings.receiptLang` + `L10n.tFor()`），让**界面语言与小票语言分离**。

- **第三次反馈（关键转折）**：`utf8` 和 `gbk` **都乱码**，只有 ASCII 正常。
  这说明问题**不在“选哪个编码”**，而要先确认**我们的指令有没有真的到达打印机**。
  于是：
  1. 测试页固定内容，并加入 **`[BIG] ESC/POS CHECK`（`ESC ! 0x30` 双倍大小）**这一行作为**决定性检查**：
     它变大 = 指令透传正常；它没变 = 中间层（多半是 Windows 驱动）把内容当文本重渲染了 → **乱码根源在驱动**，
     解法是换 **「Generic / Text Only」** 驱动或走网络/蓝牙绕开驱动。
  2. 中文探测改成**两种方式并行**（`FS &` 与 `ESC t 255` + `FS &`），一眼看出发动机支持哪种。
  3. 新增 `test/escpos_test.dart`，用**可运行的断言**证明我们的编码与指令是对的：
     GBK 中文 2 字节/字且能往返、ASCII 单字节、字节流含 `ESC @`/`ESC M 0`/`FS &`/切纸。
     → 逻辑推论：既然我们发的是对的，那乱码就出在**打印机/驱动**一侧。
- **涉及文件（追加）**：`test/escpos_test.dart`、`lib/services/ticket_builder.dart`、`lib/services/escpos.dart`

- **以后注意**：热敏打印的“文字乱码”**几乎都是编码问题**，先怀疑内码，不要怀疑排版。
  排查顺序：① 打印机是否要中文模式（`FS &`）② 内码选对（GBK / Latin-1 / CP850 / UTF-8）③ 界面语言与打印机能力匹配。

---

## 问题 7：**中文乱码的真凶 —— `gbk_codec` 的 `gbk.encode` 返回的不是字节流**

- **现象**：小票上中文全是乱码；ASCII（数字/日期/英文）一直正常。换 `utf8` / `gbk` / 各种设置都不行。
  最终被 **单元测试抓出来**：
  ```
  test/escpos_test.dart: 中文按 2 字节/字编码…
  Expected: <18>      Actual: <9>
  ```
  （「恭喜您，打印成功！」是 9 个字，GBK 应该是 18 字节，实际只得到 9 字节。）

- **原因**：`gbk_codec` 这个包里有**两个** codec，名字很像但语义完全不同：

  | 调用 | 返回什么 | 后果 |
  |---|---|---|
  | `gbk.encode(text)` | **16 位 GBK 码点**（`中` = 0xD6D0 = **54992**，一个 int 元素） | 当字节发出去时被**截断**成 1 个错字节（0xD6D0 → 0xD0）→ **中文乱码** |
  | `gbk_bytes.encode(text)` | **真正的字节流**（`中` → `0xD6 0xD0` 两个字节） | ✅ 正确 |

  看包源码 `lib/src/converter_gbk.dart` 就能发现：
  ```dart
  if (gbkCode != null) ret.add(gbkCode);   // ← 直接把 16 位码点当一个 int 塞进去
  ```
  而 `converter_gbk_byte.dart` 里才做了拆分：
  ```dart
  int a = (gbkCode >> 8) & 0xff;
  int b = gbkCode & 0xff;
  ret.add(a); ret.add(b);                  // ← 正确
  ```
  ASCII 字符因为**不在映射表里**，走的是 `ret.add(charCode)`（原样单字节），所以 ASCII 一直正常——
  这正好解释了“数字对、文字乱”的诡异现象。

- **验证**：直接从包的数据表 `json_char_to_gbk.data` 查出真值核对——
  `中=0xD6D0`、`恭=0xB9A7`、`，=0xA3AC`、`！=0xA3A1`、`A` 不在表里（单字节 `0x41`）。

- **处理**：`lib/services/escpos.dart` 里所有 GBK 编码改用 **`gbk_bytes.encode`**，并封装成 `gbkBytes()`，
  再加一层兜底（万一有字符不在表里、码点 > 255，替换成 `?`，避免被截断成乱码字节）。
  同时 `test/escpos_test.dart` 用**已知真值**把行为锁死：`中 → [0xD6, 0xD0]`、9 个中文字 = 18 字节、
  每个字节都在 `0..255`、且 `gbk_bytes.decode()` 能原样解回。

- **涉及文件**：`lib/services/escpos.dart`、`test/escpos_test.dart`

- **状态**：已修复 ✅（`flutter test` 应全绿；中文小票应能正常打印——前提是打印机有中文字库）

- **以后注意（重要经验）**：
  1. **别凭记忆用第三方包**：名字近似的 API（`gbk` vs `gbk_bytes`）语义可能完全不同，
     去 pub 缓存读它的源码（`~/.pub-cache/hosted/pub.dev/<pkg>-<ver>/lib/...`）最可靠。
  2. **写“能证伪”的测试**：这条 bug 是靠「9 字应为 18 字节」这种**具体数值断言**抓到的；
     如果只写“不抛异常”之类的弱断言，永远发现不了。
  3. 出现“只有 ASCII 正常”的乱码，优先怀疑**编码函数本身**，而不是打印机。

---

## 问题 8：（预留）下一个报错

> 遇到就照模板填（现象/原因/处理/文件/状态），并同步更新 `log.md` 变更记录。
