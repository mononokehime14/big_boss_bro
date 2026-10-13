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

## 问题 8：Excel 改了结构后，导入把「选项价格」列当成了定制项名

- **现象 / 报错原文**（`flutter test`）：
  ```
  test/menu_importer_test.dart: 真实样例 … 能解析出 2 个分类 / 12 个菜品 …
  Expected: <2>
    Actual: <9>
  ```
  （测试断言失败只是表象——真正的问题是**解析结果不对**。）

- **原因**：你把 Excel **升级了结构**。原来是「分类 / 菜名 / (定制项, 选项)×N」，现在是：
  ```
  种类 | 菜品名字 | 基础价格 | 个性化定制项1 | 定制1选项 | 定制1选项价格 | 个性化定制项2 | 定制2选项
  ```
  即：**每个定制项占 3 列**（名字 / 选项 / **每个选项的加价**），并且分类从 2 个涨到 9 个。
  而旧解析器是「剩下两列一组」，所以会把 `定制1选项价格` 当成**下一个定制项的名字**、
  把 `个性化定制项2` 当成它的选项 → 选项组全乱、价格丢失。
  （测试里写死的 `2 个分类 / 12 个菜品` 也是照旧文件写的，所以一起挂了。）

- **处理**：
  1. `models/menu_option_group.dart`：定制项增加 **`prices`（与选项一一对应的加价）** + `priceOf()` / `hasPrices`。
  2. `models/menu_item.dart`：新增 **`unitPriceFor(selections)` = 基础价 + 各选中项加价**、`minUnitPrice`（菜单起价）。
  3. `models/cart_item.dart`：新增 `unitPrice`（= `unitPriceFor`），购物车/订单金额都用它。
  4. `services/menu_importer.dart`：分组规则改成
     **「名字列 + 选项列 [+ 价格列]」**；价格列的判定是表头含「价格 / price / precio」
     （所以「定制1选项价格」会被认成价格列，而不是定制项名）；`_parsePrices('140/185') → [140,185]`，
     个数按选项数对齐、缺的补 0。
  5. 界面：菜单格子显示**起价**（`minUnitPrice`）；定制弹窗显示**随选择实时变化的单价**，
     并在选项上标出加价（如 `Grande +185`）。
  6. 测试：真实文件那条**不再写死数量**（只验证结构 + 关键事实 + 「价格列没被当成定制项」这条回归），
     并新增「三列一组」「价格不足补 0」的合成用例。

- **涉及文件**：`lib/models/menu_option_group.dart`、`lib/models/menu_item.dart`、`lib/models/cart_item.dart`、
  `lib/services/menu_importer.dart`、`lib/state/pos_controller.dart`、`lib/widgets/menu_grid.dart`、
  `lib/widgets/cart_panel.dart`、`lib/widgets/item_customize_dialog.dart`、`lib/widgets/payment_flow.dart`、
  `test/menu_importer_test.dart`、`test/pos_controller_test.dart`

- **状态**：已修复 ✅

- **以后注意**：
  1. **测试不要写死会变的业务数据**（菜品数量、分类数量）——这类断言一改表就失效；
     应该断言「结构/关系/关键事实」（如「每道菜的分类必须存在」「价格列不能被当成定制项」）。
  2. 导入器这类代码，**列的角色要按表头语义识别**，并对新增列保持宽容。

---

## 问题 9：菜单里**价格全是 0**（你的 Excel 明明有 140 / 185）

- **现象**（你在 App 里看到的）：点单页每个菜格子都显示 `$0`，定制弹窗里选 `Grande` 也不加价。
  代码里 `prices` / `unitPriceFor()` 都已经写好、`flutter test` 也全绿——**但界面还是 0**。

