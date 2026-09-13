# 餐厅收银打单应用 — 开发计划

> 项目：`big_boss_bro` · 目标：安卓 + Windows · 语言：中文优先（后续西语/英语）
> 参考 UI：`assets/` 里的 Loyverse 截图。

## 要做的功能（对标 Loyverse 的核心）

1. 点单 dashboard：分类 + 菜品格子，点一下加购。
2. 下单：购物车改数量、删条目、合计。
3. 客人付钱 → 蓝牙热敏打印机打小票。
4. 已结订单历史管理（列表 + 删除）。
5. 中文 / 西语 / 英语。

---

## 技术选型与 Flutter 可行性论证

### 为什么选 Flutter（而不是原生 / 其他跨平台）

| 需求 | Flutter 是否满足 | 说明 |
|---|---|---|
| 同时跑安卓 + Windows | ✅ | 一套 `lib/` 代码，`flutter build apk` 出安卓，`flutter build windows` 出 Windows，不用写两遍 |
| 界面像 Loyverse（网格 + 分类 + 绿色主题） | ✅ | `GridView` + `ChoiceChip` + Material 3，样式好控制，和参考图一致 |
| **必须高效、稳定** | ✅ | Flutter 是**自绘渲染**（Skia/Impeller），不依赖原生控件刷新，`GridView` 列表滚动流畅；POS 是纯本地点单，没有网络/复杂动画，性能绰绰有余 |
| 蓝牙热敏打印 / USB 打印 | ✅ 有成熟生态 | 本版用 `flutter_bluetooth_serial`（经典蓝牙 SPP）做传输；Windows USB 后续单独实现 |
| 中文小票不乱码 | ⚠️ 需处理 | 关键在**编码**：中文热敏打印机用 GBK（非 UTF-8），打包 `gbk_codec` 转码即可；不同牌子的打印机对编码支持不一，所以做“打印测试页”第一时间验证 |

### 关于“非常高效稳定”，Flutter 的底气

- **不丢单**：代码里**先记单、后打印**。打印失败弹“重试/跳过”，订单已入册，绝不清空即丢。
- **状态单一可信**：购物车/订单全部走 `PosController`（ChangeNotifier + Provider），一处改、全局同步刷新，不会出现状态不一致。
- **金额可靠**：`CartItem.lineTotal = 单价 × 数量`，小计/合计都有单测。
- **小票对齐可靠**：自写“显示宽度 = 中文 2 列”的排版引擎，58mm/80mm 不爆行，有单测兜底。
- **打印解耦**：`ReceiptPrintService` 是接口，安卓用蓝牙实现，Windows 换 USB/网络实现，界面代码不动。

### 可能的代价（诚实说明）

- 首次编译、打包体积比原生略大；对 POS 这类本地工具**影响很小**，可忽略。
- 蓝牙打印生态**包名/版本较散**（esc_pos_bluetooth、pos_universal_printer 等）。**本版绕开它**：只用 `flutter_bluetooth_serial`（稳定）+ `permission_handler`（安卓12+权限）+ `gbk_codec`（中文），小票手写 ESC/POS 字节流，从而不踩包版本雷。
- SDK 版本升级偶尔有接口变动（如 `DropdownButtonFormField`、`CardThemeData` 等）。**建议装最新稳定版 Flutter**，代码已按最新接口写。

**结论：能，而且很适合。** 用 Flutter 做这个点单应用是高效且稳定的选择。

---

## 进度（当前完成 / 待办）

### ✅ 已完成（第一步：安卓 界面 + 点单 + 蓝牙打单）

- Flutter 工程骨架（`pubspec.yaml`、`lib/` 全部写成：models / data / state / services / screens / widgets / l10n）
- 类 Loyverse 的点单主界面：顶部分类标签 → 菜品格子（emoji + 菜名 + 价格）→ 底部购物车/结账
- 点单逻辑：加购、同菜数量+1、改数量、删条目、清空
- 结账流程：选支付方式（现金/刷卡/扫码）→ 生成订单 → 打印 → 失败重试/跳过
- 小票排版：58/80mm，中文按 2 列对齐，自动算合计
- 设置页：店名、货币符号、纸宽、界面语言（zh/es/en）、蓝牙扫描/连接/断开、打印测试页、**桌号管理**
- 已结订单历史（**本地持久化，重启不丢**，含删除）
- **订单生命周期**：下单=进行中（打**厨房单**）→ 追单可继续加菜 → 结账=已结单（打**顾客小票**）
- **桌号**：订单带桌号并在订单页显示；桌号列表可在设置里增删
- 订单页分「进行中 / 已结单」两个标签页
- 单元测试：金额、中文宽度、小票不爆行
- 点单逻辑测试：`test/pos_controller_test.dart`（加购/数量合并/合计/下单/追单/结账/删除/菜单）
- 订单历史存取测试：`test/order_store_test.dart`（保存/读回/中文/金额/支付方式）

### ⏳ 待办（后续步骤，逐个做）

- [x] 蓝牙打印服务落地：`bluetooth_print_service.dart`（flutter_bluetooth_serial + permission_handler + gbk_codec）
- [x] 订单历史持久化：`data/order_store.dart`（JSON 存本机，重启不丢）
- [x] 菜品/分类管理：`screens/menu_manage_screen.dart` + `data/menu_store.dart`（可增删改并持久化，设置页进入）
- [x] Windows 桌面可运行：`flutter run -d windows`（收银机上已跑出界面）
- [x] **真·打印三通道**：蓝牙（安卓）/ 网络 TCP（以太网、局域网）/ Windows 系统打印机（USB，spooler RAW）
- [x] **购物车右侧常驻**：宽屏 60/40（左菜单 / 右购物车，右下合计 + 下单）
- [ ] **Excel 导入菜单 + 每道菜个性化定制**（下一轮）：读 Excel 的「种类/菜名/定制项/选项」，
      点菜时选「中/大份、辣度」等；再加「其他备注」（常用标签 + 自由输入 + 存成新标签）。入口在设置里。
- [ ] 菜品图片、折扣、税、日结算、AA 分开支付
- [ ] 西语、英语界面全面补全、测试

---

## 关键技术点（写代码时已内置）

1. **先记单后打印**：结账时 `PosController.checkout()` 先把订单记入历史、再清购物车，然后才尝试打印；“重试/跳过”都不会丢单。
2. **中文小票编码**：`gbk_codec` 把文本转 GBK 字节再发给打印机；先打测试页验证。
3. **蓝牙权限**：Android 12+ 需要运行时申请 `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN`（清单 + 运行时），清单见 `android/AndroidManifest.xml`。
4. **打印接口化**：`ReceiptPrintService.printOrder(order, settings)`，安卓蓝牙、Windows USB 各自实现。

## 真机验证清单

- 点几个菜 → 结账 → 小票打出、中文不乱码、金额正确 → 购物车清空
- 打印机没连上时结账 → 弹“重试/跳过”，订单仍在历史里
- 切换西语/英语 → 界面文案随切
