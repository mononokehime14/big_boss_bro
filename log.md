# 执行日志（log.md）

> 这份文件用来给 **另一个干净的编译/真机环境** 照做，并随时记录改动与测试。
> 每次改动/每轮测试都往这里追加，方便你在别处 follow。

- 项目：`big_boss_bro`（餐厅收银打单，类 Loyverse）
- 技术栈：Flutter（跨平台：Android + Windows）
- 界面语言：中文（默认）→ 可切 西语 / 英语
- 蓝牙打印：`flutter_bluetooth_serial` + `permission_handler` + `gbk_codec`（手写 ESC/POS 字节流）

---
## 代办
单子字体调整 更好看一点
后台同步

外卖备注名字
分单。
---

## 本轮改动（2026-09-19）：现金快捷金额 / 小票版式照参考图重排 / 取消打印成功横幅

> 你这次的三条要求，下面每条都标了**主要改动的文件**，方便你对照着看。
> 改完状态：**待你 `flutter test` + `flutter run -d windows`（或安卓）**，见最后一节的验证清单。

### 1. 现金结账：实收框**下方**加了快捷金额标签（正好 / 邻近整数）

- 原来的界面：实收输入框 + 右侧一个「正好」按钮（**这个按钮保留，没动**）。
- 现在下面多一排标签，**第一个是「正好」，后面两个是邻近的整数**：
  - 应收 **240** → `正好` `250` `300`（你要的例子）
  - 应收 **550** → `正好` `600` `1000`
  - 应收 **61** → `正好` `70` `100`
  - 应收 **245.5** → `正好` `245.5` `250`（带小数也不重复给一样的数）
- 规则：从「正好」开始，依次试 **10 / 50 / 100 / 200 / 500 / 1000** 这几档往上凑整，
  **跳过等于应收的、跳过重复的**，凑够 3 个为止。点一下就填进实收框，找零大字立刻跟着变。
- 币种跟着「收款币种」走（选 USD 就是按美元的应收算这些整数），所以外币收款也对。

**主要改动文件**

| 文件 | 改了什么 |
| --- | --- |
| `lib/utils/pricing.dart` | 新增纯函数 `quickReceivedAmounts(due)` —— 规则只写这一份，带单测 |
| `lib/widgets/payment_flow.dart` | 结账弹窗现金区：实收框下面加一排 `ActionChip`；抽出 `_applyReceived()`；右侧「正好」按钮也改调它 |
| `test/pricing_test.dart` | 新增 5 组用例（240 / 550 / 61 / 245.5 / 永远以「正好」开头且递增） |

### 2. 顾客小票版式：照 `assets/receipt_print.jpg` 重排

**新版式（跟参考图一致）**：

```
              我的餐厅                  ← 店名居中
        Blvd. Benito Juarez 984-L34-36   ← 店头信息（新设置，可留空）
              (661) 612-1412
----------------------------------------
日期:    2026-09-20 17:15                ← 单头「标签: 值」左对齐，标签列对齐
单号:    20260920-001  桌号 8
收银员:  ADMIN
终端:    POS-58
----------------------------------------
堂食                                     ← 堂食/外卖单独夹在两条横线中间
----------------------------------------
ARROZ CON CAMARON (MEDIANO)     $140.00  ← 菜名(+选项) + 金额右对齐
1 x  $140.00                             ← 下一行：数量 x 单价（有单位写「2 份 x」）
                                         ← 两道菜之间空一行
CHOW MEIN POLLO (MEDIANO)       $160.00
1 x  $160.00
----------------------------------------
小计                            $300.00  ← 只在小计/折扣/税需要打时才出现
折扣                            -$30.00
税 16%                           $37.24
----------------------------------------
合计                            $270.00  ← 合计单独夹在两条横线中间
----------------------------------------
支付方式: 现金                           ← 支付方式 + 币种/汇率/实收/找零
                                     谢谢光临，欢迎再次光临   ← 居中
```

- **删掉了原来的表头行**（`菜名 数量 单价 金额`）——参考图上没有这一行，
  改成「金额打在菜名那一行的右边、下一行写数量 × 单价」，跟参考图一样。
- **选项跟在菜名后面**（参考图的 `ARROZ CON CAMARON (MEDIANO)`）；
  **备注**（可能很长）仍然缩进打在下面单独一行。
- **日期格式**：西语/英语小票改成参考图的 `20/9/2026 5:15 p. m.` / `5:15 PM`；
  中文小票保持 `2026-09-20 17:15`（习惯写法）。小票语言跟随「设置 → 小票语言」。
- **店头信息**（地址 / 电话 / RFC）是新设置：**设置 → 店名**下面那个多行框，**一行一条**，
  会居中打在店名下面。留空就不打（老用户的小票头部只有店名，不会突然多出空行）。
- 「终端」那一行用的就是当前选的打印机名（蓝牙/网络/Windows 都一样），没连打印机就不打这一行。