- **原因（两个叠在一起）**：
  1. **旧解析器留下的数据**：菜单是存在 `shared_preferences` 里的（`data/menu_store.dart`）。
     你上次导入是**旧解析器**干的活——那次它没识别出价格列（见问题 8），
     所以**存进去的菜单里价格本来就是 0**。改代码只影响「以后导入」，**不会自动修好已经存下的数据**。
  2. 所以：**必须重新导入一次 Excel**（或者进「菜品管理」逐个改价），价格才会出现在菜单里。

- **处理**：
  1. 让失败**看得见**：`services/menu_importer.dart` 在「所有菜的价格都是 0」时返回**警告**，
     导入页会直接提示，不再让你蒙在鼓里。
  2. 让结果**可核对**：`screens/menu_import_screen.dart` 的预览现在会**列出每个定制项的价格样本**
     （如 `Size: Mediano 0 · Grande 185`），导入前就能看出价格有没有读进来。
  3. 链路补齐：`MenuOptionGroup.prices` → `MenuItem.unitPriceFor(selections)` → `CartItem.unitPrice`
     → 购物车/订单/小票金额全部一致（菜单格子显示 `minUnitPrice` 起价）。
  4. `log.md` 的验证清单里写死一句：**改完导入逻辑后要重新导入一次**。

- **涉及文件**：`lib/services/menu_importer.dart`、`lib/screens/menu_import_screen.dart`、
  `lib/models/menu_option_group.dart`、`lib/models/menu_item.dart`、`lib/models/cart_item.dart`

- **状态**：已修复 ✅（**待你重新导入 Excel 确认**）

- **以后注意**：
  1. **持久化的数据不会跟着代码一起修好**。改了「解析/计算」逻辑后，要问一句：
     「已经存进去的老数据怎么办？」——要么让用户重导一次，要么写一段迁移代码。
  2. 排查这类问题时，先分清楚是**读错了**还是**存错了**（这次是后者：数据早就存成 0 了）。

---

## 问题 10：`flutter test` 两个编译错误（标签字段挂错对象 / 测试里少 import material）

- **现象 / 报错原文**（`flutter test`）：
  ```
  lib/services/receipt_layout.dart:424:25: Error: The getter 'thankyou' isn't defined for the type 'SplitData'.
    lines.add(padCenter(d.thankyou, cols));
                          ^^^^^^^^

  test/widget_test.dart:29:40: Error: Undefined name 'TextField'.
      await tester.enterText(find.byType(TextField).first, '8888');
                                         ^^^^^^^^^
  ```
  两个错误都会让**整份测试文件编译不过**（显示 `Failed to load ...: Compilation failed`），
  所以 `receipt_layout_test.dart` / `split_payment_test.dart` / `widget_test.dart` 三个文件直接没跑。

- **原因**：
  1. **字段挂错对象**。为了让小票文案能跟着「小票语言」变，我把小票的文字都放进 `xxxLabels` 类里
     （`ReceiptLabels` / `KitchenLabels` / `SplitLabels`），数据放在 `xxxData` 里。
     写 `buildSplitLines` 时，最后一行「谢谢光临」我写成了 `d.thankyou`，
     但 `SplitData` 上没有这个字段 —— 它在 `d.labels.thankyou`。
     （同一个文件里其它地方我写的是对的 `d.labels.labelTotal`，就这一行漏了 `labels`。）
  2. **测试里用了 Flutter 组件类却没 import**。`TextField` 属于 `package:flutter/material.dart`，
     而 `package:flutter_test/flutter_test.dart` **不会**把它转出来。
     `find.text(...)` / `find.byType(TextField)` 里的 `TextField` 是真实类型，必须自己 import。

- **处理**：
  1. `lib/services/receipt_layout.dart`：`d.thankyou` → **`d.labels.thankyou`**。
  2. `test/widget_test.dart`：加上 `import 'package:flutter/material.dart';`（放在 `flutter_test` 之前）。
  3. 顺手把 widget_test 的等待改稳一点：`pumpAndSettle()` 之后再 `pump(100ms)` + `pumpAndSettle()`，
     确保账号从本地读回来（登录页才会出现默认管理员）。

