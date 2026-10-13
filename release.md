# release.md — 怎么打包发布到 Windows 和 Android

> 这份文档只讲**「怎么把现在这份代码变成一个能给店里用的东西」**（Windows 装到收银电脑 / Android 装到平板），
> 以及本次 `flutter run` 在 Android 侧卡住的那个报错的完整记录。
>
> 相关文档：
> - `android_test.md` —— 安卓上**怎么测**（连设备、功能清单、权限）
> - `troubleshooting.md` —— 历史报错记录（乱码、导入、Category 冲突…）
> - `setup.md` / `setup_windows.md` / `setup_supabase.md` —— 首次环境搭建
>
> 约定：本文命令都是 **PowerShell**（你现在用的终端）。路径带空格要用 `& "..."` 调用。

---

## 0. 这台电脑现在的状态（照抄，省得每次再查）

| 项目 | 值 |
| --- | --- |
| Flutter SDK | `3.49.0-0.1.pre`（**master 分支**），路径 `C:\Users\renha\workspace\flutter` |
| Dart | `3.14.0-183.0.dev` |
| JDK | **Android Studio 自带 JBR**：`C:\Program Files\Android\Android Studio\jbr`（系统的 `JAVA_HOME` / `java` 都没配，不用管） |
| Gradle | wrapper `9.3.1` |
| Android Gradle Plugin | `9.1.0`（`android/settings.gradle.kts`） |
| Kotlin | `2.4.0` |
| Android SDK | `C:\Users\renha\AppData\Local\Android\sdk`（= `android/local.properties` 里的 `sdk.dir`） |
| SDK 已装 | `platform-tools`、`platforms/android-36` + `platforms/android-37.0`、`build-tools/36.0.0`、`cmdline-tools/latest`(23.0)、**`ndk/28.2.13676358`** ✅ |
| Android 编译参数 | `compileSdk 37`（**手写覆盖**，见第 9 节）/ `minSdk 24` / `targetSdk 36` / `ndkVersion 28.2.13676358`，见 `android/app/build.gradle.kts` |
| 关键字号/插件 | `file_picker ^11.0.3`、`permission_handler ^13.0.2`；其中 `flutter_bluetooth_serial`、`file_picker` 是**本地补丁副本**（见第 8 节 / 第 9 节） |
| 测试机 | **SM T290 = Galaxy Tab A 2019**，Android **11 (API 30)**，`android-arm64`，设备 id **`R9WR201TRKJ`** |
| 应用信息 | 名字 `Big Boss Bro`、`applicationId = com.example.big_boss_bro`、当前 release 用 **debug 签名** |
| 版本号 | `pubspec.yaml`：`version: 0.1.0+1` |

> ⚠️ Flutter 是 **master（开发分支）**，AGP 也是 **9.1.0（很新）**——新组合容易出这类"工具链自己打架"的问题。
> 真要长期稳定发版，建议以后固定到 **stable** 通道（`flutter channel stable`，或用 `fvm` 把一个版本钉死在项目里），
> 别在发版当天升 SDK。

---

## 1. 【已解决 ✅】Android 曾经卡住的原因：NDK 没装，而且 AGP 9 装不上它

> **状态：已解决 ✅** —— `ndk/28.2.13676358` 已经装进 SDK（`platforms/android-36`、`build-tools/36.0.0` 也补齐了）。
> 下面把过程和原理留作记录，以后再遇到同类"SDK 包装不上"可以直接照抄。

### 1.1 报错原文

```text
WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated. Android CLI will be used instead.
Downloading Android CLI...
Unpacking embedded installation...
Package ndk not found.
Package 28.2.13676358 not found.

FAILURE: Build failed with an exception.
* Where:
Build file 'C:\Users\renha\workspace\projects\big_boss_bro\android\build.gradle.kts' line: 19
* What went wrong:
A problem occurred configuring project ':app'.
> org.gradle.api.GradleException: Android sdkmanager did not install NDK 28.2.13676358 into C:\Users\renha\AppData\Local\Android\sdk.
BUILD FAILED in 3m 48s
Running Gradle task 'assembleDebug'...                            229.2s
Error: Gradle task assembleDebug failed with exit code 1
```

### 1.2 原因（已实测确认）

链条是这样的：

1. `android/app/build.gradle.kts` 里有 `ndkVersion = flutter.ndkVersion`（值就是 Flutter 钉死的 `28.2.13676358`），
   而这台机器 **SDK 里一个 NDK 都没有**；
2. AGP 9.1.0 发现 NDK 缺失，就**自己去装**：它在 Windows 上用的是**旧的包路径语法** `ndk;28.2.13676358`；
3. 但 `cmdline-tools/23.0` 里的 `sdkmanager.bat` 现在**只是个壳**，真正的活由**新的 Android CLI**（`android.exe`）干
   （所以日志开头会说 "sdkmanager is deprecated. Android CLI will be used instead"）；
4. 新 CLI 的语法是 **`android sdk install <package>[@<version>]`**，根本不认 `;` 那种老路径
   → 它把 `ndk` 和 `28.2.13676358` 当成**两个包名**去找，两个都找不到，就打印了那两行
   `Package ndk not found.` / `Package 28.2.13676358 not found.`
5. AGP 一看"我让你装你没装上"，直接抛 `GradleException` 终止构建 → `assembleDebug failed`。