**主要改动文件**

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/receipt_layout.dart` | `buildReceiptLines()` **整个重排**；`ReceiptLabels` 精简成 `labelTotal/labelPay`；新增 `ReceiptInfoRow`；`ReceiptData` 用 `headerLines` + `infoRows` 取代原来的 `orderId` / `createdAt`；新增 `formatReceiptDateTime()` |
| `lib/services/ticket_builder.dart` | `receiptLines()` 组装新的店头/单头/堂食外卖/明暗行；收银员从「额外行」挪到单头（不再重复） |
| `lib/data/settings_store.dart` | 新设置 `Settings.storeHeader`（店头信息，多行）+ 存取键 `store_header`；新设置 `Settings.kitchenFontSize` + 键 `kitchen_font_size` |
| `lib/state/settings_controller.dart` | `setStoreHeader()` / `setKitchenFontSize()`（带 1~3 兜底） |
| `lib/screens/settings_screen.dart` | 「店名」下面加**店头信息**多行输入框；「小票语言」下面加**厨师单字体大小**下拉 |
| `lib/l10n/app_strings.dart` | zh/es/en 三份都加：`settings.storeHeader(+.hint)`、`settings.kitchenFont(+.hint/.normal/.large/.xlarge)`、`receipt.labelDate/labelOrder/labelDevice`；**删掉**已用不到的 `receipt.colName/colQty/colUnit/colAmt` |
| `test/receipt_layout_test.dart` | 按新 API 重写，并新增：单头对齐、两行式菜品、合计上下横线、日期格式（zh/es/en）、厨师单字号 |

> ⚠️ 给以后的自己：`ReceiptData` 里**没有** `orderId` / `createdAt` 了（日期和单号都进 `infoRows`，
> 因为要按小票语言排版）；`ReceiptLabels` 也只剩两个字段。改小票先看这两个类。

#### 2b. 厨师单的字体大小怎么调（你问的这条）

**设置 → 打印机 → 厨师单字体大小**，三档：

| 选项 | 实际效果（ESC/POS） | 一行能放多少字（58mm） |
| --- | --- | --- |
| 正常（默认，1） | 不放大 | 32 列（中文 16 字） |
| **大（双倍高，2）** | `GS ! 0x01` | **还是 32 列** —— 只变高，排版一个字都不动，**推荐先用它** |
| 特大（双倍宽高，3） | `GS ! 0x11` | **只剩 16 列**（80mm 纸是 24 列） |

实现要点（都写在代码注释里了）：

- 字是靠 ESC/POS 指令放大的：`GS ! n`（`0x1D 0x21 n`，高 4 位是宽倍数-1、低 4 位是高倍数-1）。
  每一行放大前发指令、**换行后立刻复原**（`escpos.dart` 的 `buildEscPosBytes()`）。
- 放大时**同时把行距也撑开**（`ESC 3 n`，n = 24×高度倍数）：有些机器不会自动加行距，
  不设的话下一行会压在放大后的字上；打完发 `ESC 2` 把行距恢复默认，后面的普通行不受影响。
- **双倍宽时列数必须减半**：`receipt_layout.dart` 里 ` ()` 用
  `kitchenColumns(纸宽, 字号)` 算列数（58mm 32→16），否则菜名右边的字会被切到纸外。
- 「大」只加高、列数不变，所以**内容一个字都不会被截断**；「特大」一行字数减半，
  长菜名会早一点被截断（字大一倍、一行就只能放一半字，这是必然的）。
- **怎么在你那台机器上验证**：设置页点「打印测试页」，测试页最后多了三行预览
  `1 normal size` / `2 LARGE` / `3 XLARGE`（还有一行 `KitchenFont set to N` 显示当前设置）。
  哪一行明显更大，就说明这台打印机认得那一档放大指令；三行一样大 = 中间那层（多半是 Windows 驱动）
  没把指令透传，那就要换驱动或改用网络/蓝牙直连。

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/escpos.dart` | 新增 `TicketScale`（normal 1×1 / large 1×2 / xlarge 2×2）+ `gsBang()` / `lineSpacing()`；`TicketLine` 多一个 `scale` 字段；`buildEscPosBytes()` 按行发放大/行距/复原指令 |
| `lib/services/receipt_layout.dart` | `KitchenData.fontSize`；新增 `kitchenWidthScale()` / `kitchenColumns()`；`buildKitchenLines()` 按字号缩列数（数量列也跟着缩） |
| `lib/services/ticket_builder.dart` | `kitchenLines()` 把设置里的字号传给排版，并给每一行带上 `TicketScale`；**测试页**末尾加了三行字号预览 |
| `lib/screens/settings_screen.dart`、`lib/data/settings_store.dart`、`lib/state/settings_controller.dart`、`lib/l10n/app_strings.dart` | 这一档设置的界面 / 存取 / 三语文案 |
| `test/escpos_test.dart` | 新增「字号指令」5 组：正常不发指令、`GS ! 0x01` / `0x11`、行距 `ESC 3 48`、列数减半、1/2/3 映射 |
| `test/receipt_layout_test.dart` | 新增「厨师单字号」3 组：正常 32 列、双倍高**排版完全相同**、双倍宽只剩 16 列且不爆行 |

### 3. 取消「打印成功」的下方横幅

- **打印成功一律不提示**（纸出来了就是成功）：厨房单、顾客小票、日结、测试页四处全取消。
- **打印失败照旧弹框**（重试 / 跳过并收款）；失败后**重试成功也不再弹横幅**，直接关掉那个框。
- 顺手删掉已经没人用的文案键 `dialog.print.success`（zh/es/en 三份）和 `payment_flow.dart` 里的 `_snack()` 工具函数。

**主要改动文件**

