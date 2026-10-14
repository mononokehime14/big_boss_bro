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
网口打印机
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


---

## 本轮改动（2026-10-11）：结账窗口第 ① 步 —— **打印和收款解绑**

**问题（你说的）**：原来第 ① 步只有一个 `确认并打印`，**必须先打出纸才能进收款界面**。
实际用起来很不顺手：打完单子去忙别的，回来还得**再打一遍**才能结账。

**新流程**（照你说的做）：

1. 点订单里的**结账** → 还是那个窗口（左边 30% 明细、右边 70% 应收 + 折扣）；
2. 右下角**两个按钮**：
   - 左：**`打印单子`** —— 打纸（明细 + 合计，含刚设的折扣），**留在本界面**，
     按钮变成 `再打一张`，右下角多一行绿字 **`已打印 14:32`**；
   - 右：**`确认`** —— **直接进第 ② 步收款**（**打没打过纸都行**）；
   - **「取消」按钮去掉了**（要退出点标题栏右上角那个 ✕）。
3. 第 ② 步收款还是老样子：应收 / 收款币种 / 现金或刷卡 / 大字找零 →
   点 `确认收款` 落账、窗口关闭（**收款这一步不打纸**）。
4. 第 ② 步的 `返回上一步` 还在：可以回去改折扣、补打一张，改完再点 `确认` 回来。

**几个明确的取舍**：

- **打纸是「想打就打」**：不打印也能结账（收银员自己决定打几次），
  所以「打完单子去干活 → 回来直接确认收款」这条路径成立了。
- **`已打印 HH:MM` 只是提示**，不参与任何判断 —— 免得又变成新的「必须先干某件事」的锁。
- **第 ② 步会提醒一句**「还没打单子（要打就返回上一步）」，但**不拦着**（灰字小提示）。
- **打不出来**（没纸/没连）还是老规矩：弹「重试打印 / 跳过，不打印」；
  跳过也**留在第 ① 步**，可以点 `确认` 先收款、回头再补打。
- 结账只记一笔账、打纸次数由收银员决定，所以**同一张单可能出两张纸**（重复点就是重打），这是有意的。

**主要改动文件**

| 文件 | 改了什么 |
| --- | --- |
| `lib/widgets/payment_flow.dart` | 第 ① 步按钮换成 `打印单子`（`OutlinedButton.icon`）+ `确认`（`FilledButton.icon`）；`_confirmAndPrint` 拆成 **`_printBill`**（打纸、留在本界面、成功标 `_printedAt`）和 **`_goToPayment`**（进第 ② 步）；新增字段 `_printedAt` 和 `_hint()`；打印内容抽成 `_billToPrint()`（临时贴上屏幕上的折扣） |
| `lib/l10n/app_strings.dart` | zh/es/en 三语各加 5 条：`checkout.printBill / printAgain / printed / confirm / notPrinted`；`checkout.step1` 改成「核对明细与折扣（打印可选，也可以直接点确认）」 |
| `test/checkout_flow_test.dart`（新） | 4 组 widget 测试：第 ① 步只有那两个按钮、**没打过纸也能点「确认」进收款**、点「打印单子」留在本界面且能再打一张、返回上一步后「已打印」标记还在 |

**你要试的**：
点任一桌的「结账」→ 点 **`打印单子`**（纸出来，窗口**不关也不跳**，按钮变 `再打一张`）→
**在这儿停一会儿**（去干别的再回来）→ 直接点 **`确认`** → 输实收/看找零 → `确认收款` →
订单进「已结单」，**并且不会再出第二张纸**。
另外试一次：**一次都不打纸**，直接 `确认` → 收款 → 也能正常结账（收款界面会有一句灰字提醒）。


---

## 本轮改动（2026-10-11 第二次）：界面文案瘦身（去掉解释性提示，**功能一行没动**）

**原则**：只删「解释给人听」的文字（段落 / tip / 步骤标题 / 输入框里的例子占位），
**所有能点的控件、按钮名字、状态信息、报错信息全留着**。收银员天天看的页面优先清理。

### 删掉的文案（三语都删）

| 位置 | 原文案 | 处理 |
| --- | --- | --- |
| 购物车下面 | `cart.buttonsHint`「保存：只记到单上，不打单 · 厨房：把没下厨的菜打给厨房」 | 整行删掉（按钮名字够清楚） |
| 桌号/外卖状态行 | `cart.takeawayHint`「外卖每单独立：保存 / 厨房都会开新单」 | 删掉；外卖没开单时**这块不显示任何字**（原来显示说明） |
| 菜品定制框 · 特别备注 | `custom.note.multi`「可以加好几条：填一条 → …」 | 删掉（只剩「特别备注」小标题 + 输入框 + `加进备注`） |
| 同上 | `custom.note.hint`「例如：不要香菜」（输入框占位） | 删掉（左边标题已经说了这是什么） |
| 同上 | `custom.note.saveTag`「把这条备注存为常用标签」 | 缩短成「**存为常用标签**」（勾选框留着，功能不变） |
| 自定义金额框（备注那格） | `custom.dialog.noteHint`「这条备注会当菜名打在小票 / 厨房单上」 | 删掉（备注空着时的报错还在，照样会提醒） |
| 外卖起名框 | `takeaway.name.why`（一长段「起名有啥用」） | 整段删掉 |
| 外卖起名框 | `takeaway.name.hint`「例如：张三 / 车牌 123」 | 删掉占位 |
| 电话外卖等待时间 | `takeaway.wait.hint`「填了就打在厨房单上（例：20）」 | 删掉（标签「等待时间（分钟）」够了） |
| 结账窗口 | `checkout.step1`「① 核对明细与折扣（…）」 / `checkout.step2`「② 收款」 | **步骤标题整个去掉**（`_stepTitle()` 方法也删了） |
| 结账窗口 | `checkout.notPrinted`「还没打单子（要打就返回上一步）」 | 删掉（上一轮加的那句灰字提醒） |
| 结账窗口 · 刷卡 | `checkout.cardNote`「刷卡机成功后，点下面的按钮」 | 删掉（银行卡动画上那句 `请刷卡 / 插卡 / 挥卡` 留着） |
| 结账窗口 · 币种 | `checkout.rateWhere`「（汇率在「菜品管理」里改）」 | 删掉括号那句；**汇率那行数字留着**（收银员要核对） |
| 签到页 | `attendance.clockInHint`「点大按钮 → 输你的 4 位 PIN…」 | 删掉（两个大按钮自己写着「签 到 / 下 班」） |
| 购物车空的时候 | `cart.empty`「购物车是空的，点上方菜品开始点单」 | 缩短成「**购物车是空的**」 |

### 特意**没**动的（怕你要，说一声就删）

- 控件自己的文字：`特别备注` / `加进备注` / `存为常用标签` / `保存` / `厨房` / `确认` / `打印单子` …；
- 状态和报错：`空桌` / `已有 N 件` / `未下厨 N` / `最后一道菜不能删` / 打印失败那几个框 / `备注不能空` …；
- 「自定义」那道菜下面的 `点一下：填金额 + 备注`（它占的是**价格那一格**，删了会空一块）；
- **设置页 / 菜品管理 / Excel 导入 / 账号 / 考勤管理**里那些 `*.hint` 长说明（后台同步、小票编码、
  厨师单字体、税率、汇率说明、导入列规则…）—— 这些是给管理员看的「说明书」，平时不占屏幕。
  **要一起瘦身的话说一句**，那些基本都是纯解释，删起来一样安全。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/widgets/cart_panel.dart` | 删掉两个按钮下面那行说明；外卖状态行改成「没单就不显示」 |
| `lib/widgets/item_customize_dialog.dart` | 特别备注区去掉长说明和占位；备注输入框只留边框 |
| `lib/widgets/custom_item_dialog.dart` | 备注输入框去掉 `helperText` |
| `lib/widgets/takeaway_name_dialog.dart` | 起名框去掉整段说明 + 两个占位/辅助文字 |
| `lib/widgets/payment_flow.dart` | 去掉两个步骤标题（顺带删掉 `_stepTitle()` 和 `_hint()`）；刷卡说明、汇率那行的括号说明删掉 |
| `lib/screens/attendance_screen.dart` | 签到页去掉底部那行长说明 |
| `lib/screens/settings_screen.dart` | 常用备注为空时不再显示「例如：不要香菜」 |
| `lib/l10n/app_strings.dart` | 三语各删 14 条、改 2 条（`cart.empty` / `custom.note.saveTag`）；三份 map 键数仍然一致（各 395 条） |
| `test/checkout_flow_test.dart` | 原来断言 `② 收款` 那两处改成断言收款按钮（步骤标题没了） |

**你要试的**：点单页 / 菜品定制框 / 结账窗口 / 签到页各看一遍 —— 应该只剩标题、按钮、数字，
没有解释性小字；所有按钮、状态、报错跟以前**一模一样**。


---

## 本轮改动（2026-10-11 第三次）：厨师单顶部 —— **外卖打名字 / 号 + 电话外卖打等待时间（特大字）**

**你要的**：原来顶上只有「外卖 / 电话外卖 / 堂食桌子」。
现在**外卖 / 电话外卖**要多打：**名字**（没起名字就打**系统给的号**），
**电话外卖**还要打**等待时间**，而且这行要**特大号**（跟最上面的「厨师单 1 / 2」一样大）。

### 改后的样子（58mm，默认 2 张）

**堂食（没变）**
```
        厨师单 1              ← 特大（双倍宽 + 双倍高）
  桌号 5 · 堂食   10-10 13:45  ← 大（双倍高）
```

**外卖（有名字）**
```
        厨师单 1              ← 特大
          张三                 ← ★ 新：名字，特大
   外卖 · 10-10 13:45          ← 大（原来就有）
```

**外卖（没起名字）**
```
        厨师单 1              ← 特大
           #3                 ← ★ 新：系统给的号（当天第几号外卖），特大
   外卖 · 10-10 13:45
```

**电话外卖**
```
        厨师单 1              ← 特大
          张三                 ← ★ 新：名字 / 号，特大
       等待 20 分钟             ← ★ 新：等待时间，特大（以前是「大」）
   电话外卖 · 10-10 13:45
```

### 规则（`buildKitchenRows` ①b / ②b）

| 单子类型 | 顶上那行特大字 |
| --- | --- |
| 堂食 | **不打**（第 ②行「桌号 5 · 堂食」里已经有桌号） |
| 外卖（有名字） | 名字（`Order.label`） |
| 外卖（没起名字） | `#号`（`Order.dailyNo`，系统给的当天第几号） |
| 外卖（老数据既没名字也没号） | 这行不打 |
| 电话外卖 | 同外卖，**再加一行**「等待 N 分钟」（`Order.waitMinutes` > 0 才有） |

- 字号走新的 `_headline()`：**能放下就特大（双倍宽高），放不下自动退回「大」**（只双倍高）——
  58mm 特大一行只有 16 列，「等待 20 分钟」= 12 列放得下；名字太长就自动变小，不会被切、也不会被打印机折行。
- 顺带把顶部标题也换成同一个 `_headline()`，行为跟以前一模一样（少了一段重复代码）。

### 顺手修的一个**真 bug**（不修的话这个功能在点单页上打不出来）

