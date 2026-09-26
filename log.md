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
点菜界面右边的购物车已下厨也要可以改动，比如删除；购物车中的任何菜品，点击都要回到编辑界面，方便改动；
所有的菜品在点菜的时候都要有特别备注，不管是不是在Excel中有定制化选项。特别备注有可能有多个，所有填入一个之后，要可以保存，然后填写下一个。
菜品点菜的时候加入数量，默认1，提供一个加号按钮，或者直接输入数字
菜品和种类提供按照首字母排序和按照流行度排序，因此我们需要加入每个菜品及其种类被点的次数，以结账时候为准，在结账确认的时候录入。
外卖备注名字
加入购物车，为下单厨房，只保存，之后返回可以再下厨。
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

## 修 2 个问题（2026-09-19）：保存后打不了厨房单 / Excel 的单选项 = 加料开关

### 问题 1：先点「保存」，就再也点不了「厨房」（换桌回来也一样）

**原因有两层**（都在我上一轮写的代码里）：

1. `cart_panel.dart` 里两个按钮**共用**了一个条件「购物车里有新菜」——
   而「保存」正好把菜从**购物车**搬到了**单上**，购物车一空，两个按钮一起变灰；
2. `payment_flow.dart` 的 `_submitOrder()` 开头还有一句 `if (pos.cartEmpty) return;`，
   所以就算按钮能点，也会立刻返回、什么也不打。

**修法**：

- 两个按钮**分开**判断：`canSave` = 有新菜；`canKitchen` = **有新菜，或者这张单上还有没下厨的菜**；
- `_submitOrder()`：购物车空也能走「厨房」分支 —— 直接取这张桌进行中的单，
  把它**没下厨的行**打给厨房（这也顺手支持了「上次厨房单打失败被跳过」的补打）。

| 文件 | 改了什么 |
| --- | --- |
| `lib/widgets/cart_panel.dart` | `canSave` / `canKitchen` 分开判断 |
| `lib/widgets/payment_flow.dart` | `_submitOrder()` 支持「购物车空 + 单上有未下厨的菜」 |
| `test/cart_panel_test.dart`（新） | 4 组回归：有新菜都能点 / **保存后厨房还能点** / 换桌回来还能打 / 全空都点不动 |

### 问题 2（你 Excel 的改动）：定制选项不一定有多个 —— 单个就是「加料开关」

规则（都写进模型，注释也写清了）：

- **加料开关** = 只有**一个**选项（Excel 那格没写 `/`），**或者**正好是一对 **Yes/No**
  → `MenuOptionGroup.isToggle`；
- 点菜框里**默认不选**（不加钱），客人点一下才加；再点一下可以取消；
- 加的钱 = 组里**最贵**的那个价（`togglePrice`，通常就是 Yes 那个）；
- 单子上存的是**组名**（`EXTRA BOBA` / `JARRA`）—— 小票和厨房单上不会出现看不懂的「Yes」；
- 选「No / +0」等于**没加**，不写进单子（所以票上也不会多出一行「No」）；
- **普通多选项**（Size: Mediano/Grande）默认选**最便宜**那个 →
  框里显示的价 = 菜单格子上写的「起价」，不会一点开就贵一档；
- 菜单格子上的「起价」也同步**跳过加料开关**（`MenuItem.minUnitPrice`），两边永远一致。

| 文件 | 改了什么 |
| --- | --- |
| `lib/models/menu_option_group.dart` | 新增 `isToggle`（单选项 / Yes-No，含 Sí/是/要 等写法）、`togglePrice` |
| `lib/models/menu_item.dart` | `unitPriceFor()` 认「组名」形式的选择；`minUnitPrice` 跳过加料开关 |
| `lib/widgets/item_customize_dialog.dart` | 默认选择规则（`_defaultOption`）、存组名的规则（`_selections`）、编辑时按组名认回来、「（可不选）」提示、加料可点击取消 |
| `lib/l10n/app_strings.dart` | 新增 `custom.optional`（（可不选）/ (opcional) / (optional)） |
| `test/item_customize_dialog_test.dart` | 新增 4 组：加料默认不选 / 点一下加钱再点取消 / **存的是组名** / JARRA Yes-No 默认不加钱、点 No 等于没加 |
| `test/pos_controller_test.dart` | 新增 1 组：`isToggle`、`togglePrice`、按组名算价、起价 = 基础价、普通多选项仍取最便宜 |

> 导入器**不用改**：Excel 的「选项」那格只写一个（没有 `/`）本来就解析得出来，
> 之前的问题是**点菜时的默认选择**和**小票上写什么**。


---

## 新功能（分阶段）：后台 + 多设备同步（方案：Supabase 云）

**你选的方案**：云（Supabase 免费档）+ 2～3 台设备共用一个单池 + 后台用浏览器打开。
（另外两个候选是「店里那台 Windows 自己当服务器（局域网、零月费）」和「先只做上传备份、后台只读」，
都记在这份文档的聊天记录里，以后想换也只要改服务器地址。）

### 为什么必须有后台存储

现在数据都在**每台设备各自的** SharedPreferences（`orders_history` / `menu_data`），
设备之间没有任何中间人 → 做不到「A 设备下的单 B 设备看得到」。所以必须先有一个大家都能连的真相源。

### 关键设计（决定了实现方式）

1. **服务器是权威**：`rev`（版本号）和 `updated_at` 由数据库触发器维护，
   App 只送 `data`（整张单的 JSON）；推成功后把服务器返回的 `rev/updated_at` 存回本地。
   本地 `rev = 0` 表示「还没推上去」。
2. **结账只允许成功一次**：`close_order()` RPC 做 CAS（`in_progress → completed`），
   三台设备同时点也只算一次钱；另一台拿到「已结账」的现状并采纳。
3. **拉 → 合并 → 推**（这个顺序很重要）：先拉增量、谁新听谁的（`rev` 大者胜，
   一样比时间、再一样比设备名保证两台算同一个结果），再推本地脏数据。
4. **本地优先**：点单/打单/结账永远先写本机，同步只是后台异步的事，**断网照常营业**。
5. **菜单单向**：在 App 里改菜单（菜品管理 / Excel 导入）→ `version + 1` → 其他设备拉到新版
   整体覆盖（订单里存的是菜的快照，所以正在点的购物车不受影响）。
   后台网页的「菜单」页是**只读**的，看版本号和内容用。
6. **现实硬规矩**：一张桌只在一台设备上点单/改单/结账，别的设备只看 —— 冲突概率几乎为 0。

### 这一轮做了什么（第 1 阶段：地基 + 你要做的准备）

