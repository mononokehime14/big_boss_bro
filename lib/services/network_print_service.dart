import 'dart:io';

import '../data/settings_store.dart';
import 'receipt_print_service.dart';

/// 网络/以太网/局域网打印机：把 ESC/POS 字节直接通过 TCP 发到打印机。
///
/// 绝大多数网络小票机监听 **9100** 端口（也叫 RAW/JetDirect）。
/// 你只要在设置里填打印机的 IP 和端口即可。Windows 和安卓都能用。
class NetworkPrintService {
  /// 打印前连通性测试：能不能连上 IP:端口。
  Future<bool> ping(Settings settings) async {
    if (settings.printerAddress.isEmpty) return false;
    try {
      final socket = await Socket.connect(
        settings.printerAddress,
        settings.printerPort,
        timeout: const Duration(seconds: 4),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 把字节发给网络打印机。成功返回 null，失败返回原因。
  Future<PrintError?> printBytes(Settings settings, List<int> bytes) async {
    if (settings.printerAddress.isEmpty) return PrintError.noPrinter;
    Socket? socket;
    try {
      socket = await Socket.connect(
        settings.printerAddress,
        settings.printerPort,
        timeout: const Duration(seconds: 5),
      );
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      socket.destroy();
      return null;
    } catch (_) {
      try {
        socket?.destroy();
      } catch (_) {}
      return PrintError.notConnected;
    }
  }
}