**实测证据（我在这台机器上验过）：**

- `& "...\cmdline-tools\latest\bin\sdkmanager.bat" "ndk;28.2.13676358"` → 输出**一模一样的两行**
  `Package ndk not found.` / `Package 28.2.13676358 not found.`（说明问题出在工具链的语法代沟，不是网络、不是磁盘、不是你写错了命令）
- `android.exe sdk install --help` → 明确写着位置参数是 `<package>[@<version>]`
- `android.exe sdk list ndk` → `(no installed packages match pattern ndk)`（确认 NDK 确实没装）

> 注意：报错里那句 "Android sdkmanager did not install NDK…" 是 AGP 的**兜底错误信息**，
> 不代表"网络不通"或"没接受许可"（`licenses\android-sdk-license` 是有的）。

### 1.3 三种解法（**A 推荐**，B 命令行，C 应急绕过）

| 方案 | 怎么做 | 代价 / 何时用 |
| --- | --- | --- |
| **A. 用 Android Studio 的 SDK Manager 装（推荐）** | 打开 Android Studio → `Tools` → `SDK Manager` → 页签 **`SDK Tools`** → 勾 **`NDK (Side by side)`** → 在右边/下拉里选 **`28.2.13676358`** → `Apply` → 等下载完 | GUI 不走上面那个 CLI 语法，最稳。NDK 约 1GB 左右下载、装完几个 GB 磁盘 |
| **B. 命令行用新语法装** | 见下面代码块 | 不想开 Android Studio 时用。**（此命令尚未在本机跑通验证 ⏳，装完请用 1.4 验证）** |
| **C. 干脆不装 NDK，先出包（应急）** | 把 `android/app/build.gradle.kts` **第 10 行** `ndkVersion = flutter.ndkVersion` **注释掉** → AGP 就不再尝试装 NDK | 本工程**没有任何带 C/C++ 的插件**（`ffi` 只在 Windows 侧调 `winspool.drv`，Android 侧不用），所以 Android 打包**不需要 NDK**。代价：APK 里的 `.so` 不会被 strip（体积略大）；以后一旦引入原生插件，还是得装回来。**（此绕过方案尚未实测 ⏳）** |

方案 B 的命令：

```powershell
$sdk = "$env:LOCALAPPDATA\Android\sdk"
# 新 Android CLI 的正确写法：包名 @ 版本（不是旧的 ndk;版本）
& "$sdk\cmdline-tools\latest\bin\android.exe" --sdk="$sdk" sdk install "ndk@28.2.13676358"
```

### 1.4 装完怎么验证（做完第 1 节后跑这三条）

```powershell
# 1) 目录里应该出现 ndk\28.2.13676358
Get-ChildItem "$env:LOCALAPPDATA\Android\sdk\ndk"

# 2) Gradle 配置阶段不再报 NDK → 直接跑 debug
flutter run -d R9WR201TRKJ

# 3) 出 release 包（真正给店里用的）
flutter build apk --release
```

> 如果 `ndkVersion` 被你改过（比如装了别的版本），记得让 **`android/app/build.gradle.kts` 里写的版本 = 实际装上的版本**，
> 否则 AGP 还是会去找那个缺失的版本。

### 1.5 顺带两个坑（本次也踩到了）

| 现象 | 原因 / 处理 |
| --- | --- |
| `flutter run -d RF8M1234ABC` → `No supported devices found with name or id matching ...` | 那是**不存在的 id**。设备 id 每次插到不同 USB 口/换线都可能变，**要用 `flutter devices` 当前显示的那个 id**（本例：`R9WR201TRKJ`） |
| `flutter run -d SM T290` → `Target file "T290" not found.` | `-d` 后面跟的**必须是设备 id，不能是型号名**；`SM T290` 里有**空格**，shell 会把它拆成 `SM` 和 `T290` 两个参数，`T290` 被当成"要运行的 dart 文件"。千万不要写 `-d "SM T290"`（加引号也只是把型号当 id，一样找不到） |

---

## 2. 每次发版的通用三步

```powershell
# ① 改版本号（见下表）—— Android 和 Windows 的版本号都从这里来
#    编辑 pubspec.yaml 的第一行 version:
#    version: 0.1.0+1   →   version: 0.1.1+2

# ② 清干净再拉依赖（避免旧缓存导致的诡异报错）
flutter clean
flutter pub get

# ③ 质量闸门：测试全绿 + 真机走一遍主流程
flutter test
flutter analyze        # 可选，看警告
```

| 你要改的东西 | 改哪里 | 说明 |
| --- | --- | --- |
| 显示给用户的版本号（如 `0.1.1`） | `pubspec.yaml` 的 `version:` 的**前半段** | Android 的 `versionName`、Windows exe 的文件属性版本号都用它 |
| 内部版本号（整数，如 `+2`） | `pubspec.yaml` 的 `version:` 的 **`+` 后半段** | = Android 的 `versionCode`。**每次发版必须比上次大**，否则平板/商店认为是同一个包，装不上或不给更新 |

> 原理：`flutter build` 会把 `pubspec.yaml` 的版本写进 `android/local.properties`
> （`flutter.versionName` / `flutter.versionCode`）和 `windows/runner/Runner.rc`（`FLUTTER_VERSION*` 占位符）。
> 所以**改完 pubspec 一定要重新 build**，光改 gradle 文件没用。

