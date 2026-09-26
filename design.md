# design.md — 项目架构与系统设计说明

> 面向**第一次做开发**的你。用大白话，也讲得足够“系统化”：这个 App 分几层、
> 一次点单的数据走到哪、Provider/ChangeNotifier 到底怎么驱动界面刷新、为什么这样设计。
> 技术栈：Flutter 跨平台（Android + Windows）。

---

## 一、这个 App 是干什么的

一个餐厅收银台：服务员/收银员在屏幕上点菜 → 客人付钱 → 打印机打小票 →
订单记进“已结订单”，可查看/删除。界面中文，可切西语/英语。

---

## 二、一次完整的业务流转（flow）

```
① 点菜 + 下单（给厨房）            ② 追单（可选）                ③ 结账（给顾客）
------------------------        ------------------           ------------------
购物车顶部下拉选「桌号 / 外卖」      继续点菜                     订单页「进行中」找到该单
 → 点菜 → 「下单」                 → 按钮自动变「加单」           → 点「结账」→ 选支付方式
 → 确认（打厨房单）                 → 确认（打标注「追加」的厨房单） → 订单转「已结单」
 → 订单变「进行中」                  → 菜并入同一张单               → 打「顾客小票」(单价/金额/支付方式)
```

> **下单目标（桌号/外卖）怎么选**：不用先选桌、也不用进单独页面，**就在右侧购物车最上面的下拉框里选**
> （`widgets/cart_panel.dart` 的 `_targetSelector`）。理由是收银员点菜和「给哪桌」是同一件事的两半，
> 放在一起就不用为「改桌」跳来跳去。下拉里**已有菜的桌子标橙色 +「已有 N」**，空桌标绿色，
> 一眼能看出哪桌还在吃。选中堂食某桌时，如果那桌有进行中的单，按钮自动变「**加单**」
> （`PosController.openOrderForSelectedTable()` 判定）；**外卖永远不自动并入**（每单独立）。

> **结账这一步现在能做的事**（`widgets/payment_flow.dart` 的收款框）：
> 看金额明细（小计/折扣/税/合计）→ 给**折扣**（百分比或减金额）→ 选**收款币种**（MXN/USD/RMB，
> 每格显示该币种的应收与汇率）→ 选现金（输入实收，下面大字显示找零）或刷卡（显示应收 + 银行卡动画）。
> **一单一次收清**（不做 AA），收完即结单并打顾客小票。

**两条关键设计**
1. **先记单、后打印**：只要确认下单/结账，订单立刻保存；打印失败只提示“重试/跳过”，**订单绝不丢**。
2. **两种打印**：
   - **厨房单**（下单/追单时）：只有 `菜名 + 数量 + 桌号`，不含价格 —— 给厨房做菜用。
   - **顾客小票**（结账时）：含 `单价 / 金额 / 合计 / 支付方式 / 谢谢光临` —— 给客人。

---

## 三、目录结构解说

```
big_boss_bro/
├─ lib/
│  ├─ main.dart              入口：按平台选打印服务 → 启动 App
│  ├─ app.dart               主题(Loyverse绿 #1FA85A) + MultiProvider 注入全局状态/服务 + **登录门禁**
│  ├─ l10n/app_strings.dart  全部文案 zh/es/en，用 L10n.t('key') 取
│  ├─ models/                数据“形状”：Category/MenuItem/CartItem/Order(+Payment)/Account
│  ├─ utils/                 纯函数规则：pricing(折扣/税/金额)、category_colors、format
│  ├─ data/                  数据存取与默认值：sample_menu/菜单、订单、设置、**账号** 四个 Store
│  ├─ state/                 业务状态：pos_controller(点单/购物车/结账/收款/历史/菜单)、settings_controller、**auth_controller(账号/权限)**
│  ├─ services/              打印与统计：receipt_print_service(接口)/print_service(三通道分发)/receipt_layout(排版)/sales_totals(日结统计)/escpos/ticket_builder/menu_importer
│  ├─ screens/               整页：home_shell(底部3tab)/login_screen(**登录**)/pos_screen/orders_screen/daily_summary_screen/settings_screen/menu_manage_screen/menu_import_screen/**accounts_screen**
│  └─ widgets/               可复用块：menu_area/menu_grid/cart_panel/payment_flow(**收款框**)/admin_gate/account_menu
├─ test/                     单元/冒烟测试
├─ android/ windows/         Flutter 自动生成的原生外壳
├─ pubspec.yaml              依赖清单  assets/ 资源
├─ README.md  setup.md  log.md  design.md  troubleshooting.md  PLAN.md
```