| 文件 | 改了什么 |
| --- | --- |
| `lib/widgets/payment_flow.dart` | `submitOrderFlow`（厨房单）、`settleOrderFlow`（顾客小票）、失败框重试成功 —— 三处成功提示全删；删掉 `_snack()` |
| `lib/screens/daily_summary_screen.dart` | 日结打印：只在失败时弹提示 |
| `lib/screens/settings_screen.dart` | 打印测试页：只在失败时弹提示 |
| `lib/l10n/app_strings.dart` | 删掉 `dialog.print.success`（zh/es/en） |

### 本轮验证清单（你自己跑）

- [ ] `flutter test` —— 改了 4 个测试文件（`receipt_layout` / `escpos` / `pricing` / `settings`），新增/重写的用例都在里面
- [ ] `flutter run -d windows`（或安卓）：现金结账，输入实收框下面应看到 **`正好` `250` `300`**（应收 240 时）
- [ ] 设置 → 店名下面填**店头信息**（一行一条）→ 结账打一张小票，看头部是不是居中的多行
- [ ] 设置 → 打印机 → **厨师单字体大小**选「大」→ 点单打厨房单：字应该**又高又清楚、行不会重叠、内容一个不少**
      （想先确认机器认不认，就打一张测试页看最后那三行 `1 normal size` / `2 LARGE` / `3 XLARGE`）
- [ ] 再选「特大」看效果（58mm 一行只剩 16 列，长菜名会被截断，属正常）
- [ ] 打单成功时**屏幕上不该再出现下方横幅**；把打印机关掉再打，应该照旧弹「打印失败」框

### 本轮之后仍未做（沿用你的清单）

- [ ] 零钱柜（你说以后再做）
- [ ] 菜品图片、西语英语界面逐屏检查


---

## 本轮改动（2026-09-19 第二次）：结账窗口改成「左右两栏 + 两步走」

**新流程**（照你说的做）：

1. **① 核对明细**：窗口左边 30% 是这张单的菜（菜名 / 数量×单价 / 选项 / 备注 / 金额，
   **每道菜右边一个垃圾桶**），右边 70% 是金额明细 + 折扣 + **应收（总和）大字**，
   右下角两个按钮：`取消` / **`确认并打印`**。
2. 点「确认并打印」→ **先打单子**（明细 + 合计，含刚设的折扣）→ 同一个窗口切到第 ② 步。
3. **② 收款**：应收（外币会带换算）、收款币种、现金/刷卡；现金有实收输入框、
   `正好` + 邻近整数快捷标签、大字找零；刷卡是银行卡动画。右下角 `返回上一步` / **`确认收款`**。
4. 点「确认收款」→ **结账完成、窗口关闭**（**不再重复打纸**：单子第 ① 步已经打过了）。

**几个明确的取舍**（你选的 + 必须定的）：

- **一整单只打一张纸**：`确认并打印` 打的就是给客人的单子；收完钱只记账不出纸。
- **删除**：收银员就能删（不用管理员密码），但**点垃圾桶会先弹一次「确定删掉这道菜？」**；
  删完 PosController 立刻重算合计并落盘，右边数字同步变。
- **删不了的情况**：只剩最后一道菜时垃圾桶是灰的（删空就没法结账，要撤整单请点「取消」）；
  **第 ② 步（单子已经打出去）明细锁定不能改**，否则纸上的金额跟收的钱对不上。
- **折扣放在第 ① 步**：它会影响打出去的金额，所以必须在打单前给；收款币种放在第 ② 步。
- 窗口里的明细是**实时读 PosController** 的（不是打开窗口时那个旧对象），
  所以删菜后「屏幕合计 = 打出去的单子 = 最后记的账」三边一致。
- **窄屏（手机竖屏）**：左右 30/70 按你说的做死了（窗口最宽 960），但每道菜的明细
  排成三行（菜名+垃圾桶 / 数量×单价 / 金额），所以 30% 那栏很窄时也不会挤成一条线。
  手机竖屏还是偏挤，**建议横屏或平板**；要竖屏改成「上下排」也可以，说一声就加。

**主要改动文件**

| 文件 | 改了什么 |
| --- | --- |
| `lib/widgets/payment_flow.dart` | 结账窗口重写：`showCheckoutDialog` 多一个 `printBill` 参数；窗口变成 `Row(左 30% 明细 + 右 70% 内容)`、`_step` 两步；新增 `_titleBar / _stepTitle / _dueBig / _linesPane / _lineTile / _actionRow / _confirmAndPrint / _finish / _deleteLine`；`settleOrderFlow` **收完钱不再打印**（只记账） |
| `lib/state/pos_controller.dart` | 新增 `removeOrderLine(orderId, index)`：删一行菜 → 按这张单自己的折扣/税重算应收并落盘；越界/已结单/只剩一道菜会返回 null（界面禁用按钮兜底） |
| `lib/l10n/app_strings.dart` | zh/es/en 三份各加 9 条：`checkout.title / step1 / step2 / items / deleteLine / deleteLast / deleteConfirm / locked / back`（`确认并打印` 复用已有的 `dialog.confirm.ok`） |
| `lib/services/receipt_print_service.dart`、`lib/services/print_service.dart` | 只改注释：说明 `printReceipt` 现在是**结账窗口第 ① 步**打的「单子」（还没有支付方式/实收/找零那几行） |
| `test/pos_controller_test.dart` | 新增 4 组用例：删菜后行数/小计/税额/应收都对、带价外税也重算、只剩一道菜不给删、越界和已结单不给删 |