---

## 3. Windows 版发布

### 3.1 构建

```powershell
flutter build windows --release
```

- 前置：Visual Studio 2022 + **"使用 C++ 的桌面开发"** 工作负载（能 `flutter run -d windows` 就说明已经有了）。
- 产物（**整个文件夹一起用**）：

```text
build\windows\x64\runner\Release\
├─ big_boss_bro.exe          ← 双击这个
├─ flutter_windows.dll
├─ *.dll                     ← 插件带的 DLL
└─ data\
   ├─ icudtl.dat / flutter_assets\...
```

> ⚠️ **只拷 `big_boss_bro.exe` 一定会启动失败**（找不到 DLL 和 `data\`）。
> 找不到产物时：`Get-ChildItem build\windows -Recurse -Filter *.exe`。

### 3.2 打包成"给店里用的东西"

| 方式 | 怎么做 | 适用 |
| --- | --- | --- |
| **压缩包（最简单）** | 把整个 `Release` 文件夹压成 `BigBossBro-0.1.1-win64.zip`，拷到收银电脑解压 → 双击 exe | 自己店里几台机器，够用 |
| **安装包（更正式）** | 用 **Inno Setup** 写个脚本：把 `Release` 整个文件夹装到 `{app}`、建桌面快捷方式、写卸载项 | 要给不熟电脑的人装 |
| **绿色自解压** | 7-Zip 的 SFX 自解压包 | 折中 |

- 目标电脑若提示缺 `MSVCP140.dll` / `VCRUNTIME140.dll` → 装一次 **VC++ 2015-2022 运行库**（`vc_redist.x64.exe`）。
- 首启动会被 SmartScreen 拦（"未知发布者"）→ 点"更多信息 → 仍要运行"；想彻底没有，需要买代码签名证书。

### 3.3 Windows 侧发布前必查（打印是重点）

| # | 检查 | 期望 |
| --- | --- | --- |
| W1 | 设置 → 打印机 → **USB 打印机**（走 Windows spooler RAW 通道）→ 打测试页 | 出纸、中文不乱码（`lib/services/windows_print_service.dart`，用 `winspool.drv`） |
| W2 | 设置 → 打印机 → **网络(IP)** → `打印机IP:9100` → 打测试页 | 出纸（收银电脑和打印机同网段） |
| W3 | 小票编码 / 字号 / 铺满纸宽（Font A）三项 | 中文正常（乱码排查见 `troubleshooting.md` 问题 6、7） |
| W4 | 点单 → 厨房 → 结账（现金 + 打折） | 小票金额、日结数字都对 |
| W5 | Excel 导入菜单 | 解析出菜名/价格/定制项（改过导入逻辑后**必须重导一次**） |
| W6 | 后台同步（Supabase） | 设置页显示"同步完成 ↑N ↓M"，网页后台能看到单子 |

> `assets\` 里的图片（`IMG2026*.jpg`、`receipt_print.jpg` 等）会被打进 `data\flutter_assets\`。
> 如果它们只是**参考图/调试素材**，发布前可以清掉 `pubspec.yaml` 的 `assets:` 列表（能显著减小体积）。

---

## 4. Android 版发布

> 前置：**第 1 节的 NDK 问题必须先解决**，否则 `flutter build apk` 一样会失败。

### 4.1 先出一个"能装进平板"的包（debug 签名，店里自己用完全够）

```powershell
# 只编 arm64（这台平板是 arm64，能省一半构建时间）
flutter build apk --release --target-platform android-arm64

# 产物
# build\app\outputs\flutter-apk\app-release.apk

# 装到平板（USB 连着、已授权 USB 调试）
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

不想用线：把 `app-release.apk` 用微信/网盘/U 盘拷到平板 → 点它安装（平板要允许"安装未知来源应用"）。

> 现在 `android/app/build.gradle.kts` 里 release **用的是 debug 签名**（文件里有 TODO）。
> 自己店里的平板：完全够用。**要上架 / 要长期覆盖升级**：走 4.2。

### 4.2 正式签名（换自己的 keystore）

**① 生成 keystore（只做一次，做完立刻备份！）**

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" `
  -genkeypair -v `
  -keystore android\app\bigbossbro-release.jks `
  -storetype PKCS12 `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias bigbossbro
```

**② 新建 `android/key.properties`**（不要提交到 git）

```properties
storePassword=你的密码
keyPassword=你的密码
keyAlias=bigbossbro
storeFile=bigbossbro-release.jks
```

**③ 改 `android/app/build.gradle.kts`**（把 debug 签名换成上面的）

```kotlin
import java.util.Properties
import java.io.FileInputStream

// 放在 plugins {} 和 android {} 之间
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // …（namespace / compileSdk / ndkVersion 保持不动）…

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")   // ← 原来是 signingConfigs.getByName("debug")
            // 可选：瘦身 / 混淆（本工程纯 Dart，收益不大，先别开）
            // isMinifyEnabled = false
            // isShrinkResources = false
        }
    }
}
```

**④ `.gitignore` 加上**（**目前还没有这两行**，务必补）

```gitignore
android/key.properties
*.jks
```

**⑤ 必须记住的两件事**