| 文件 | 说明 |
| --- | --- |
| `supabase/schema.sql`（新） | 建表 + 索引 + RLS + `close_order()` CAS + 自动维护 `rev/updated_at` 的触发器。**去 Supabase 的 SQL Editor 里整段跑一次**（可重复执行） |
| `setup_supabase.md`（新） | 你要做的：建项目 → 跑 SQL → 建设备账号（记得勾 Auto Confirm）→ 抄 Project URL / anon key → 填进 App。含断网行为、备份、排错表 |
| `lib/models/order.dart` | 加同步四件套：`updatedAt`（本地改动时间）、`rev`（服务器版本，0=没推过）、`deviceId`、`dirty`（本地脏标记）+ `touch()` 助手；JSON 往下兼容（老单读回来 `rev=0/dirty=true` → 第一次同步自动推上去） |
| `lib/services/order_sync.dart`（新） | **纯逻辑**（不联网、好测）：`isNewer()`、`chooseOutgoing()`、`chooseIncoming()`、`toRow()`、`closePatch()`、`RemoteOrder` |
| `lib/services/supabase_rest.dart`（新） | 极简 Supabase 客户端（GoTrue 登录/刷新 + PostgREST 查/upsert + RPC），只依赖 `http`，`http.Client` 可注入 → 测试用 MockClient，不联网 |
| `pubspec.yaml` | 新增依赖 `http: ^1.2.2`（**你要跑一次 `flutter pub get`**） |
| `test/order_sync_test.dart`（新） | 10 组：谁新谁赢/推哪些/拉哪些/送上去的行/结账补丁/同步字段 JSON 往返/老数据兼容/`touch()` |
| `test/supabase_rest_test.dart`（新） | 10 组：登录 url+apikey+body、失败原因、刷新、查表查询串、upsert 的 `Prefer`、RPC 参数与返回、RLS 报错、URL 结尾斜杠 |

### 下一轮（第 2 阶段，还没做）

1. 设置页加「后台同步」一栏（URL / anon key / 设备名 / 账号密码 / 测试连接 / 立即同步 / 状态）；
2. `PosController` 接线：改单后标脏 + 防抖推送；启动/定时「拉 → 合并 → 推」；结账走 `close_order()`；
3. 后台网页 `supabase/admin.html`（菜单 / 进行中单 / 已结单 / 日结 / 导出备份），浏览器打开即用；
4. 菜单单向同步（版本号比对）。

### 你现在可以先做的（不用等我）

按 `setup_supabase.md` 把 **Supabase 项目 + SQL + 设备账号**建好，把
**Project URL / anon key** 抄在手边 —— 下一轮我做好设置页，你直接填进去就能连。

---

## 后台同步（第 2 阶段）：设置页配置 + App 端接线 + 后台网页

第 1 阶段的地基（SQL / 模型字段 / 纯逻辑 / REST 客户端）已经在上面一节里；
这一轮把它**接起来能用了**：

### 1. 设置页多了「后台同步（云端）」一栏

`设置 → 后台同步（云端）`：
- 开关「启用后台同步」（默认关）；
- 填 **Supabase 项目地址** + **anon key**（Project Settings → API 里的 anon public）；
- 填**这台设备的名字**（例如「收银台A」，会写在同步记录里，用来区分谁改的单）；
- 填**这台设备的后台账号**（邮箱 + 密码，见 `setup_supabase.md` 第 3 步）；
- 两个按钮：**测试连接**（登录 + 问一次服务器时间）、**立即同步**（↑推了几张 ↓拉了几张）；
- 状态行：**上次同步时间 · 待上传 N 张**；出错时下面红字显示原因（不影响收银）。

### 2. App 端接线（`SyncService`）

新文件 `lib/services/sync_service.dart` —— 它做三件事，都在**后台异步**做：

1. **本地一变就标脏 + 防抖推**（2 秒）：点单/改单/结账/删单都会 `dirty=true`，
   同步成功后再把服务器的 `rev / updated_at` 存回本地、把 `dirty` 清掉；
2. **每 25 秒拉一次**（也可以手动点「立即同步」）：别人的新单/改动会并到本机；
3. **菜单单向同步**：服务器版本高就拉下来覆盖本地；本地改过（菜品管理 / Excel 导入）
   就推上去（`menuDirty` 标记）。

**顺序永远是「拉 → 合并 → 推」**，所以不会用本机的旧数据盖掉别人刚结的单；
**结账走 `close_order()` RPC**（服务器做 CAS），三台设备同时点也只算一次钱。

**收银永远不受影响**：所有网络错误都只记到状态里（`status.error`），
本地单还是脏的，下一次同步自动重试。

### 3. 后台网页 `supabase/admin.html`

一个**单文件网页**（不依赖任何库/ CDN，双击就能用）：
- 顶上填 Supabase 地址 + anon key + 账号密码（存在浏览器本地）→ 登录；
- 四个标签页：**进行中的单**（含每台设备正在点的菜）· **已结账的单**（按日期筛）·
  **日结**（堂食/外卖/电话外卖 + 现金/刷卡 + 单数 + 每道菜卖了多少份）·
  **菜单**（种类/菜名/基础价/定制项与加价）；