**注意（给以后的自己）**：第 ② 步那段界面沿用了原来的缩进（能编译，只是比周围浅一层）；
有空 `dart format lib/widgets/payment_flow.dart` 一下就整齐了（纯格式化，不改行为）。
另外：现在删菜**只改账单**，厨房不会收到「退菜」通知（要的话以后可以加一张「退菜单」）。

**你要试的**：点任一桌的「结账」→ 左边删一道菜看右边合计变不变 → 点「确认并打印」看纸出来 →
输实收看找零 → 点「确认收款」，窗口应该关掉、订单进「已结单」，并且**不再出第二张纸**。

### 本轮之后仍未做（沿用你的清单）

- [ ] 零钱柜（你说以后再做）
- [ ] 菜品图片、西语英语界面逐屏检查
- [ ] 退菜要不要给厨房打一张「退菜单」（现在只改账单，不通知厨房）


---

## 本轮改动（2026-09-19 第三次）：点单页——选桌 → 点菜 → 购物车下面「保存 / 厨房」

**新逻辑**（照你说的做）：

1. **选桌**：购物车顶部下拉（堂食 / 外卖都在这里选）；
2. **点菜**后购物车分两个区：
   - **已在单上**：这张桌**当前这张单**已有的菜（选桌就自动带出来，只读）；
   - **本次新增**：刚点的菜（可加减份数 / 删除 / 清空）；
3. **购物车下面两个按钮**：
   - **左「保存」**：把新增的菜**记到这张桌的单上，但不打单**（酒水、先垫着不下厨的菜）；
   - **右「厨房」**：记到单上 **+ 打厨房单**。厨房单打的是**这张单上所有还没下厨的菜**
     （之前「保存」过的会一起送过去，不会漏菜）；票上「（追加）」按「之前有没有下过厨」判断；
4. **结账没变**：还是「订单」→ 选进行中的单 → 结账。

**「已下厨 / 未下厨」的标记**（你要的颜色 / 效果）：每行左边一条**竖色条** + 右边小标签 ——
**绿色「已下厨」** = 厨房已收到；**橙色「未下厨」** = 只保存过、厨房还没收到。
靠 `OrderLine.sentToKitchen` 区分，**厨房单打成功了才置 true**（失败还是未下厨，可以再点一次重打）；
**老数据没有这个字段 → 当作已下厨**，所以升级后老单显示正常。

**主要改动文件**

| 文件 | 改了什么 |
| --- | --- |
| `lib/models/order.dart` | `OrderLine.sentToKitchen`（+ `copyWith` / `toJson` / `fromJson`，老数据默认 `true`） |
| `lib/state/pos_controller.dart` | 新增 `unsentLines(orderId)` / `markOrderSent(orderId)`；`appendToOrder` **不再并进已下厨的行**（新菜另起一行） |
| `lib/widgets/cart_panel.dart` | 面板重构：已在单上（只读 + 绿/橙标记）+ 本次新增（可编辑）+ 整桌合计 + **左保存 / 右厨房**；新增 `_PlacedLine`、`_sectionHeader` |
| `lib/widgets/payment_flow.dart` | `submitOrderFlow` 拆成 **`saveOrderFlow`（不打单）/ `kitchenOrderFlow`（打厨房单）**，共用 `_submitOrder` |
| `lib/widgets/cart_bottom_bar.dart` | 窄屏底栏显示**整桌**件数/合计，按钮变「保存 / 厨房」→ 打开购物车弹窗 |
| `lib/widgets/cart_sheet.dart`、`lib/screens/pos_screen.dart` | 接上两个回调 |
| `lib/l10n/app_strings.dart` | zh/es/en 各加 9 条 `cart.onOrder / sent / unsent / save / kitchen / totalTable / actions / buttonsHint / takeawayHint`；删掉没人用的 4 条；`dialog.print.skip` 改成中性文案「跳过，不打印」 |
| `test/pos_controller_test.dart` | 新增 4 组：新单都是未下厨 → `markOrderSent` 全变已下厨；已下厨的行不再合并（新菜另起一行）；未下厨的行照旧合并；`sentToKitchen` 存取 + 老数据当已下厨 |

**两个现状（要改随时说）**：

- **外卖仍是「每单独立」**：外卖没有桌号，所以保存 / 厨房每次都开**新单**，购物车不会带出上一张外卖单的菜。
- **已在单上的菜在购物车里是只读的**：要删已下厨/未下厨的菜，走「订单 → 结账」窗口里那个垃圾桶。

**你要试的**：选桌 → 点两个菜 → **「厨房」**（出纸，菜变绿「已下厨」）→ 再点一个菜 →
上面绿的、下面新的 → 点**「保存」**（菜变橙「未下厨」）→ 再点**「厨房」**：
这次厨房单应该只打**没下厨的那一份**，然后全部变绿。


---

## 修 + 新功能（2026-09-19）：加「电话外卖」这第三种单子类型

### 你那个报错错在哪（两处写法）

**① 枚举里的分号位置**（编译器直接报的那条）

```dart
enum OrderType {
  dineIn('dine_in'),
  takeaway('takeaway');                       // ← ✗ 分号写这儿 = 枚举到此结束
  phonecallTakeaway('phonecall_takeaway');    // ← 这行就成了枚举体里的非法成员
```

