import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/receipt_print_service.dart';
import 'services/sync_service.dart';
import 'state/attendance_controller.dart';
import 'state/auth_controller.dart';
import 'state/pos_controller.dart';
import 'state/settings_controller.dart';

/// Loyverse 式的品牌绿。
const Color kLoyverseGreen = Color(0xFF1FA85A);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kLoyverseGreen);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF4F6F5),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF232829),
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kLoyverseGreen,
        // 只设最小高度；宽度不能用 infinity（Size.fromHeight 会让宽度=∞，
        // 一旦按钮放进 Row 这种「无界宽度」的父级就会崩）。
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class BigBossBroApp extends StatelessWidget {
  final ReceiptPrintService printService;

  const BigBossBroApp({super.key, required this.printService});

  /// 建同步服务，并把 PosController / AttendanceController 的「本地变了」钩子接上。
  ///
  /// 注意：PosController / SettingsController / AttendanceController 都是
  /// **惰性创建一次**（用 `create:`），不能写成在 `build()` 里 `new`
  /// （build 会跑很多次 → 状态会被清掉）。
  static SyncService _createSync(BuildContext ctx) {
    final pos = ctx.read<PosController>();
    final settingsCtl = ctx.read<SettingsController>();
    final attendance = ctx.read<AttendanceController>();
    final sync = SyncService(
      pos: pos,
      settingsCtl: settingsCtl,
      attendance: attendance,
    );
    pos.onOrdersChanged = sync.onLocalOrdersChanged;
    pos.onMenuChanged = sync.onLocalMenuChanged;
    attendance.onStaffChanged = sync.onLocalStaffChanged;
    attendance.onPunchesChanged = sync.onLocalPunchesChanged;
    return sync;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PosController()),
        ChangeNotifierProvider(create: (_) => SettingsController()..load()),
        // 账号：启动就读回；没登录的话下面会显示登录页
        ChangeNotifierProvider(create: (_) => AuthController()..load()),
        // 员工签到（考勤）：自己一套存储，跟点单/结账互不影响
        ChangeNotifierProvider(create: (_) => AttendanceController()..load()),
        Provider<ReceiptPrintService>.value(value: printService),
        // 后台同步（Supabase）：收银永远先写本机，它只在后台搬运
        ChangeNotifierProxyProvider3<PosController, SettingsController,
            AttendanceController, SyncService>(
          create: _createSync,
          // 依赖变了就沿用同一个实例（内部自己判断要不要同步）
          update: (ctx, pos, settings, attendance, sync) =>
              sync ?? _createSync(ctx),
        ),
      ],
      child: const _AppShell(),
    );
  }
}

/// 真正的界面（单独抽出来：provider 建好之后再启动同步）。
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  SettingsController? _settings;
  SyncService? _sync;

  @override
  void initState() {
    super.initState();
    // 监听「前台/后台」：平板息屏或切走时定时器可能被系统冻住，
    // 回到前台要马上补一次同步（否则要等下一个 25 秒才看到别人的改动）。
    WidgetsBinding.instance.addObserver(this);
    // 等一帧：provider 都建好了再接线。
    // 设置是异步读回来的，所以监听它：读回来（或用户改了配置）就重启同步。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync = context.read<SyncService>();
      _settings = context.read<SettingsController>();
      _settings!.addListener(_onSettings);
      _onSettings();
    });
  }

  void _onSettings() => _sync?.onSettingsChanged();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final sync = _sync;
    if (sync != null) unawaited(sync.syncNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_onSettings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: L10n.lang,
      builder: (context, _, __) {
        return MaterialApp(
          onGenerateTitle: (ctx) => L10n.t('app.title'),
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          locale: Locale(L10n.currentLang),
          supportedLocales: const [Locale('zh'), Locale('es'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: _SplashGate(
            child: ValueListenableBuilder<String>(
              valueListenable: L10n.lang,
              builder: (context, _, __) => Consumer<AuthController>(
                // 没登录 → 登录页；登录了 → 正常界面
                //
                // ⚠️ 这里**故意不写 `const HomeShell()` / `const LoginScreen()`**：
                // 分析器会提示加 const，但那样在切语言时 Flutter 会因为「widget 完全相同」
                // 而跳过整棵子树的重建，界面上的文字就不会跟着语言变了。
                // （登录页那个语言按钮点了没反应，真因就是这个 —— 已踩过。）
                builder: (authContext, auth, child) =>
                    auth.isSignedIn ? HomeShell() : LoginScreen(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// **启动画面**：白底 + 中文 logo（`assets/bbb_log_chinese.png`）。
///
/// 什么时候进主界面：`设置` 和 `账号` 都从本机读回来了，**并且**至少显示了
/// [_minShow] 那么久。后者是为了让 logo 看得见 —— 本机读取只要几毫秒，
/// 不压一下的话 logo 只闪一下，等于没有。
///
/// 想调长短就改 [_minShow]；不想要启动画面的话，把 `_AppShell.build()` 里的
/// `home:` 恢复成直接的 `ValueListenableBuilder` 就行。
class _SplashGate extends StatefulWidget {
  final Widget child;
  const _SplashGate({required this.child});

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  /// 最少显示多久：**1.8 秒**（够看清 logo，又不至于让人等得不耐烦）。
  static const Duration _minShow = Duration(milliseconds: 1800);

  bool _timeUp = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_minShow, () {
      if (mounted) setState(() => _timeUp = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 账号没读回来就进去的话会先闪一下登录页，设置没读回来界面会是默认值 —— 等它俩。
    final ready = context.watch<SettingsController>().loaded &&
        context.watch<AuthController>().loaded;
    if (_timeUp && ready) return widget.child;
    return const _SplashView();
  }
}

/// 启动画面本体：一张 logo 居中（图里已经带了店招文字，不用另外加字）。
class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        // `cacheWidth`：原图 1254×1254，按显示宽度（380 逻辑像素 × 2 倍屏 = 760）
        // 解码就够了 —— 解码后的内存从 ~6MB 降到 ~2MB，清晰度看不出来差别。
        child: Padding(
          // 手机那种窄屏：FittedBox 会自动缩小，不会撑破
          padding: const EdgeInsets.all(24),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Image.asset(
              'assets/bbb_log_chinese.png',
              width: 380,
              cacheWidth: 760,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}