- 右上角 **导出备份**（订单 + 菜单存成一个 JSON）；「进行中」页可以开 20 秒自动刷新；
- 手机浏览器也能开（响应式）。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/data/settings_store.dart` | 新增同步配置 10 个字段 + `SettingsStore` 的 10 个键（load/save） |
| `lib/state/settings_controller.dart` | `persist()`（同步服务改 `lastSyncAt/refreshToken/menuVersion` 用）+ `updateSync()` |
| `lib/state/pos_controller.dart` | `deviceId` + `onOrdersChanged` / `onMenuChanged` 钩子；`ordersSnapshot / menuSnapshot / adoptServerOrders / confirmDeletedPush / replaceMenuFromServer`；**每次改单都 `touch()`**（标脏）；删单进「待删除」名单；采纳服务器那份时不重复触发同步 |
| `lib/services/sync_service.dart`（新） | 同步引擎：登录/续期、拉→合并→推、结账 CAS、菜单单向、防抖、25 秒定时、状态（`SyncStatus`）；**任何错误都不上抛** |
| `lib/services/supabase_rest.dart` | 加 `delete()`（删行必须带过滤条件，防手滑清表） |
| `lib/app.dart` | 用 `ChangeNotifierProxyProvider2` 接上 SyncService（**惰性创建一次**，不能在 build 里 new）；`_AppShell` 在设置读回来后启动同步 |
| `lib/screens/settings_screen.dart` | 新增「后台同步（云端）」一栏 + 5 个输入框 + 测试连接/立即同步 + 状态行 |
| `lib/l10n/app_strings.dart` | 三语各加 20 条 `settings.sync / sync.*` |
| `supabase/admin.html`（新） | 后台网页（进行中 / 已结账 / 日结 / 菜单 / 导出备份） |
| `lib/data/deleted_store.dart`（新） | 「本地删掉、还没告诉后台」的单号（重启后还记得去删，避免被拉回来） |
| `lib/state/pos_controller.dart`（补充） | `markAllOrdersDirty()`（重置同步状态用） |
| `test/sync_service_test.dart`（新） | 10 组**假服务器**测试：脏单推上去并把 rev 存回、别人的单拉下来、已结账走 RPC、RPC 说没有就整单推、网络出错不抛异常且还是脏的、登录失败只记错误、删单真的删、菜单推/拉、没启用/没配置时一个请求都不发 |

### 顺手补的两个坑

1. **删单会被「拉回来」**：删单时如果正好断网，重启后本地已经不记得删过谁，
   下一次同步就会把那张单又拉回来（看着像删不掉）。→ 新增
   `lib/data/deleted_store.dart`（把「本地删掉、还没告诉后台」的单号**存到本机**），
   `adoptServerOrders()` 会跳过这些单号；服务器删成功后清掉标记。测试里也加了这个回归。
2. `setup_supabase.md` 排错表里提到的「重置同步状态」原本还不存在 → 现在真有这个按钮了
   （设置页 → 后台同步 → 重置同步状态：忘掉登录态 + 把所有单子和菜单重新推一遍，**不删单子**）。


### 你要试的

1. `flutter pub get`（有新的 `http` 依赖）；
2. 按 `setup_supabase.md` 建好项目 + 跑 SQL + 建设备账号；
3. 三台设备（或先一台）在 `设置 → 后台同步` 里填好 → **测试连接** → **立即同步**；
4. 点单 → 看后台网页「进行中的单」有没有出现（20 秒自动刷新，或点「刷新」）；
5. 结账 → 后台网页「已结账的单」里能看到金额/支付/菜；
6. 拔网线点单结账 → 照常收银打单，设置页显示「待上传 N 张」；插回网线 → 自动补推。

---

## 后台同步（第 3 阶段）：看得见的同步状态 + 三个「长时间跑才会遇到」的坑

上面那轮做完之后，同步是能用的，但有几个**只有真开一整天才会撞上**的问题；
这一轮把它们补掉，并且在收银界面上把「同步到哪了」露出来。

### 1. token 过期 → 自动重登（重要）

Supabase 的 access token **默认 1 小时就过期**。之前过期后所有请求都是 401，
同步就会**一直失败到人工去点「重置同步状态」**（实际表现是「下午开始后台就不更新了」）。

现在：`SyncService.syncNow()` 碰到 `401` → `clearSession()` + 清掉本机 refresh token
→ **自动重登一次再重试一遍**（只重试一次，避免密码填错时死循环）。
测试里加了回归：假服务器第一次回 401、第二次正常 → 断言「重登后数据还是上去了」。

### 2. 订单页右上角能看到同步状态

`订单` 页 AppBar 上多了一个云朵按钮（**没启用后台同步时整块隐藏**，不用的人不占地方）：

- 图标即状态：☁️↑ 还有没传的 / ☁️✔ 都传完了 / ☁️✕（红）出错；
- 文字「同步 N」（N = 待上传张数，含「本地删掉还没告诉后台」的单）；
- 点一下就立刻同步（同步中转圈）；
- 鼠标悬停显示「上次同步：yyyy-MM-dd HH:mm · 待上传：N」。

另外**每张单的卡片上**，如果它还没推到后台，会有一个橙色小标「未上传」——
不用去设置页翻状态，一眼就看得出哪几张后台还没收到。

### 3. 从后台切回前台马上补一次同步

平板息屏/切走时，系统的定时器可能被冻住，回来后原来要等最多 25 秒才看到别人的改动。
现在 `_AppShell` 监听生命周期，`resumed` 时立刻同步一次（`syncNow()` 本身有
「没启用/正在同步中」的短路，不会重复发请求）。

### 4. 小整理

- 时间格式化抽到 `lib/utils/format.dart` 的 `timeShort()`（设置页 + 订单页 tooltip 共用，
  不再各写一份）；
- 补上缺的三语词条 `sync.short` / `sync.notUploaded`。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/sync_service.dart` | **401 自愈**：清会话 + 重登一次再试；`_syncAll()` 抽出来复用 |
| `lib/screens/orders_screen.dart` | 新增 `_SyncButton`（云朵图标 + 待上传数 + 点击同步 + tooltip 状态）；单卡片上的橙色「未上传」小标 |
| `lib/app.dart` | `_AppShellState` 混入 `WidgetsBindingObserver`，回到前台立刻同步一次 |
| `lib/utils/format.dart` | 新增 `timeShort()`（`2025-01-31 09:05`） |
| `lib/screens/settings_screen.dart` | 时间格式化改用 `timeShort()`（顺手补 `import`） |
| `lib/l10n/app_strings.dart` | 三语补 `sync.short` / `sync.notUploaded` |
| `test/sync_service_test.dart` | 新增第 11 组：**token 过期（401）→ 自动重登一次再同步** |

### 你要试的

1. `flutter test`（新增的那个 401 用例在 `test/sync_service_test.dart` 最后）；
2. App 用起来跑一会儿：设置页 → 后台同步 → 填好后点「测试连接」；
3. 订单页右上角应该出现云朵按钮；点单后短暂显示「同步 1」→ 一两秒后变成「同步」（0 张）；
4. 想验证 401 自愈不太好手动造（要等 1 小时）：如果哪天看到设置页红字报
   `JWT expired` 之类的，现在它自己会重登，下一次同步就恢复正常；实在不行再点「重置同步状态」。

---

## 后台同步（第 4 阶段）：增量拉取 + 翻页 + 「别人删的单」对账

前三轮把同步跑通了，但**真开一段时间**会暴露两个问题，这一轮修掉：

### 1. 之前每 25 秒都把**全部历史单**下载一遍

原来每次同步都是「拉全表」——店开了一个月、几千张单，就每 25 秒下载几千行：
流量白烧（免费档 5GB/月，超了就限流）、同步也越来越慢。

现在改成**增量**：

- App 启动后第一趟仍然**全量**（新设备要能把整个单池拉全，历史单也要有）；
- 之后每趟只拉 `updated_at > 水位线` 的行 —— 稳定状态下基本是「0 行」；
- **水位线只由「拉回来的行自己的时间」推进**（服务器写的 `updated_at`），
  一行都没拉到就不推进；往前退 5 秒做重叠；
  **不用响应头里的服务器时间**当水位线 —— 它比查询那一刻晚（网络慢时晚几秒），
  用它就可能跳过「这趟查询期间刚提交」的行（那些行要等下次重启全量拉取才回来）；
  响应头时间只当**上限兜底**（万一某行时间戳被写到未来，水位线也不会跳过头）；