分号是「枚举值列完了」的标记，**只能写在最后一个值的后面**，中间一律用**逗号**。
所以编译器报 `Expected an identifier, but got ''phonecall_takeaway''`，紧接着又报
`Enums can't declare abstract members`（它把这行当成枚举的方法声明了）。正确写法：

```dart
enum OrderType {
  dineIn('dine_in'),
  takeaway('takeaway'),                        // ← 逗号
  phonecallTakeaway('phonecall_takeaway');     // ← 最后一个才写分号
```

**② `||` 两边必须是 bool**

```dart
bool get isTakeaway => orderType == OrderType.takeaway || OrderType.phonecallTakeaway;
//                                                            ^^^^^^^^^^^^^^^^^^^^^^^ 枚举值，不是 bool
```

（当时编译器先报枚举那条，这条还没轮到。枚举一修好它就会报类型错。）正确写法：

```dart
bool get isTakeaway => orderType != OrderType.dineIn;          // 不是堂食 = 外卖类
bool get isPhoneTakeaway => orderType == OrderType.phonecallTakeaway;
```

### 顺手把「电话外卖」补全了

光加一个枚举值是不够的 —— 不补下面这些地方，下拉里选不到它、打单也不会区分、日结还会把它算进普通外卖：

| 文件 | 改了什么 |
| --- | --- |
| `lib/models/order.dart` | 修好枚举；`isTakeaway` = 不是堂食；新增 `isPhoneTakeaway` |
| `lib/state/pos_controller.dart` | 选中目标从「bool 外卖」升级成 `OrderType _selectedType`：`selectTable(table, takeaway: true, type: OrderType.phonecallTakeaway)`；新增 `selectedType / isPhoneTakeaway / openPhoneTakeawayCount`；`placeOrder` 用 `_selectedType` 当类型 |
| `lib/widgets/cart_panel.dart` | 顶部下拉多一项 **电话外卖**（紫色圆点 + 有几个进行中的电话单） |
| `lib/services/ticket_builder.dart` | 小票 / 厨房单的类型文字改成三态 `_typeLabel()`：堂食 / 外卖 / **电话外卖** |
| `lib/services/sales_totals.dart` | 汇总多一个 `phoneTakeaway` 桶（**三种单加起来 = 总营业额**，不漏账不重复） |
| `lib/services/receipt_layout.dart` | 日结小票多一个 `phoneTakeawayTotal`；**有电话单才多打一行**（没有电话单的老格式一个字不变） |
| `lib/screens/daily_summary_screen.dart` | 日结左边多一行「电话外卖」（非 0 才显示），打印时把数带进小票 |
| `lib/screens/pos_screen.dart`、`lib/widgets/payment_flow.dart`、`lib/screens/orders_screen.dart` | 标题栏 / 结账窗口的类型标签 / 订单卡片：堂食显示桌号，外卖和电话外卖显示类型文字 |
| `lib/l10n/app_strings.dart` | 你已经加好的 `order.phonecallTakeaway` / `summary.phonecallTakeaway`（三语）正好用上，没再动 |
| `test/pos_controller_test.dart` | 新增 2 组：电话外卖的类型/桌号/每单独立/计数器；堂食+外卖+电话外卖**日结三行加起来 = 总营业额** |
| `test/receipt_layout_test.dart` | 新增 3 组：电话外卖的小票和厨房单都打「电话外卖」；堂食/外卖老文案没串台 |

**一个现状**：电话外卖跟外卖一样**没有桌号、每单独立**（保存 / 厨房各开一张新单）。
想让它像堂食那样「接着同一张单加菜」，说一声我加。

---

## 第 12 阶段：安卓版审计（功能是否有缺）+ 安卓测试指南

你问「安卓版是不是所有功能都更新到了」。逐项对了一遍：

**功能代码本身一条都不缺**（打印、点单、结账、菜单、Excel 导入、后台同步都是纯 Dart，
平台无关）；但**安卓平台配置里有 2 个坑**，其中第 1 个是真会坏功能的：

### ❌ 坑 1：`INTERNET` 权限只写在 debug 的 manifest 里（release 包会没网）

`android/app/src/main/AndroidManifest.xml` 里**没有** `android.permission.INTERNET`；
Flutter 只在 `src/debug/AndroidManifest.xml` 里加它（给热重载用）。后果很典型：

- `flutter run`（debug）→ 同步、网络打印都正常；
- `flutter build apk --release` 装到平板上 → **同步连不上、网络打印机连不上**
  （报 `SocketException: Failed host lookup` 之类），而且看着像「功能没做」。

**已修**：把 `INTERNET` 写进 main manifest，并在旁边写清楚为什么必须写在这里。
（网络打印机走的是 TCP 9100，也要这个权限。）

### ⚠️ 坑 2：「Windows 系统打印机（USB）」在安卓上也显示

设置页原来三个选项都显示，安卓上选了只会得到 `PrintError.unsupported`。
**已修**：只在 `Platform.isWindows` 时显示这一个选项。

### ✅ 顺便核对没问题的部分

