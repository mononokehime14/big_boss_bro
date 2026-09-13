import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'screens/home_shell.dart';
import 'services/receipt_print_service.dart';
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
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF232829),
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

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PosController()),
        ChangeNotifierProvider(create: (_) => SettingsController()..load()),
        Provider<ReceiptPrintService>.value(value: printService),
      ],
      child: ValueListenableBuilder<String>(
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
            home: ValueListenableBuilder<String>(
              valueListenable: L10n.lang,
              builder: (context, _, __) =>
                  // 不写 const：语言一变，强制整棵界面重建，让 L10n.t 重新取文案。
                  HomeShell(),
            ),
          );
        },
      ),
    );
  }
}