---

## 四、三层架构（总览）

Flutter 推荐“界面层 → 状态层 → 数据/服务层”，本项目就是：

```
┌──────────── 界面层 (UI) ──────────────┐
│ screens/ + widgets/                   │
│ 只管“显示什么”和“用户点了就调状态层”    │
│ 例：点菜 → pos.addToCart(item)         │
└───────────────┬───────────────────────┘
                │ 通过 Provider 读状态 / 调方法
┌───────────────▼───────────────────────┐
│ 状态层 (State)                         │
│ state/pos_controller (ChangeNotifier) │
│ 持有：购物车/选中分类/订单(进行中+已结)/菜单│
│ 方法：addToCart/increment/decrement/    │
│   removeFromCart/clearCart/            │
│   placeOrder(下单)/appendToOrder(追单)/ │
│   closeOrder(结账)/deleteOrder/         │
│   分类菜品CRUD/resetMenu                │
│ 任何一变 → notifyListeners()            │
└───────────────┬───────────────────────┘
                │ 读写
┌───────────────▼───────────────────────┐
│ 数据/服务层 (Data & Services)           │
│ data/×Store + models/  持久化(JSON)    │
│ services/ReceiptPrintService 接口→实现│
└───────────────────────────────────────┘
```

**为什么这样分层**
- 界面不碰业务：算钱/记单在 `pos_controller`，界面只负责“画”和“叫”。
- 单一数据源：所有状态集中在 controller，杜绝界面各写一份导致的不一致。
- 打印可替换：`ReceiptPrintService` 是接口，安卓用蓝牙、Windows 用别的，界面代码不用改。

---

## 五、系统设计深入（重点）

### 1. 状态管理：ChangeNotifier + Provider

**ChangeNotifier** 是一个“变化通知器”。它维护一堆“听众”。当你调用 `notifyListeners()`，
所有听众都会收到“我变了”的信号。

```dart
class PosController extends ChangeNotifier {
  int _total = 0;
  int get total => _total;
  void add(int n) { _total += n; notifyListeners(); }  // 通知界面
}
```

**Provider** 把它放进“全局”，让任何界面都能读到同一个实例，并订阅它的变化。
`app.dart` 用的是 `MultiProvider`，一次性注入 3 个全局对象：

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => PosController()),              // 状态：点单
    ChangeNotifierProvider(create: (_) => SettingsController()..load()), // 状态：设置
    Provider<ReceiptPrintService>.value(value: printService),           // 服务：打印(非状态)
  ],
  child: ... MaterialApp(...),
)
```

### 2. 三种读取方式：watch / read / listen（关键）

Provider 给 `BuildContext` 提供了三种用法，语义不同：

| 方式 | 语义 | 什么时候用 |
|---|---|---|
| `context.watch<T>()` | **读 + 订阅**：这个值一变，当前 widget 自动重新 build | 界面 build 里取值，需要响应变化 |
| `context.read<T>()` | **只读一次**：订阅，但值变化不重建当前 widget | 事件回调里取值（如按钮的 onPressed）|
| `context.listen<T>()` | 订阅 + 拿到值，值变化时执行一段代码 | 需要“值变了就做某事”但又不重建界面的场景 |

> 新手最容易犯的错：在 `build` 里用了 `read`，导致“看起来没反应”；
> 或在非 build 阶段用了 `watch`。记住：**要响应变化就用 watch，只在回调里拿值就用 read。**

### 3. 一次点菜点击，数据怎么走（数据流）

```
点“牛肉炒饭”格子
 → 该格子的 onTap → context.read<PosController>().addToCart(item)
      ↑ 这里是 read：只在点击时拿一次状态，调用方法
 → PosController.addToCart 改 _cart（同一道菜数量+1）
 → notifyListeners()
 → 所有 context.watch<PosController>() 的 widget 收到变化，重新 build
 → 菜单格子的数量徽标、底部购物车的“件数+合计”都刷新