- **涉及文件**：`lib/services/receipt_layout.dart`、`test/widget_test.dart`

- **状态**：已修复 ✅（等你重跑 `flutter test` 确认）

- **以后注意**：
  1. **文案和数据分家时，最容易写错归属**。规则：`XxxData` 只放数据，`XxxLabels` 只放文字；
     用到文字时一律 `d.labels.xxx`。加字段时**两边都看一眼**。
  2. `flutter test` 一次只把「第一个编译错误」摆在你面前（每个测试文件单独编译）。修完一个**要再跑一次**，
     可能还有下一个 —— 别以为修好一个就完事了。
  3. 测试文件里凡是出现 Flutter 的组件类（`TextField`、`Text`、`Column`…），
     就要 `import 'package:flutter/material.dart';`；只用 `find.text` / `expect` 则不需要。

---

## 问题 11：Android 构建失败 `Could not find method jcenter()`（停更插件的古董 Gradle 脚本）

- **现象 / 报错原文**（`flutter run -d R9WR201TRKJ`，NDK 装好之后紧接着报的）：

  ```
  FAILURE: Build completed with 2 failures.

  1: Task failed with an exception.
  * Where:
  Build file 'C:\Users\renha\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_bluetooth_serial-0.4.0\android\build.gradle' line: 6
  * What went wrong:
  A problem occurred evaluating project ':flutter_bluetooth_serial'.
  > Could not find method jcenter() for arguments [] on repository container of type
    org.gradle.api.internal.artifacts.dsl.DefaultRepositoryHandler.

  2: Task failed with an exception.
  * What went wrong:
  A problem occurred configuring project ':flutter_bluetooth_serial'.
  > Failed to notify project evaluation listener.
     > The Android plugin must be applied before accessing the Android extension.
     > 'kotlin-android' plugin requires one of the Android Gradle plugins.
  ```

- **原因**：`flutter_bluetooth_serial` 停在 **0.4.0（2021-08-17，pub.dev 上至今仍是最新版，没有 0.5.0）**，
  它的 `android/build.gradle` 是 Gradle 6 / AGP 4 时代的写法，和本项目的 **Gradle 9.3.1 + AGP 9.1.0** 完全不兼容：

  | 上游写法 | 现在的问题 |
  | --- | --- |
  | `jcenter()` | **Gradle 9 已删除该方法** → 就是这次报的错（第 1 条） |
  | `buildscript { classpath 'com.android.tools.build:gradle:4.1.0' }` | 硬拉 AGP 4.1.0，和项目的 AGP 9.1.0 打架 |
  | `compileSdkVersion 30` / `buildToolsVersion '30.0.3'` | AGP 9 不认这种旧 DSL，且本机没装这两个版本 |
  | 没有 `namespace`（模块名写在 manifest 的 `package=` 属性里） | AGP 8 起 `namespace` 是**必需**的 |
  | `lintOptions { }` | AGP 9 已移除该块 |

  第 2 条错误是**连带**的：脚本在第 6 行就中断了，`com.android.library` 没应用成功，
  所以后面报"Android 插件必须先于 Android extension 应用"。

- **处理**：**不去改 pub 缓存**（`flutter pub cache repair` 一跑就没了），改成把包**收进本仓库**再打补丁：

  1. 把包拷贝到 `third_party/flutter_bluetooth_serial/`（只拷 `lib/ android/ ios/ pubspec.yaml LICENSE README.md CHANGELOG.md`）；
  2. `third_party/flutter_bluetooth_serial/android/build.gradle` **整个重写**成 AGP 9 能认的写法
     （`namespace`、`compileSdk 36`、`minSdk 24`、Java 17、`androidx.core`/`androidx.annotation` 依赖，
     删掉 `buildscript`/`jcenter()`/`buildToolsVersion`/`lintOptions`）；
  3. `third_party/flutter_bluetooth_serial/android/src/main/AndroidManifest.xml` 删掉根标签上的 `package="..."`；
  4. `third_party/flutter_bluetooth_serial/pubspec.yaml` 把 `sdk: '>=2.12.0 <3.0.0'` 放宽到 `'>=2.12.0 <4.0.0'`
     （本地路径依赖会用这个文件，`<3.0.0` 会让 pub 直接拒绝解析）；
  5. 项目 `pubspec.yaml` 末尾加 `dependency_overrides: flutter_bluetooth_serial: path: third_party/flutter_bluetooth_serial`。

  ⚠️ **Dart（`lib/`）和 Java（`src/main/java/`）源码一行都没动**，App 侧代码（`lib/services/bluetooth_print_service.dart` 等）也不用改。

