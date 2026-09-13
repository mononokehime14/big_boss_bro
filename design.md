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
点单页点菜 → 底部「下单」          继续点菜 → 「下单」            订单页「进行中」找到该单
 → 购物车选「新单 + 桌号」           → 购物车切「追加到已有单」      → 点「结账」→ 选支付方式
 → 确认                             → 选那张单 → 确认              → 订单转「已结单」
 → 订单变「进行中」                  → 菜并入同一张单               → 打「顾客小票」
 → 打「厨房单」(菜名+数量+桌号)       → 打一张标注(追加)的厨房单      (单价/金额/支付方式)
```

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
│  ├─ app.dart               主题(Loyverse绿 #1FA85A) + 用 MultiProvider 注入全局状态/服务
│  ├─ l10n/app_strings.dart  全部文案 zh/es/en，用 L10n.t('key') 取
│  ├─ models/                数据“形状”：Category/MenuItem/CartItem/Order（含 toJson/fromJson）
│  ├─ data/                  数据存取与默认值：sample_menu/菜单、订单、设置 三个 Store
│  ├─ state/                 业务状态：pos_controller(点单/购物车/结账/历史/菜单)、settings_controller
│  ├─ services/              打印：receipt_print_service(接口)/bluetooth_print_service(蓝牙)/stub_print_service(占位)/receipt_layout(排版)
│  ├─ screens/               整页：home_shell(底部3tab)/pos_screen(点单)/orders_screen(历史)/settings_screen(设置)/menu_manage_screen(菜品)
│  └─ widgets/               可复用块：category_chips/menu_grid/cart_bottom_bar/cart_sheet/payment_flow
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

### 8. 异步与重建（容易踩的两个点）

- **fire-and-forget 加载**：`SettingsController()..load()` 在 provider 里不 await；`load` 完成后 `notifyListeners()` 让界面刷新。所以短暂“默认值 → 读到真实值”的过渡是预期行为。
- **const 对重建的影响**：const widget 实例相同，父级重建时 Flutter 会**跳过它**。
  如果某个 widget 读 `L10n.t(...)`（语言文案）而被包在 `const` 里，切换语言时它不会刷新。
  本项目已把读文案的组件（CategoryChips/CartBottomBar/空状态等）改为**非 const**，并在 `app.dart` 用
  `ValueListenableBuilder` 监听语言切换。

### 9. 命名空间与名字冲突（务必记住）

Flutter 自带的 `foundation.Category` 与我们 `models/category.dart` 的 `Category` 重名，
同文件既 import 两者会冲突。解决方案是 `import 'package:flutter/...' hide Category` 或
`show ChangeNotifier`。详见 `troubleshooting.md` 问题 1。**新文件碰到类似情况照做即可。**

### 10. 测试策略

- `test/receipt_layout_test.dart`：金额、中文按 2 列、58/80mm 不爆行、小票内容。
- `test/pos_controller_test.dart`：点单逻辑（加购/数量合并/合计/结账/清空/删除/菜单CRUD/恢复默认）。
- `test/order_store_test.dart`、`test/menu_store_test.dart`：持久化保存→读回。
- `test/widget_test.dart`：App 能启动并出现“菜单”。
这些都用**纯逻辑 + 假存储**（`SharedPreferences.setMockInitialValues`），不需要真机/打印。

---

## 六、常见坑速查

> 详细“现象 + 原因 + 处理”都集中在 **`troubleshooting.md`**，这里只放清单：
- 1️⃣ `Category` 名字冲突 → `hide Category` / `show ChangeNotifier`
- 2️⃣ Windows 构建报 `BluetoothConnection.output` 的 `Uint8List` / `allSent` → 用 `Uint8List.fromList` + `output.allSent`
- 3️⃣ 切语言文字不刷新 → 不要用 `const` 包住读 `L10n.t` 的组件；`app.dart` 监听 `L10n.lang`
- 4️⃣ `flutter test` 报 `MyApp` 未定义 → `flutter create` 生成的默认测试覆盖了你的 `widget_test.dart`，删掉即可

---

## 七、怎么跑起来 / 测试

- Windows 收银机：见 **`setup.md`**（`flutter run -d windows`、打包 exe）。
- 完整步骤：`flutter create . --platforms=android,windows` → `flutter pub get` → `flutter test` → `flutter run`。
- 真机验证：设置页先打“打印测试页”确认中文不乱码，再正式点单打小票。

---

## 八、后续可扩展点

- **Windows USB/网络打单**：新增一个实现 `ReceiptPrintService` 的类，在 `main.dart` 换掉即可。
- **菜品图片 / 折扣 / 桌号 / 税**：`models` 加字段 → `pos_controller` 加逻辑 → 界面加输入 → 小票加行。
- **西语/英语补全**：往 `app_strings.dart` 对应 map 加 key。
- **日结算**：今天所有结过的单子做一个汇总（可按日期统计营业额/单数）。
- **分开支付（AA）**：从购物车挑出几项先结，剩下的再结，方便多人各自付各自。