| 项 | 结论 |
| --- | --- |
| 蓝牙权限（Android 12+） | `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` 已声明，运行时也会请求 ✓ |
| 蓝牙权限（Android ≤11） | 插件 `flutter_bluetooth_serial` 的 manifest 里已声明 `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`，App 里也会请求「位置」✓ |
| 平台判断 | 蓝牙/网络打印跨平台 ✓；Windows 打印在非 Windows 上直接返回「不支持」✓ |
| Excel 导入 | 用系统文件选择器（SAF），安卓**不需要**存储权限 ✓ |
| 应用名 | 桌面名原来叫 `big_boss_bro` → 改成 **`Big Boss Bro`**（想改成店名就改那一行 `android:label`） |
| 构建环境 | SDK 37 + build-tools 36 + adb ✓、Android Studio 自带 JDK ✓、Gradle 9.3.1 / AGP 9.1 / Kotlin 2.4（Flutter 自动生成的那套）✓ |

### 新增：`android_test.md`（怎么测安卓）

一份 15 分钟的清单：准备（开发者模式 / USB 调试）→ debug 与 **release** 两种跑法 →
25 条功能核对（打印 6 条 / 点单结账 4 条 / 菜单 2 条 / 后台同步 8 条 / 安卓专属 5 条）→
安卓专属坑排查表；另外补了 **§0「插上线 Windows 没反应」**（线/模式/驱动三分支、
Redmi/三星/一加的差别、无线调试、直接拷 APK 三条路）。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `android/app/src/main/AndroidManifest.xml` | **加 `INTERNET` 权限**（+注释说明）、`android:label` 改成 `Big Boss Bro` |
| `lib/screens/settings_screen.dart` | 「Windows 打印机」选项只在 Windows 上显示（补 `dart:io` 的 `Platform` 导入） |
| `android_test.md`（新） | 安卓测试清单 + 排查表（含 §0 连不上电脑怎么办） |

### 可选优化（没做，等你说要不要）

- 平板**锁定横屏**（`SystemChrome.setPreferredOrientations`）；
- 点单页**不息屏**（需要 `wakelock_plus` 之类的新依赖）；
- 返回键二次确认（防手滑退出）；
- 上 Google Play 需要：自己的 keystore + 把 `applicationId` 从 `com.example.*` 改掉。

---

## 新功能：员工签到（考勤）

底部导航加了第 4 个标签「**签到**」（在「设置」前面；收银员也能用，不受管理员限制）。

### 员工怎么用（这一半完全不挡人）

进「签到」页 → 中间一个**又高又绿的大按钮**「签 到」→ 点一下 → 弹出**数字键盘** →
输入自己的 **4 位 PIN** → 满 4 位**自动提交** → 大 ✓ +「签到成功」+ **姓名 + 时间**
（1.8 秒后自己关掉，不耽误下一个人）。

- **同一天再打一次**：不会重复记账，显示「今天已经签到过了 8:05」（把第一次的时间还给他）；
- **PIN 不对**：就地红字「PIN 不对，再试一次」，**不用重新点一次大按钮**，接着输就行；
- 按钮下面还有「**今天已签到 (N)**」列表（头像 + 姓名 + 时间），员工自己能确认打上了。

### 管理员怎么用（点开才看得到）

页面下半部分默认是一把「锁」：**「查看本周考勤 / 管理员工」** → 点它 →
**输管理员密码（默认 8888）** → 解锁后出现两张卡片：

1. **本周考勤**：一行一个员工，7 列是**周一到周日**（格子里是签到时间，绿色；没来是「—」），
   最后一列是「出勤」天数；右上角 ‹ **今天** › 可以翻上一周/下一周；
2. **员工管理**：列表显示「姓名 + PIN」（老板要告诉员工自己的 PIN），
   右边**修改**（姓名和 PIN 一起改）/ **删除**（会问一句「已经打过的卡会留着」）+
   「**添加员工**」。PIN 必须 **4 位数字**而且**不能跟别人重复**。

右上角「锁上」可以随时把管理员区收回去。

### 几个设计决定（都是有意这么做的）

| 决定 | 为什么 |
| --- | --- |
| **员工 ≠ 登录账号** | 洗碗/端菜的同事不需要（也不该）有 App 账号；他们只要一个 4 位 PIN。登录账号那套（`models/account.dart`）管的是「谁能改菜单/设置」，跟考勤分开 |
| 管理员用**现有账号的密码**验证（`requireAdmin`，默认 8888） | 不新造一套「管理密码」；而且已经是管理员的账号直接进，收银员才需要输 |
| 一天一个人**只记一条**（只签到，不做签退） | 你要的就是「谁来了、几点来的」。等你说要签退，再加一步就行（数据结构已经是「一条条记录」，加签退不用改存储） |
| 删员工**不删**他的历史打卡 | 不然上个月的考勤会凭空变少；记录留着，只是名单/表格里不再显示他 |
| 数据**只存本机** | 跟订单/菜单一样先本地跑；多台设备共用一个考勤表要后台加张表再同步 —— **这条没做**，你要的话我按订单那套加 |
| 日期用 `DateTime(y, m, d ± n)` 算，不用 `Duration` | 夏令时那天 ±24 小时会变成前一天 23:00，考勤就会记到隔壁那天去 |

### 主要改动文件