- **涉及文件**：`third_party/flutter_bluetooth_serial/{pubspec.yaml, android/build.gradle, android/src/main/AndroidManifest.xml}`、
  `pubspec.yaml`（新增 `dependency_overrides`）。说明见 `release.md` 第 8 节。

- **状态**：已修复 ✅（`flutter pub get` 通过；Gradle 已越过插件配置阶段，开始安装缺失的
  `platforms/android-36` 与 `build-tools/36.0.0` —— 待你本地跑 `flutter run -d R9WR201TRKJ` 最终确认）

- **以后注意**：
  1. **别用 `flutter pub upgrade` 去"升"这个包**：pub.dev 上就停在 0.4.0，升不动；它已经停更，只能自己维护这份 `third_party/` 副本。
  2. 如果哪天要换蓝牙库，优先看维护中的经典蓝牙（SPP）方案（BLE-only 的库连不上大多数小票机）；
     换库要同步改 `lib/services/bluetooth_print_service.dart` 的扫描/连接/发送三处。
  3. 遇到"某插件构建脚本报错"，先判断是**插件的脚本过时**还是**项目配置错**：
     插件脚本过时就用 `third_party/` + `dependency_overrides` 收编打补丁，**别改 pub 缓存**。

---

## 问题 12：`AAR metadata` —— 两个插件还编译在 android-34 上（file_picker / permission_handler）

- **现象 / 报错原文**（`flutter run -d R9WR201TRKJ`，NDK 和 jcenter 都过了之后）：

  ```
  FAILURE: Build failed with an exception.

  * What went wrong:
  Execution failed for task ':file_picker:checkDebugAarMetadata'.
  > A failure occurred while executing com.android.build.gradle.internal.tasks.CheckAarMetadataWorkAction
     > An issue was found when checking AAR metadata:

         1.  Dependency ':flutter_plugin_android_lifecycle' requires libraries and applications that
             depend on it to compile against version 36 or later of the Android APIs.

             :file_picker is currently compiled against android-34.

             Recommended action: Update this project to use a newer compileSdk
             of at least 36, for example 36.
  ```

- **原因**：要把三件事分开看，否则很容易改错地方。

  1. **AGP 的 AAR metadata 检查**规则是：**消费者（本 App）的 compileSdk ≥ 被依赖模块编译时用的 compileSdk**。
  2. 本项目里 **有两个插件的 Android 模块把 compileSdk 写死成 34**（不是"跟着项目走"）：

     | 包 | 版本 | 它自己写的 compileSdk |
     | --- | --- | --- |
     | `file_picker` | 8.3.7 | `compileSdk 34` ❌ |
     | `permission_handler_android`（`permission_handler` 11.x 的安卓实现） | 12.1.0 | `compileSdk 34` ❌ |
     | `flutter_plugin_android_lifecycle`（传递依赖） | 2.0.35 | `compileSdk = flutter.compileSdkVersion`（=36） |
     | `shared_preferences_android` | 2.4.28 | `compileSdk = flutter.compileSdkVersion`（=36）✅ |

  3. 于是 `file_picker`（34）依赖了 `flutter_plugin_android_lifecycle`（36）→ 冲突，
     报错原文里那句 **"Update this project to use a newer compileSdk"** 指的是**那个插件工程**，
     **不是**本 App 的 `android/app/build.gradle.kts`。
     （所以"把 App 的 compileSdk 调大"在这一步是**没用**的。）

  > 另一个容易踩的点：`permission_handler` 13.x 的安卓实现 `permission_handler_android 14.1.0`
  > 自己是按 **compileSdk 37** 编译的 → 反过来要求**本 App 的 compileSdk ≥ 37**。所以最后两边都得往上抬。