- 水位线只在**内存**里：App 重启后第一趟又是全量（顺便做一次对账），
  这样不用操心「换过后台项目 / 本机时钟跳变」这些坑；
- 「重置同步状态」会把水位线清掉 → 下一趟重新全量。

### 2. 一次最多只给 1000 行，而且**不翻页就是静默截断**

Supabase 的接口单次默认最多返回 1000 行。历史单一多，新单就永远拉不到了
（而且不报错）。现在拉取**自动翻页**（`limit` + `offset`），一直拉到不满一页为止；
再加一个保险丝（一趟最多 1 万行），剩下的**下一趟接着拉**
（水位线是按拉到的那批行的时间推进的，所以既不会卡住、也不会漏掉中间的行）。

### 3. 别人删掉的单，本机不会一直挂着（对账）

删单只会在**这台设备**留下「待删除」标记推给服务器，别的设备根本不知道 ——
A 上取消了一张单，B 上会一直显示「进行中」，甚至可能被再结一次账。

现在每趟同步会做一次**很便宜的对账**：只问「我本机这几张进行中的单，服务器上还有吗」
（`id=in.(...)`，一般就几张单）：

- 服务器上**还在**（哪怕已经结了账）→ 不动，结账那份会走正常合并；
- 服务器上**确实没有** → 是被删了 → 本机也删掉。

⚠️ **只对「进行中」的单做这件事**：已结账的历史留在本机（日结要用），
万一以后后台清了老数据，本机历史不能跟着消失。这一步是**尽力而为**：
它失败只当没做（下一趟还会再对账），绝不影响点单/结账/推送。

### 4. 顺手修的一个「隐形重推」

增量之后，「这次拉回来的行里没有」**不再等于**「服务器上没有这张单」。
原来的推送规则遇到这种情况会把单再推一遍 —— 增量之后就会变成
「每 25 秒把全部历史单重新上传一遍」。现在只有
**没推过的（`rev == 0`）**或**本地脏的**单才会推。

### 5. 顺手把两处文档写错的地方改对

- 后台网页的「导出备份」是 **JSON**（文档里原来写成「JSON/SQLite」）；
- 后台网页的「菜单」页是**只读**的（改菜单在 App 的「菜品管理」里；文档里已写清）。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/sync_service.dart` | `_pullOrders()`：**增量 + 翻页 + 保险丝**（`pageSize` 默认 1000、一趟上限 1 万行，剩下的下一趟接着拉）；水位线 `_since`（内存态，由拉回来的行的时间推进、退 5 秒做重叠）；`_reconcileDeletedInProgress()` 对账；换后台项目/重置同步时清水位线；删单的 `in.(...)` 加了单号防御 |
| `lib/services/order_sync.dart` | `chooseOutgoing()` 规则收紧（增量窗口里没有 ≠ 服务器没有）；新增纯函数 `nextWatermark()`（水位线怎么算，含「响应头只当上限」的理由） |
| `lib/services/supabase_rest.dart` | `select()` 支持 `offset`（翻页）；新增 `lastServerTime`（读响应头 `Date`，**不区分大小写**，用作水位线上限兜底） |
| `lib/state/pos_controller.dart` | 新增 `dropOrdersRemovedOnServer()`（服务器已经删了的单，本地也去掉；不算「待删除」，不用再推） |
| `test/order_sync_test.dart` | 新增 4 组：不重推「窗口里没有但推过」的单、`nextWatermark` 的三种情况（含「一行没拉到就不推进」「行时间在未来也不越过响应头」） |
| `test/sync_service_test.dart` | 新增 3 组：第一趟全量/第二趟带 `gt.<水位线>`、翻页（`pageSize=2` 拉 3 行）、别人删掉的进行中单本地跟着删（已结账的不动、也不重推） |
| `test/supabase_rest_test.dart` | 新增 1 组：`offset` 翻页参数 + 响应头服务器时间（含大写 `Date` 键） |
| `setup_supabase.md` | 补「同步是增量的」「删单在两台设备上的表现」两段 + 额度那段说明带宽花在哪；顺手把两处写错的地方改对（后台网页的「导出」是 **JSON**、菜单页是**只读**） |

### 你要试的

1. `flutter test`（新增用例在 `test/order_sync_test.dart` / `test/sync_service_test.dart` /
   `test/supabase_rest_test.dart`）；
2. 真机验证增量：点几次「立即同步」，第二次之后设置页显示的 `↑0 ↓0`（没有新改动就不会有大流量）；
3. 对账验证（两台设备）：A 上删掉一张「进行中」的单 → B 上最多 25 秒后它自己消失；
4. 已结账的历史**不会**因为后台没有就被删掉（这是故意留的安全边界）。

---

## 后台同步（第 5 阶段）：两个会「悄悄丢菜」的坑

这一轮没加新功能，专门自查同步路径里**会丢数据**的地方 —— 找出来两个，
都是「本地的改动被服务器那份旧数据盖掉」，而且都是**不报错、无声无息**的：

### 坑 1：点完菜又加菜、然后马上结账 → 新加的那道菜会消失

场景（很常见）：

1. 14:00 点了一单，推上去了（`rev=1`）；
2. 14:05 又加了一道菜（本地 `dirty`，**还没推上去**，比如刚好断网）；
3. 14:06 客人结账 → 走 `close_order()` 那个 CAS。

原来的 `closePatch()` 只挑「结账相关」的字段发过去（status / 收款 / 折扣 / 总额…），
服务器是拿**它自己那份旧数据**（少一道菜）来合并的；结完账我们再把服务器那份采纳回来
→ **新加的那道菜在小票、日结、后台里全都凭空消失**，而且没有任何报错。

**修法**：`closePatch()` 现在送**整份本地 JSON**（`data = data || p_patch` 是浅合并，
等于把整张单覆盖成本地这份）。CAS（`status <> 'completed'`）照样保证「只结成功一次」，
所以「三台设备同时点只算一次钱」这条没动。

### 坑 2：推送请求「在路上」的时候又改了这张单 → 改动被回包盖掉

推单是异步的（网络慢的时候可能一两秒）：请求发出去之后，收银员又加了/改了一份菜。
等服务器回包一到，我们把回包那份（= 我们**发出去时**的那一版）写回本地、
并且把 `dirty` 清掉 → **刚改的那一份就没了**，还不显示「未上传」，等于彻底丢了。

**修法**：`_upsertOrders()` 现在记下「我们发出去的是哪一版」；回包回来时如果发现
本机这张单**又脏了、而且时间戳变了** → **不采纳**服务器那份（本地留着，
下一次同步把新版本再推一遍）。没改动的情况下行为完全不变。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/order_sync.dart` | `closePatch(closed, {deviceId})`：改成送**整份本地 JSON**（原来只送结账字段），注释里写清为什么 |
| `lib/services/sync_service.dart` | 结账 RPC 传 `deviceId`；`_upsertOrders()` 加「推送期间本地又改过就不采纳回包」的保护 |
| `supabase/schema.sql` | `close_order()` 的注释写清 `p_patch` 是**整张单的 JSON**（SQL 行为没变，本身就是 `||` 浅合并） |
| `test/order_sync_test.dart` | `closePatch` 那组改成断言「明细也在」（`lines` 必须有） |
| `test/sync_service_test.dart` | 新增 2 组：**结账补丁要带上新加的菜**、**推送期间改的单不被回包盖掉**；顺手加了 `TestRig` 类型别名 |
| `log.md` | 你正在看的这一节 |