- **keystore 和密码丢了 = 这个 App 永远无法再更新**（同一个 `applicationId` 的更新必须用同一把钥匙签名）。备份到网盘/U 盘/密码管理器。
- **签名一换，老包装不上**（会报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`）→ 平板上**先卸载旧版**再装新版。
  以后店里的机器统一用**正式签名的包**，就不会再有这个麻烦。

### 4.3 三种产物：APK / 拆分 APK / AAB

| 命令 | 产物 | 用途 |
| --- | --- | --- |
| `flutter build apk --release` | `build\app\outputs\flutter-apk\app-release.apk` | **一个包通吃**（含 armeabi-v7a / arm64-v8a / x86_64），体积最大（~几十 MB）。最省事 |
| `flutter build apk --release --split-per-abi` | `app-armeabi-v7a-release.apk`<br>`app-arm64-v8a-release.apk`<br>`app-x86_64-release.apk` | 按 CPU 拆分，每个都小很多。**这台平板装 `app-arm64-v8a-release.apk`** |
| `flutter build appbundle --release` | `build\app\outputs\bundle\release\app-release.aab` | **只有上 Google Play 才需要**（AAB 不能直接装到平板上） |

可选（保护 Dart 代码 + 能还原堆栈）：

```powershell
flutter build apk --release --obfuscate --split-debug-info=build\symbols
# 崩溃堆栈要用 build\symbols 里的文件还原 → 这个目录要留着（但别提交到 git）
```

### 4.4 装到平板（SM T290 / Android 11）

```powershell
# 看设备（id 是 R9WR201TRKJ，别用型号名）
flutter devices

# 用 adb 装
$adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
& $adb install -r build\app\outputs\flutter-apk\app-release.apk

# 签名不同装不上时：先卸载
& $adb uninstall com.example.big_boss_bro
```

连不上设备 / 驱动没装 / 想用无线调试：见 `android_test.md` 第 0 节（写得很细）。

### 4.5 Android 11 平板的两个注意点

| 点 | 说明 |
| --- | --- |
| **首次扫蓝牙要"位置"权限** | Android 11 及以下，扫经典蓝牙必须有 `ACCESS_FINE_LOCATION`（这个权限由 `flutter_bluetooth_serial` 插件声明，会**合并进最终 manifest**；运行时由 `permission_handler` 申请）。**不给就一个打印机都扫不到** |
| **Android 12+ 是"附近的设备"** | 对应 `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`，本项目 `android/app/src/main/AndroidManifest.xml` 里已声明；Android 12+ 还需运行时授权 |

想核对最终 manifest 里到底有哪些权限（合并后的结果）：

```powershell
Get-Content build\app\intermediates\merged_manifests\release\AndroidManifest.xml |
  Select-String "uses-permission"
