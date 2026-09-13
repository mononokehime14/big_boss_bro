import 'package:flutter/material.dart';

import 'app.dart';
import 'services/print_service.dart';
import 'services/receipt_print_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 统一打印服务：按设置里的「打印方式」自动走
  // 蓝牙（安卓）/ 网络 TCP（以太网、局域网）/ Windows 系统打印机（USB 等）。
  final ReceiptPrintService printService = UnifiedPrintService();

  runApp(BigBossBroApp(printService: printService));
}