### 你要试的

1. `flutter test`（重点是 `test/sync_service_test.dart` 里新加的两组）；
2. 手测坑 1（一台设备就能试）：连上后台 → 点一单 → 再**拔网线/关 WiFi** 加一道菜 → 结账 →
   插回网线等同步 → 后台网页「已结账的单」里那道菜应该在、金额也要对；
3. 手测坑 2 比较难手动复现（窗口就一两秒），靠单测盯住。

---

## 后台同步（第 6 阶段）：后台网页的两个坑（看老日期是空的 / 日结合计不显示）

顺手把 `supabase/admin.html` 从头看了一遍，找到两个会让你「以为数据没了」的问题：

### 坑 1：单子一多，后台的老日期就变成空的

Supabase 的 REST 接口**一次最多返回 1000 行**（控制台 API 设置里的「Max Rows」默认
1000）。原来后台网页是一把 `limit=2000` 拉订单 —— 服务器只会给你 1000 行，
而且**不报错**。于是：一天 200 单 → 第 6 天开始，「已结账的单」里翻 5 天前的日期是空的、
「日结」看老日期也是 0，看着像单子丢了（其实还在服务器上）。

**修法**：跟 App 一样**翻页**拉（每页 1000，最多 1 万单），页面上显示「已加载最近 N 单」；
自动刷新改成**只拉增量**（`updated_at > 上次`），所以每 20 秒那一下不会又把几千单重下一遍
（不然免费档 5GB/月的流量几天就烧完了）。手动点「刷新」才是整份重拉。

### 坑 2：已结账页的「N 单 · 合计 M」永远不显示

`refreshAll()` 里渲染完之后多了一句 `$('doneSummary').textContent = '';`，
把刚算好的合计又清空了。删掉即可。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `supabase/admin.html` | 订单**翻页加载**（`PAGE=1000`、上限 1 万单）+「已加载最近 N 单」提示（已结账 / 日结两个页都显示）；自动刷新改成**增量**（`updated_at > since`，按 id 合并进内存）；手动「刷新」= 整份重拉；删掉那句把日结合计清空的代码；导出备份里标注「只有已加载的那些单」 |
| `setup_supabase.md` | 后台网页一节补上「翻页加载最近 1 万单 / 自动刷新只拉增量」 |
| `log.md` | 你正在看的这一节 |

### 你要试的

1. 打开后台网页（`supabase/admin.html`）→ 登录 → 「已结账的单」页下面应该能看到
   「已加载最近 N 单」，日期筛到前几天也要有数据；
2. 「日结」页选某一天，KPI 和「卖出份数」要出数字 —— 别再无缘无故显示 0；
3. 开着 20 秒自动刷新看一会儿浏览器 Network（F12）：每 20 秒应该只有一个很小的
   请求（没有新单时基本是空数组），不是每次几 MB。

---

## 后台同步（第 7 阶段）：菜单同步的抖动 + 地址容错

这轮继续自查（菜单那条线 + 设置页填写体验），改了三处：

### 1. 改菜单不再「改一下就同步一趟」

`onLocalMenuChanged()` 原来是**立刻** `syncNow()`：在「菜品管理」里改一条菜、
Excel 导入几百条，都会连着触发同步。而且每推一次，服务器上的**菜单版本号就 +1**，
别的设备看到版本变了又要整份拉一遍 —— 白折腾，别的设备上的菜单还会在中间状态之间闪。

现在跟订单一样**防抖 2 秒**（`_scheduleSync()`），最后一个改动之后 2 秒推一趟；
「已经改过还没推上去」的状态**立刻落盘**，所以中途断电/退出也不会丢改动。

顺带：设置页的同步状态那行现在会显示「**菜单待上传**」（橙色），
让你知道刚才改的菜单还没上后台（`SyncService.menuPending`）。

### 2. 地址怎么写都能连（容错）

设置页是手填的，实际会遇到两种很常见的写法：

- 少写协议头：`xxxxxxxx.supabase.co` → 原来会拼出一个**没有 scheme** 的 URL，
  `http` 包直接抛错，界面上只显示一句看不懂的失败；
- 从 Supabase 文档里复制时带上了路径：`https://xxx.supabase.co/rest/v1`
  → 我们会拼成 `…/rest/v1/rest/v1/orders`，全是 404。

现在 `SupabaseRest.normalizeUrl()` 会统一整理（补 `https://`、去掉结尾 `/`、
去掉误带的 `/rest/v1`）。

⚠️ **顺手防了一个自己挖的坑**：`SyncService` 判断「要不要重建客户端」时用的是
`rest.url == 整理后的设置地址`。如果这两边的整理规则**不一致**，每趟同步都会
认为「地址变了」→ 重建客户端 → 内存里的登录态没了 → **每次同步都重新登录**。
所以现在两处都用 `SupabaseRest.normalizeUrl()` 这一个实现（注释里也写了原因）。

### 3. 文档：两台设备都改菜单听谁的

写进 `setup_supabase.md`：菜单是「谁最后推上去听谁的」，建议固定在一台设备上改；
后台网页的菜单页只读，不会跟 App 抢。

### 4. 切到「订单」页就顺手同步一次（不用干等 25 秒）

定时同步是 25 秒一趟，所以实际用起来会有个感觉：「另一台开的单，我这边要等一会儿才出现」。
而底部三个标签是用 `IndexedStack` 铺的（三个页面一开始就都建好了），
所以在订单页 `initState` 里同步**没用**（那只会在 App 启动时跑一次）。

改成在**底栏切到「订单」**时同步一次（`HomeShell._onSelect`）：
收银员切过去看到的就是最新的。`syncNow()` 自己会判断「没启用 / 正在同步中」，
所以反复切来切去也不会发多余请求，更不会卡住界面（它是后台跑的）。