- **处理**（三处，一起改才自洽）：

  | 改哪里 | 原来 | 改成 | 为什么 |
  | --- | --- | --- | --- |
  | `pubspec.yaml` | `file_picker: ^8.0.0` | `file_picker: ^11.0.3` | 10.x 起才用 `compileSdk = flutter.compileSdkVersion`；但 **10.x 的 buildscript 还钉着 AGP 8.5.1 + Kotlin 1.8.22**（Gradle 9 下会炸），**11.0.0 的 changelog 才写 "Updated Android package to support AGP 9"** |
  | `pubspec.yaml` | `permission_handler: ^11.3.0` | `permission_handler: ^13.0.2` | 13.x 的安卓实现是 AGP 9 + compileSdk 37，已跟上时代 |
  | `android/app/build.gradle.kts` | `compileSdk = flutter.compileSdkVersion`（36） | `compileSdk = 37` | 因为 permission_handler_android 14.1.0 是按 37 编译的（见上面第 3 点）。compileSdk 只影响"能调用哪些 API"，**不影响 minSdk/targetSdk，也不影响装机范围** |
  | `lib/screens/menu_import_screen.dart` | `FilePicker.platform.pickFiles(...)` | `FilePicker.pickFiles(...)` | **file_picker 11.0.0 起改成静态方法**（`FilePickerResult` / `withData` / `PlatformFile.bytes` / `.path` 都还在，只有调用方式变了） |

  - **为什么不用 file_picker 12/13**：12.0.0 把它拆成联邦包并**删掉 `FilePickerResult`**、废弃 `withData`，
    13.0.0 直接把 `withData` / `allowMultiple` 删了，要用 `pickFile()` + `PlatformFile.readAsBytes()`。
    11.0.3 是"支持 AGP 9 且代码改动最小（一行）"的版本。
  - **为什么 permission_handler 代码一行没改**：`Permission.bluetoothScan / bluetoothConnect / location`
    来自 `permission_handler_platform_interface`，13.0.2 要求的还是 `^4.4.0`（跟现在一样），枚举没变。

- **涉及文件**：`pubspec.yaml`、`android/app/build.gradle.kts`、`lib/screens/menu_import_screen.dart`

- **状态**：待验证 ⏳（等你再跑一次 `flutter run -d R9WR201TRKJ`；首次可能还会自动下载
  Build-Tools/Platform 之类，看到 `Preparing "Install ..."` 是正常的，别关窗口）

- **以后注意**：
  1. 看到 `:某个插件:checkDebugAarMetadata` + `is currently compiled against android-XX`，
     要升级的是**那个插件**（或改插件的 `compileSdk`），不是本 App 的 `compileSdk`。
  2. 反过来，如果插件自己按很高的 compileSdk 编译（如 37），**本 App 就必须 ≥ 37**，
     否则同样报 AAR metadata。
  3. 判断"某个包的安卓模块编译在哪个 compileSdk"：直接看 pub 缓存里它的 `android/build.gradle(.kts)`，
     或去 pub.dev 下载对应版本的 tar.gz 看。**别猜**（这次就是靠看脚本才选对版本的）。
  4. 升级插件前先看它的 CHANGELOG 里 **BREAKING CHANGE**，这次 file_picker 就是靠这个避开了 12/13。

---

## 问题 13：`cannot find symbol: class FilePickerPlugin` —— Kotlin 源码根本没被编译