```

> `android_test.md` 开头提到的那个大坑（**Flutter 只在 debug/profile 自动加 `INTERNET`，release 包会没有**）
> 已经在本项目 main manifest 里补好了。但**每次改完都要用 release 包复测网络同步和网络打印**，别只信 debug。

### 4.6 如果以后要上 Google Play（现在不用急）

| 项 | 现状 / 要做的 |
| --- | --- |
| `applicationId` | 现在是 `com.example.big_boss_bro`，**`com.example.*` 不允许上架** → 改成自己的域名倒写（如 `com.yourname.bigbossbro`）。注意：改了就是**另一个 App**，老数据/老安装不通用 |
| 目标 API | `targetSdk 36`，满足 Play 的新要求 ✅ |
| 产物 | 用 **AAB**（`flutter build appbundle`） |
| 隐私 | 这个 App 会把订单/员工/菜单同步到 Supabase → 属于"收集数据"，必须填 **Data safety** 表单 + 有**隐私政策网址** |
| 蓝牙权限 | `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` 要说明用途（连接小票打印机），否则容易被拒 |
| 打印机 | Play 版**不能**用 `REQUEST_INSTALL_PACKAGES` 之类敏感权限；本项目没用，OK |

---

## 5. 发布前总检查清单

**代码/版本**
- [ ] `pubspec.yaml` 的 `version:` 已升（`+N` 必须比上次大）
- [ ] `flutter clean` + `flutter pub get`
- [ ] `flutter test` 全绿；`flutter analyze` 无 error
- [ ] 改过导入/价格/打印相关逻辑 → **重新导入一次 Excel 菜单**（老数据不会自己变，见 `troubleshooting.md` 问题 9）

**Windows**
- [ ] `flutter build windows --release` 成功
- [ ] 在**目标收银电脑**上解压整个 `Release` 文件夹能启动（不是只在开发机跑）
- [ ] USB 打印机 / 网络打印机各打一张测试页；中文不乱码
- [ ] 点单 → 厨房单 → 结账 → 日结 数字对得上
- [ ] 后台同步能上传/下载（release 专属坑）

**Android**
- [ ] **NDK 问题已解决**（第 1 节；`android\...\sdk\ndk\28.2.13676358` 存在）
- [ ] `flutter build apk --release` 成功
- [ ] 装到 **SM T290** 上：桌面名字是 `Big Boss Bro`、能启动
- [ ] 蓝牙扫描（给"位置"权限）→ 连打印机 → 测试页出纸、中文正常
- [ ] 网络打印（IP:9100）测试页出纸
- [ ] 点单/厨房/结账/日结 走一遍（照 `android_test.md` 第 3 节的清单更全）
- [ ] 后台同步：设置页"测试连接"成功、"立即同步"出 `↑N ↓M`
- [ ] 后台同步 →「菜品（菜单）」那两行数字：**本机和云端的「N 道有基础数量」一致**；
      不一致就点「从云端下载菜单」（这台旧了）或「上传本机菜单」（云端旧了）——
      ⚠️ 菜单**不在**「店级配置」里，换设备 / 重新导入 Excel 后必须单独同步一次（见 `troubleshooting.md` 问题 15）
- [ ] 点一道 **2 份起**的菜：弹窗份数从 2 开始、格子上有「2 份起」角标
- [ ] 息屏/切后台再回来，同步能自己补上
- [ ] 装的是**签名一致的包**（不然下次升级要卸载重装）

**发布物管理**
- [ ] keystore 已备份（丢了就不能更新！）
- [ ] `android/key.properties` 和 `*.jks` **没被提交到 git**
- [ ] 打包好的 zip/APK 记一句发布说明（版本、日期、改了什么）——建议追加到 `log.md`

---

## 6. 报错速查（和发版相关的）

| 报错 / 现象 | 原因 | 处理 |
| --- | --- | --- |
| `No supported devices found with name or id matching 'xxx'` | id 写错/过期 | `flutter devices` 取当前 id（本例 `R9WR201TRKJ`） |
| `Target file "T290" not found.` | `-d` 后面写了带空格的**型号名** `SM T290` | 用设备 id，别用型号名、别加引号硬写型号 |
| `Package ndk not found.` + `Package 28.2.13676358 not found.` | AGP 9.1.0 用旧语法 `ndk;版本` 调新 Android CLI（新语法是 `ndk@版本`） | 见第 1 节（已解决 ✅） |
| `Could not find method jcenter()`（出在 `flutter_bluetooth_serial` 的 `android/build.gradle`） | 插件停在 2021 年，脚本用了 **Gradle 9 已删除**的 `jcenter()` | 已解决 ✅：改用本仓库 `third_party/flutter_bluetooth_serial` 补丁副本 + `dependency_overrides`，见第 8 节 |
| `:file_picker:checkDebugAarMetadata` + `An issue was found when checking AAR metadata` + `:file_picker is currently compiled against android-34` | 老插件把 `compileSdk` **写死成 34**，而它依赖的模块是按 36+ 编译的 | 已解决 ✅：升级 `file_picker` ≥11、`permission_handler` ≥13，并把 App 的 `compileSdk` 提到 37，见第 9 节 |
| `error: cannot find symbol: class FilePickerPlugin`（`GeneratedPluginRegistrant.java`） | file_picker 11.x 把 Kotlin 插件写成**条件式应用**（AGP 9 下跳过），而 Flutter 靠**扫文本**判定"插件自己会应用 KGP"→ 谁都没应用 → Kotlin 源码没编译 | 已解决 ✅：file_picker 收编成 `third_party/file_picker`，KGP 改无条件应用，见第 9.7 节 |
| `Gradle task assembleDebug failed with exit code 1` | 只是**结果**，真正原因在上面几行 | 往上翻找第一条 `What went wrong` / `Caused by` |
| `flutter build windows` 报 MSVC / CMake 错 | 没装 VS C++ 桌面工作负载 | 装 VS 2022 + "使用 C++ 的桌面开发" |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 新旧包**签名不同** | `adb uninstall com.example.big_boss_bro` 后重装 |
| release 包在平板上"同步不了/网络打印打不出"，debug 正常 | Flutter 只在 debug/profile 自动加 `INTERNET` | main manifest 已补；**改完必须重新 build release 包** |
| 小票中文乱码（数字正常） | 编码/中文模式（`FS &` + GBK）；不是排版问题 | 见 `troubleshooting.md` 问题 6、7（根因是 `gbk.encode` 用错，已改 `gbk_bytes`） |
| 装完启动黑屏/闪退 | 少了 DLL 或没带 `data\` 文件夹 | Windows 分发**整个** `Release` 目录 |

---

## 7. 相关文档

| 文档 | 内容 |
| --- | --- |
| `android_test.md` | 安卓连接（USB/无线/adb）、25 项功能自测清单、安卓专属坑 |
| `troubleshooting.md` | 历史报错：`Category` 冲突、打印乱码真凶、Excel 导入结构变化、数据不会跟着代码变好 |
| `setup.md` / `setup_windows.md` | 环境搭建、打印机设置、首次运行 |
| `setup_supabase.md` | 后台同步（登录 + 读写表）的配置步骤 |
| `PLAN.md` / `log.md` | 计划与变更记录（每次发版建议在这里追加一行） |

---

## 8. 废弃插件 `flutter_bluetooth_serial`（已收编为 `third_party/` 本地补丁副本）

### 8.1 报错原文（NDK 装好之后就撞上它）

```text
1: Task failed with an exception.
* Where:
Build file 'C:\Users\renha\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_bluetooth_serial-0.4.0\android\build.gradle' line: 6
* What went wrong:
A problem occurred evaluating project ':flutter_bluetooth_serial'.
> Could not find method jcenter() for arguments [] on repository container of type
  org.gradle.api.internal.artifacts.dsl.DefaultRepositoryHandler.

