# 执行日志（log.md）

> 这份文件用来给 **另一个干净的编译/真机环境** 照做，并随时记录改动与测试。
> 每次改动/每轮测试都往这里追加，方便你在别处 follow。

- 项目：`big_boss_bro`（餐厅收银打单，类 Loyverse）
- 技术栈：Flutter（跨平台：Android + Windows）
- 界面语言：中文（默认）→ 可切 西语 / 英语
- 蓝牙打印：`flutter_bluetooth_serial` + `permission_handler` + `gbk_codec`（手写 ESC/POS 字节流）

---

## 0. 当前进度（截至本次）

**已完成（DONE）** —— 源码已全部写好在本仓库 `lib/` 下：

- [x] 工程骨架：`pubspec.yaml`、`analysis_options.yaml`、`.gitignore`、`README.md`、`PLAN.md`、`log.md`
- [x] 数据模型：`models/`（分类 / 菜品 / 购物车行 / 订单）
- [x] 示例菜单：`data/sample_menu.dart`（写死，之后做管理）
- [x] 点单状态：`state/pos_controller.dart`（加购/数量/删除/清空/结账/历史）
- [x] 设置状态 + 持久化：`state/settings_controller.dart`、`data/settings_store.dart`
- [x] 点单界面：`screens/pos_screen.dart` + `widgets/`（分类标签→菜品格子→底部购物车/结账）
- [x] 结账流程：`widgets/payment_flow.dart`（选支付方式→生成订单→打印→失败重试/跳过，**先记单后打印不丢单**）
- [x] 小票排版：`services/receipt_layout.dart`（58/80mm，中文按 2 列对齐，自动算合计）
- [x] 蓝牙打印服务：`services/receipt_print_service.dart`（接口）+ `bluetooth_print_service.dart`（Android 实现）
- [x] Windows 占位：`services/stub_print_service.dart`（先跑起来，打印提示“暂不支持”）
- [x] 设置页：`screens/settings_screen.dart`（店名/货币/纸宽/语言/蓝牙扫描连接/测试页）；入口可进菜品管理
- [x] 菜品/分类管理：`screens/menu_manage_screen.dart` + `data/menu_store.dart`（可增删改分类/菜品并持久化，设置页进入）
- [x] 订单历史 + 删除：`screens/orders_screen.dart`；持久化：`data/order_store.dart`（JSON 存本机，重启不丢）
- [x] **订单生命周期（新）**：下单=进行中 / 结账=已结单；`PosController.placeOrder/appendToOrder/closeOrder`
- [x] **两种打印（新）**：下单/追单打「厨房单」（`printKitchenTicket`，只有菜名+数量+桌号）；结账打「顾客小票」（`printReceipt`，含金额/支付方式）
- [x] **桌号（新）**：订单带桌号并在订单页显示；设置里可增删桌号（`settings.tables`）
- [x] **追单（新）**：购物车里可选「新单+桌号」或「追加到已有单」，把菜加进进行中的单
- [x] 订单页分「进行中 / 已结单」两个标签页；进行中的单可结账
- [x] 去掉点单页右上角无效的购物车图标
- [x] **真·打印三通道（新）**：`services/print_service.dart` 统一分发
  - **Windows 系统打印机（USB）**：`windows_print_service.dart`，用 `dart:ffi` 调 `winspool.drv` 走 spooler 的 **RAW** 通道
  - **网络/以太网/局域网**：`network_print_service.dart`，纯 TCP（默认 9100）
  - **蓝牙**：`bluetooth_print_service.dart`（安卓）
  - 排版/字节抽到公共模块：`services/escpos.dart`（ESC/POS + GBK）、`services/ticket_builder.dart`（厨房单/顾客小票/测试页）
- [x] **购物车常驻右侧（新）**：宽屏 60/40（左菜单 / 右购物车），右下角合计 + 下单；`widgets/cart_panel.dart`；窄屏仍用底部购物车弹窗
- [x] 设置页新增「打印方式」选择（蓝牙 / 网络 / Windows 打印机）与各自配置
- [x] 单元测试：`test/receipt_layout_test.dart`（金额/中文宽度/不爆行）+ `test/pos_controller_test.dart`（点单/下单/追单/结账/删除/菜单）+ `test/order_store_test.dart` + `test/menu_store_test.dart`
- [x] 多语言：`l10n/app_strings.dart`（zh / es / en）