- **现象 / 报错原文**（`flutter run -d R9WR201TRKJ`，AAR metadata 修好之后）：

  ```
  WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): file_picker
  Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
  ...
  C:\...\android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java:19: error: cannot find symbol
        flutterEngine.getPlugins().add(new com.mr.flutter.plugin.filepicker.FilePickerPlugin());
                                                                           ^
    symbol:   class FilePickerPlugin
    location: package com.mr.flutter.plugin.filepicker

  * What went wrong:
  Execution failed for task ':app:compileDebugJavaWithJavac'.
  > Compilation failed; see the compiler output below.
  ```

- **原因**（三层套在一起，最后表现成"类不存在"）：

  1. **file_picker 11.0.3 把 Kotlin 插件的应用写成了"条件式"**（`android/build.gradle`）：
     ```groovy
     def isAgp9OrAbove = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.tokenize('.')[0].toInteger() >= 9
     apply plugin: 'com.android.library'
     if (!isAgp9OrAbove) {                     // ← AGP ≥ 9 时【不】应用 Kotlin 插件
         apply plugin: 'org.jetbrains.kotlin.android'
     }
     ```
     （它的想法是"AGP 9 自带内置 Kotlin，所以不用再应用 KGP"。）
  2. **Flutter 判断"这个插件是否自己应用了 KGP"靠的是【扫 build.gradle 文本】的正则**
     （`FlutterPluginUtils.getSubprojectPluginState`）。它在文本里看到 `apply plugin: 'org.jetbrains.kotlin.android'`
     这句 → 就认为"插件自己会处理" → **Flutter 于是不再帮它应用 KGP**。
  3. 于是 AGP 9 下：它自己跳过、Flutter 又不帮忙 → **谁都没应用 KGP** →
     `android/src/main/kotlin/` 里的 5 个 `.kt`（`FilePickerPlugin.kt` 等）**一个都没编译** →
     模块 jar 里没有 `FilePickerPlugin` 类 → `GeneratedPluginRegistrant.java` 引用它时找不到 → Java 编译失败。

  - 关键背景：本项目的 `android/gradle.properties` 里是 **`android.builtInKotlin=false`**（Flutter 模板的默认值），
    也就是说 **Kotlin 必须由 KGP 编译**，不能指望 AGP 的"内置 Kotlin"——而 file_picker 恰好按"内置 Kotlin 开着"来假设。
  - 顶部那句 `WARNING: ... plugins that apply Kotlin Gradle Plugin (KGP): file_picker` 是**同一个正则判定的产物**，
    它是"结果/提示"，不是原因（真正原因是第 3 步：没人编译 Kotlin）。

- **处理**：把 file_picker **收编进本仓库**再改构建脚本（和 `flutter_bluetooth_serial` 同一套路）：

  | 改动 | 内容 |
  | --- | --- |
  | 新增 | `third_party/file_picker/`（从 pub 缓存拷 `lib/ android/ ios/ macos/ pubspec.yaml LICENSE CHANGELOG README`，共 ~230 KB） |
  | `third_party/file_picker/android/build.gradle` | ① 删掉 `buildscript{}`（里面钉着 **AGP 8.5.1 + Kotlin 1.8.22**，Gradle 9 下不能用）② **无条件** `apply plugin: 'org.jetbrains.kotlin.android'` ③ `jvmTarget` 用 KGP 2.x 新 DSL 固定 17 ④ 删掉 AGP 9 已移除的 `lintOptions{}` |
  | `third_party/file_picker/android/src/main/AndroidManifest.xml` | 删掉根标签的 `package="..."`（AGP 8 起模块名写在 `namespace` 里） |
  | `pubspec.yaml` | `dependency_overrides` 里加 `file_picker: path: third_party/file_picker` |

  ⚠️ **Dart（`lib/`）与 Kotlin/Java 源码一行未动**；`lib/screens/menu_import_screen.dart` 那处 `FilePicker.pickFiles(...)`
  是上一步（问题 12）为了 11.x 的 API 改的，与本次无关。

  > **为什么不用"一行 `android.builtInKotlin=true`"**：那会把整个项目的 Kotlin 编译模式换掉
  > （app 的 `build.gradle.kts` 里 `kotlin { compilerOptions { ... } }`、以及另外几个插件都按 KGP 模式在跑），
  > 牵动面比"只修一个坏模块"大得多，且我没有实测环境去验证；而收编打补丁只影响 file_picker 一个模块，
  > 其余模块维持"已经跑通"的现状。等以后真要全面迁到 built-in Kotlin，再单独做一次。