### 5. 自查：修掉一个「编译不过」的错误（重要）

写这一轮改动时，`lib/services/sync_service.dart` 里的 `onLocalMenuChanged()` **被写了两份**
（新那份带防抖的放在前面，文件后面旧的没删）—— Dart 会直接报
`The name 'onLocalMenuChanged' is already defined`，**整个 App 都编译不过**。
已经把旧的那份删掉，现在全文件只有一份（带 2 秒防抖）。

顺手把「会编译不过/会静默出错」的几类问题用脚本扫了一遍（纯读文本，没跑任何测试）：

- 所有 `lib/`、`test/` 文件的**成员重名**（就是上面这种）→ 除它以外没有别处；
- **花括号/圆括号平衡**：`sync_service.dart` 表面差 7，查下来全是注释里的 `1)` `2a)`
  这种编号（代码部分是平衡的，每个方法结束都回到 0）；
- **`L10n.t('…')` 用到的键**：代码里用到 259 个键，字典里全都有；
- **三语齐全**：295 个文案键 × 3 种语言 = 885 条，正好对上（而且字典是 `const` map，
  同一个语言块里重名的键编译器会直接报错）；
- 编辑残留（`{` 后面被压成一行之类的）→ 没有。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/sync_service.dart` | 订单/菜单共用的 `_scheduleSync()`（防抖 2 秒）；`onLocalMenuChanged()` 不再立刻同步、并 `notifyListeners()` 让状态行马上更新；新增 `menuPending` getter；URL 比较改用 `SupabaseRest.normalizeUrl()`；`dispose()` 里把防抖定时器也取消（否则销毁后醒来会对已销毁对象 `notifyListeners`，会抛异常） |
| `lib/services/supabase_rest.dart` | 新增 `normalizeUrl()`（补协议头 / 去尾斜杠 / 去误带的 `/rest/v1`），构造函数用它 |
| `lib/screens/home_shell.dart` | 底栏切到「订单」时顺手同步一次（`IndexedStack` 导致 initState 只在启动时跑，所以放在这里） |
| `lib/screens/settings_screen.dart` | 状态行加「菜单待上传」（橙字） |
| `lib/l10n/app_strings.dart` | 三语加 `sync.menuPending` |
| `test/sync_service_test.dart` | 新增 1 组：改菜单**防抖**（改两次只推一趟、2 秒后一定推、`menuPending` 跟着变） |
| `test/supabase_rest_test.dart` | 新增 2 组：地址整理的 5 种写法、没写协议头也能真的发出去 |
| `setup_supabase.md` | §8 补「菜单冲突听谁的」+ 地址容错小提示 |

### 你要试的

1. `flutter test`（新用例：`test/supabase_rest_test.dart` 最后两组、
   `test/sync_service_test.dart` 里那组防抖 —— 它会等 3 秒，属正常）；
2. 设置页故意把地址填成 `xxxxxxxx.supabase.co`（不写 https）→ 「测试连接」应该成功；
3. 在「菜品管理」里连着改几道菜 → 设置页状态行先出现橙字「菜单待上传」，
   停手 2 秒后消失（已推上去）；
4. 换台设备（或后台网页「菜单」页）看版本号：一次编辑只应该 +1 版，不是改一次 +1 版；
5. 多设备体感：A 上点一单 → B 上从别的标签切到「订单」→ 应该**立刻**看到那张单
   （不用等 25 秒）。

---

## 后台同步（第 8 阶段）：`flutter analyze` / `flutter test` 报出来的问题（已修）

你跑了 `flutter analyze` + `flutter test`，报出来 2 个**真问题** + 一堆提示。逐条处理：

### ❌ 错误 1：`Category` 名字撞车（**编译不过**，App 也起不来）

```
error - ambiguous_import - lib/services/sync_service.dart:542:25
The name 'Category' is defined in the libraries
'package:big_boss_bro/models/category.dart' and
'package:flutter/src/foundation/annotations.dart' (via package:flutter/foundation.dart)
```

原因：`sync_service.dart` 里写了 `import 'package:flutter/foundation.dart';`（为了 `ChangeNotifier`），
而 Flutter 的 foundation **也导出一个叫 `Category` 的注解类** —— 跟我们自己的
`models/category.dart` 里的 `Category` 撞名，`.map((e) => Category.fromJson(...))` 就不知道用哪个。

**修法**：只导入真正要用的那一个（跟 `pos_controller.dart` 里的写法一致）：

```dart
import 'package:flutter/foundation.dart' show ChangeNotifier;
```

（顺带那个 `List<dynamic> can't be assigned to List<Category>` 是它的连带错误，一起没了。）

### ❌ 错误 2：`test/supabase_rest_test.dart` 里 7 个用例失败

```
登录失败：服务器没返回 access_token
```

**这是测试自己的 bug**（第一轮写这份测试时就埋下了，之前没跑到而已）：
假服务器的 handler 对**任何**请求都返回同一份数据，所以 `signIn()` 收到的是「订单表那几行」
（没有 `access_token`）→ 直接抛错，测试还没跑到正题就挂了。

**修法**：加一个 `loginOk(req)` 助手，每个 handler 第一句先处理 `/auth/v1/token`，
返回 `{'access_token': 'AT', ...}`；表请求/RPC 请求才走各自的假数据。
（`upsert 空列表` 那个用例还多修一点：`called` 必须在 `signIn` 之后重置，
不然「登录那一次」会被算进去。）

### ✅ 顺手清掉的 analyze 提示（都是 info/warning，不改行为）

| 文件 | 提示 | 改法 |
| --- | --- | --- |
| `lib/screens/menu_manage_screen.dart` | warning `undefined_hidden_name`：`import 'package:flutter/material.dart' hide Category;` | material **并不导出** `Category`，这个 `hide` 是多余的 → 去掉 |
| `lib/services/menu_importer.dart` | `prefer_if_null_operators` / `prefer_conditional_assignment` ×3 | 改成 `??` / `??=` |
| `lib/screens/menu_import_screen.dart` | `unnecessary_brace_in_string_interps` | `${first}` → `$first` |
| `lib/services/ticket_builder.dart` | `prefer_const_constructors` ×7 | 那几行是纯数据（测试页内容），加 `const` 安全 → 加了 |
| `lib/widgets/payment_flow.dart` | `use_build_context_synchronously` | 那个 `context` 是**参数**不是 State 的，所以额外加 `!context.mounted` 判断 |
| `test/menu_store_test.dart`、`test/pos_controller_test.dart` | `prefer_const_constructors` ×3 | 加 `const`（测试里的假数据，安全） |
| `test/sync_service_test.dart` | `prefer_interpolation_to_compose_strings` ×2 | 用字符串插值 |