**未完成（TODO）**：

- [ ] **Excel 导入菜单 + 每道菜个性化定制**（下一轮）：从 Excel 读「种类/菜名/定制项/选项」，
      点菜时可选「中/大份、辣度」等选项；再加固定的「其他备注」（常用标签 + 自由输入 + 存成新标签）。入口放设置里。
- [ ] 菜品图片、折扣、税、日结算、AA 分开支付
- [ ] 西语/英语界面补全

> ✅ `flutter test` 全部通过过；`flutter run -d windows` 已能在收银机跑出界面。
> ⚠️ 本轮新增依赖 **`ffi`**，改完代码先跑一次 `flutter pub get`。

### 下一步：在 Windows 收银机上验证（含打印机）

**① 拉依赖 + 跑起来**

```powershell
cd C:\Users\renha\workspace\projects\big_boss_bro

flutter pub get              # ← 本轮新增依赖 ffi，必须先拉一次
flutter test                 # 期望：All tests passed!
flutter run -d windows       # 编译并弹出收银窗口
```

> 退出：在 PowerShell 里按 `q`，或直接关窗口。
> 想装成桌面程序：`flutter build windows` → 产物在 `build\windows\x64\runner\Release\`。

**② 配打印机（重点）**

1. 设置 → **打印机** → 打印方式选「**Windows 打印机（USB）**」→「**选择打印机**」→ 选你那台 → 「**打印测试页**」。
   （详细说明见 `setup.md` 第 5 节；网络/以太网打印机就选「网络（IP）」填 IP + 9100。）
2. 测试页若中文正常、宽度正常，就可以正式用了。

**③ 按这个顺序点一遍**

| 步骤 | 操作 | 期望 |
|---|---|---|
| 0 | 打开点单页（用宽屏窗口） | **左边 60% 菜单、右边 40% 常驻购物车**，右下方是合计 + 下单按钮 |
| 1 | 设置 → **桌号管理** 加几个桌号（默认 1–5） | 桌号以标签显示，可删除 |
| 2 | 点几个菜 → 右侧购物车选「新单 + 桌号」→ 点「**下单**」 | 购物车清空；订单页「进行中」出现这单并**带桌号**；**打出一张厨房单** |
| 3 | 再点两个菜 → 购物车切「**追加到已有单**」→ 选那单 → 点「**追加**」 | 菜并入同一张单、金额累加；打一张标注**（追加）**的厨房单 |
| 4 | 订单页「进行中」→ 该单点「**结账**」→ 选支付方式 | 单子移到「已结单」；**打出一张顾客小票**（含单价/金额/支付方式） |
| 5 | 关掉 App 再启动 | 订单仍在（持久化） |

**④ 下一轮要做的（已排好）**：Excel 导入菜单 + 每道菜的个性化定制（选项/其他备注/常用标签）。

---

## 1. 一次性：在新环境装好开发工具（只做一次）

> **重要**：开发沙箱里没有 Flutter、没有安卓 SDK，也连不上 pub.dev，所以**无法在沙箱内编译**。
> 请在你的电脑上做下面这些（Windows）。

```powershell
# 1) 装 Flutter SDK
git clone https://github.com/flutter/flutter.git C:\flutter

# 2) 用 Android Studio 一次性装好 JDK17 + Android SDK（推荐）
winget install Google.AndroidStudio
# 打开 Android Studio → SDK Manager → 勾选 Android SDK Platform 34、Build-Tools、Platform-Tools → 应用