- **涉及文件**：`third_party/file_picker/**`（新增）、`pubspec.yaml`

- **状态**：待验证 ⏳（再跑 `flutter run -d R9WR201TRKJ`；顶上那句 KGP 的 WARNING 仍会出现，**属于提示、不影响构建**）

- **以后注意**：
  1. 看到 `cannot find symbol: class XxxPlugin`，先判断"那个插件的源码到底编译了没有"：
     看它的 `android/src/main/` 下是 Java 还是 Kotlin，再确认**谁负责应用 Kotlin 插件**。
  2. **插件里写"条件式 apply 插件"很容易两头落空**：Flutter 的判定是文本正则、不是运行时状态。
     给插件作者报 issue 时可以直接引用 `FlutterPluginUtils.getSubprojectPluginState` 是"regex 扫文件"这一点。
  3. `android.builtInKotlin=false`（模板默认）下，插件如果不自己 apply KGP，就得靠 Flutter 帮忙 apply；
     一旦脚本里出现那句文本，Flutter 就不帮了。

---

## 问题 14：种类格子 `BOTTOM OVERFLOWED BY 16 PIXELS`（安卓平板）

- **现象**：安卓平板上，点单页左边的**种类**列表里，**只有两个**格子出现黄黑条纹 +
  `BOTTOM OVERFLOWED BY 16 PIXELS`，其它格子正常。（`flutter run` 的终端里会打出
  `A RenderFlex overflowed by 16 pixels on the bottom.` + `The relevant error-causing widget was: Column`）

- **原因**：和**问题 4**（菜品格子）是同一个病根，只是换了地方 ——
  `lib/widgets/category_grid.dart` 的格子高度是 `SliverGridDelegateWithMaxCrossAxisExtent`
  按 `childAspectRatio: 1.7` **算出来的固定值**（格子宽 ÷ 1.7），而格子里的内容是：

  ```
  14 内边距 + 种类名（fontSize 20，最多 2 行） + 6 间距 + 「N 件 · 已卖 M」（fontSize 13）
  ```

  平板竖屏时左栏列窄 → 格子又矮又窄；**名字最长的那两个种类**会折成**两行**（20px × 2 ≈ 47px），
  于是总高 ~96px 刚好超过格子高度（~95px）→ 溢出 16px（含系统字体缩放时更多）。
  名字一行的格子只要 ~73px，所以看起来"只有那两个坏了"。

- **处理**：给格子内容加"装不下就等比缩小"的兜底（**问题 4 用的就是这一套**）：

  1. `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2)` ——
     系统"字体大小"调得很大时，格子里最多按 1.2 倍渲染（不然下面的 FittedBox 会把整块缩得太小）；
  2. `LayoutBuilder` 拿到格子的**真实宽度** → 文字照这个宽度正常折行（不能直接套 FittedBox，
     否则里面的 Text 会因为"无界宽度"变成一行不折行）；
  3. `FittedBox(fit: BoxFit.scaleDown)` —— 装得下就原样显示，装不下**整体等比缩小**，永不溢出；
  4. 外面再包一层 `Center`：内容比格子矮时仍然**垂直居中**（保持原来的观感）。

  另外给底下那行小字加了 `maxLines: 1 + ellipsis`（它本来没限制行数，也是溢出的帮凶）。

- **涉及文件**：`lib/widgets/category_grid.dart`