```

结论：**“数据在 controller 里改一次，界面靠订阅自动同步”**，不需要你手动去改每个界面文字。

### 4. 依赖注入（打印服务怎么“塞”进去的）

- `main.dart`：判断平台 `Platform.isAndroid` → 安卓用 `BluetoothReceiptPrintService`，否则 `UnsupportedPrintService`。
- `app.dart`：`Provider<ReceiptPrintService>.value(value: printService)` 注入全局。
- 界面用 `context.read<ReceiptPrintService>()` 取。
好处：打印服务在哪初始化、用什么实现，集中在 `main.dart`，界面完全不用关心。

### 5. 数据持久化（重开 App 还在）

三个 `data/*_store.dart`，都基于 `shared_preferences`（键值存储，简单可靠）：

| Store | 存什么 | 何时写 |
|---|---|---|
| `order_store.dart` | 订单列表(JSON，含进行中/已结单) | 下单/追单/结账/删除订单时写；启动读回 |
| `menu_store.dart` | 分类+菜品(JSON) | 增删改菜单/恢复默认时写；启动读回 |
| `settings_store.dart` | 店名/货币/纸宽/打印机地址/**桌号列表** | 设置保存时写；启动读回 |

- 用 JSON 序列化（`models` 里有 `toJson/fromJson`）。
- 启动时**异步**读回：`..load()` 在 provider 里 fire-and-forget，读完 `notifyListeners()` 刷新界面。
- **安全回退**：数据损坏时 `load()` 返回 null/默认，不让 App 崩。

### 6. 打印服务的抽象（关键设计）

打印被拆成**「排版 → 字节 → 通道」**三层，互不干扰：

```
订单 + 设置
   │
   ├─ services/ticket_builder.dart   把订单排成“行文本”（厨房单 / 顾客小票 / 测试页）
   │
   ├─ services/escpos.dart           行文本 → ESC/POS 字节（GBK 编码中文、初始化、切纸）
   │
   └─ services/print_service.dart    UnifiedPrintService 按【打印方式】把字节发出去
          ├─ bluetooth_print_service.dart   蓝牙 SPP（安卓）
          ├─ network_print_service.dart     网络/以太网：纯 TCP，默认 9100
          └─ windows_print_service.dart     Windows 系统打印机：dart:ffi → winspool.drv → spooler RAW
```

- 接口仍是 `ReceiptPrintService`，界面只依赖它；换通道 = 设置里换个选项，界面代码不动。
- **为什么 Windows 走 spooler 的 RAW**：这才是把 ESC/POS 指令**原样**交给打印机的方式（不经系统渲染），
  中文用 GBK 直出、速度快、排版准。技术上是 `dart:ffi` 调 `winspool.drv` 的
  `OpenPrinterW → StartDocPrinterW(RAW) → StartPagePrinter → WritePrinter → EndDocPrinter`。
- **蓝牙服务按需创建**：`UnifiedPrintService` 里用 `BluetoothPrintService? _btInstance`，
  只有真的选蓝牙才会去碰蓝牙插件——避免 Windows 上无谓地初始化移动端插件。
- 未来加新通道（例如串口 COM、云端打印）= 再写一个分支，其它层都不用动。

> ⚠️ **为什么 Windows 构建也会编译蓝牙文件**（踩过的坑）：`main.dart` 无条件 `import 'bluetooth_print_service.dart'`，
> 即使 Windows 不会用它，Dart 也会把该文件连同其依赖编译进 Windows 版。
> 所以**蓝牙文件本身的类型必须能在 Windows 下编译通过**（详见 `troubleshooting.md` 问题 2）。

### 7. 订单生命周期（进行中 / 已结单）

- `Order` 带 `status`（`inProgress`/`completed`）、`table`（桌号）、可空的 `paymentMethod`、`closedAt`。
- 状态层把「所有订单」放在一个列表 `_orders`，界面用两个 getter 分类展示：
  `inProgressOrders` / `completedOrders`。
- 关键方法：
  - `placeOrder(table:)`：购物车 → 新的**进行中**单（→ 打厨房单）。
  - `appendToOrder(id)`：购物车**并入**某张进行中的单（合并同名同价的行、重算合计）。
  - `closeOrder(id, method)`：进行中 → **已结单**（记支付方式/结单时间 → 打顾客小票）。
- 这样“加菜/追单”“先下单后结账”“一桌多次点单”都天然支持。

### 8. 菜单来源：手输 or **Excel 导入**，以及**个性化定制**

**菜单数据的来源**
```
Excel(.xlsx) ──xlsx_reader──> 二维字符串表 ──menu_importer──> MenuData(分类+菜品+定制项)
                                                                    │
                                        PosController.replaceMenu() ─┘─> MenuStore 持久化 ─> 界面
```
- `services/xlsx_reader.dart`：xlsx 就是个 zip，自己解压后读 `sharedStrings.xml` + `worksheets/sheet1.xml`，
  拼成「二维字符串表」。**故意不依赖 `excel` 包**（它的 API 跨大版本变过，容易踩坑）。
- `services/menu_importer.dart`：**按表头名字**识别列（中/英/西都认），然后再解析：
  - `分类` / `菜名` / `价格`(可选) / `图标`(可选)
  - **其余列两两一组** = `(定制项名, 选项列表)`，选项用 `/` 分隔 → `Size` + `Mediano/Grande`
  - 价格兼容 `12,50`（西语逗号小数）与 `€9.90`
- 导入是**整表替换**：`replaceMenu()` 会覆盖分类/菜品、清空购物车（避免指向已不存在的菜）并落盘。

**个性化定制怎么进到订单里**
- `MenuItem.options : List<MenuOptionGroup>`（来自 Excel 的定制项）。
- 点菜时 `item_customize_sheet.dart` 收集两个东西：**所选的选项** + **「其他备注」**，
  然后 `pos.addToCart(item, selections:, note:)`。
- 购物车用**复合键** `CartItem.key = 菜id|选项|备注`：
  所以「同一道菜、大份」和「同一道菜、中份」是**两行**，不会互相覆盖。
- 订单行 `OrderLine` 也带 `options/note`，于是**厨房单和顾客小票**都会在菜名下面缩进打印出来。
- 「其他备注」的**常用标签**存在 `Settings.savedNotes`（设置页可增删）；
  定制弹窗里点标签即可复用，输入新备注时可勾选「存为常用标签」。

**点单界面：两步导航 + 分类配色**

- `PosController.selectedCategoryId` 为空 = **第一步（选种类）**，非空 = **第二步（选菜品）**。
  `widgets/menu_area.dart` 根据它切换：`CategoryGrid`（种类卡片）↔ `CategoryHeader + MenuGrid`。
  点顶部色条 → `clearCategory()` 回到种类列表。
- 配色在 `utils/category_colors.dart`（**纯 Dart**，服务和测试都能用）：
  10 色调色板 + `paletteColorAt(index)`。**按分类顺序轮换取色，所以相邻分类必然不同色**。
  `Category.colorValue` 存最终颜色；为 0 时按序号自动取，用户也能在「菜品管理」里手动指定。
- 菜品格子**底色 = 所属分类颜色**、白字显示菜名与价格（不再用 emoji/图案占位）。
- 弹出窗统一**居中**：个性化定制用 `Dialog`（`widgets/item_customize_dialog.dart`），
  选打印机用 `AlertDialog`——比底部抽屉更适合大屏触控收银机。

### 9. 金额规则：折扣与税（**只写一遍**）

「金额算错」是收银系统最要命的 bug，所以规则**只集中在一处**：`utils/pricing.dart`。

```
小计 subtotal = Σ(单价 × 数量)
折扣 discount = 小计 × 折扣率   或   固定金额（上限 = 小计）
净额 net      = 小计 - 折扣
税   tax      = 价外税：net × 税率        价内含税：net - net×100/(100+税率)
应收 total    = 含税 ? net : net + tax
```

- `PriceBreakdown.of(...)` 是**纯函数**：购物车、订单、收款框、小票、日结全调它，
  杜绝「购物车显示一个数、小票打另一个数」。每次计算都过 `round2()`（四舍五入到分）。
- **顺序**：先打折、后算税（各地税务的通行做法）。
- **什么时候算**：
  - 税 —— 设置里配（税率 + 含税开关），**下单时快照进订单**（`Order.taxRate/taxIncluded`），
    以后改设置不影响已开的单；`appendToOrder()` 用订单自己的税率重算。
  - 折扣 —— **结账时**由收银员在收款框里输，写进订单（`Order.discountType/discountValue`）；
    追单时也用订单自己的折扣重算，不会丢。
- 归类：`DiscountType`（none/percent/amount）也在 pricing 里，`Order.discountLabel()` 负责显示成 `-10%` / `-¥20.00`。

### 10. 账号与权限（管理员 / 收银员）

```
accounts(JSON) ──AccountStore──> AuthController ──> app.dart 门禁(未登录 → LoginScreen)
                                        │
                                        ├─ requireAdmin(context)：管理员直通 / 收银员输管理员密码**临时提权**
                                        └─ 界面里的危险入口（设置、日结、删单、菜单管理）都包一层它
```

- 角色只有两种，避免复杂：`admin`（菜单/设置/日结/删单/账号管理）、`cashier`（点单/下单/结账/打折）。
- **默认管理员**：`admin` / `8888`；`AccountStore.load()` 发现一条账号都没有时**自动创建**，
  保证任何情况下都进得去（不会把自己锁在门外）。
- **提权（elevate）**：收银员做管理员的事时弹「请输入管理员密码」，对了就在**本次会话**内有效，
  退出登录/重启即失效。好处是收银台前面不用「退出→登录→做事→再退出→登录」。
  这个状态记在 `AuthController._elevated`，界面用 `canManage` 判断、`isElevated` 给提示。
- 密码是**明文存本机**的：这类离线收银机只需要挡「店员随手改菜单」，不用于防攻击；
  真要更安全，以后把 `Account.pin` 换成哈希即可（改动只在 `Account` 和 `AuthController`）。
- 安全护栏写在控制器里（不是界面里）：**不能删自己、不能删/降级最后一个管理员**。

### 11. 收款：一次收清 + 三个币种 + 汇率

```
收款框（widgets/payment_flow.dart）
  ├─ 应收（大字，本位币）+ 小计 / 折扣 / 税 / 合计明细
  ├─ 收款币种：MXN / USD / RMB —— 每格写着「这个币种要收多少」+ 汇率
  ├─ 现金 → 输入实收 → **大字找零**（不够就红字「还差」并禁用确认按钮）
  └─ 刷卡 → 应收 + 银行卡动画（widgets/bank_card_anim.dart）
        │
        └─ CheckoutResult ──> PosController.closeOrder() ──> 打「顾客小票」
```

- **一单一次收清**：不做分开付（AA 已按你的要求删掉），所以 `Order.payments` 实际只有一条。
  保留成列表是为了**老数据能读回来**（`Order._paymentsFromJson` 把只有 `paymentMethod` 的老单补成一条收款）。
- **汇率口径**（`Settings.exchangeRates`）：**1 个外币 = 多少「店里收钱的货币」**（本位币 = `Settings.baseCurrency`）。
  例：本位币 MXN、`1 USD = 18.5` → 应收 84 MXN 在收款框里显示成 `$4.54 USD`。
  本位币自己的汇率恒为 1；没填（0）表示**没设汇率** → 那格是灰的，不瞎换算。
  换算只有两个纯函数：`toForeign()` / `toBase()`（`utils/pricing.dart`，有单测）。
  汇率在「**菜品管理 → 币种与汇率**」里改（老板改菜单时顺手能改）。
- **账怎么记（关键不变量）**：
  - `Payment.amount` **永远记本位币**（= 订单应收）→「已收 = 应收」永远成立，日结总营业额永远对得上；
  - `Payment.received` / `change` 记**客人那个币种**的数字（实收/找零按那个币种打在小票上）；
  - `Order.exchangeRate`：**0 = 用店里的货币收的**（不需要换算），> 0 = 外币汇率。
    界面和打印都用这一条判断「是不是外币单」（`Order.isForeignCurrency`）。
- **日结**（`services/sales_totals.dart`）：刷卡按订单应收（本位币）汇总；
  现金**按客人付的币种分行**，金额取 `实收 - 找零`（= 钱箱里实际剩下的那种钱）。
  所以「现金 USD」那一行是「钱箱里有多少美元」，而总营业额始终是本位币 —— 单位不同、不会对不上账。
- **刷卡动画**：不连刷卡机，纯用 `AnimationController` + `Transform` 画一张会摇晃的卡 + 波纹，
  只表示「请在刷卡机上操作」；刷卡机成功了收银员再点确认（钱的事不让程序自己猜）。
- **菜品单位**：`MenuItem.unit`（Excel 的「单位」列）沿 `CartItem → OrderLine.unit` 带到小票；
  菜单格子和购物车显示 `¥140.00 / 份`，厨房单的数量栏打 `2 份`；
  **单位太长就只打数量**（`_qtyCell` 先量显示宽度），免得把整张票的列挤歪。

### 12. 异步与重建（容易踩的两个点）

- **fire-and-forget 加载**：`SettingsController()..load()` 在 provider 里不 await；`load` 完成后 `notifyListeners()` 让界面刷新。所以短暂“默认值 → 读到真实值”的过渡是预期行为。
- **const 对重建的影响**：const widget 实例相同，父级重建时 Flutter 会**跳过它**。
  如果某个 widget 读 `L10n.t(...)`（语言文案）而被包在 `const` 里，切换语言时它不会刷新。
  本项目已把读文案的组件（CategoryChips/CartBottomBar/空状态等）改为**非 const**，并在 `app.dart` 用
  `ValueListenableBuilder` 监听语言切换。

### 12. 命名空间与名字冲突（务必记住）

Flutter 自带的 `foundation.Category` 与我们 `models/category.dart` 的 `Category` 重名，
同文件既 import 两者会冲突。解决方案是 `import 'package:flutter/...' hide Category` 或
`show ChangeNotifier`。详见 `troubleshooting.md` 问题 1。**新文件碰到类似情况照做即可。**

### 13. 测试策略

- `test/pricing_test.dart`：**折扣 / 税 / 取整 / JSON 往返 / 老数据兼容**（金额规则只有这一处，必须钉死）。
- `test/currency_test.dart`：**汇率换算 / 外币结账 / 小票上的币种与单位 / 日结按币种分现金**。
- `test/auth_test.dart`：默认管理员、登录、临时提权、不能删自己/最后一个管理员、账号持久化。
- `test/receipt_layout_test.dart`：金额、中文按 2 列、58/80mm 不爆行、小票内容。
- `test/pos_controller_test.dart`：点单逻辑（加购/数量合并/合计/结账/清空/删除/菜单CRUD/恢复默认）。
- `test/order_store_test.dart`、`test/menu_store_test.dart`、`test/settings_test.dart`：持久化保存→读回。
- `test/widget_test.dart`：**先验证登录页，再用默认管理员登录**，能看到“菜单”标签。
- 这些都用**纯逻辑 + 假存储**（`SharedPreferences.setMockInitialValues`），不需要真机/打印。

---

## 六、常见坑速查

> 详细“现象 + 原因 + 处理”都集中在 **`troubleshooting.md`**，这里只放清单：
- 1️⃣ `Category` 名字冲突 → `hide Category` / `show ChangeNotifier`
- 2️⃣ Windows 构建报 `BluetoothConnection.output` 的 `Uint8List` / `allSent` → 用 `Uint8List.fromList` + `output.allSent`
- 3️⃣ 切语言文字不刷新 → 不要用 `const` 包住读 `L10n.t` 的组件；`app.dart` 监听 `L10n.lang`
- 4️⃣ `flutter test` 报 `MyApp` 未定义 → `flutter create` 生成的默认测试覆盖了你的 `widget_test.dart`，删掉即可
- 5️⃣ `const` map 里 key 写重 → 编译报错（`app_strings.dart` 加文案时注意别和已有的重名）
- 6️⃣ 加了「登录门禁」后旧的冒烟测试会挂 → 测试要**先登录**再断言主界面（见 `test/widget_test.dart`）
- 7️⃣ 金额算错 → 只改 `utils/pricing.dart`，别在界面里另算一遍

---

## 七、怎么跑起来 / 测试

- Windows 收银机：见 **`setup.md`**（`flutter run -d windows`、打包 exe）。
- 完整步骤：`flutter create . --platforms=android,windows` → `flutter pub get` → `flutter test` → `flutter run`。
- 真机验证：设置页先打“打印测试页”确认中文不乱码，再正式点单打小票。

---

## 八、后续可扩展点

- **Windows USB/网络打单**：已实现（`print_service.dart` 三通道分发）；再加通道只需实现 `ReceiptPrintService`。
- **菜品图片 / 零钱柜**：`models` 加字段 → `pos_controller` 加逻辑 → 界面加输入 → 小票加行。
- **西语/英语补全**：文案已补齐（`app_strings.dart` 三个 map），还差**逐屏人工检查**（长文案会不会挤爆布局）。
- **折扣更细**：现在是「整单折扣」。要做**单品折扣**就在 `OrderLine` 上加折扣字段，
  并让 `PriceBreakdown` 的小计改成「按行算完再相加」；规则仍然只改 pricing 一处。
- **税更细**：现在是「全店一个税率」。要做**按菜品分类不同税率**，
  给 `Category`/`MenuItem` 加 `taxRate`，然后 `PriceBreakdown` 按行累加税（应收 = 各行净额+各行税）。
- **AA 更细**：现在**没有**分开付（已按要求删掉）。真要做「按菜分账」（谁点了哪几个菜谁付），
  在收款框里加一个「按菜勾选」界面，把选中的行金额作为本次收款额，
  并让 `closeOrder` 支持传入已收金额（数据模型不用改：`payments` 本来就是列表）。
- **账号安全**：`Account.pin` 明文 → 换哈希（只动 `Account` / `AuthController`）。
- **云端同步 / 多收银台**：现在全部是本机 `shared_preferences`；要联网得加一层「Store 的远端实现」，
  界面和控制器不用改（这也是把存取的 `data/×Store` 单独放一层的原因）。