# 3) 让 flutter 可用 & 检查环境
C:\flutter\bin\flutter  doctor
# 要求：Flutter 那项 ✓、Android toolchain 那项 ✓（装好 Android Studio 后基本就 ✓ 了）
```

> 若没装 git：先到 https://git-scm.com 装。
> 让 `flutter` 全局可用：把 `C:\flutter\bin` 加进系统 `PATH`；或一直用全路径 `C:\flutter\bin\flutter`。

---

## 2. 生成安卓/Windows 原生工程（在本项目目录，一次）

这一步会生成 `android/`、`windows/` 这些原生外壳，**不会覆盖**我写好的 `lib/` 和 `pubspec.yaml`：

```powershell
flutter  create . --platforms=android,windows
```

---

## 3. 下载依赖 + 跑单元测试（先验证逻辑，不碰真机）

```powershell
flutter  pub get
flutter  test
```

`test/` 里现在有：
- `receipt_layout_test.dart`：金额、中文宽度、小票不爆行
- `pos_controller_test.dart`：点单逻辑（加购/数量合并/合计/结账/清空/删除）
- `order_store_test.dart`：订单保存/读回
- `menu_store_test.dart`：菜单（分类+菜品）保存/读回
- `widget_test.dart`：冒烟测试（App 能启动并显示「菜单」）

会验证：
- 金额格式化（`¥28.00` …）
- 中文宽度（`牛肉炒饭` = 8 列）
- 58mm 每行 ≤ 32 列（不爆行）、80mm 每行 ≤ 48 列
- 小票含店名 / 合计 / 谢谢光临

> 预期：`All tests passed!` 就是好的。
> ⚠️ 若 `flutter test` 报 `MyApp` 未定义：那是 `flutter create .` 生成的默认 `test/widget_test.dart` 覆盖了我给你的版本。
> 把它**删掉**（重新用我提供的 `test/widget_test.dart`）即可；只保留 `receipt_layout_test.dart` 也不影响单测。

---

## 4. 蓝牙权限（安卓 12+ 必做，一次）

`flutter create` 生成的 `android/app/src/main/AndroidManifest.xml` 里，`<manifest>` 下加上：

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

> 代码里已用 `permission_handler` 在“扫描/连接”时**运行时请求**授权，第一次会弹系统框。
> （一加/OxygenOS 有时还需要定位权限才能扫描，代码里也已请求。）

---

## 5. 真机运行（一加 12 为例）

```powershell
# 手机：设置→关于手机→连点“版本号”7次→开“开发者选项”→开“USB调试”或“无线调试”(同一Wi-Fi)
flutter  devices          # 能看到手机
flutter  run              # 首次编译较慢，之后秒装
```

无线调试连不上时：用“无线调试→使用配对码配对”，按提示
`adb pair ip:端口 配对码` 再 `adb connect ip:端口`。

---

## 6. 真机验证清单（打印是小票是否正确的关键）

- [ ] 点几个菜（加购、重复点数量+1、改数量、删条目）→ 底部购物车数字/合计正确
- [ ] 进设置页 → 改店名、货币符号、纸宽 58/80
- [ ] 在设置页点 **扫描蓝牙打印机** → 选中你的打印机 → 显示“已连接”
- [ ] 点 **打印测试页** → 小票打出、**中文不乱码**、宽度正确（58mm 别爆行）
- [ ] 回到点单页 → 结账 → 选支付方式 → 小票打出：店名、单号、时间、每行“菜名 数量×单价 金额”、合计、支付方式、谢谢光临
- [ ] 打印成功后购物车清空、订单出现在“订单”页
- [ ] **打印机没连上时结账** → 弹“重试打印 / 跳过并收款”，订单仍保留在历史里（不丢单）
- [ ] 订单页点删除 → 确认后消失
- [ ] 设置页切 西语/英语 → 界面文案随切

---

## 7. 打安装包（给店里别的手机装）

```powershell
C:\flutter\bin\flutter  build apk --release
# 产物：build\app\outputs\flutter-apk\app-release.apk
```

---

## 8. 需要重点盯的坑（新手最常见）

| 现象 | 原因 / 处理 |
|---|---|
| flutter 命令找不到 | `C:\flutter\bin` 没进 PATH；改用全路径 |
| `flutter doctor` 安卓项没 ✓ | 没装 Android SDK / 没装 JDK17；用 Android Studio 装 |
| 编译报 `CardThemeData` / `DropdownButtonFormField value` 等 | 装的是旧版 Flutter；**请装最新稳定版**（≥ 3.29） |
| `flutter create .` 后 android 报错 | 版本不匹配；先在干净目录 `flutter create` 生成的模板再对照 |
| 中文小票乱码 | 打印机走 GBK；本版已用 `gbk_codec`。个别牌子需按说明书开启“中文模式”或切换内码 |
| 蓝牙看不到打印机 | ① 手机没开蓝牙 ② 未授权（先允许）③ 一加需定位权限 ④ 打印机离太远/未进入配对模式 |
| 连上但打印失败（ioError） | 打印机没电/没纸/未开机；或 SPP 端口被占用，重启打印机 |
| 金额或对齐不对 | 看 `test/` 单测；58mm 每行最多 32 列，中文算 2 列 |

---

## 9. 变更记录（每轮追加）

> 格式：`YYYY-MM-DD  改动摘要  对应文件  测试结果`

- `2026-01-01` 初始：完成全套源码（lib/ 全部）+ 单测 `receipt_layout_test.dart`。开发沙箱无法编译，未跑真机。（下一步：在干净环境按本文件第 1–6 节跑通。）
- `2026-01-01` 自检修复①：`lib/main.dart` 补 `package:flutter/material.dart`（原缺失会编译失败）；`analysis_options.yaml` 精简为默认规则；新增 `test/widget_test.dart` 规避 `flutter create` 生成的 `MyApp` 引用导致 `flutter test` 失败。
- `2026-01-01` 自检修复②（切语言刷新）：`app.dart` 的 `home` 改成 `ValueListenableBuilder`，并去掉 `home_shell.dart`/`pos_screen.dart`/空状态里包住 L10n 文案组件的 `const`（否则切中文/西语/英语时界面文字不更新，只改 Material 内部文案）。
- `2026-01-01` 功能新增：订单历史**本地持久化**。新增 `data/order_store.dart`（JSON 存 shared_preferences），`PosController` 启动读回、结账/删除时保存；新增单测 `test/order_store_test.dart`。
- `2026-01-01` 测试新增：`test/pos_controller_test.dart`（点单逻辑：加购/同菜数量+1/合计/结账生成订单并清空/删除历史）。单号改为含秒+毫秒，避免重启后撞号误丢订单。
- `2026-01-01` 功能新增：**菜品/分类管理**。新增 `data/menu_store.dart` 持久化菜单，`models` 加 `toJson/fromJson/copyWith`，`PosController` 增加菜单 CRUD，新增 `screens/menu_manage_screen.dart`（设置页进入），新增单测 `test/menu_store_test.dart`。菜单从「写死」变为「可自定义并持久化」。
- `2026-01-01` 稳健性：菜单管理加「恢复默认菜单」（`PosController.resetMenuToDefault()` + 界面按钮 + 确认弹窗）；`test/pos_controller_test.dart` 追加菜单增删改/恢复默认的测试。
- `2026-01-01` **修复编译错误（关键）**：`Category` 名字冲突。`lib/state/pos_controller.dart` 改为 `show ChangeNotifier`；`lib/widgets/category_chips.dart`、`lib/screens/menu_manage_screen.dart` 的 flutter import 加 `hide Category`。**`flutter test` 全部通过。**
- `2026-01-01` 文档：新增 `design.md`（架构与流程说明，含 Category 冲突坑）；新增 `setup.md`（Windows 触屏收银机跑法）。
- `2026-01-01` **修复 Windows 构建报错**：`flutter_bluetooth_serial` 0.4.0 的 `output` 是 `StreamSink<Uint8List>`（`add` 需 `Uint8List`、无 `flush()`、用 `allSent`）。`lib/services/bluetooth_print_service.dart`：`import 'dart:typed_data'`；`output.add(Uint8List.fromList(bytes))`；`await output.allSent`。详见 `troubleshooting.md` 问题 2。状态：**已验证通过**（`flutter run -d windows` 已能出界面）。
- `2026-01-01` **订单生命周期重构（大改）**：
  - `models/order.dart`：加 `OrderStatus`(进行中/已结单)、`table`(桌号)、`paymentMethod` 可空、`closedAt`、`copyWith`、`itemCount`；旧数据兼容（无 status 视为已结单）。
  - `state/pos_controller.dart`：`_orders` 统一存放 + `inProgressOrders`/`completedOrders` getter；`placeOrder`(下单) / `appendToOrder`(追单) / `closeOrder`(结账) / `deleteOrder`。
  - `services/receipt_print_service.dart`：接口拆成 `printKitchenTicket(order, settings, {isAppend})`（厨房单）+ `printReceipt(order, settings)`（顾客小票）+ `printTestPage`；两个实现同步更新。
  - `services/receipt_layout.dart`：新增 `KitchenLabels`/`KitchenData`/`buildKitchenLines`；并把菜名截断改为**按显示列宽**（修掉长中文菜名撑爆排版的隐患）。
  - `widgets/payment_flow.dart`：`placeOrAppendFlow`(下单/追单→厨房单) + `settleOrderFlow`(结账→顾客小票)，失败仍“重试/跳过”。
  - `widgets/cart_sheet.dart`：加「新单+桌号 / 追加到已有单」选择与「下单/追加」按钮。
  - `screens/orders_screen.dart`：分「进行中 / 已结单」两个标签页，进行中的单可结账。
  - `screens/settings_screen.dart`：加「桌号管理」（增删）；`data/settings_store.dart` 增加 `tables` 持久化。
  - `screens/pos_screen.dart`：**删掉右上角无效的购物车图标**。
  - `l10n/app_strings.dart`：补 zh/es/en 文案（下单/追加/桌号/进行中/已结单/厨房单…）。
  - `test/pos_controller_test.dart`：改为「下单→结账」两步 + 新增「追单」用例。
  - 状态：**待你在收银机验证**（`flutter test` + `flutter run -d windows`，按上面第 2–6 步走一遍）。
- `2026-01-01` **修复布局崩溃**：`flutter test` 报 `BoxConstraints forces an infinite width`（`FilledButton` @ `settings_screen.dart:125`）。
  根因：主题里 `minimumSize: Size.fromHeight(52)` 等于宽度 = `infinity`，放进 `Row`（无界宽度）就非法。
  修：`lib/app.dart` 改 `minimumSize: const Size(0, 52)`；`lib/widgets/cart_sheet.dart` 主按钮包 `SizedBox(width: double.infinity)`。详见 `troubleshooting.md` 问题 3。
- `2026-01-01` 文档：新增 `troubleshooting.md`（报错与修复记录：问题1 Category 冲突、问题2 Windows 蓝牙类型）；重写 `design.md` 为系统设计版（三层架构、Provider 的 watch/read/listen、数据流、DI、持久化、打印抽象、异步与重建、命名空间、测试策略），并保留了你补的「日结算 / AA 分开支付」两条；`README.md` 加指引。
- `2026-01-01` **真·打印三通道 + 购物车右侧常驻（大改）**：
  - 新增 `services/escpos.dart`（ESC/POS + GBK 字节，三通道共用）、`services/ticket_builder.dart`（厨房单/顾客小票/测试页文案与排版）。
  - 新增 `services/network_print_service.dart`：**TCP 直发**（默认 9100），Windows/安卓通用。
  - 新增 `services/windows_print_service.dart`：`dart:ffi` 调 `winspool.drv`，走 Windows spooler **RAW** 通道打给已安装打印机（USB）。
  - 新增 `services/print_service.dart`：`UnifiedPrintService`，按设置里的「打印方式」分发；蓝牙服务按需创建（不选蓝牙就不碰蓝牙插件）。
  - `bluetooth_print_service.dart` 改为纯传输（排版/字节已抽公共模块）；`stub_print_service.dart` 同步新接口。
  - `data/settings_store.dart`：新增 `transport / printerPort / windowsPrinterName / savedNotes`；`state/settings_controller.dart` 加对应 setter。
  - `screens/settings_screen.dart`：打印区改为「打印方式（蓝牙/网络/Windows）+ 各自配置 + 测试页」。
  - `widgets/cart_panel.dart`（新）+ `screens/pos_screen.dart`：宽屏 **60/40**（左菜单/右购物车，右下合计+下单）；窄屏仍用底部弹窗（`cart_sheet.dart` 复用 `CartPanel`）。
  - `pubspec.yaml`：新增依赖 **`ffi`**（改完要 `flutter pub get`）。
  - 状态：**待你在收银机验证**（先 `flutter pub get`，再 `flutter test`、`flutter run -d windows`，然后设置里配 USB 打印机打测试页）。
- `2026-01-01` **修复菜品格子溢出**：`flutter test` 报 `RenderFlex overflowed by 17 pixels`（`menu_grid.dart:63`）。
  根因：宽屏 60/40 后左侧菜单列变窄、格子变矮，而格子内容（emoji+菜名+价格）是固定尺寸。
  修：`_MenuCell` 内容套 `FittedBox(fit: BoxFit.scaleDown)` + 固定宽度 `SizedBox(108)`，任何尺寸下等比缩小不溢出。详见 `troubleshooting.md` 问题 4。
- `2026-01-01` **修复 Windows 构建报错**：`Method not found: 'free'`（`windows_print_service.dart`）。
  根因：`package:ffi` 已移除顶层 `free()`。修：全部改为 `calloc.free(ptr)` / `malloc.free(ptr)`（谁分配谁释放），
  并把内存分配提到 try 前、在 `finally` 统一释放。详见 `troubleshooting.md` 问题 5。