### ⚠️ 故意**不加 const** 的地方（别用 `dart fix --apply` 盲目修）

分析器还会提示这几处「加 const」，但**加了会出 bug**：

- `lib/screens/home_shell.dart`：`IndexedStack` 的三个页面；
- `lib/screens/pos_screen.dart`：底部的购物车栏；
- `lib/widgets/cart_panel.dart`：空购物车提示 `_EmptyCart`；
- `lib/app.dart`：`HomeShell()`。

它们里面都是 `L10n.t(...)` 的文案。加了 `const` 之后，切语言时 Flutter 会因为
「widget 完全没变」而**跳过整棵子树的重建**，界面文字就不会跟着语言变了。
（代码里已经在两处写了注释说明，这次又在 `app.dart` 补了一条。）

### 你要做的

```
flutter analyze     # 应该只剩那几条「const」的 info（故意的）
flutter test        # 应该全绿
```

---

## 后台同步（第 9 阶段）：HTTP `Date` 头解析（analyze 已经干净，测试差最后 1 条）

你第二次跑：`flutter analyze` 里**那个 error 没了**（只剩 const 提示），
`flutter test` **204 通过 / 1 失败** —— 失败的是我自己新加的那条
「翻页 + 响应头里的服务器时间」：

```
Expected: DateTime:<2026-09-20 12:00:00.000Z>
  Actual: <null>
```

### 原因：`DateTime.parse` **不认** HTTP 的日期格式

我在 `_noteServerTime()` 里想当然地用了 `DateTime.tryParse('Sun, 20 Sep 2026 12:00:00 GMT')`。
Dart 的 `DateTime.parse` 只认 ISO 8601 那一套（`2026-09-20T12:00:00Z` 这种），
**不认**「带星期几 + GMT」的 HTTP 日期 → 直接返回 null →
`lastServerTime` 永远是 null（那层「服务器时间上限兜底」就形同虚设，
等于我上一轮写的兜底逻辑一次都没生效过）。

（影响范围说清楚：**正常同步不受影响** —— 增量水位线是按「拉回来的行自己的时间」推进的，
响应头只是个上限保险；但这个保险之前一直是空转，测试也因此红了。）

### 修法：自己解析

`lib/services/supabase_rest.dart` 新增 `SupabaseRest.parseHttpDate()`：

- 先按 RFC 1123 的正则解析 `Wed, 21 Oct 2015 07:28:00 GMT`（月份名查表 → `DateTime.utc`）；
- 不匹配就退回 `DateTime.tryParse`（有些网关/自建代理会给 ISO 串）；
- 都不行返回 null（不抛异常）。

顺带加了 **1 组针对性单测**（三种输入 + 垃圾输入），这样以后再挂，一眼就能看出
是「取响应头」还是「解析」哪一层的问题；翻页那条测试里也加了一句
「确认响应头确实带得上」的断言。

> 写这个解析的时候我自己还数错了一次捕获组下标（`(\d{2}) (\w{3}) (\d{4})` 的顺序是
> **日 / 月名 / 年**，我一开始把「第 3 组」当成月份了 → 查表查的是年份）。
> 改成**具名分组**（`(?<day>…) (?<mon>…) (?<year>…)`）之后这种错误就不可能再犯，
> 也顺手在注释里写明顺序。

### 顺手：把 analyze 归到 0 error / 0 warning / 9 条故意留的 info

- 修掉 3 条 `prefer_const_declarations`（测试里 `final x = const Y(...)` → `const x = Y(...)`）；
- 剩下 9 条 `prefer_const_constructors` 全是**故意不加 const** 的（`home_shell` 三个页面、
  `pos_screen` 的购物车栏、`cart_panel` 的空购物车、`app.dart` 的 `HomeShell()`），
  加了切语言就不刷新，代码里都写了注释说明。

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/supabase_rest.dart` | 新增 `parseHttpDate()`（RFC1123 + ISO 兜底），`_noteServerTime()` 改用它（**不再用 `DateTime.tryParse` 解 HTTP 日期**） |
| `test/supabase_rest_test.dart` | 新增「HTTP Date 头能解析」一组（4 个断言）；翻页那条加「响应头带得上」的前置断言 |
| `test/menu_store_test.dart`、`test/pos_controller_test.dart` | `final x = const Y(...)` → `const x = Y(...)`（清掉 3 条 info） |

---

## 后台同步（第 10 阶段）：真机上报的「同步 0 张」——开关没开，而且界面不说

你的实测：**HTML 后台能连上**（说明项目、SQL、RLS、账号都对），但 App 里结了一单，
数据库里没有；点「立即同步」显示 0 张上传。

### 诊断（读代码推理出来的）

1. 先排除「结账没标脏」：`closeOrder()` 结尾**有** `.touch(deviceId: …)`
   （`pos_controller.dart`），所以结完账这张单是脏的、应该会被推 —— 不是这个原因。
2. 「立即同步」那个 `↑0 ↓0` 是 `status.pushed / pulled`。而 **`syncNow()` 在「开关没开 /
   没填全」的时候是静默 `return` 的**，toast 还是会照旧把**上一次的状态**（全 0）打出来
   —— 看着就像「同步成功，但 0 张上传」。
3. 而「**启用后台同步**」这个开关**默认是关的**（`Settings.syncEnabled = false`），
   它是这一栏最上面的一个 SwitchListTile。填了地址 / key / 账号，但没拨那个开关 →
   正好就是这个现象：**一个请求都没发出去**。

### 改法：让界面自己说清楚，不再静默

| 位置 | 以前 | 现在 |
| --- | --- | --- |
| `SyncService` | 只有 `isConfigured`（不含开关和密码） | 新增 `syncBlockedReason`：返回「为什么同步不了」的文案 key（开关没开 / 没填地址 / 没填 anon key / 没填邮箱 / 没填密码），都齐了返回 null |
| 设置页 · 按钮上方 | 什么都没有 | **橙色警告行**直接写出原因（例如「同步没开：先把上面那个「启用后台同步」开关打开」） |
| 设置页 · 立即同步 | 拦着的时候按了会显示假的 `↑0 ↓0` | 拦着的时候按钮**直接灰掉**；万一还是被调到，toast 直接说原因 |
| 设置页 · 成功 toast | `同步完成: ↑0 ↓0` | `同步完成: ↑N ↓M · 待上传: K` —— ↑0 但待上传 >0 就一眼看出没推上去 |
| 订单页 · 右上角的云 | 开关没开时整块隐藏 | 开关开了但没填全 → 红色 `cloud_off` + tooltip 写原因，点一下弹 SnackBar 说明 |

（`syncEnabled` 是**每台设备各自**的设置：A 开了不代表 B 开了。）

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/sync_service.dart` | 新增 `syncBlockedReason`（5 种情况 + 注释写清「为什么要它」） |
| `lib/screens/settings_screen.dart` | 橙色原因行；立即同步按钮按 `blocked` 灰掉；成功 toast 带「待上传」；拦着时 toast 说原因（顺手删掉不再用的 `configured` 局部变量，否则会有 unused 警告） |
| `lib/screens/orders_screen.dart` | 云朵按钮：blocked 时红色 + tooltip 写明 + 点了弹 SnackBar |
| `lib/l10n/app_strings.dart` | 三语各加 5 条 `sync.blocked*` |
| `test/sync_service_test.dart` | 新增 1 组：5 种拦截情况各返回对应 key，且**拦着的时候真的一张都不发** |

