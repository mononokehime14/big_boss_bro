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