| 文件 | 说明 |
| --- | --- |
| `lib/models/employee.dart`（新） | `Employee`（id/姓名/PIN）、`AttendancePunch`（打卡记录）、`PunchOutcome`/`PunchResult`、`EmployeeError` |
| `lib/data/employee_store.dart`（新） | 员工 + 打卡记录的本机存储（两个键、坏数据当空、打卡最多留 5000 条） |
| `lib/state/attendance_controller.dart`（新） | `punch()`（认 PIN / 当天不重复）、`punchAt()`、`punchesOnDay()`、`daysPresent()`、`weekOf()`（周一到周日）、员工增删改 + PIN 唯一/4 位校验 |
| `lib/widgets/clock_in_dialog.dart`（新） | 签到对话框：数字键盘（0-9 / 退格 / 确定）+ 4 个圆点 + 成功 ✓ 界面（自动关闭） |
| `lib/screens/attendance_screen.dart`（新） | 签到页：大按钮 + 今天已签到 + 管理员区（本周考勤表 + 员工管理） |
| `lib/utils/format.dart` | 加 `timeHm()`（09:05）和 `dayKey()`（2025-01-31） |
| `lib/app.dart` | 加 `AttendanceController` 的 provider |
| `lib/screens/home_shell.dart` | 底部导航加第 4 个标签「签到」；`_settingsTab` 改成常量 3（以后加标签不会再把权限门禁指错） |
| `lib/l10n/app_strings.dart` | 三语各加 36 条 `attendance.*` / `nav.attendance` |
| `test/attendance_test.dart`（新） | 17 组纯逻辑：打卡/重复打卡/错 PIN/删员工后失效/PIN 校验与唯一/改名改 PIN/周分组（跨月跨年）/一周格子数据/今天列表排序/重启后数据还在/坏数据不崩 |
| `test/attendance_screen_test.dart`（新） | 2 组界面测试：点大按钮→输 PIN→「签到成功 + 姓名」→名单里出现；PIN 不对→就地报错→接着输对的能成功 |

### 你要试的（Windows 上就能全试完，安卓同一套代码）

1. `flutter test`；
2. `flutter run -d windows` → 登录（admin / 8888）→ 底部点「**签到**」；
3. 先点大按钮 → 会提示「还没有员工：请管理员在下面添加」（正常，还没加人）；
4. 点「查看本周考勤 / 管理员工」→ 因为你已经是管理员，**直接进**（收银员账号才需要输 8888）→
   「添加员工」加两个人：张三 1234、李四 5678（试试故意填 `123`、`abcd`、或跟别人重复的 PIN，
   应该都被拦下来）；
5. 点大按钮 → 输 **1234** → 应该出现大 ✓「签到成功 张三 时间」→ 1.8 秒后自动关掉 →
   「今天已签到 (1)」里有张三；
6. 再打一次 1234 → 应显示「今天已经签到过了」+ 第一次的时间（**不会记两次**）；
7. 输 9999 → 红字「PIN 不对，再试一次」，接着输 5678 能成功；
8. 回管理员区看**本周考勤**：今天的格子里有签到时间、出勤 = 1；点 ‹ 上一周 → 应该全是「—」；
9. 「修改」把张三的 PIN 改成 4321 → 之后 1234 打不了、4321 能打；
10. 「删除」李四 → 名单里没了，但他今天的打卡**还在数据里**（回头做「本月汇总」还能用）。

---

## 员工考勤（第 2 轮）：加「下班」打卡 + 考勤同步到 Supabase

你说 Windows 上测过了、要两件事：① 考勤连到 Supabase；② 加一个「下班」大按钮。都做了。

### 1. 「下 班」大按钮

签到按钮**下面**多了一个蓝色大按钮「下 班」（和签到一样全宽，点完输同一个 4 位 PIN）：

- **签到 → 下班**：两次都记上，成功提示里还会写「**今天工作了 10:25**」（上班→下班算出来的）；
- **今天还没签到就点下班** → 橙字提示「今天还没签到：请先点上面的「签 到」」，**不记任何东西**
  （避免表里出现「有下班没上班」的怪数据）；
- **同一天下班打两次** → 「今天已经下班打卡过了 18:00」，不重复记账；
- 「今天已签到」列表右边现在显示「**08:05 → 18:30**」；
- 本周考勤表的格子里：**上面绿色 = 上班、下面蓝色 = 下班**（表底下有图例），
  并多了一列「**工时**」（这一周的总小时数，按上班→下班累加；只打了上班没打下班的不算）。

### 2. 考勤同步到 Supabase（两张新表）

> ⚠️ **你要做的第一件事**：去 Supabase 的 SQL Editor 把 `supabase/schema.sql`
> **整段粘进去重跑一次** —— 它会给现有项目补上两张新表（可重复执行、不删数据）。
> 不跑的话：订单/菜单照常同步，只是设置页状态栏会提醒「考勤表还没建好」。

| 表 | 形状 | 同步规则 |
| --- | --- | --- |
| `attendance_staff` | **只有一行**（`id='current'`），整份员工名单 JSON + `version` | 跟**菜单**一样：版本号大的赢；本地改过就先推本地（后改的赢） |
| `attendance_punches` | **一次打卡一行**（id / employee_id / kind=in,out / at / device_id / created_at） | 跟**订单**一样：先拉后推，按 id **并集** —— 打卡只增不改，**不存在冲突**，两台设备各打各的卡不会互相覆盖 |

- 拉取是**增量 + 翻页**的（打卡按服务器写的 `created_at` 推水位线，稳定状态下基本 0 行）；
- 每条打卡自带 `device_id`，后台一眼能看出是哪台机器打的；
- 本地每条打卡有「**已上传**」标记（跟订单的 `dirty` 一样），推成功后清掉；
- **打完卡 2 秒内**就会推一趟（老板在后台很快能看到），不用等 25 秒那趟定时；
- 设置页「待上传 N」现在**也把没上传的打卡算进去**；
- 「重置同步状态」会把员工名单和所有打卡重新标成「要推」（走 upsert，不会重复记账）。