### 你要做的（这次应该就能看到数据了）

1. 设置 → **后台同步（云端）** → 最上面那个「**启用后台同步**」开关**打开**；
2. 确认 4 个框都填了：项目地址 / anon key / 设备名（可选）/ 登录邮箱 + 密码；
3. 点 **测试连接** → 应该弹「连接成功」（这一步能验证地址、key、账号密码）；
4. 然后点 **立即同步** → 应该显示 `同步完成: ↑N ↓M · 待上传: 0`；
5. 回订单页点一单结账 → 最多 2 秒后自动推上去 → 后台网页「已结账的单」里能看到；
6. 如果还是看不到：把设置页那几行文字（状态行 / 橙色警告行）原文发我，
   现在界面会把原因写出来，就不用猜了。

---

## 后台同步（第 11 阶段）：`type 'NULL' is not a subtype of type 'String' in type cast`

你打开开关后点「立即同步」，状态行报了这个类型错误 —— 同步整个失败了。
查下来有**两个**问题：一个是根因（结完账的单上不去后台），一个是「一个坏行拖垮整趟同步」。

### 根因（很可能就是这个）：`close_order` 返回的「一行全 NULL」被当成了正常数据

`close_order()` 是这么写的（`supabase/schema.sql`）：先按 `id` 更新，`returning *`；
如果没更新到（**服务器上还没有这张单**，比如离线开的单），再查一次，查不到就 `return r`
—— 此时 `r` 是一个**所有字段都是 NULL 的组合类型**。

问题在 App 这边：`SupabaseRest.rpc()` 原来只认「响应体是对象」这一种情况，于是
「一行全 NULL」会被当成**正常返回的一行**交上去，然后：

1. 上层拿它去 `Order.fromJson(...)` → `json['id'] as String` 撞上 null →
   **`type 'NULL' is not a subtype of type 'String' in type cast`**（就是你看到的报错）；
2. 更糟的是：**再也不会走「整单推上去」那条路** → 你那一单**永远上不了后台**
   （这也正好解释了“结了一单，数据库里没有”）。

**改法**：`rpc()` 认三种「没有这一行」的写法 —— 响应体是 `null`、
`[{"id":null,…}]`（PostgREST 有时包一层数组）、`{"id":null,…}` —— 一律返回 `null`，
让上层按「整单推上去」处理；另外在 2a 里加了一道硬保险：
**只有回包确实是「我们这张单」（id 对得上）且能解析才采纳，否则整单 upsert**。
结完账的单从此不可能「上不去」。

### 附带：一个坏行不再拖垮整趟同步

服务器上那一行如果 `data` 形状不对（手动改过之类），解析会抛类型错误。
原代码在 `chooseIncoming()` / `_upsertOrders()` 里直接调 `Order.fromJson(...)`，
一抛异常整趟同步就失败 → **一张单都同步不上去**（你之前那单也就一直卡在「待上传」）。

| 位置 | 现在 |
| --- | --- |
| `OrderSync.tryOrderFromRemote()`（新） | 解析失败返回 `null`，不抛异常 |
| `chooseIncoming(..., onBadRow:)` | 跳过解析不了的那一行，并把「坏行」回调出去（纯函数，可测） |
| 拉取 / 推送回包 / 结账回包 / 菜单拉取 四个解析点 | 失败就跳过，只对**那一条**放弃，别的照常同步 |
| `RemoteOrder.fromRow` | `data` 用 `is Map` 判断（原来 `as Map?` 在读取阶段就会抛） |
| 状态栏 | 有坏数据时显示「服务器上有几张单的数据不完整，已跳过（控制台里有详细堆栈）(N)」 |
| 控制台 | `debugPrint` 打出**坏行的完整 payload** + 堆栈（`flutter run` 的终端里能看到） |
| 所有同步错误 | `_fail(e, st)` 现在连**堆栈**一起打出来（这种类型错误光看消息根本不知道在哪一行） |

### 主要改动文件

| 文件 | 改了什么 |
| --- | --- |
| `lib/services/supabase_rest.dart` | `rpc()` 认三种「没有这一行」的写法（`null` / 全 NULL 数组 / 全 NULL 对象），主键为空就返回 null；新增 `_firstRow()` |
| `lib/services/sync_service.dart` | 结账 2a：只有回包 id 对得上且能解析才采纳，否则**整单推上去**；拉取/推送/结账/菜单四个解析点改走 try 版；`_skippedBadRows` 计数并写进状态；`_fail(e, st)` 打堆栈 |
| `lib/services/order_sync.dart` | 新增 `tryOrderFromRemote()`；`chooseIncoming()` 支持 `onBadRow` 回调并跳过坏行；`RemoteOrder.fromRow` 用 `is Map` |
| `lib/l10n/app_strings.dart` | 三语各加 `sync.badRows` |
| `test/supabase_rest_test.dart` | 新增 2 组：三种「全 NULL」都当「没有这一行」、单行被包成数组也能认 |
| `test/sync_service_test.dart` | 新增 2 组：**close_order 回一行全 NULL → 整单推上去**（这个 bug 的回归测试）、服务器上有坏单时同步不失败 |
| `test/order_sync_test.dart` | 新增 1 组：坏行跳过、好行照拉 |

### 你要做的

1. 重新跑（`flutter run`）→ 设置 → 后台同步 → 点**立即同步**；
2. 正常的话：`同步完成: ↑1 ↓0 · 待上传: 0`，后台网页「已结账的单」里就能看到你结的那一单；
3. **如果状态行/控制台还提到「数据不完整」**：把 `flutter run` 终端里那几行
   `后台同步：服务器上的单 xxx 数据不完整，已跳过。payload={...}` **原文发我** ——
   那行 payload 会告诉我服务器上那行到底长什么样，我来判断是补数据还是清掉那行。