`payment_flow.dart` 的 `_submitOrder()` 打厨房单时是**临时造一张 Order**（只放这次没下厨的菜），
原来**没把 `label` / `dailyNo` / `waitMinutes` 抄过去** → 从点单页点「厨房」打出来的票，
顶上永远没有名字 / 号 / 等待时间。现在这三样跟着票一起走。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/receipt_layout.dart` | `KitchenData` 加 `isTakeaway` / `orderLabel` / `dailyNo`；`buildKitchenRows` 加 **①b 名字/号**、**②b 等待时间改特大**；新增 `_headline()` / `_headlineScale()`（标题也用它们） |
| `lib/services/ticket_builder.dart` | `kitchenLines()` 把 `order.isTakeaway` / `order.label` / `order.dailyNo` 交给排版 |
| `lib/widgets/payment_flow.dart` | **修 bug**：打厨房单的临时 Order 补上 `label` / `dailyNo` / `waitMinutes` |
| `lib/models/order.dart`、`lib/state/pos_controller.dart` | 只改注释（`dailyNo` 以前写着「厨房单不打这个号」，现在会打） |
| `test/receipt_layout_test.dart` | 新增 7 组：外卖打名字 / 打号、都是**特大**、等待时间也是特大、没填就不打、堂食不打这行、长名字不爆行 |
| `kitchen_ticket.md` | 补上「外卖 / 电话外卖」的样子和规则表；「想两个都打（`张三 #3`）」「想永远特大」怎么改 |

**你要试的**（打三种单各看一眼）：

1. **外卖单**（保存时起了名字，例如「张三」）→ 点「厨房」→ 票顶应该有**特大**的 `张三`；
2. **外卖单**（保存时点「不用名字」）→ 票顶应该是**特大**的 `#3`（当天第几号）；
3. **电话外卖**（填等待 20）→ 票顶是名字 / 号 + **特大**的「等待 20 分钟」；
4. **堂食**→ 跟以前一样（只有桌号，没有多出来的行）。

> 想改成「名字和号都打」（例如 `张三 #3`）：`receipt_layout.dart` ①b 那三行换个拼法就行，
> 现成的 `Order.takeawayTag` 就是干这个的（`kitchen_ticket.md` §5 有例子）。


---

## 本轮改动（2026-10-11 第四次）：厨师单顶部再调 + 菜品居中特大 + **修「备注被 cut」的 bug**

### 1. 顶部（外卖 / 电话外卖）

你要的样子（现在就是这样）：
```
         厨师单 1              ← **大**（原来是特大）
   外卖 10-10 13:45            ← **特大**（票面上最大的一行；原来是「大」）
           张三 / #3            ← **特大**（原来是"跟标题一样大"）
        等待 20 分钟            ← 特大（电话外卖才有）
```
- 顺序也按你画的：**标题 → 「外卖 + 时间」→ 名字/号 → 等待时间**。
- 宽度是硬的：58mm 特大一行只有 16 列。「外卖 10-10 13:45」正好 16 列 → 特大 ✅；
  「电话外卖 10-10 13:45」（20 列）、堂食「桌号 5 · 堂食 10-10 13:45」（25 列）放不下 →
  **自动退回「大」**（不会切字）。所以外卖那行**用的是空格不是「·」**，多那 3 列就放不下了。

### 2. 菜品：**菜名居中 + 特大**（顺手修掉一个让菜名只剩 3 列的老 bug）

- **菜名在数量右边居中**（原来左对齐，挤在数量旁边、右边空一大片）。
- **菜品字号默认改成「特大」**（`Settings.kitchenFontSize` 默认 2 → 3）。
  设置页那一项还在：想换回「大」就点一下（58mm 用「大」菜名字数多一倍）。
- ⚠️ **修的真 bug**：`buildKitchenRows` 原来先把整张票的列数按菜品字号缩一遍（`kitchenColumns`），
  菜品行又用 `columnsFor()` 缩了一遍 → **特大档下菜品行只剩 3 列**，菜名被砍成一两个字
  （「餐品挤成一团」的根源）。现在：**普通字号的行用纸张原始列数（58mm = 32）**，
  只有放大的行才按字号换算。
- 菜名太长 → **折到下一行**（整行居中），**不再截断**。

### 3. 你报的 bug：选项 + 备注挤一行，备注被 cut ✅ 已修

原来 `OrderLine.detail` 把「选项 + 备注」拼成一行（`Grande · 不要香菜`）再按纸宽**截断** ——
备注排在最后，一超长整条都没了（厨房看不到"不要香菜"）。

现在（`_detailLines()` + 新的 `_wrapToWidth()`）：
```
2     牛肉炒饭          ← 菜品（特大、居中）
  Grande                ← 选项：单独一行、普通字号、**一条一行**
  不要香菜               ← 备注：单独一行
  少放辣                 ← 再来一条就再来一行
```
- **一条一行**，每条都缩进 2 列；
- 太长就**折行**（优先在空格处断，中文按字符断），**一个字都不丢**；
- 这些行用**普通字号、整张纸宽**（58mm = 30 列可用），不再被菜品行的半宽挤掉。
- 顾客小票上的备注也一起改成折行了（同一个毛病）。

### 4. 「字体能换成 Arial 吗？」—— **不能直接换**，答案写在 `kitchen_ticket.md` §3.0

ESC/POS 热敏机的字库在**打印机固件**里，没有可替换的字体文件（蓝牙 / 网口 / Windows USB
这三条通道都是把 ESC/POS 字节原样丢给打印机）。最接近 Arial 的做法是
**设置 → 小票编码改 `cp850` + 小票语言 Español/English** → 走打印机自带的**西文字库**
（干净的无衬线点阵，就是我们参考图那种观感）；代价是**中文菜名会变 `?`**。
真要 Arial（含中文）就得改成**位图打印**（App 里把票画成图片再发点阵）——
那是另一个大改动，要做跟我说。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/receipt_layout.dart` | `buildKitchenRows` 重排：①标题（大）②「地点+时间」（特大）③名字/号（特大）④等待时间（特大）⑤菜品（数量在左、**菜名居中**、字号按设置）；**每行按自己的字号算列数**（修双重缩放 bug）；新增 `_wrapToWidth()` / `_detailLines()`（选项、备注一条一行 + 折行）；`_headline(..., preferred:)` 支持"标题固定大"；小票备注也改成折行 |
| `lib/data/settings_store.dart` | `kitchenFontSize` 默认 **2 → 3（特大）**（两处：构造函数 + 读取兜底）；注释写清 58/80mm 的差别 |
| `lib/l10n/app_strings.dart` | 「厨师单字体大小」的说明改成「特大：长菜名会折到下一行；58mm 建议用大」（三语） |
| `test/receipt_layout_test.dart` | 顶部按新字号重测（标题大 / 地点时间特大 / 名字在时间下面）；新增「选项+备注一条一行、备注不再被 cut」「超长备注折行不丢字」；「菜品行占满 16 列」（锁那个双重缩放 bug）；原来的"菜名从同一列开始"改成"菜名居中、中心列对齐"；超宽检查改成**按每行自己的字号** |
| `kitchen_ticket.md` | §0 版式图全部重画 + 字号规则表；§2 加了 4 条新旋钮；§3.0 回答 Arial；§4 补「每行按自己的字号算列数、别缩两次」 |

**你要试的**（还是打四种单）：

1. 外卖（有名字）：`厨师单 1`（大）→`外卖 10-10 13:45`（特大）→`张三`（特大）→ 菜品**特大居中**；
2. 外卖（没名字）：名字那行是 `#3`；
3. **点一道菜 → 选定制项 → 再加两条特别备注** → 厨房单上应该是：定制项一行、每条备注各一行，
   **一条都不少**（这就是你报的 bug）；
4. 电话外卖：多一行「等待 20 分钟」（特大）。

> 如果菜品看起来还是「大」不像「特大」：去 **设置 → 厨师单字体大小** 点一下「特大」
> （我把默认值改成特大了，但以前存过的老设置优先）。58mm 纸觉得挤就点回「大」。


---

## 修（2026-10-11 第五次）：**设置里的「厨师单字体大小」整个删掉**，菜品字号写死「特大」

**你说的**：厨师单的字号不要在设置里改，代码里定死菜品特大。

### 改了什么

1. **菜品字号写死在代码里**：`receipt_layout.dart` 新增
   `const kKitchenItemScale = TicketScale.xlarge;`（特大 = 双倍宽 + 双倍高），
   排版里直接用它；列数用新的 `kitchenItemColumns(纸宽)`（58mm = 16、80mm = 24）。
2. **设置项删干净**（不是藏起来）：
   - `settings_screen.dart`：删掉「厨师单字体大小」那个下拉（**「厨师单打印份数」保留**）；
   - `settings_controller.dart`：删掉 `setKitchenFontSize()`；
   - `settings_store.dart`：删掉字段 `kitchenFontSize`、旧键 `kitchen_font_size` 的读写
     （老设备里存过的值留着不管，读的时候忽略 —— 不会崩，也不会再影响打印）；
   - `app_strings.dart`：删掉三语的 `settings.kitchenFont` / `.hint` / `.normal` / `.large` / `.xlarge`；
   - `escpos.dart`：删掉 `TicketScale.fromKitchenFontSize()`（设置没了，映射也没用了）。
3. **测试页**那行 `KitchenFont set to N` 改成 `Kitchen items: XLARGE (16 cols)`（顺便核对列数）；
   三档字号预览 `1 normal size / 2 LARGE / 3 XLARGE` 保留（还是用来验证打印机认不认 `GS ! n`）。

### 修掉你贴的那个报错

`test/settings_test.dart` 里那条「厨师单字体大小默认 2 = 大」的断言现在没意义了
（字段和设置都没了），已经删掉；`test/escpos_test.dart` 里 4 条 `fromKitchenFontSize` 的断言
也一起删了。`test/receipt_layout_test.dart` 整个改成按"菜品固定特大"来测：
58mm 菜品行必须**占满 16 列**、80mm 占满 24 列、每行不超过**自己字号**的列数。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/receipt_layout.dart` | 新增 `kKitchenItemScale`（特大）和 `kitchenItemColumns()`；`KitchenData` 去掉 `fontSize`；删掉 `kitchenWidthScale()` / `kitchenColumns()` |
| `lib/services/escpos.dart` | 删掉 `TicketScale.fromKitchenFontSize()`；枚举注释改成"厨师单哪几行用哪档" |
| `lib/data/settings_store.dart`、`lib/state/settings_controller.dart`、`lib/screens/settings_screen.dart` | 删除「厨师单字体大小」设置的字段 / 键 / 存取 / 下拉框 |
| `lib/services/ticket_builder.dart` | `kitchenLines()` 不再传 `fontSize`；测试页那行改成 `Kitchen items: XLARGE (16 cols)` |
| `lib/l10n/app_strings.dart` | 三语各删 5 条与该项设置有关的文案（三份 map 仍然 390 条，对齐） |
| `test/settings_test.dart`、`test/escpos_test.dart`、`test/receipt_layout_test.dart` | 删掉/改掉跟着设置的断言；菜品行按"固定特大"重测 |
| `kitchen_ticket.md` | 「菜品字号」那几格改成"写死在 `kKitchenItemScale`，设置页已无此项" |

**你要试的**：`flutter test` 应该全绿；设置 → 打印机 里**看不到**「厨师单字体大小」了
（份数还在）；打一张厨房单，菜品行照旧是**特大**（这个行为本身没变，只是不再能调）。


---

## 本轮改动（2026-10-11 第六次）：**小票（结账单）的「合计」那一行加大加粗**

**你要的**：结账时打给客人的单子，Total 这一行要**加大加粗**。

### 改了什么

小票以前是「一行行纯文本」（`buildReceiptLines` 返回 `List<String>`），
所以**没法只放大一行**。现在改成跟厨房单一样的做法 —— **一行带自己的字号和字重**：

| 之前 | 现在 |
| --- | --- |
| `buildReceiptLines()` 返回 `List<String>` | `buildReceiptRows()` 返回 `List<TicketRow>`（含 `scale` / `bold`）；`buildReceiptLines()` 保留成"只要文本"的旧接口（测试在用） |
| `TicketRow`（原来的 `KitchenRow` 改的名，小票/厨房单共用） | 一行 = 文本 + 字号 + 是否加粗；`TicketBuilder` 把它翻成 `TicketLine(text, scale:, bold:)` |
| 合计行 = 普通字号、普通字重 | **特大（双倍宽高）+ 加粗**，上下还是两条横线 |

**合计行怎么定字号**（`buildReceiptRows` 最后那段）：
- 先试 **特大**（双倍宽 + 双倍高，58mm 一行只有 16 列）；
- 「标签 + 至少一格 + 金额」放不下就**自动退回「大」**（只加高、列数不变）——
  例：中文「合计 ¥61.00」= 11 列 → 特大 ✅；西语「Importe adeudado $61.00」= 23 列 → 退回「大」✅。
  所以**三种语言都不会切字**，而且金额永远贴右边缘（占满整行）。
- 加粗走 `ESC E 1`（跟厨房单菜品行同一套指令）。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/receipt_layout.dart` | `KitchenRow` → **`TicketRow`**（小票/厨房单共用）；新增 **`buildReceiptRows()`**（合计行加大加粗 + 自动降级），`buildReceiptLines()` 变成它的纯文本包装 |
| `lib/services/ticket_builder.dart` | `receiptLines()` 改用 `buildReceiptRows()`，把每行的 `scale` / `bold` 传给 `TicketLine` |
| `test/receipt_layout_test.dart` | 新增 4 组：合计行**加粗 + 特大**、别的行仍是正常字号、占满整行且金额贴右、西语标签太长时**自动退回「大」**、每行不超自己字号的列数 |
| `kitchen_ticket.md` | §4 的 `KitchenRow` 改成 `TicketRow`；小票那段补一句"只有合计行放大加粗" |

