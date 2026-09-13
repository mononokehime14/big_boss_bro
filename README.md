# big_boss_bro — 餐厅收银打单应用（类 Loyverse）

一套 Flutter 源码，同时编译出 **安卓** 和 **Windows** 两个平台。

- 点单 dashboard（分类 + 菜品格子）
- 购物车、改数量、结账
- 蓝牙热敏打印机打小票 + 打印失败“重试/跳过，绝不丢单”
- 已结订单历史（含删除）
- 多语言：中文（当前）/ 西语 / 英语

> 🖥️ 想在 **Windows 触屏收银机**上跑（安卓手机不在时）：请直接看 **`setup.md`**。
> 架构与代码怎么分层、`Category` 名字冲突的坑，看 **`design.md`**。

---

## 目录结构

```
lib/
  main.dart                           程序入口（在这里选打印服务）
  app.dart                            主题（Loyverse 绿） + Provider 装配
  l10n/app_strings.dart               全部文案（zh/es/en）
  models/                             分类 / 菜品 / 购物车行 / 订单
  data/sample_menu.dart               示例菜单（写死，之后自己做管理界面）
  data/settings_store.dart            设置存取（存到本机 shared_preferences）
  state/pos_controller.dart           点单状态（购物车、结账、订单历史）
  state/settings_controller.dart      设置状态
  services/receipt_print_service.dart 打印服务【接口】
  services/bluetooth_print_service.dart 蓝牙打印【实现】
  services/receipt_layout.dart        小票排版（纯逻辑，方便单测）
  screens/                            主页 / 点单 / 订单 / 设置
  widgets/                            分类标签 / 菜品格子 / 购物车 / 结账流程
  utils/format.dart                   金额格式化
```

## 在你电脑上跑起来（一步步）

> 说明：你的项目源码我已经写好。下面 1–3 步是**装开发环境**（一次性），
> 之后就能直接在手机上看到界面了。

### 第 1 步 装 Flutter SDK（Windows）

打开一个 **PowerShell** 窗口，运行：

```powershell
# 用 git 拉取（若没装 git，先到 https://git-scm.com 装它）
git clone https://github.com/flutter/flutter.git C:\flutter
C:\flutter\bin\flutter  --version   # 首次会下载 Dart SDK，稍等
```

> 让 `flutter` 全局可用：把 `C:\flutter\bin` 加进系统环境变量 `PATH`。
> 或者每次用全路径 `C:\flutter\bin\flutter`。

### 第 2 步 装 Android 开发环境（JDK + Android SDK）

推荐用 **Android Studio** 一键装好（会带 JDK17 和 Android SDK）：

```powershell
winget install Google.AndroidStudio
```

装完打开 Android Studio → 右上角 `SDK Manager` → 勾选 **Android SDK Platform 34**、
**Android SDK Build-Tools**、**Platform-Tools** → 应用。

再运行一次 flutter 确认：

```powershell
C:\flutter\bin\flutter  doctor
```

`doctor` 里 Android toolchain 那项打勾（✓）就说明配好了。

### 第 3 步 生成安卓/Windows 原生工程

在你这个项目目录（`big_boss_bro`）里运行一次（**不会覆盖**我写好的 `lib/` 和 `pubspec.yaml`，
只是生成 `android/`、`windows/` 这些原生外壳）：

```powershell
C:\flutter\bin\flutter  create . --platforms=android,windows
```

### 第 4 步 下载依赖

```powershell
C:\flutter\bin\flutter  pub get
```

### 第 5 步 手机开无线/USB 调试

以**一加 12** 为例：

1. 手机：设置 → 关于手机 → 连点“版本号”7 次 → 开启“开发者选项”。
2. 设置 → 开发者选项 → 打开 **USB 调试**（有线）或 **无线调试**（和电脑同一 Wi-Fi）。
3. 电脑上：

```powershell
C:\flutter\bin\flutter  devices        # 看到你的手机
C:\flutter\bin\flutter  run            # 首次编译稍慢，之后秒装
```

> 如果无线调试连不上：用 **无线调试 → 使用配对码配对设备**，然后按提示执行
> `adb pair ip:端口 配对码`，再 `adb connect ip:端口`。

成功后在手机上就能看到点单界面了。

---

## Android 蓝牙权限 & 打包安装包

### 蓝牙权限（Android 12+ 必须）

在 `android/app/src/main/AndroidManifest.xml` 里，`<manifest>` 下加：

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

> 蓝牙打印包一般会在**运行时**替你申请授权，第一次连接时系统会弹窗，点允许即可。

### 打一个安卓安装包（APK）

```powershell
C:\flutter\bin\flutter  build apk --release
```

产物在 `build\app\outputs\flutter-apk\app-release.apk`，发到手机直接装。

---

## 蓝牙打印小票

- **扫描/连接/打印/切纸** 都在 `lib/services/bluetooth_print_service.dart`。
- 首次连接需要在设置页点 **扫描蓝牙打印机**，选中你的打印机。
- 设置页还提供 **打印测试页**：先打一张中文测试页确认不乱码、纸宽正确。
- Android 12+ 运行时需要申请蓝牙权限（已处理，第一次连接时系统会弹窗）。

> 用到的包（已锁定版本）：`flutter_bluetooth_serial`（蓝牙传输）、
> `permission_handler`（安卓12+权限）、`gbk_codec`（中文 GBK 编码）。

---

## 多语言

所有文案在 `lib/l10n/app_strings.dart`，用 `L10n.t('key')` 取。
当前含 `zh / es / en` 三套，设置页可切换语言。加新文案只需三套 map 各加一行。

---

## 后续要做（不在第一步）

- Windows 版 USB 打单
- 菜品图片、折扣、桌号、税
- 西语/英语界面补全

> 菜单（分类/菜品）已可在「设置 → 菜品管理」里增删改并保存；示例菜单仅作初次默认。