2: Task failed with an exception.
* What went wrong:
A problem occurred configuring project ':flutter_bluetooth_serial'.
> Failed to notify project evaluation listener.
   > The Android plugin must be applied before accessing the Android extension.
   > 'kotlin-android' plugin requires one of the Android Gradle plugins.
```

### 8.2 原因

`flutter_bluetooth_serial` **停在 0.4.0（2021-08-17）**——我查过 pub.dev 的 API，它的全部版本是
`0.0.1 → 0.4.0`，**根本没有 0.5.0**（所以 `^0.5.0` 那种"升个版本试试"会直接让 `pub get` 解析失败）。
它自带的 `android/build.gradle` 是 Gradle 6 / AGP 4 时代的写法，和本项目现在的 **Gradle 9.3.1 + AGP 9.1.0** 不兼容：

| 上游写法 | 现在的问题 |
| --- | --- |
| `jcenter()` | **Gradle 9 已删除该方法** → 报错第 1 条就是它 |
| `buildscript { classpath 'com.android.tools.build:gradle:4.1.0' }` | 硬拉 AGP 4.1.0，和项目的 AGP 9.1.0 打架 |
| `compileSdkVersion 30` / `buildToolsVersion '30.0.3'` | AGP 9 不认这种旧 DSL，本机也没装这两个版本 |
| 没有 `namespace`（模块名写在 manifest 的 `package=` 里） | AGP 8 起 `namespace` 是**必需**的 |
| `lintOptions { }` | AGP 9 已移除该块 |

第 2 条是**连带**错误：脚本在第 6 行就中断，`com.android.library` 没应用成功，
所以后面抱怨"Android 插件必须先于 Android extension 应用"。

### 8.3 处理方式：收进本仓库打补丁（**没有改 pub 缓存，也没有改 App 代码**）

```text
third_party/flutter_bluetooth_serial/     ← 上游 0.4.0 的副本（lib/ android/ ios/ pubspec.yaml LICENSE README CHANGELOG）
├─ android/build.gradle                   ← 【重写】AGP 9 能认的写法
├─ android/src/main/AndroidManifest.xml   ← 【删一行】根标签的 package="..."
└─ pubspec.yaml                           ← 【改一行】sdk 约束 '>=2.12.0 <3.0.0' → '>=2.12.0 <4.0.0'
```

项目 `pubspec.yaml` 末尾：

```yaml
dependency_overrides:
  flutter_bluetooth_serial:
    path: third_party/flutter_bluetooth_serial
```

重写后的 `third_party/flutter_bluetooth_serial/android/build.gradle` 关键内容：

- `namespace 'io.github.edufolly.flutterbluetoothserial'`（必须）
- `compileSdk 36`、`minSdk 24`、Java 17（**与 app 模块保持一致**，否则 Flutter 会报"插件要求的 SDK 版本比项目高"）
- 依赖 `androidx.core:core` + `androidx.annotation:annotation`（插件源码用到 `ActivityCompat` / `ContextCompat` / `@NonNull`）
- 删掉 `buildscript{}` / `jcenter()` / `buildToolsVersion` / `lintOptions{}`（AGP 由项目 root 的 `pluginManagement` 统一提供）

> ⚠️ **Dart（`lib/`）与 Java（`src/main/java/`）源码一行未动**，`lib/services/bluetooth_print_service.dart` 等 App 代码也不用改。

### 8.4 为什么不用"直接改 pub 缓存"那条路

改 `C:\Users\renha\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_bluetooth_serial-0.4.0\...` 确实能立刻跑通，
但 **`flutter pub cache repair`（或换电脑/清缓存）会把它还原**，而且改动不在 git 里、别人拉下来还是坏的。
收进 `third_party/` 后：进 git、可复查 diff、换机器一致、`pub cache repair` 也不受影响。

### 8.5 你要记住的三件事

1. **别再"升级"这个包**：pub.dev 上就停在 0.4.0，`flutter pub upgrade` 升不动；
   它已经不维护了，以后要修就往 `third_party/flutter_bluetooth_serial/` 里改。
2. **别删 `third_party/flutter_bluetooth_serial/`**，也别删 `pubspec.yaml` 末尾的 `dependency_overrides`——
   删了这个包就又会回到 `Could not find method jcenter()`。
3. 以后真想换蓝牙库：换的是**经典蓝牙 SPP**能力（BLE-only 的库连不上多数小票机），
   并且要同步改 `lib/services/bluetooth_print_service.dart` 里的**扫描 / 连接 / 发送**三处。

### 8.6 验证（你在自己终端跑）

```powershell
flutter pub get                    # 应输出 Got dependencies!
flutter run -d R9WR201TRKJ         # 应能越过 Gradle 配置阶段，装上平板
```

> 我这边 `flutter pub get` 已经跑通 ✅，Gradle 也已越过插件配置阶段（并在自动补装缺失的
> `platforms/android-36` 与 `build-tools/36.0.0`，这两个现在都装好了）。
> 如果还报别的错，把终端输出发我，按 `troubleshooting.md` 的模板记一条。

---

## 9. AAR metadata：插件"编译在 android-34 上"（file_picker / permission_handler）

### 9.1 报错原文

```text
* What went wrong:
Execution failed for task ':file_picker:checkDebugAarMetadata'.
> A failure occurred while executing com.android.build.gradle.internal.tasks.CheckAarMetadataWorkAction
   > An issue was found when checking AAR metadata:

       1.  Dependency ':flutter_plugin_android_lifecycle' requires libraries and applications that
           depend on it to compile against version 36 or later of the Android APIs.

           :file_picker is currently compiled against android-34.

           Recommended action: Update this project to use a newer compileSdk
           of at least 36, for example 36.