**你要试的**：结账窗口点「打印单子」→ 纸上的**合计那一行应该又高又粗、金额贴右边**；
别的行（明细、店头、谢谢光临）跟以前一模一样。别的语言（西语/英语）也打一张，
看合计行是不是**没有被切字**（西语会小一号，那是故意的 —— 放不下就退回「大」）。


---

## 本轮改动（2026-10-11 第七次）：界面瘦身 —— 点单页 + 订单页（**只删显示，功能一条没动**）

你提的四条，逐条对应：

### 1. 菜品格子：**只剩菜名**（`menu_grid.dart`）

- 删掉格子下面那行价格（`¥140.00 / 份`）和「自定义」格子的「点一下：填金额 + 备注」；
- 价格在**点开后的「点菜」框**里写得清清楚楚（单价 + 合计），格子上不用再写一遍；
- 小角标留着（`可选规格` / `2 份起` / `卖出 N`）—— 它们不是价格，是"这道菜有讲究"的提醒；
  要一起去掉说一声。

### 2. 点单页左右比例改成 **7 : 3**（`pos_screen.dart`）

`Expanded(flex: 7, MenuArea)` + `Expanded(flex: 3, CartPanel)`（原来是 6 : 4）。

### 3. 购物车面板（`cart_panel.dart`）

| 删掉的东西 | 原来长什么样 |
| --- | --- |
| 目标状态那一行 | `已有 3 件 · 未下厨 1`（没单时是`空桌`）—— 整行不要了 |
| 「已在单上」小标题 | `已在单上   31 件` —— 标题整行不要了（下面的行自己带「已下厨 / 未下厨」标签） |
| 桌号小标题 | 下拉框上面那行 `桌号` 两个字（下拉里每一项自己就写着「桌号 5 / 外卖」） |

> 「本次新增 N 件」那个小标题**留着**（旁边挂着「清空」按钮，是操作入口）。

### 4. 订单卡片：**一条单只剩一行**（`orders_screen.dart`）

```
[桌号 5]  2×牛肉炒饭，1×可乐，3×Taco…        [🗑]  [结账]
  ↑桌号/外卖名字·号（不变）   ↑餐品一行、超出省略号   ↑按钮（不变）
```

| 删掉 | 说明 |
| --- | --- |
| 单号 | `单号 20261011-003` 整行 |
| 时间 | `🕐 2026-10-11 13:45` 整行（那一行原来还带**支付方式**，见下面） |
| 金额 | 右上角那个大号 `¥550.00` |
| 折扣 / 税 明细行 | 有折扣/税时多出来的那行（金额信息，跟你说的"取消金额显示"一致） |
| 外币明细行 | `USD 1 = ¥18.50 · 应收 $31.15 · 实收 $40.00 · 找零 $8.85` |
| 等待时间那一行 | 电话外卖的 `⏱ 等待 20 分钟` → 挪到右边**一行小灰字**里 |

- **保留**：桌号 / 外卖名字·号的小绿标签、餐品摘要（**一行，超出用 `…` 省略**）、
  删除 + 结账按钮、`未上传` 橙色小标记，以及右边那行小灰字（电话外卖的等待时间、
  已结单的支付方式 —— 它们不是单号/时间/金额，而且是收银员要看的）。
- 卡片上下内边距 12 → **6**、列表间距 10 → **6**、删除按钮用了 compact 密度
  → 一条单大概从 150px 高降到 ~50px，一屏能多放两三倍。
