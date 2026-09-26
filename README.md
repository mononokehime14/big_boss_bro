# big_boss_bro — 餐厅收银打单应用（类 Loyverse）

一套 Flutter 源码，同时编译出 **安卓** 和 **Windows** 两个平台。

- 点单 dashboard（种类 → 菜品两步，格子按种类配色）
- 购物车常驻右侧（宽屏 60/40）、桌号 / 堂食外卖、追加单（加单）
- 每道菜的**个性化定制**（大小份、加料…）+ 按种类分组的常用备注；菜单可**从 Excel 导入**
- 结账：**折扣**（百分比 / 减金额）、**税**（含税或价外税）、
  **三个币种 MXN/USD/RMB 带汇率**（汇率在「菜品管理」里改）、现金实收 + **大字找零**、刷卡**银行卡动画**
- 菜品**单位**（Excel 的「单位」列：份 / 杯 / 公斤），菜单、购物车、厨房单都会显示
- 两种打印：下单打「厨房单」、结账打「顾客小票」；通道 = 蓝牙 / 网络 / Windows 打印机
  （打印失败「重试 / 跳过」，**绝不丢单**）
- 订单历史（进行中 / 已结单，可删除）、**日结**（营业额 + 折扣 + 税 + 分支付方式/币种 + 支出 + 净额）
- **多账号 + 权限**：管理员（菜单/设置/日结/删单）与收银员（点单/结账/打折）
- 多语言：中文 / 西语 / 英语（界面与小票可分别设语言）

> 🔑 **第一次启动会要求登录**：默认账号 `admin`，密码 `8888`（进「设置 → 账号管理」可改密码、加收银员）。
> 🖥️ 想在 **Windows 触屏收银机**上跑（安卓手机不在时）：请直接看 **`setup.md`**。
> 架构与代码怎么分层、权限与金额规则怎么设计的，看 **`design.md`**。

---

## 目录结构

```
lib/
  main.dart                           程序入口（在这里选打印服务）
  app.dart                            主题（Loyverse 绿） + Provider 装配 + 登录门禁
  l10n/app_strings.dart               全部文案（zh/es/en）
  models/                             分类 / 菜品 / 购物车行 / 订单(+收款) / 账号
  utils/pricing.dart                  金额规则：小计 / 折扣 / 税 / 应收（唯一一份）
  data/                               sample_menu / 菜单 / 订单 / 设置 / 账号 的存取
  state/pos_controller.dart           点单状态（购物车、下单、追单、收款结账、订单历史）
  state/settings_controller.dart      设置状态
  state/auth_controller.dart          账号与权限（登录、临时提权、账号 CRUD）
  services/receipt_print_service.dart 打印服务【接口】
  services/print_service.dart         三通道分发（蓝牙 / 网络 / Windows 打印机）
  services/receipt_layout.dart        小票排版（纯逻辑，方便单测）
  services/sales_totals.dart          日结统计（纯函数）
  screens/                            登录 / 主页 / 点单 / 订单 / 日结 / 设置 / 菜单 / 账号
  widgets/                            菜单区 / 购物车 / 收款框 / 权限门禁 / 账号菜单
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