```

### 9.2 一句话原理（**别改错地方**）

> AGP 的 AAR metadata 规则：**消费者（本 App）的 compileSdk ≥ 每个被依赖模块编译时用的 compileSdk。**

- 报错里写着 `:file_picker is currently compiled against android-34` —— 说的是**那个插件模块自己**编译在 34；
  所以 `Recommended action: Update this project...` 指的是**插件工程**，**不是**本 App 的 `build.gradle.kts`。
  （"把 App 的 compileSdk 调大"在这一步是没用的，因为问题在插件那一侧。）
- 反过来也有：如果某个插件自己按**很高的** compileSdk 编译（本次是 `permission_handler_android 14.1.0` → **37**），
  那**本 App 就必须 ≥ 37**，否则同样报 AAR metadata。所以最后是"插件往上、App 也往上"。

各包实际编译在哪个 compileSdk（本次实测，看的是它们各自的 `android/build.gradle(.kts)`）：

| 包 | 版本 | 它的 compileSdk |
| --- | --- | --- |
| `file_picker`（旧） | 8.3.7 | `compileSdk 34` ❌ |
| `permission_handler_android`（旧，`permission_handler` 11.x 的安卓实现） | 12.1.0 | `compileSdk 34` ❌ |
| `flutter_plugin_android_lifecycle` | 2.0.35 | `compileSdk = flutter.compileSdkVersion`（36） |
| `shared_preferences_android` | 2.4.28 | `compileSdk = flutter.compileSdkVersion`（36）✅ |
| `permission_handler_android`（新，`permission_handler` 13.x 的安卓实现） | 14.1.0 | `compileSdk = 37` ✅ |

### 9.3 本次改了 5 处（缺一处都不自洽）

| 文件 | 原来 | 改成 |
| --- | --- | --- |
| `pubspec.yaml` | `file_picker: ^8.0.0` | `file_picker: ^11.0.3` |
| `pubspec.yaml` | `permission_handler: ^11.3.0` | `permission_handler: ^13.0.2` |
| `android/app/build.gradle.kts` | `compileSdk = flutter.compileSdkVersion`（36） | `compileSdk = 37` |
| `lib/screens/menu_import_screen.dart` | `FilePicker.platform.pickFiles(...)` | `FilePicker.pickFiles(...)` |
| `pubspec.yaml` + `third_party/file_picker/` | 用 pub.dev 上的 file_picker | 收编成**本地补丁副本**（原因见 9.7） |

- `compileSdk` 只决定"能调用哪些 API"，**向后兼容**；
  `minSdk`（24，能装到哪些机器）和 `targetSdk`（36，运行时行为）**都没动**。
- `permission_handler` 的**业务代码一行没改**：`Permission.bluetoothScan / bluetoothConnect / location`
  来自 `permission_handler_platform_interface`，13.0.2 要求的还是 `^4.4.0`，枚举没变。
- `file_picker` 只改了**调用方式**：11.0.0 起 `FilePicker` 是**静态方法**
  （`FilePickerResult` / `withData` / `PlatformFile.bytes` / `.path` 都还在）。

### 9.4 为什么是这两个版本（选型理由，以后升级时照这个思路）

| 候选 | 结论 |
| --- | --- |
| `file_picker` 10.3.11 | ❌ 虽然已经用 `compileSdk = flutter.compileSdkVersion`，但它的 buildscript 还钉着 **AGP 8.5.1 + Kotlin 1.8.22**（Gradle 9 下会炸）；11.0.0 的 CHANGELOG 才写 "Updated Android package to support AGP 9" |
| `file_picker` 11.0.3 | ✅ **选它**：支持 AGP 9、`compileSdk = flutter.compileSdkVersion`、只改**一行**调用方式 |
| `file_picker` 12 / 13 | ❌ 12.0.0 联邦化并**删掉 `FilePickerResult`**、废弃 `withData`；13.0.0 直接删掉 `withData`/`allowMultiple`，要用 `pickFile()` + `PlatformFile.readAsBytes()` |
| `permission_handler` 12.0.3 | ❌ 它的安卓实现 13.0.1 还在用 `compileSdkVersion 35` + buildscript 里的 **AGP 8.0.2** |
| `permission_handler` 13.0.2 | ✅ **选它**：安卓实现 14.1.0 = AGP 9 + compileSdk 37 + Kotlin 2.3.20；API 没变（枚举来自 platform_interface ^4.4.0） |

### 9.5 验证

```powershell
flutter pub get
flutter run -d R9WR201TRKJ
```

> 首次可能会看到 `Preparing "Install Android SDK Platform ..."` / `Build-Tools ...`——那是 AGP 在补装
> SDK 包（本项目允许），**不要中途关掉**；如果弹出 `[y/N]` 之类的许可询问，按 `y` 回车。

### 9.6 以后再加插件时，怎么提前避坑

1. 看它在 pub 缓存里的真实脚本（别信文档、别猜）：
   ```powershell
   Get-ChildItem "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev" -Directory |
     Where-Object { $_.Name -like "你的包名-*" } |
     ForEach-Object { Select-String -Path "$($_.FullName)\android\build.gradle*" -Pattern "compileSdk" }
   ```
   - 出现 `compileSdk 34` 这种**写死的低版本** → 迟早报 AAR metadata，提前升级该插件。
   - 出现 `compileSdk = flutter.compileSdkVersion` → ✅ 跟着项目的 compileSdk 走，最省心。
   - 出现比本 App `compileSdk` 还**高**的版本 → 本 App 的 `compileSdk` 要抬到那个数。
2. 升级前先读它的 **CHANGELOG（BREAKING CHANGE 部分）**——本次就是靠这个避开了 file_picker 12/13 的 API 大改。
3. 别顺手大跳版本：够用就好（本次 file_picker 只跳到"第一个支持 AGP 9 且 API 不变"的 11.x）。

### 9.7 后续坑（同一个包的第二颗雷）：Kotlin 源码根本没被编译

升级到 file_picker 11.0.3 之后，AAR metadata 过了，但紧接着又报：

```text
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): file_picker
...
GeneratedPluginRegistrant.java:19: error: cannot find symbol
      flutterEngine.getPlugins().add(new com.mr.flutter.plugin.filepicker.FilePickerPlugin());
  symbol:   class FilePickerPlugin