- 顺手删掉两个用不到的私有方法（`_foreignLine` / `_formatTime`）和 `format.dart` 的 import。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/widgets/menu_grid.dart` | 格子只画菜名（删掉价格 / 「点一下填金额」那行） |
| `lib/screens/pos_screen.dart` | 左右分栏 6:4 → **7:3** |
| `lib/widgets/cart_panel.dart` | 删 3 处文字（状态行 / 已在单上标题 / 桌号小标题）；`_targetSelector()` 去掉不再用的 `unsent` 参数 |
| `lib/screens/orders_screen.dart` | 订单卡片改成**一行**；删单号/时间/金额/折扣税/外币明细；`_foreignLine()`、`_formatTime()` 删除 |
| `lib/widgets/cart_sheet.dart` | 只改一句注释（分区标题没了） |

**你要试的**：点单页 — 格子只有菜名、左右大约 7:3、购物车上面干净了（下拉 + 菜 + 合计 + 两个按钮）；
订单页 — 每条单只有一行，`桌号 + 餐品…+ 删除/结账`，一屏能放很多张。

> 说明：`discount/tax/外币` 这些明细从**订单列表**里去掉了（小票上和「日结」里都还在）。
> 要是想在列表上留个"这单打过折"的小标记，说一声我加。


---

## 修（2026-10-11 第八次）：订单页**编译不过** —— `timeShort` 找不到

**报错**：
```
lib/screens/orders_screen.dart:104:73: Error: The method 'timeShort' isn't defined for the type '_SyncButton'.
```

**原因（我的锅）**：上一轮把订单卡片里的金额/明细删掉之后，我顺手删了 `orders_screen.dart`
里那行 `import '../utils/format.dart';` —— 当时只查了 `money(` 这个用法，**漏了同一个文件里
顶栏「同步」按钮用的 `timeShort()`**（打印「上次同步 2026-10-11 09:05」用的）。

**修法**：把那行 import 加回来（并加了一句注释说明"顶栏同步按钮要用它"）。

**顺手做的全仓自查**（免得还有同类漏网）：
按"用了 `format.dart` / `pricing.dart` / `escpos.dart` / `receipt_layout.dart` /
`receipt_print_service.dart` / `app_strings.dart` 里的东西却没 import"扫了 `lib/` + `test/`
（**剥掉注释再扫**，免得注释里提到函数名误报）：

- 真正的问题只有上面这一个 ✅ 已修；
- 两条"命中"是误报：`app_strings.dart` 里英文文案 `collect money` 里的单词 money；
  `menu_manage_screen.dart` 的 `kCashCurrencies` 其实 import 自 `models/order.dart`（不是 pricing.dart）。

**改动文件**：`lib/screens/orders_screen.dart`（+1 行 import）。

**你要试的**：`flutter test` 现在应该能编译过了（这次我改了 import，还是没法在本地跑，麻烦你跑一下）。


---

## 本轮改动（2026-10-11 第九次）：常用备注能删能管 / 桌号按顺序 / **自定义排序（拖动）**

### 1. 常用备注（设置页）：先选种类 → 看 / 删 / 加

以前一进设置页就是「通用」那个种类，看不出"现在在管谁"；现在：

- 下拉框**一开始什么都不选**，写着「选择一个种类」（`settings.notes.pickCategory`）；
- **选了一个种类**才显示它的备注：一条一个标签，**点后面的 ✕ 直接删**（叉叉放到 18，
  鼠标悬停有提示「删除：xxx」）；
- 没选种类时输入框和「添加」按钮**是灰的**（避免把备注存到"不知道哪个种类"下）；
- 选中的种类没有备注时给一句「这个种类还没有备注」，不再是一片空白。

> 删除功能其实**一直都有**（标签上的 ✕），只是列表默认停在「通用」、又没有任何提示，
> 所以看不出来。现在把流程和提示都摆明了。`settings.notes.category` 那句小标题也就去掉了。

### 2. 桌号列表：按**自然顺序**排（点单页 + 设置页）

- 新增 `utils/menu_sort.dart` 的 `naturalCompare()` / `sortedTables()`：
  **数字段按数值比、文字段按字母比**（大小写不敏感）→ `1 2 9 10 A B C S-A S-B`；
- 点单页桌号下拉、设置页「桌号管理」都走它 —— **存的是什么顺序都不影响显示**。

### 3. **自定义排序**（第四种排序方式，拖动排序）

排序条多了第 4 个：`默认 / 首字母 A-Z / 流行度 / **自定义**`。选「自定义」后：

- 每个格子**长按拖起来**，放到另一个格子上就换位置（种类、菜品都能拖，
  例如把「饮料」拖到第一位）；
- 拖动时被拖的格子变淡、落点描一圈白边，看得清会落到哪儿；
- 顺序存在 `Settings.menuOrder`（**本机**，跟着"这台设备的排序方式"走，不参与云端同步）；
- 顺序表里同时装**种类 id 和菜品 id**，屏幕上一次只看得到一组（所有种类 / 某个种类下的菜），
  所以拖动只重排"这一组"，别组的顺序原样不动（`applyVisibleOrder()`）；
- 没排过的（新导入的菜 / 从没拖过）**排在最后，并保持菜单原本的先后**
  （`sortByCustomOrder()` 用"下标 + 大偏移"当名次，因为 Dart 的 sort 不稳定）；
- 内置的「自定义」种类 / 那道「自定义」菜**不给拖**（它永远排最后），但可以拖到它上面
  （= 排到倒数第二）。

⚠️ **一处取舍**：菜品格子原来是「长按 = 快速加一份」，现在**自定义排序模式下长按归拖动用**
（不然会一边拖一边加菜）；其它三种排序方式下长按快速加一份照旧。排序条右边也写了提示
「长按格子拖动排序」。

还有一个贴心处理：**第一次**从别的排序切到「自定义」时，会先把**当前屏幕上的顺序**
（`PosController.currentOrderSnapshot()`）存成自定义顺序的起点 ——
不然一切过去就跳回菜单原本的顺序，看着像"排序丢了"。之后再拖只改你拖的那几个。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/utils/menu_sort.dart` | `MenuSort.custom`；`sortCategories/sortMenuItems` 多一个 `order` 参数；新增 `sortByCustomOrder()`；新增拖动用的 `moveBefore()` / `applyVisibleOrder()`；新增桌号用的 `naturalCompare()` / `sortedTables()` |
| `lib/widgets/reorderable_cell.dart`（新） | `ReorderableCell`：把格子包成"长按可拖 + 可当落点"，只在自定义模式下生效，其它模式**原样返回** |
| `lib/widgets/category_grid.dart`、`lib/widgets/menu_grid.dart` | 用 `ReorderableCell` 包住格子；把 `settings.menuOrder` 传给排序；拖动后写回顺序 |
| `lib/widgets/menu_area.dart` | 排序条改成遍历 `MenuSort.values`（4 个）；自定义模式右边显示「长按格子拖动排序」 |
| `lib/data/settings_store.dart`、`lib/state/settings_controller.dart` | 新字段 `Settings.menuOrder` + 键 `menu_order`（JSON 数组）+ `setMenuOrder()` |
| `lib/state/pos_controller.dart` | `categoriesSorted()` / `itemsSorted()` 多一个 `order` 具名参数 |
| `lib/screens/settings_screen.dart` | 常用备注区改成「先选种类 → 看/删/加」；桌号管理按自然顺序显示 |
| `lib/widgets/cart_panel.dart` | 桌号下拉按自然顺序显示 |
| `lib/l10n/app_strings.dart` | 三语各加 5 条：`menu.sort.custom` / `menu.sort.custom.hint` / `settings.notes.pickCategory` / `settings.notes.pickFirst` / `settings.notes.none` |
| `test/menu_sort_test.dart` | 新增 2 组：「自定义排序」（顺序表 / 空表 / 拖动 / 写回全局表）和「桌号的自然顺序」（1,2,9,10 / 数字在前 / 大小写 / 不改原表） |

**你要试的**：

1. **常用备注**：设置 → 常用备注 → 下拉选一个种类 → 应该看到那个种类的备注，点 ✕ 能删掉；
   输入一条新的点「添加」。不选种类时输入框和按钮是灰的。
2. **桌号顺序**：点单页 → 购物车上面那个下拉 → 桌号应该是 `1 2 … 9 10 A B C …` 这种顺序。
3. **自定义排序**：点单页排序条选「**自定义**」→ **长按**某个种类格子拖到第一个 →
   松手后它就到第一位了（重启/切回来还在）。点进某个种类里，菜也能这么拖。
   ⚠️ 这个模式下长按不再"快速加一份"（改回其它排序方式就恢复了）。


---

## 本轮改动（2026-10-11 第十次）：拖动排序并进「默认」/ 格子再瘦身 / 汇率搬到设置 / 菜品管理能改定制项

### 1. 拖动排序**并进「默认」**（不再有单独的「自定义」那一档）

- 排序条回到 **3 档**：`默认 / 首字母 A-Z / 流行度`；
- **「默认」= 本机记住的顺序**：一开始就是菜单原本的顺序（Excel 导入的），
  用户**长按拖动格子**之后就按拖出来的顺序 —— 顺序存在 `Settings.menuOrder`（本机，
  **不上云**，跟"这台设备怎么看菜单"一样属于设备偏好）；
- 拖只在「默认」下有效（首字母 / 流行度是算出来的顺序，拖了没意义）；
- 选了「默认」时排序条右边写一句「长按格子拖动排序」（不然没人知道能拖）；
- **老设备无缝**：以前存过 `'custom'` 的，`MenuSort.fromId()` 现在一律当「默认」——
  默认用的就是那张顺序表，所以拖好的顺序**不会丢**；
- 顺带**去掉了**上一轮那个"第一次切到自定义时先把当前顺序存成起点"的逻辑（不需要了：
  默认一直就是那张表）。

### 2. 格子进一步瘦身

- **角标全去掉**：菜品格子上的「可选规格」「2 份起」「卖出 N」，
  种类格子上的「N 件 · 已卖 M」—— 格子上**只剩名字**；
- **格子变小**：菜品 210 → **150**（宽高比 1.25 → 1.4）、种类 240 → **190**（1.7 → 2.0），
  间距 12 → 10；一屏能放下的格子明显更多；
- **名字超了就省略号**，格子**不会为了显示全而变大**：
  名字最多 2 行 + `TextOverflow.ellipsis`，外面还有 `FittedBox(scaleDown)` 兜底，
  所以既不会溢出（黄黑条纹），也不会把字切掉。

> **格子大小是怎么定的**（你问的）：`GridView` 的 `SliverGridDelegateWithMaxCrossAxisExtent`
> 给一个**最大宽度**（150 / 190），系统按可用宽度算出**列数**，每列宽度 = 可用宽度 ÷ 列数；
> **高度 = 列宽 ÷ `childAspectRatio`**。所以格子大小是"配置出来的固定值"，
> 跟名字长短**无关**。

### 3. 币种与汇率：从「菜品管理」搬到**设置页**

- 设置页新增一节 **币种与汇率**（就在「税」下面，都是钱的事）：本位币下拉 + 各币种汇率输入框，
  改完立刻保存、清空 = 没设汇率（收款时那个币种是灰的）；
- 「菜品管理」里那一整节**删掉**了，连带 `settings.rateWhereHint` / `settings.rateGo`
  那两句"汇率在菜品管理里改 / 去改汇率"的文案也删了（信息已经不成立了）。

### 4. 菜品管理：能改「基础价格 / 基础数量 / 定制项」了

以前只能改 菜名 + 价格 + 单位，Excel 导进来的**基础数量**和**定制项**改不了。现在新增
`lib/widgets/menu_item_edit_dialog.dart`（独立弹窗），一道菜可以改：

| 字段 | 说明 |
| --- | --- |
| 名称 / 基础价格 / 单位 | 跟以前一样 |
| **基础数量** | Excel 的「基础数量」列（2 份起那种）；空着 = 1 |
| **定制项** | 一个定制项 = **组名 + 若干选项**，每个选项能写**加价**（`Size: Mediano +140 / Grande +185`）；可以**加/删组**、**改组名**、**加/删选项**、**改选项名和加价** |

- 保存时**空组、名字空着的选项会自动丢掉**（不留空壳）；
- 只有一个选项（或 Yes/No 两行）的组仍然是「**加料开关**」的语义（点单时默认不加钱，
  小票上打组名）—— 弹窗里有一句提示说明；
- 菜品列表的副标题也跟着显示全了：`¥140.00 / 份 · 2 份起 · 定制项 2`。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/utils/menu_sort.dart` | 删掉 `MenuSort.custom`（老 id 走 `fromId` → 默认）；**默认排序**改用 `order`（本机顺序）；`sortByCustomOrder` 改名叫"本机顺序"的说明 |
| `lib/widgets/menu_area.dart` | 排序条回到 3 档；「默认」下显示拖动提示；去掉切到自定义时的"起点"逻辑 |
| `lib/widgets/category_grid.dart`、`lib/widgets/menu_grid.dart` | 拖动只在「默认」下生效；**去掉所有角标**；格子变小；名字 2 行省略号 |
| `lib/state/pos_controller.dart` | 排序方法注释更新；删掉不再用的 `currentOrderSnapshot()` |
| `lib/screens/settings_screen.dart` | 新增「币种与汇率」一节（含汇率输入框、本位币下拉）；常用备注那节保持上一轮的改法 |
| `lib/screens/menu_manage_screen.dart` | 删掉汇率那一节（连带 `_rateCtls`/`_rateRow` 等）；改用新的菜品编辑弹窗；菜品副标题加「N 份起 · 定制项 N」 |
| `lib/widgets/menu_item_edit_dialog.dart`（新） | 菜品编辑弹窗：名称 / 基础价格 / 单位 / 基础数量 / 定制项（组名 + 选项 + 加价，都能增删改） |
| `lib/l10n/app_strings.dart` | 加 10 条（`menu.sort.dragHint`、定制项编辑那一套 `menu.itemMinQty` / `itemOptions` / `noOptions` / `addOptionGroup` / `optionGroupName(.Hint)` / `optionName` / `optionPrice` / `addOption` / `optionToggleHint`），删 3 条（`menu.sort.custom(.hint)`、`settings.rateWhereHint`、`settings.rateGo`），恢复 `menu.rates.hint`（三语各一份，键数仍然对齐：397） |
| `test/menu_sort_test.dart` | 「自定义排序」那组改成「**默认排序 = 本机记住的顺序**」，加一条"老 custom 当默认"的迁移用例 |

**你要试的**：

1. **拖动**（默认排序下就能拖，不用再切模式）：长按一个种类 → 拖到第一位 → 松手；
   重启后顺序还在。切到「首字母」再切回「默认」，顺序应该还是你拖过的那个。
2. **格子**：菜品格子上应该只剩名字、格子比之前小一圈；名字长的显示 `…`。
3. **设置页**：找到「币种与汇率」，改一下 USD 的汇率 → 结账收款框里那个币种的金额应该跟着变；
   「菜品管理」里**不再有**汇率那一节。
4. **菜品管理**：点一道菜的编辑 → 能看到**基础数量**和**定制项**：
   加一个定制项（组名 `Size`）、里面加两个选项（`Mediano` / `Grande`，加价 `140` / `185`）→
   保存 → 去点单页点这道菜，点菜框里应该出现这两个选项和加价。


---

## 本轮改动（2026-10-11 第十一次）：字体放大 / **菜品昵称** / 自定义的常用备注 / 自定义框调顺序

### 1. 字体放大，格子只大一点点

| 位置 | 之前 | 现在 |
| --- | --- | --- |
| 菜品格子的名字 | 16 | **19** |
| 种类格子的名字 | 20 | **24** |
| 购物车行的菜名 | 14 | **16** |
| 购物车行的「单价 · 点击可改」 | 12 | **13** |
| 购物车行右边金额 | 14 | **16** |
| 菜品格子尺寸 | 最大宽 150、1.4 | 最大宽 **175**、**1.35** |
| 种类格子尺寸 | 最大宽 190、2.0 | 最大宽 **215**、**1.9** |

> **要不要写死？**（你问的）现在就是**写死的两个数**：`GridView` 的
> `SliverGridDelegateWithMaxCrossAxisExtent`（最大宽度）+ `childAspectRatio`（宽高比）。
> **不建议写死"每排 5 个"**：那样在大屏上格子会被拉得很宽、手机上又挤成小方块；
> 现在这样是"格子保持差不多大小，屏幕宽就多排几个" —— 常见的收银机窗口宽度下正好
> **一排 5 个左右**。想永远 5 个也就一行改动（换 `SliverGridDelegateWithFixedCrossAxisCount`）。

### 2. **菜品昵称**（Excel 新列）

规则照你说的：**点单界面 + 厨师单显示昵称；顾客小票永远打全名**；昵称留空 = 两边都用全名。

- `MenuItem.nickName`（Excel 的「菜品昵称」列）+ `MenuItem.displayName`（有昵称用昵称）；
- `OrderLine.nickName`（下单时的**快照**，跟菜名/单价一样）—— 老单子不会因为菜单改了而变；
- 显示昵称的地方：点单页格子、购物车行、点菜框标题、结账窗口左边明细、**厨师单**；
- 显示全名的地方：**顾客小票**（`buildReceiptLines` 用 `name`）、订单列表里的餐品摘要、
  菜品管理列表的标题（副标题里另外写了「菜品昵称: xxx」，方便核对）；
- 菜单云同步自动带上（`menu` 表存的就是 `toJson()` 整份，不用改表结构）。

#### ⚠️ 顺手修了一个会让**整张菜单都导入错**的坑

新的表头是：`种类 | 菜品名字 | **菜品昵称** | 基础价格 | 基础数量 | 定制项1 | 选项 | 选项价格 | 定制项2 | …`。

「菜品昵称」这个表头里**有「菜品」两个字**，而且它右边紧跟着定制项 —— 老代码**认不出它**，
于是把它当成"一组定制项的名字列"、把「定制项1」当成它的**选项**：
**每道菜都会多出好几组乱七八糟的定制项，价格和选项全歪**（我按代码逐列走过一遍，
确认会歪）。现在 `_isNickHeader()` 认它并且**在「菜名」之前**占住这一列（顺序很关键）。

### 3. Excel 里**三组**定制项：能认，测试也没写死数量

- 导入器本来就是"剩下几列就按三列一组一直切下去"（**不定数量**），所以 3 组、4 组都没问题；
- 我把你的真实表（`data/palacio_royal_09_12_2026.xlsx`）扒开数了一遍：
  14 列、定制项 1/2/3 都在，**157 行数据里 99 行有第 1 组、38 行有第 2 组、9 行有第 3 组**，
  70 行填了昵称 ✓；
- 测试里**没有**写死"只能有几组"这种断言；唯一接近的是"抽一道菜（VERDURA CANTONES）
  应该有 1 组 Size"—— 你表里那道菜确实只有 1 组 ✓ 不会挂；
- 顺手**加了两组测试**：①「菜品昵称」列被正确认出来、且没被当成定制项；
  ② 一个菜**三组定制项**都能认（组名 / 选项 / 每组价格都对得上）；
  ③ 真实表那组测试里补了"昵称规则"和"样例里存在 2 组 / 3 组的菜"的断言。

### 4. 常用备注能管「自定义」那一类 + 自定义框顺序对调

- 设置 → 常用备注 的下拉里**多了「自定义」**（就是内置那一类）——
  点「自定义」时那个框读的就是它（`notesFor(kCustomCategoryId)`，本来是读得到、
  但设置页里没法管理，现在补上了）；
- 点单页点「自定义」时的框：**先填特别备注，再填金额**（原来金额在前）——
  常用备注标签和「存为常用标签」跟着备注走，回车从备注跳到金额。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/models/menu_item.dart` | 新字段 `nickName` + `displayName`；JSON 读写 / `copyWith` 都带上 |
| `lib/models/order.dart` | `OrderLine.nickName`（快照）+ `displayName`；JSON 读写 / `copyWith` |
| `lib/services/menu_importer.dart` | 新增 `_isNickHeader()` / `_Layout.nickCol`，**在菜名之前占住昵称列**；读进 `nickName`；表头打分也算上昵称 |
| `lib/state/pos_controller.dart` | 生成订单行时带上 `nickName`（下单 + 追单两处） |
| `lib/widgets/menu_grid.dart` | 名字用 `displayName`、字体 19、格子 175/1.35；长按提示也用昵称 |
| `lib/widgets/category_grid.dart` | 字体 24、格子 215/1.9 |
| `lib/widgets/cart_panel.dart` | 购物车行 / 已在单上行的**菜名用昵称**、字体放大（16 / 13） |
| `lib/widgets/payment_flow.dart` | 结账明细用 `displayName`（收银员看的） |
| `lib/services/receipt_layout.dart` | 厨师单菜品行用 `displayName`（小票仍然用 `name`）；注释写清两边区别 |
| `lib/widgets/custom_item_dialog.dart` | **备注在前、金额在后**；加了 `_amountFocus` 做回车跳转 |
| `lib/screens/settings_screen.dart` | 常用备注下拉加「自定义」一类 |
| `lib/widgets/menu_item_edit_dialog.dart`、`lib/screens/menu_manage_screen.dart`、`lib/screens/menu_import_screen.dart` | 菜品编辑框加「菜品昵称」；列表副标题显示昵称；导入页的示例/说明改成新表头 |
| `lib/l10n/app_strings.dart` | 三语各加 2 条（`menu.itemNick(.Hint)`）；`menu.import.hint` 改成新列说明（键数仍然对齐：397） |
| `test/menu_importer_test.dart` | 新增 3 组（昵称列 / 三组定制项 / 没有昵称列时的回退）+ 真实表那组补断言 |
| `test/receipt_layout_test.dart` | 新增 1 组 4 条：**厨师单打昵称、小票打全名**、没昵称两边都用全名、`displayName` 规则 |

**你要试的**：

1. **重新导入一次 Excel**（表里已经有「菜品昵称」列了）→ 点单页格子 / 购物车 /
   厨师单上应该是**昵称**（`L #1` 这种）；**打印的顾客小票上是全名**。
2. **菜品管理**：列表副标题里能看到「菜品昵称: L #1」；点编辑能改昵称。
3. **三组定制项**：像 `Caldo De Verdura` 那种菜（Size + con Noodle + con Hefen），
   点单时应该三组都能选、加价都对。
4. **设置 → 常用备注** → 下拉最下面有「自定义」→ 选它、加两条备注 →
   点单页点「自定义」→ **备注框在上面**，下面能看到那两条标签，再填金额。
5. **字体/格子**：格子和购物车里的字应该明显大了；格子比上一轮大一点点、一屏还是 5 个左右。


---

## 修（2026-10-11 第十二次）：`receipt_layout_test` 里那条**我自己写错的断言**

**报错**：`菜品昵称：厨师单用昵称、顾客小票用全名 › 没昵称时两边都用全名` 挂了：

```
Expected: contains 'Chop Suey Pollo'
Actual:   '1     Chop Suey \n     Pollo      '
```

**原因**：**不是功能 bug，是断言写错了**。厨师单的菜品是**特大**字号，58mm 一行 16 列，
减去数量列 5 列 → **菜名只剩 11 列**；`Chop Suey Pollo`（15 列）放不下，
就按既定规则**折成两行**（优先在空格处断、整行居中）——**一个字都没丢**。
我却要求它在一行里连续出现。

**修法**：断言前先把空白/换行去掉（`flat()`）再比内容，并把"折行是正常的"写进注释；
另外两条断言（厨房单打昵称、小票打全名）本来就没问题，保持原样。

**改动文件**：`test/receipt_layout_test.dart`（只改测试，产品代码没动）。

> 📌 顺带说明：**58mm + 特大字号下，长菜名必然折行**（15 列以上就会）。
> 想让长菜名一行放下，只有两条路：把菜品字号调回「大」（32 列），或者换 80mm 纸（24 列）。


---

## 本轮改动（2026-10-11 第十三次）：**结账变成一个页面**

以前是"两步走"：第 ① 步核对 + 打单 → 第 ② 步收款。现在**一个页面全部搞定**，
不用再翻页，右边也不用重复显示一遍金额。

### 新的结账窗口

```
┌──────────────────────────┬──────────────────────────────────────────┐
│ 单子明细  6件             │  应收  $660.00 MXN      ← 跟着币种变的大字 │
│ ────────────────────      │                                          │
│ 2 × Chop Suey     ¥320    │  折扣  [不打折][按百分比][减金额]          │
│   加辣                    │        （选了百分比还有 5/10/15/20% 快捷键）│
│ 1 × Coca         ¥30      │                                          │
│ …（可滚动）…              │  收款币种  [MXN 本位币][USD 16.5][RMB 未设汇率]│
│ ────────────────────      │                                          │
│ 小计            ¥550.00   │  支付方式  [现金][刷卡]                    │
│ 折扣 -¥50.00    -¥50.00   │  ┌ 实收 (MXN) ────────┐ [正好][600][700] │
│ 税 (已含税)      ¥80.00   │  └────────────────────┘                  │
│ 合计            ¥660.00   │  找零  $40.00                            │
├──────────────────────────┴──────────────────────────────────────────┤
│                                [ 🖨 打印单子 ]   [ 确认收款 ]        │
└─────────────────────────────────────────────────────────────────────┘
```

1. **小计 / 折扣 / 税 / 合计挪到左边清单底部**（你说的）：右边就省出一块地方给操作；
   它照样**跟着右边的操作实时变**（折扣、币种都会反映上去）。
   顺手修了个小毛病：折扣那一行的说明文字以前读的是**订单上存的**折扣
   （要收款成功才落账，这会儿还是空的）→ 现在读**窗口里当前选的**，能正常显示 `10%` / `-¥20.00`。
2. **收款币种 + 支付方式搬到同一页** → 结账一个页面搞定，原来第 ② 步整段没有了。
3. **收款币种的按钮瘦身**：只剩 **币种码 + 汇率** —— `MXN 本位币` / `USD 16.5` / `RMB 未设汇率`
   （没设汇率的那个点不动）；原来每个按钮里的"换算后应收"和下面那行汇率提示**全删了**。
4. **应收直接按收款币种显示**：`应收 $660.00 MXN` / `应收 $40.00 USD`（大小和颜色跟以前一样），
   换币种时**这个数字直接变**，不再另写一行换算。
5. **现金的快捷金额搬到实收框右边**：`[实收] [正好] [600] [700]`
   （原来在下面单独一行；那个单独的「正好」按钮也去掉了 —— 快捷标签第一个就是它）。
6. 右下角按钮变成**两个**：`打印单子`（打完留在本界面、可以再打）和 `确认收款`
   （现金还差钱时是灰的；**刷卡时不再看实收框**，免得先输过现金再切刷卡就点不动）。
   `返回上一步` 和 `确认` 这两个按钮跟着步骤一起没了。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/widgets/payment_flow.dart` | `build()` 重写成一个页面：左边 `_linesPane()` 底部加 `_breakdown()`；右边顺序改成 应收 → 折扣 → 币种 → 支付方式 → 收款；`_dueBig()` 改成显示**选中的币种**；`_currencyChip()` 瘦身成「币种 + 汇率」；删掉 `_rateHint()`、`_step`、`_goToPayment()`、`返回上一步`；实收框右边跟快捷金额；新增 `_discountText()` |
| `lib/l10n/app_strings.dart` | 删 2 条（`checkout.back`、`checkout.confirm`）；结账那段注释改成"一个页面"（三语仍对齐：395） |
| `lib/services/receipt_print_service.dart`、`lib/services/print_service.dart` | 只改注释（"第 ① 步" → "结账窗口里"） |
| `test/checkout_flow_test.dart` | 4 条测试按新交互重写：一页只有那两个按钮、**折扣/币种/支付方式/实收找零都在同一页**、没打纸也能直接收款、打印后标记还在（切支付方式也不丢） |

**你要试的**：点任一桌的「结账」→

1. 左边最下面应该是**小计/合计**；改右边的折扣，左边的数字**立刻跟着变**；
2. **应收那行**换币种会直接变（`应收 $40.00 USD`），币种按钮上只有币种码和汇率；
3. 实收框**右边**就是快捷金额（正好 / 邻近整数），下面是大字找零；
4. 只有 `打印单子` + `确认收款` 两个按钮：不打纸直接收款也行；打了纸按钮变「再打一张」，
   上面还会标「已打印 HH:MM」。


---

## 修（2026-10-11 第十四次）：`checkout_flow_test` 里那条新测试 —— **不能对有循环动画的界面用 `pumpAndSettle`**

**报错**：`打过纸的标记：同一页上切支付方式也还在` 失败。

**原因**：**不是产品 bug，是测试写法**。刷卡时那个银行卡动画
（`lib/widgets/bank_card_anim.dart`）是 `AnimationController(..)..repeat()` —— **无限循环**；
切到「刷卡」之后再 `await tester.pumpAndSettle()`，它在等一个**永远不会静止**的界面，
于是超时失败（`pumpAndSettle timed out`）。

**修法**：这条测试里切完支付方式只 `pump()` 两帧（一帧处理点击、一帧画新状态），
并在注释里写明"刷卡动画是循环的，不能用 pumpAndSettle"，免得以后又踩。

> 顺带记住这条规矩：**只要屏幕上有 `repeat()` 的动画（银行卡动画、加载转圈之类），
> 就不能用 `pumpAndSettle`**，要用 `pump()` / `pump(duration)`。

**改动文件**：`test/checkout_flow_test.dart`（只改测试，产品代码没动）。


---

## 本轮改动（2026-10-11 第十五次）：结账标题带名字和等待时间 / 进行中两种排序 / **整体放大字号**

### 1. 结账窗口标题：外卖把**名字和等待时间**也写上

标题右边那个小标签以前只写类型，现在：

| 单子 | 标签内容 |
| --- | --- |
| 堂食 | `桌号 5` |
| 外卖 | `外卖 张三 #3`（名字 / 号都带上） |
| 电话外卖 | `电话外卖 张三 #3 · 等待 20 分钟`（等待时间跟厨房单上打的一模一样） |

用的就是 `Order.takeawayTag`（`名字 #号`）和 `waitMinutes`，跟订单页那张卡片一个来源。
标签字号 12 → 15，一眼能看清。

### 2. 「进行中」订单：两种排法（列表上面两个小开关）

| 排法 | 规则 |
| --- | --- |
| **按位置**（默认） | **外卖 → 电话外卖 → 桌子**；桌子按**桌号清单的顺序**（`1 2 … 9 10 A B C`，跟点单页那个下拉一致）。组内：外卖/电话外卖按「当天第几号」`#1 #2 …`；清单里没有的桌号排最后（按名字自然顺序） |
| **按时间** | **最近保存 / 下厨房的在最上面**（用 `Order.updatedAt`：追单、改份数、改备注都会刷新 → 收银员要找的"我刚动过的那张"永远在最上面） |

- 新增纯逻辑文件 `lib/utils/order_sort.dart`：`OrderSort` 枚举 + `sortInProgressOrders()`；
- 键一样时（同一张桌两张单）**保持原来的先后**（Dart 的 `sort` 不稳定，这里把原下标当最后一级键）；
- 选择存在设置里（`Settings.orderSort`，键 `order_sort`）——**只存本机、不上云**（跟 `menuSort` 一样）；
- 开关只出现在「进行中」那一页（已结单的按时间倒序就够了）；一张单都没有时开关也不显示。

### 3. 字号整体放大（**你可以自己改，位置在下面**）

这一轮放大的是"天天看"的关键信息：

| 位置 | 之前 → 现在 |
| --- | --- |
| 订单卡片：桌号 / 外卖名字 | 14 → **18**（内边距也加大） |
| 订单卡片：餐品行 | 13 → **15**；右边小字 12 → **13** |
| 购物车：菜名 | 16 → **18**；选项/备注 13 → **14**；单价行 13 → **14**；行金额 16 → **18** |
| 购物车：底部合计 | 标签 16 → **18**、金额 22 → **26** |
| 结账：应收大字 | 30 → **34** |
| 结账：左边清单菜名 / 明细 / 金额 | 13 / 10.5 / 13 → **15 / 12 / 15** |
| 结账：小计·合计那几行 | 13 → **15**，合计那行 15/16 → **17/19** |
| 结账：找零大字 | 40 → **44** |
| 菜品格子名字 | 19 → **22**（格子 175 → 190、比例 1.35 → 1.3） |
| 种类格子名字 | 24 → **28** |

> **「这个我可以自己改吗」——可以，就是几个写死的数字**。想自己调的话改这几处
> （`fontSize:` 后面那个数就是字号）：
>
> - 订单页：`lib/screens/orders_screen.dart` 里 `_OrderCard` 的 `fontSize: 18 / 15 / 13`；
> - 购物车：`lib/widgets/cart_panel.dart` 里 `_CartLine` / `_PlacedLine` 的 `fontSize: 18 / 14`、
>   底部合计的 `18 / 26`；
> - 结账窗口：`lib/widgets/payment_flow.dart` 的 `_dueBig()`（34）、`_lineTile()`（15 / 12 / 15）、
>   `_row()`（15 / 17 / 19）、找零那块（44）；
> - 格子：`lib/widgets/menu_grid.dart`（`fontSize: 22` + `maxCrossAxisExtent: 190`、
>   `childAspectRatio: 1.3`）、`lib/widgets/category_grid.dart`（`fontSize: 28` + `215` / `1.9`）。
>
> 改完 `flutter run` 热重载就能看到（改格子大小那几个数要一起调：字变大 → 格子也要大一点，
> 否则格子里的 `FittedBox` 会把内容缩回去）。
>
> 也可以**做成设置项**（一次调全部，像"小 / 正常 / 大"）：技术上就是在
> `lib/app.dart` 外面套一层 `MediaQuery(textScaler: ...)`。我没直接做，是因为有几处
> 是按固定尺寸手工调过的（尤其两个格子的"防溢出"钳制），全局放大会需要跟着一起改；
> **你要的话我加上**。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/utils/order_sort.dart`（新） | `OrderSort`（position / time）+ `sortInProgressOrders()` + 稳定的排序实现 |
| `lib/screens/orders_screen.dart` | 按设置里的排法排「进行中」；新增 `_InProgressSortBar`（两个 ChoiceChip）；`_OrderList` 支持 `header`；卡片字号放大 |
| `lib/data/settings_store.dart`、`lib/state/settings_controller.dart` | 新字段 `Settings.orderSort` + 键 `order_sort` + `setOrderSort()` |
| `lib/widgets/payment_flow.dart` | 标题栏带上外卖名字 / 号 / 等待时间；应收 34、清单和总计字号放大、找零 44 |
| `lib/widgets/cart_panel.dart` | 购物车行 / 已在单上行 / 底部合计的字号放大 |
| `lib/widgets/menu_grid.dart`、`lib/widgets/category_grid.dart` | 格子字号放大（格子也略大一点） |
| `lib/l10n/app_strings.dart` | 三语各加 2 条：`order.sort.position` / `order.sort.time`（仍对齐：397） |
| `test/order_sort_test.dart`（新） | 7 组用例：外卖→电话外卖→桌子、桌号自然顺序、外卖按号、清单外桌号排最后、按时间（含"追单后冒到最上面"）、两种排法都不改原列表、同位置保持原先后 |

**你要试的**：

1. 结账一张**外卖单 / 电话外卖单** → 标题右边应该写着 `外卖 张三 #3` / `电话外卖 张三 #3 · 等待 20 分钟`；
2. 订单页「进行中」→ 上面两个开关：切「按位置」= 外卖 → 电话外卖 → 桌子（桌号按顺序）；
   切「按时间」= 刚保存 / 刚下厨房的那张在最上面（重启后还记得你选的哪个）；
3. 各页看字号：订单卡片、购物车、结账窗口、种类 / 菜品格子。


---

## 本轮改动（2026-10-11 第十六次）：订单卡片重排（金额大字 / 按钮永远靠右）/ 已结单按日期范围+金额 / 日结能核对 / 图标 + 启动画面

### 1. 订单卡片：一单一行，重新排过

从左到右固定成：

```
[桌号 / 外卖名字（电话外卖带等待时间）]  [金额大字]  [菜名…]  [支付方式]  [未上传]  [删除]  [结账]
```

- **结账 / 删除按钮永远贴着最右边**。你说的"有时不在最右边、好像是菜名长度决定的"，
  真因是这一行里**有两块弹性区域**（菜名 `Expanded` + 右边小字 `Flexible`，两个都是 `flex: 1`），
  再加上左边那个标签**没有宽度上限**（外卖名字长就无限撑）→ 窗口一窄 / 菜一多，
  Flutter 就让这一行溢出，右边两粒按钮被挤出可视区域或被压变形。
  现在**只有中间那段菜名是弹性的**，其余全部是固定宽度或**有上限**的宽度 →
  不管菜名多长，右边的按钮都在原来的位置上：
  - 左边标签上限 240（窗口窄时 150），超了在标签里省略；
  - 右边小字上限 170；
  - 窗口宽度 < 700（手机那种）**自动减内容**：不显示"支付方式"和"未上传"两个小字，标签也收窄。
- **金额大字（24 号粗体）**：紧跟桌号 / 名字后面，两个标签页都有
  （进行中 = 这一单现在的应收；已结单 = 实收）。金额用 `Order.total`——
  每次改单都会按折扣/税重算（`price.total`），加了菜马上就是新价。
- **电话外卖的等待时间**从最右边挪进左边标签里：`电话外卖 张三 #3   20 分钟`（橙色）。
  以前它挤在最右边，菜名一长就被省略掉，最需要看的时候反而看不见。
- 已结单右边那点小字还是支付方式（现金 / 刷卡 / 混合）。

### 2. 「已结单」页：**日期范围** + 两种排法

列表上面多了一条：

| 控件 | 说明 |
| --- | --- |
| 日期按钮 | 默认 **全部日期**；点开是系统日期范围选择器（`1 号到 3 号`，**两头都算**，3 号 23:59 结的单也算在内）；选了之后按钮变成 `2026-10-01 ~ 2026-10-03`，右边出现 ✕ 一键回到全部 |
| **按时间**（默认） | **结账确认时间由近到远**（今天结的最上面）。老数据没有 `closedAt` 就用开单时间 |
| **按金额** | **金额由大到小**；金额一样时最近结账的在前面 |
| 末尾的「单数 N」 | 当前筛出来几张，跟标签页括号里的数字一致 |

- 排法存在本机（`Settings.closedSort`，键 `closed_sort`），跟"进行中"那个开关一样**不上云**；
- 日期范围**不落盘**（打开订单页默认就是全部看得见，想只看几天时再挑）；
- 排序 / 筛选条**一张单都没有时也留着**：筛没了得能改回来（以前空列表会整条藏起来）。

### 3. 日结：**汇总逻辑没动**，但补了一处时间显示 + 加了"当天单子明细"

你报的"今天没有任何结单，但还是显示有很多数字"——**钱和单数的算法是查过的、是对的**
（营业额按订单算、收款按每一笔付款算；"某一天"= `closedAt ?? createdAt` 的**本机日历日**）。
能解释你看到的现象的有两点，其中第 1 条是真问题、已修：

1. **开着过零点不刷新（已修）**：以前页面上的日期是 `initState` 里定死的 →
   收银台**开着过了半夜**，页面上还是**昨天**那一天的数字，看着就是"今天啥也没干却一堆数"。
   现在没手动挑过日期就每次刷新重算"今天"；手动挑过的一直停在你挑的那天
   （点右上角日期再选一天即可换成别的）。
2. **改过系统时区（不是 bug，是数据边界）**：本机存的时间是"墙上时间"
   （本地时间、不带时区信息），而"今天"是拿**现在的**时钟算出来的 →
   换了时区之后，"今天"这个 24 小时窗口会和老单子记的墙上时间**错开一个时差**
   （中国 ↔ 墨西哥差 14 小时），于是"昨天傍晚"的单会落进"今天"里。
   **钱没算错，是分组边界跟着时钟挪了**；按新时区结的单从现在起一切正常。
   要彻底免疫得把时间存成 UTC（带时区），这会动到存盘格式和云同步，**没动**——
   你说过"逻辑没问题就不用改"，需要的话我再单独做。

为了让你**一眼核对**，日结下面加了「**当天结单明细**」：这一天算进来的每一单
（时间 / 桌号·外卖 / 支付方式 / 金额），条数跟上面的「单数」对得上。
哪天觉得数字不对，对着这张表看时间就知道是哪些单被算进来了。
（版式：上面两块卡占 3，明细占 2。）

### 4. 应用图标 + 启动画面

**图标**（用 `assets/bbb_log.png`，从短边方形裁切）：

- Android：五个 mipmap `ic_launcher.png` = 48 / 72 / 96 / 144 / 192（5 KB ~ 56 KB）；
- Windows：`windows/runner/resources/app_icon.ico` = 16 / 32 / 48 / 64 / 128 / 256 六个尺寸
  （手写的 32bpp DIB，370 KB）；
- 生成脚本 `tool/make_icons.ps1`，以后换图重跑：
  `powershell -File tool/make_icons.ps1`（或 `& .\tool\make_icons.ps1`），
  换源图加 `-Source 别的.png`。
  > 踩坑记录：这个脚本里有中文，**必须存成带 BOM 的 UTF-8**，
  > 否则 Windows PowerShell 5.1 会按 ANSI 读、把中文字符串读坏直接语法报错。
- ⚠️ **图标是编进 exe / APK 的**：热重载看不到，要**重新 build / 重新 run**。
  Android 桌面如果还是老图标，重启手机或卸载重装一下。

**启动画面**（`lib/app.dart` 里的 `_SplashGate` + `_SplashView`）：

- 白底居中显示 `assets/bbb_log_chinese.png`（带"大生意，大哥大！"那张，图里已经有字，不用另加）；
- **最少显示 1.2 秒**（`_SplashGateState._minShow`，想改快/改慢就改这一个数），
  并且要等"设置 + 账号"从本机读回来才进主界面（不然会先闪一下登录页 / 默认值）；
- 解码用 `cacheWidth: 760`（显示 380 逻辑像素 × 2 倍屏）→ 解码后的位图从 ~6 MB 降到 ~2 MB。
- ⚠️ **文件名对一下**：你说的是 `assets/bbb_logo_chinese.png`，
  实际磁盘上是 **`assets/bbb_log_chinese.png`**（少一个 `o`），代码里用的是实际那个；
  另外还有个 `assets/bbb_logo_with_title.png` 目前没被用到。

> **PNG 怎么处理才高效（你问的）**：
>
> - **影响运行时内存的是"解码后的位图"，不是文件大小**：1254×1254 × 4 字节 ≈ 6.3 MB。
>   所以 `Image.asset(..., cacheWidth: 760)` 这类**按需解码**是最有效的一招（我们现在就这么用）；
> - **影响安装包 / 仓库大小的是文件本身**：1.5 MB 的 PNG 转 **WebP**（同画质通常小 5~10 倍）
>   或直接降到 512~760 px 都能明显变小，对界面没影响；要我顺手做就说一声；
> - 别给 logo 用 `filterQuality: high` 之类的大缩放（费 GPU），`medium` 足够；
> - 小图标（格子、角标那种）也用 `cacheWidth`，别拿 1000px 的图去显示 40px。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/screens/orders_screen.dart` | 改成 `StatefulWidget`（装日期范围）；卡片重排：**金额 24 大字**、等待时间挪进左边标签、**只有菜名是弹性的** → 删除/结账永远靠右；窄窗口自动减内容；新增 `_SortChip` / `_Bar` / `_ClosedFilterBar`（日期范围 + 两种排法 + 张数）；空列表也显示排序条 |
| `lib/utils/order_sort.dart` | 新增 `ClosedSort`（time / amount）、`sortClosedOrders()`、`filterOrdersByDateRange()`、`closedOrCreatedAt()`；内部排序键从 `int` 放宽到 `num`（金额有小数） |
| `lib/utils/order_label.dart`（新） | `orderPlaceLabel()` / `orderPaymentLabel()`：桌号·外卖标签和支付方式文字，**订单页和日结共用同一份**（免得两处写法对不上） |
| `lib/screens/daily_summary_screen.dart` | 日期不再定死（跨零点自动跟"今天"；手动挑过就停在你挑的）；支出输入框跟着换天；新增 `_DayOrdersList`（当天结单明细）；上面两块卡 3 : 明细 2 |
| `lib/data/settings_store.dart`、`lib/state/settings_controller.dart` | 新字段 `Settings.closedSort` + 键 `closed_sort` + `setClosedSort()` |
| `lib/app.dart` | 新增启动画面 `_SplashGate` / `_SplashView`（中文 logo，最少 1.2 秒，等设置 + 账号读回来） |
| `tool/make_icons.ps1`（新） | 用 `assets/bbb_log.png` 生成 Android 五个 mipmap + Windows `.ico`（六个尺寸） |
| `lib/l10n/app_strings.dart` | 三语各加 4 条：`order.sort.amount` / `order.dateRange.all` / `order.dateRange.pick` / `summary.dayOrders`（三语仍对齐：**401** 条） |
| `test/order_sort_test.dart` | 新增两组：已结单两种排法（含"金额一样看结账时间"、"老数据用开单时间"）、日期范围筛选（两头都算 / 只给一头 / 都不给 / 空结果） |
| `test/widget_test.dart` | 启动画面会先显示 → 冒烟测试里要把时间推过 1200ms 才看得到登录页（加了 `pump(1400ms)`） |

**你要试的**：

1. **订单页「进行中」**：挑一张菜名很长的单 → **结账 / 删除永远贴在卡片最右边**；
   桌号右边就是**金额大字**；电话外卖的等待时间在左边标签里（橙色）；
   已结单右边小字是支付方式。
2. **「已结单」**：点日期按钮选 `X 日 ~ Y 日` → 只剩那段日子的单，标签页括号和「单数」跟着变；
   切「按金额」= 大单在上面；点 ✕ 回到全部日期。
3. **日结**：看新加的「当天结单明细」是不是跟「单数」对得上；
   开着这一页过零点的话日期会自动变成新的一天。
4. **图标 / 启动画面**：图标要**重新 build** 才看得到；启动画面重启 app 就能看到
   （1.2 秒后进登录页 / 主界面）。
5. 跑测试：`flutter test`（这轮动了 `test/order_sort_test.dart` 和 `test/widget_test.dart`）。


---

## 本轮改动（2026-10-11 第十七次）：桌号/名字/金额**绝不省略** / 已结单点开看明细+补打 / 已结单改成**按天**看 + 日结挪进来

> ⚠️ 先说清楚：**上面第十六次里的几处已经被这次改掉了** ——
> ① 已结单的「日期**范围**」→ 换成「**一天**」；
> ② 日结下面那张「当天结单明细」→ **去掉了**（日结只看数字，跟以前一样）；
> ③ 日结按钮从顶栏 → 挪到「已结单」那条的**最右边**。

### 1. 桌号 / 外卖名字 / 单号 / 金额：**完整显示，绝不省略**

你反馈的"电话外卖+名字太长会把后面省略掉" —— 现在这一行里**只有菜名可以省略**：

| 位置 | 以前 | 现在 |
| --- | --- | --- |
| 桌号 / 外卖名字 / 单号（左边标签） | 超过 240 就打省略号 `…` | **折行显示完整**（不打省略号）：宽度上限 260（窗口窄时 160），名字再长也只是多占一行 |
| 金额（大字） | 本来就不省略 | 保持完整，绝不切字 |
| 菜名 | 省略号 | **还是省略号** —— 要看全就**点开这张单看明细**（一道菜一行） |
| 支付方式 / 未上传（右边小字） | 有宽度上限 | 窗口窄（< 700 逻辑像素）时**直接不显示**，先保桌号和金额 |

### 2. 「已结单」点一下就开：**看明细 + 补打小票**（就这两件事）

- 已结单的卡片以前点了没反应，现在**点开一个明细窗口**：
  - 头：桌号/外卖名字 + **金额大字** + 支付方式 + **结账时间** + 单号 + 收银员；
  - 菜品：**昵称 ×份数** + 金额；下面一行小字是单价和**选项 / 备注**（备注折行，不省略）；
  - 金额：小计 / 折扣 / 税（有才算）→ **合计**；
- 窗口里两个按钮：**「补打小票」**（＝顾客小票，跟结账时同一个排版函数；结过账的单子里
  已经有支付方式 / 实收 / 找零，所以补打出来票面是完整的）+ 「确定」关闭；
- ⚠️ **没有「结账」**：钱早收过了，不需要再收一次；
- 打印失败照样弹「重试 / 跳过」（跟结账那边同一套处理，成功不弹提示）。

### 3. 「已结单」改成**按天**看（跟日结一模一样）+ 日结按钮挪到右边

- 日期按钮：点一下开**日期选择器**（一天，不是时间段），显示 `2026-10-11`；
  默认就是**今天**，**跨零点自动跟到新的一天**；
  挑过过去的某一天 → 旁边出现「**今天**」小圆片，一键跳回来；
- 排序两个小圆片照旧：**按时间**（结账确认时间由近到远，默认）/ **按金额**（由大到小）；
- 这条的**最右边是「日结」按钮**（要管理员权限）；**打开时带上你正在看的那一天** ——
  不然会出现"看着 10/3 的单子、点开日结却是今天的数字"。顶栏那个日结按钮**去掉了**；
- 末尾「单数 N」＝这一天筛出来几张，跟标签页括号里的数字一致。

### 4. 日结：回到"只看数字"

去掉了上一轮加的「当天结单明细」（你说不需要），版式跟以前一样：
营业额 / 单数 / 小计·折扣·税 / 现金(按币种) / 刷卡 / 扫码 / 总营业额 / 支出 / 净额。
（**跨零点自动跟到"今天"** 那个修正保留着 —— 以前开着过零点，页面还停在昨天。）

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/screens/orders_screen.dart` | 左边标签**不打省略号**（折行显示完整，上限 260 / 160）；已结单卡片点击 → 明细窗口；日期改成**一天**（默认今天 + 「今天」一键返回）；**日结按钮挪到这条最右边**并带上同一天；顶栏去掉日结 |
| `lib/widgets/order_detail_dialog.dart`（新） | `showClosedOrderDetail()`：明细（头 + 菜品 + 金额）+ **补打小票**（复用 `ReceiptPrintService.printReceipt`，失败走同一个重试弹窗） |
| `lib/utils/order_sort.dart` | `filterOrdersByDateRange()` → **`filterOrdersOnDate(orders, 'yyyy-MM-dd')`**（一天；空串 = 不筛） |
| `lib/screens/daily_summary_screen.dart` | 去掉「当天结单明细」（`_DayOrdersList`）；新增 `initialDayKey`（从已结单进来时看同一天）；跨零点自动跟今天保留 |
| `lib/l10n/app_strings.dart` | 去掉 3 条（`order.dateRange.all` / `order.dateRange.pick` / `summary.dayOrders`）、新增 4 条（`order.date.today` / `order.detail.title` / `order.closedAt` / `order.reprint`）—— 三语仍对齐：**402** 条 |
| `test/order_sort_test.dart` | 「按日期范围筛」那组换成「**只看某一天**」：当天 23:59 算当天 / 零点过一分算第二天 / 那天没单 → 空 / 空串 = 不筛 / 老数据用开单时间 |

**你要试的**：

1. 造一张**名字很长的电话外卖**（带等待时间）→ 左边的标签应该**折行显示完整**
   （桌号 / 名字 / 单号 / 金额都在），右边「删除 / 结账」照样贴最右；
   菜名太长就省略 —— 想要看全就在「已结单」里**点开这张单**。
2. 「已结单」→ 点一张单 → 明细窗口（菜品 + 金额 + 结账时间）→ **点「补打小票」应该出票**；
   窗口里**没有结账**。
3. 「已结单」日期按钮：选昨天 → 只剩昨天的单，旁边出现「今天」一键跳回；
   点最右边的「**日结**」→ 显示的应该是**同一天**的数字。
4. 日结页面：只有数字（没有当天单子列表了）。
5. 跑测试：`flutter test`（这轮动了 `test/order_sort_test.dart`）。


---

## 本轮改动（2026-10-11 第十八次）：卡片改成「左边名字 · 中间菜名 · 右边一组」/ **所有单子共用一个每日单号** + 默认按单号排 / 结账找零更干净 / 购物车去掉单价行

### 1. 订单卡片重排：金额挪到右边，左边给名字

一行现在是三段：

```
[ 桌号/名字/单号（最多占半行，完整显示） ] [ 菜名（可以省略） ] 支付方式 · 金额(大字) · 删除 ·( 结账)
```

- **金额挪到了最右边**（24 号大字）：它的**右边缘每张单都在同一个位置** → 一列数字对齐，扫一眼就知道哪单多大；
- 右边依次是：**支付方式（现金/刷卡）→ 金额 → 删除 →（进行中的还有）结账**；
  这一组**都没有弹性**，所以永远贴着卡片右边缘；
- 左边「名字 / 单号」的宽度上限从固定 260 改成**整行的 50%** —— 从最左边开始，
  名字长的外卖单能占半行（以前挤在 260 里会向下折两三行，中间一大片空着）；
- 菜名放中间（`Expanded`，太长省略号）—— 你说过不看完整没关系，**点开明细**能看全。

### 2. **所有单子共用一个"每天从 1 开始"的单号** + 新增**默认排序**

- 以前只有外卖 / 电话外卖有号（`Order.dailyNo`），**现在堂食也有**，而且是**同一条序列**：
  一天里谁先开的、一号到几号，一目了然（不会出现"三张单都是 #1"）；
- 界面上的写法：堂食 `桌号 5  #12`、外卖 `外卖 张三 #3`、电话外卖 `电话外卖 张三 #3`；
- **新排序方式「默认（单号）」**：号大的在最上面（= 更近开的单）。
  号**每天归零**，所以内部先按"哪一天"排（新的一天在上面），同一天里再按号从大到小；
  老数据没号（`dailyNo = 0`）排最后；
- **「进行中」和「已结单」的默认排序都是它**（`OrderSort.number` / `ClosedSort.number`）。
  原来那些排法都还在：进行中 = 按位置 / 按时间；已结单 = 按时间 / 按金额；
- ⚠️ **如果这一页以前点过别的排法**，本机会记住那个选择（设置存在本机）→
  想用新默认，点一下「默认（单号）」即可；要我强制把所有设备重置成默认也可以。

### 3. 排序按钮的位置：修掉「被居中」

「进行中」那一条以前会**显示在中间**（有时看着像跑到右边）—— 真因是列表外面那个 `Column`
默认把收缩到内容宽度的子项**居中**（`_OrderList` 的 `CrossAxisAlignment` 没设成 `stretch`）。
现在改成 `stretch`，两种标签页的排序按钮都从**最左边**开始排。

### 4. 结账：找零只留金额；快捷取整**三个**

- 找零那个绿框里原来底下还有一行小字「实收: xxx · 应收: xxx」—— **去掉了**，
  现在就是「找零 / 还差」+ 一个大数字（上面实收框里本来就填着实收，重复了）；
- 实收框右边的快捷金额：**正好 + 三个取整档**（以前是正好 + 两个）。
  档位还是 10 / 50 / 100 / 200 / 500 / 1000 依次向上取，跳过等于应收的和重复的，
  所以像 240 → `240 / 250 / 300 / 400`，550 → `550 / 600 / 1000`（凑不满四个就少给几个）。
  想换档位（比如按墨西哥纸币 20/50/100/200/500）改 `lib/utils/pricing.dart` 里那个列表即可。

### 5. 购物车：去掉菜名下面那行单价

右边那个金额就是「单价 × 份数」，单价不用再写一遍：
- 购物车里（还没保存的行）：只留「点这一行可以改」这句提示；
- 「已在单上」的行：那一行只留**选项 / 备注**（有才显示），单价不显示了。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/screens/orders_screen.dart` | 卡片重排（左名字≤50% / 中菜名 / 右：支付方式→金额→删除→结账）；两种标签页都加「默认（单号）」小圆片并放到最左；`_OrderList` 用 `CrossAxisAlignment.stretch` 修掉排序按钮被居中 |
| `lib/utils/order_sort.dart` | `OrderSort.number` / `ClosedSort.number`（默认）+ `_byNumber()`：先按天、再按号从大到小；`fromId()` 认不出时回落到 `number` |
| `lib/state/pos_controller.dart` | `_nextTakeawayNo()` → **`_nextDailyNo()`**：堂食/外卖/电话外卖**共用**一条"当天从 1 开始"的序列，新单都带号（`dailyNo`） |
| `lib/utils/order_label.dart` | 堂食标签带上单号：`桌号 5  #12` |
| `lib/data/settings_store.dart`、`lib/state/settings_controller.dart` | 两个排法的默认值改为 `'number'`（老设备存过的选择仍然生效） |
| `lib/widgets/payment_flow.dart` | 找零框去掉「实收/应收」那行小字；快捷金额注释同步（正好 + 三个取整档） |
| `lib/utils/pricing.dart` | `quickReceivedAmounts(max: 3 → 4)`：正好 + 三个取整档 |
| `lib/widgets/cart_panel.dart` | 购物车行 / 已在单上的行**去掉单价行**（已在单上那行只留下选项 / 备注） |
| `lib/l10n/app_strings.dart` | 三语各加 1 条：`order.sort.default`（默认（单号））—— 三语仍对齐：**403** 条 |
| `test/pricing_test.dart` | 快捷金额那组按新的四个档位更新（240 / 550 / 61 / 245.5 / 100）；新增「最多四个、整千只有正好」 |
| `test/order_sort_test.dart` | 新增一组「默认排序：按单号」：号大的在前 / **跨天时新的一天在前** / 老数据没号排最后 / 已结单也能按单号排；`fromId` 用例改成回落到 `number` |

**你要试的**：

1. 订单页（两个标签页）：**金额应该在最右边**，一列数字对齐；左边名字 / 单号最多占半行、
   **完整显示**；中间菜名太长会省略；「删除 / 结账」永远贴最右。
2. 开几张**堂食**单 → 左边应该显示 `桌号 N  #x`，号是接着外卖一起往下排的（每天从 1 开始）。
3. 排序：点「**默认（单号）**」→ 号大的在最上面（**今天新开的第一张会排在昨天那些单前面**）。
   ⚠️ 以前点过「按位置 / 按时间」的话，本机记着那个选择 → 点一下「默认（单号）」切过来。
4. 结账窗口（现金）：找零那块**只有一个大数字**（没有「实收 / 应收」那行小字）；
   实收框右边有**三个**取整快捷键。
5. 点单页购物车：菜名下面**不再显示单价**（右边金额就是总价）。
6. 跑测试：`flutter test`（这轮动了 `test/pricing_test.dart` 和 `test/order_sort_test.dart`）。


---

## 本轮改动（2026-10-11 第十九次）：购物车加**「结账」**第三个按钮 / 启动画面 1.8 秒 / 排序改叫「按单号」并变成默认

### ⚠️ 先说一件要紧的事：`lib/l10n/app_strings.dart` 被旧内容覆盖过

检查时发现你保存的那一版**少了 8 条文案键**（连注释一共约 35 行）——
应该是编辑器里开着旧内容直接保存了：
`order.sort.number` / `order.sort.position` / `order.sort.time` / `order.sort.amount` /
`order.date.today` / `order.detail.title` / `order.closedAt` / `order.reprint`。

**表现出来会是**：订单页的排序小圆片、日期按钮、「今天」、点开的明细窗口、「补打小票」
这些地方**显示英文键名**（比如 `order.sort.time`）而不是中文。

- 这 8 条（三语）**已经补回来了**；
- 顺手扫了一遍"**代码里用到、文案里没有**"的键 → 现在 **0 个缺失**；
- 三语各 **402 条**，完全对齐；
- 你自己加的那条 `cart.checkout`（结账）我看到了，**新的结账按钮就用它** ✅。

> 你以后编辑这个文件之前，请**重新打开/重新加载**一下（别在旧标签页里直接保存），
> 不然又会把新加的键盖掉。改文案的路径是：`lib/l10n/app_strings.dart`，
> 三个 map（`zh` / `es` / `en`）里**同一个键要各改一处**。

### 1. 启动画面：1.2 秒 → **1.8 秒**

`lib/app.dart` 里 `_SplashGateState._minShow` 改成 `Duration(milliseconds: 1800)`
（想再长/再短就改这一个数）。`test/widget_test.dart` 里"把时间推过去"也跟着改成 2000ms。

### 2. 购物车第三个按钮：**结账**（外卖客人当场付钱用）

一行三个：**保存 / 厨房 / 结账**（`flex` = 2 : 3 : 3 —— 保存窄一点，把地方让给后两个）。

- **按「结账」发生什么**：先把本次新增的菜**记到单上**（跟「保存」一样，
  但**不问外卖名字** —— 客人正等着付钱），然后**直接打开这张单的结账窗口**
  （就是订单页那个结账：折扣 / 税 / 收款 / 打小票都在里面）。结完这张单就是「已结单」。
- **按钮什么时候能点**：购物车里有新菜，**或者**当前这张单 / 刚动过的那张单还没结
  （所以"菜都下过厨房了、就等收钱"也点得动）。
- **购物车空了也能结**（比如刚点过「厨房」）：靠的是新加的"**刚动过的那张单**"
  （`PosController.lastTouchedOrder`）。为什么要专门做它：**没起名字的外卖单**
  既没有桌号也没有名字，`openOrderForSelectedTable()` 是故意找不到它的，
  但"刚下的这一单"当然要能直接结账。
- 结账按钮颜色用**深蓝**（`0xFF1565C0`），跟「厨房」的绿区分开，免得点错。

### 3. 排序：「默认（单号）」改叫「**按单号**」，并且真的默认它

- 小圆片文字改成 **按单号 / Por número / By number**（键也从 `order.sort.default`
  改成 `order.sort.number`，名字跟含义一致）；
- **默认值**：这一版**第一次启动**会把两个排法都重置成「按单号」
  （设置里加了一次性标记 `order_sort_migrated`：没迁移过就忽略本机存的老值，
  存过一次之后就完全按你点的走）。
  你之前看到「按时间」—— 那是上一版存下来的老默认值，这次会被清掉。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/widgets/cart_panel.dart` | 新增 `onCheckout` + 第三个按钮「结账」（一行三个，保存窄一点、结账深蓝）；`canCheckout` 单独判断 |
| `lib/widgets/payment_flow.dart` | 新增 **`checkoutOrderFlow()`**：记单（`askName: false`）→ 直接开这张单的结账窗口；`_submitOrder()` 改成**返回刚记下的那张单**（`Future<Order?>`）+ 新增 `askName` 开关 |
| `lib/state/pos_controller.dart` | 新增 `lastTouchedOrder` / `markTouchedOrder()`：给"没名字的外卖单也能直接结账"兜底 |
| `lib/screens/pos_screen.dart`、`lib/widgets/cart_sheet.dart` | 宽屏面板 / 窄屏底部弹窗都把「结账」接上 |
| `lib/app.dart` | 启动画面 1.2 → **1.8 秒** |
| `lib/data/settings_store.dart` | 一次性迁移标记 `order_sort_migrated`：第一次启动把两个排法重置成 `number` |
| `lib/l10n/app_strings.dart` | **补回被覆盖掉的 8 条键 × 3 语**；`order.sort.default` → **`order.sort.number`**（按单号 / Por número / By number） |
| `test/cart_panel_test.dart` | `CartPanel` 多一个 `onCheckout`（构造处补上）；新增「菜都下过厨房、购物车空 → 结账仍能点」；原来"两个按钮都点不动"改成三个 |
| `test/widget_test.dart` | 启动画面 1.8 秒 → 推时间改成 `pump(2000ms)` |

**你要试的**：

1. **外卖当场结账**：选「外卖」→ 加两个菜 → 点购物车的「**结账**」→
   应该直接弹这张单的结账窗口（不是跳去订单页）；收完钱那张单就进「已结单」了。
2. 再试一遍"**先厨房、后结账**"：加菜 → 点「厨房」→ 购物车空了 → 再点「结账」→
   **仍然应该结到刚下的那一单**（这是以前会"点不动"的情况）。
3. 点单页一行三个按钮：保存（窄、白底）/ 厨房（绿）/ 结账（深蓝）；
   购物车和单上都空的时候三个都灰。
4. 启动 app：logo 应该显示大约 **1.8 秒**。
5. 订单页：排序小圆片第一颗是「**按单号**」并且**默认选中**（如果你以前点过别的，
   这次第一次启动会被重置成按单号；之后再点就记住了）。
6. 顺手确认一下语言：随便切到 English / Español 看订单页排序按钮是不是
   `By number / Por número`（不是键名）。
7. 跑测试：`flutter test`（这轮动了 `test/cart_panel_test.dart` 和 `test/widget_test.dart`）。

