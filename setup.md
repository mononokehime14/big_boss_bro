---

## 1. 一次性：在新环境装好开发工具（只做一次）

> **重要**：开发沙箱里没有 Flutter、没有安卓 SDK，也连不上 pub.dev，所以**无法在沙箱内编译**。
> 请在你的电脑上做下面这些（Windows）。

```powershell
# 装git
winget install Python.Python.3.12

# 装Python winget install Python.Python.3.12

# 装venv 
python -m venv .venv
Desktop development with C++

# 装Node.js
winget install CoreyButler.NVMforWindows


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
flutter create . --platforms=android,windows
```

might need 
```
start ms-settings:developers
```
Enable Developer Mode

---

## 3. 下载依赖 + 跑单元测试（先验证逻辑，不碰真机）

```powershell
flutter pub get
flutter test
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

## 5. 连接打印机（设置页里配）

打开 App → **设置 → 打印机** → 先选「**打印方式**」，三种任选：

### ① Windows 打印机（USB，你用这种）

1. 先在 Windows 里把 USB 小票机装好（你已经 test print 过了，说明驱动 OK）。
2. App 里选「**Windows 打印机（USB）**」→ 点「**选择打印机**」→ 从列表里选你那台。
3. 点「**打印测试页**」验证。

> 原理：走 Windows 后台打印（spooler）的 **RAW** 通道，把 ESC/POS 指令**原样**交给打印机驱动，
> 所以中文用 GBK 编码直出，**不经过系统渲染**，速度快、格式准。
> 若测试页打不出来：多半是驱动把 RAW 拦掉了，改用「通用 / Generic 文本打印机」驱动再试。

### ② 网络 / 以太网 / 局域网打印机

1. 给小票机设一个固定 IP（打印机自带的网络设置、或路由器里绑定）。
2. App 里选「**网络（IP）**」→ 填 **IP** 和 **端口**（多数是 `9100`）→ 点「保存 IP/端口」。
3. 点「**打印测试页**」。Windows 和安卓都能用（纯 TCP）。

### ③ 蓝牙（安卓手机）

1. 手机先和打印机配对。
2. App 里选「**蓝牙**」→ 点「**扫描蓝牙打印机**」→ 选中它 → 打印测试页。

> 三种方式**共用同一套小票排版**（58/80mm、中文按 2 列对齐、厨房单/顾客小票）。

### ④ 打出来乱码 / 纸宽不对？按这 4 步排查

> ✅ **先说结论**：中文乱码的**真凶已经找到并修复** —— 用的第三方包 `gbk_codec` 里
> `gbk.encode()` 返回的是**16 位 GBK 码点**而不是字节流，被当成字节发出去就被截断了（所以只有 ASCII 正常）。
> 已改用正确的 `gbk_bytes.encode()`，并用单元测试把正确字节锁死（`中` → `D6 D0`、9 个中文字 = 18 字节）。
> **所以现在再打测试页，中文很可能已经正常了。**

测试页（内容已固定，每行都有用途）：

```
------ TEST PAGE ------
Paper 80mm  Cols 48
Codec gbk  FontA on
----------------------------------------
ASCII  : 0123456789 ABCDEFG
Espanol: Gracias
中文A(FS&): 恭喜您，打印成功！
中文B(ESCt): 恭喜您，打印成功！
[BIG] ESC/POS CHECK              ← 这行应该是「双倍大小」
----------------------------------------
ruler should touch both edges
```

**第 1 步：先看 `[BIG]` 那行（最重要）**

| 现象 | 结论 | 怎么做 |
|---|---|---|
| **明显比别的字大** | ESC/POS 指令**原样送达**了打印机（RAW 通道正常） | 继续第 2 步 |
| **和普通字一样大** | 中间那层（通常是 **Windows 驱动**）**没把指令透传**，把内容当“文本”重新渲染了 | **这才是乱码根源** → 把该打印机驱动换成 **「Generic / Text Only（通用/纯文本）」**，或改用**网络/蓝牙**通道绕开驱动 |

> 这一条能一锤定音：如果 `[BIG]` 没变大，说明我们发的 `ESC @`、`FS &`、编码字节**全都被改写了**，
> 那不管怎么换编码都不会好。

**第 2 步：看 `中文A(FS&)` / `中文B(ESCt)` 两行**（它们**无视你设的编码**，强制用两种方式打中文）

| 现象 | 结论 | 怎么做 |
|---|---|---|
| 有一行**正常** | 打印机**支持中文** | 「小票编码」设为 **`gbk`**；若只有 B 行正常，告诉我，我把默认指令改成 `ESC t` 方式 |
| **两行都乱码** | 打印机**没有中文字库** | 中文打不了 → 「**小票语言**」设成 **Español**，编码用 `cp850` 或 `latin1` |

> 「**小票语言**」= **界面语言**与**小票语言**分开。
> 你（老板）界面用中文，小票打成西语给客人 —— 正适合你这种西语餐厅。
> 菜品名来自你的 Excel（西语），本来就不受影响。

**第 3 步：刻度尺 / 纸宽**
`----` 应**顶到纸两边**。没顶满 → 设置里「纸宽」选 **80mm**、「铺满纸宽（Font A）」打开。
（你实测关掉它也能铺满，说明你的打印机默认就是 12×24 字体，保持关闭即可。）

**第 4 步：完全打不出来（连空白都没有）**
把该打印机驱动换成 **「Generic / Text Only（通用/纯文本）」** 再试。

> ✅ 我们的编码本身**已经被单测证明是对的**：`test/escpos_test.dart` 会验证
> GBK 中文按 2 字节/字编码且能往返、ASCII 保持单字节、字节流里确实含 `ESC @` / `ESC M 0` / `FS &` / 切纸指令。
> 所以如果打印出来还是乱码，问题在**打印机或驱动**这一侧，不在我们的编码。

---

## 6. 真机运行（安卓，一加 12 为例）

```powershell
# 手机：设置→关于手机→连点“版本号”7次→开“开发者选项”→开“USB调试”或“无线调试”(同一Wi-Fi)
flutter  devices          # 能看到手机
flutter  run              # 首次编译较慢，之后秒装
```

无线调试连不上时：用“无线调试→使用配对码配对”，按提示
`adb pair ip:端口 配对码` 再 `adb connect ip:端口`。

---

## 7. 新增了依赖记得拉一次

这轮加了 `ffi`（Windows 打印用），**改完代码要先跑一次**：

```powershell
flutter pub get
```