**万一后台还没建那两张表**（404）：考勤那一步会**单独跳过**并提醒一句，
**订单/菜单照常同步** —— 收银优先，不能因为没跑 SQL 把整个同步搞挂。

### 3. 后台网页多了「考勤」页

`supabase/admin.html` 多了一个标签「**考勤**」：
本周表（员工 × 周一到周日，绿=上班 / 蓝=下班）+ 出勤天数 + 本周工时，
底下有 ‹ 上一周 / **本周** / 下一周 › 可以翻周；再下面还有员工名单（姓名 + PIN）。
「导出备份」也把员工名单和打卡一起导出去了。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `supabase/schema.sql` | 新增 `attendance_staff`（+`touch_staff()` 触发器、RLS）、`attendance_punches`（+两个索引、RLS）；自检段改成「4 张表 + 4 个函数」 |
| `lib/models/employee.dart` | 新增 `PunchKind`（in/out）；`AttendancePunch` 加 `id`/`kind`/`pushed`；新增 `PunchOutcome.needClockIn`、`PunchResult.worked`（老数据没 kind → 当「上班」；没 id → 用员工+时间推一个稳定 id，同步不会重复记账） |
| `lib/state/attendance_controller.dart` | `punch(pin, kind:)` 支持下班；`clockInAt/clockOutAt/workedOn/weekWorked/daySummary`；`onStaffChanged/onPunchesChanged` 钩子；`staffSnapshot/replaceStaffFromServer/adoptServerPunches/unpushedPunches/markPunchesPushed/markAllPunchesUnpushed` |
| `lib/services/attendance_sync.dart`（新） | 纯逻辑：`staffToRow/staffFromData`、`punchToRow/punchFromRow/punchCreatedAt`、`shouldPullStaff`、`RemoteStaff` |
| `lib/services/sync_service.dart` | 注入 `AttendanceController`；新增 `_syncAttendance()`（名单按版本、打卡按 id 并集）；`_pullOrders` 抽成通用 `_pullRows`（订单/打卡共用、都翻页）；打卡水位线 `_punchSince`；两个新钩子；考勤失败**单独跳过**；`resetSyncState` 也重置考勤 |
| `lib/data/settings_store.dart` | 加 `staffVersion` / `staffDirty`（读、写、键都加了） |
| `lib/app.dart` | 改成 `ChangeNotifierProxyProvider3`（多接一个 AttendanceController）+ 接上考勤那两个钩子 |
| `lib/widgets/clock_in_dialog.dart` | 支持上班/下班两种（标题颜色、文案、下班显示工时）；「还没签到」用橙色提示 |
| `lib/screens/attendance_screen.dart` | 两个大按钮（签到 + 下班）；今天列表「上班 → 下班」；本周表格子上下两行（绿/蓝）+ 工时列 + 图例 |
| `lib/utils/format.dart` | 加 `durationHm()`（9:25）和 `hoursDecimal()`（38.5） |
| `lib/l10n/app_strings.dart` | 三语补 `attendance.clockOut/doneOut/alreadyOut/needClockIn/worked/hours/legendIn/legendOut` + `sync.attendanceTableMissing` |
| `supabase/admin.html` | 新增「考勤」标签页（本周表 + 翻周 + 员工名单）；打卡按 `created_at` 增量拉；导出备份带上考勤 |
| `setup_supabase.md` | §2 写清「老项目要重跑 SQL、会有 4 张表」；§5 加考勤页；排错表加两条 |
| `test/attendance_test.dart` | 扩到 26 组：下班（没签到被拦、重复下班、工时、时间段反了算 0）、工时统计、`punchAt` 拆成 `clockInAt/clockOutAt`、同步小接口（标已上传 / 采纳服务器那份 / 整体替换名单） |
| `test/attendance_sync_test.dart`（新） | 8 组纯逻辑：名单 JSON 往返与坏数据、打卡行不带 `created_at`、老数据兼容、稳定 id、`shouldPullStaff` 三种情况 |
| `test/sync_service_test.dart` | 假服务器补上两张考勤表；新增 5 组：名单+打卡都会推、下班推上去（kind=out）、别人打的卡拉下来且不重推、服务器名单版本更高就替换、**404 时订单照常同步只提醒一句** |

### 你要试的

1. **先在 Supabase 里重跑 `supabase/schema.sql`**（Table Editor 里应该多出 `attendance_staff`、`attendance_punches` 两张空表）；
2. `flutter test`；
3. `flutter run -d windows` → 签到页加两个人（张三 1234、李四 5678）；
4. 点**签到** → 输 1234 → 成功；点**下班** → 输 1234 → 成功，提示里应有「今天工作了 X:XX」；
5. 直接点**下班** → 输 5678（今天没签到过）→ 应橙字提示「今天还没签到」；
6. 设置 → 后台同步 → 打开开关填好 → **立即同步** → 应显示 `↑N ↓M · 待上传: 0`；
7. 打开后台网页 → 「**考勤**」标签 → 应看到本周表（今天那格上下两个时间）+ 工时 + 员工名单；
8. 换台设备（或点「重置同步状态」再同步）验证员工名单能拉到另一台；
9. 断网打卡 → 设置页「待上传」+1 → 联网自动补推 → 后台能看到。