- **状态**：待验证 ⏳（等你重新 `flutter run -d R9WR201TRKJ` 看一眼那两个格子）

- **以后注意**：凡是"固定高度（`childAspectRatio` / 固定 `SizedBox`）+ 内部是文字 Column"的格子，
  都要按这一套兜底（`LayoutBuilder` + `FittedBox(scaleDown)`，必要时先 clamp 字体缩放）——
  这类问题**只在特定设备宽度 / 系统字体大小下才出现**，自己的开发机上看不到，
  所以别用"我这儿没复现"来判断修好没修好。

---

## 问题 15：Windows 上「N 份起」好使，安卓平板上不生效（菜单没同步过去）

- **现象**：
  - 在 Windows 上重新导入 Excel（表里新加了「基础数量」列）→ 点某道菜，数量从 2 开始、格子上也有「2 份起」角标；
  - 在安卓平板上同一道菜还是从 1 开始（没有角标）；
  - 就算在 Windows 上点了设置里的 **「上传本机配置」** 也没用。
  （`minQuantity` 在数据里、代码也是同一份，所以问题**只可能是"平板上的那份菜单是旧的"**。）

- **原因**：**「店级配置」和「菜单」是两条独立的同步线**。
  - `store_settings`（店名 / 地址 / 税率 / 货币 / 桌号 / 备注 / 日结支出）走「上传本机配置 / 从云端恢复配置」；
    **它里面根本没有菜品** —— 所以点它当然带不过去 `minQuantity`；
  - `menu`（分类 + 菜品）是另一条线，按**版本号**走：本机 `menuDirty` 就推、否则服务器版本更高才拉。
    平板要是从来没在那之后同步过（或它自己也被标成"待上传"），菜单就一直停在旧那份 ——
    旧的 JSON 里没有 `minQuantity`，`MenuItem.fromJson` 默认补 1，于是"看起来功能没生效"。

- **处理**：
  1. `lib/services/sync_service.dart`：
     - 每次同步读到 `menu` 表那一行就顺手记下**云端菜单摘要** `CloudMenuInfo`（版本 / 道菜数 / 有几道「几份起」）——
       只数 JSON 里的条数，不建模型，很便宜；
     - 新增 `localMenuSummary`（本机道菜数 + 几份起的道数）；
     - 新增两颗**手动**按钮的后端：`pushMenu()` / `pullMenu()`（`pullMenu` 用 `replaceMenuFromServer` **不看版本号**地覆盖本机，
       并且拒绝「云端那份是空的」，不让人手改坏的 JSON 把本机菜单清空）。
  2. `lib/screens/settings_screen.dart`：后台同步区加一块「菜品（菜单）」——
     直接写出两边的差别（本机 3 道有基础数量 / 云端 0 道就变橙），下面两颗按钮
     「从云端下载菜单」「上传本机菜单」；
  3. 文案 zh/es/en 各一份（`sync.menu*`）；`setup_supabase.md` §5.1 改成四颗按钮 + 这段坑的说明。

- **涉及文件**：`lib/services/sync_service.dart`、`lib/screens/settings_screen.dart`、
  `lib/l10n/app_strings.dart`、`setup_supabase.md`

- **状态**：待验证 ⏳（平板上升级 App 后：设置 → 后台同步 看那两行数字 → 点「从云端下载菜单」，
  然后点那道 2 份起的菜，数量应该从 2 开始）

- **以后注意**：菜单 / 店级配置 / 员工名单**三条线各走各的**，报"某台设备上少了什么"时，
  先分清那样东西属于哪条线；`menu` 表里是整份 JSON，所以**新增字段（unit / minQuantity）
  不会自己长到旧数据上** —— 要么重新导入 Excel，要么把新版那份上传/下载一次。

---

## 问题 16：（预留）下一个报错

> 遇到就照模板填（现象/原因/处理/文件/状态），并同步更新 `log.md` 变更记录。
