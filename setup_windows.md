# setup.md — 在 Windows 触屏收银机上跑起来

> 你的环境：Windows 10 专业版 · Intel i5-4300U · 8GB RAM · 10 点触控 · 有 USB 和以太网口。
> 本文教你**在 Windows 桌面上跑这个收银应用**（先在电脑上进店、点单、看效果；安卓版以后照 `log.md` 跑）。

---

## 0. 先说三点，帮你心里有底

1. **Windows 已能跑**：应用本身可以编译成 Windows 桌面版，界面、点单、订单历史都能用。
2. **Windows 暂时还不能打印**：当前的打印实现是给安卓的（蓝牙）。而 Windows 版还没接打印机，
   所以点“结账”会提示“当前平台暂不支持该打印机”。**这是下一阶段要做的**（USB / 以太网打印）。
   在此之前，你可以在 Windows 上体验完整点单流程、看订单历史。
3. **你的机器很适合当收银台**：10 点触控 + 大按钮界面，基本可用；可横屏/竖屏换着看。

---

## 1. 前置依赖（一般已装好，确认一下）

在 `big_boss_bro` 项目目录打开 PowerShell，运行：

```powershell
flutter doctor -v
```

重点看 **Windows toolchain** 那项是不是打勾（✓）。构建 Windows 桌面版需要 **Visual Studio
（含“使用 C++ 的桌面开发”工作负载）**。如果没勾：

```powershell
winget install Microsoft.VisualStudio.2022.BuildTools
# 安装时勾选：使用 C++ 的桌面开发  →  安装完成后重启，再跑 flutter doctor
```

---

## 2. 在 Windows 上跑起来（最常用）

>`flutter` 在你自己的 PowerShell 里已在 PATH 上，直接用即可；
> 如果提示找不到，就用全路径 `C:\Users\renha\workspace\flutter\bin\flutter`。

```powershell
# ① 生成 Windows 原生外壳（如果还没 windows/ 目录才需要；你已经有了就跳过这步）
flutter create . --platforms=windows

# ② 拉依赖
flutter pub get

# ③ 运行 Windows 桌面版
flutter run -d windows
```

第一次运行会编译一会儿，之后会弹出一个 Windows 窗口，就是收银界面。

**exit 退出**：在 PowerShell 里按 `q`，或直接关窗口。

---

## 3. 打一个 Windows 安装包（给收银机直接装）

```powershell
flutter build windows --release
```

产物目录：`build\windows\x64\runner\Release\`，
里面 `big_boss_bro.exe` 就是可执行程序。把它拷到收银机桌面上双击即可运行
（这台机器本身收银用就是最合适的）。

> 发布到没有装 Flutter 的机器上时，需把整个 `Release\` 文件夹（exe + 关联 dll）一起拷过去。

---

## 4. 收银机上的触控使用建议

- 界面按钮都做得比较大，适合手指/触控笔。
- 想在点单页显示更多菜品：**宽屏模式**下菜品格子会自动排更多列。
- 如果字体/按钮想更大，以后可以做“字号”设置；当前先这样用。

---

## 5. 在 Windows 上能做什么、暂时不能做什么

| 能 | 暂不能 |
|---|---|
| 点单：分类切换、点菜加购、改数量、删条目、合计 | ❌ Windows 打印（需接打印机实现） |
| 结账：选支付方式（现金/刷卡/扫码）、确认 | ❌ 真机安卓版（需手机在） |
| 订单历史：查看、删除 | |
| 菜品管理：增删改分类/菜品、恢复默认 | |
| 语言切换：中文/西语/英语 | |

---

## 6. 下一步（Windows 打印怎么加）—— 已列入 `log.md`

你的机器有 **USB** 和 **以太网**，常见接法是二选一：

- **以太网/WiFi 网络小票机**：直接给它一个 IP，App 通过 TCP(9100/8300) 发 ESC/POS 指令 →
  这是接下来最优先做的（不依赖驱动，最通用）。
- **USB 小票机**：作为系统打印机安装，或走串口(COM)；需要另外写 Windows 打印实现。

具体实现与测试步骤我会写进 `log.md`，到时候你在收银机上照做即可。

---

## 相关文档

- `README.md` 快速上手
- `design.md` 项目架构与流程（为什么这样分层、Category 名字冲突注意）
- `log.md` 执行日志 / 下一步