FAILURE: ... Execution failed for task ':app:compileDebugJavaWithJavac'.
```

**为什么会这样**（三层叠加）：

1. file_picker 11.0.3 的 `android/build.gradle` 把 Kotlin 插件的应用写成了**条件式**：
   `if (!isAgp9OrAbove) { apply plugin: 'org.jetbrains.kotlin.android' }`
   （它假定"AGP 9 自带内置 Kotlin"，所以 AGP≥9 时不再应用 KGP）。
2. **Flutter 判断"插件是否自己应用了 KGP"靠的是【扫 build.gradle 文本】的正则**
   （`FlutterPluginUtils.getSubprojectPluginState`）。文本里有这句 → Flutter 认为"它自己会处理" → **不再帮它应用 KGP**。
3. AGP 9 下它自己又跳过 → **谁都没应用 KGP** → `android/src/main/kotlin/` 下 5 个 `.kt` 一个都没编译
   → 模块 jar 里没有 `FilePickerPlugin` → App 的 `GeneratedPluginRegistrant` 引用不到 → Java 编译失败。

> 关键背景：本项目 `android/gradle.properties` 里是 **`android.builtInKotlin=false`**
> （**Flutter 模板的默认值**，见 `flutter/packages/flutter_tools/templates/app/android.tmpl/gradle.properties.tmpl`），
> 也就是 Kotlin 必须由 KGP 编译。file_picker 却按"内置 Kotlin 开着"来假设 → 两边错开。
> 顶部那句 KGP 的 WARNING 是**同一个正则的产物**，属提示，不是原因。

**处理：把 file_picker 也收编进 `third_party/`**（与第 8 节的蓝牙插件同一套路）：

```text
third_party/file_picker/                 ← 上游 11.0.3 的副本（lib/ android/ ios/ macos/ pubspec.yaml LICENSE CHANGELOG README，~230KB）
├─ android/build.gradle                  ← 【重写】删掉 buildscript{AGP 8.5.1 + Kotlin 1.8.22}，
│                                            改成**无条件** apply plugin: 'org.jetbrains.kotlin.android'，
│                                            jvmTarget 用 KGP 2.x 的 compilerOptions 固定 17，删掉 lintOptions{}
└─ android/src/main/AndroidManifest.xml  ← 【删一行】根标签的 package="..."
```

```yaml
# pubspec.yaml
dependency_overrides:
  file_picker:
    path: third_party/file_picker
```

- ⚠️ **Dart 与 Kotlin/Java 源码一行未动**，只改构建脚本和 manifest。
- 构建时**仍会打印**那句 `plugins that apply KGP: file_picker` 的 WARNING——**属提示，不影响构建**
  （Flutter 现在只是警告；未来版本才会强制要求迁移到 built-in Kotlin）。

**为什么不用"一行 `android.builtInKotlin=true` 搞定"**：那会把**整个项目**的 Kotlin 编译模式换掉
（app 的 `build.gradle.kts` 里 `kotlin { compilerOptions { ... } }`、以及其它几个插件现在都按 KGP 模式在跑），
牵动面比"只修一个坏模块"大，而且没法在改动前实测（本机跑一次构建要 3～5 分钟）。
收编打补丁只影响 file_picker 一个模块，其余维持"已经跑通"的现状。

**验证**：`flutter pub get` → `flutter run -d R9WR201TRKJ`。

**以后怎么避开这类"类找不到"**：

1. 先确认那个插件的源码**到底编译了没有**：看 `android/src/main/` 下是 Java 还是 Kotlin，
   再确认**谁负责应用 Kotlin 插件**。
2. 插件里写"条件式 apply 插件"极易两头落空——Flutter 的判定是**文本正则**，不是运行时插件状态。
3. 判断某个插件是否"自己应用了 KGP"：直接看它的 `android/build.gradle` 里有没有
   `apply plugin: 'kotlin-android'` / `id("org.jetbrains.kotlin.android")`。

