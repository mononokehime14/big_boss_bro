import '../data/settings_store.dart';
import '../models/order.dart';

/// 一台可打印的设备。
/// - 蓝牙：`address` 是 MAC 地址
/// - 网络：`address` 是 IP（端口在设置里）
/// - Windows：`address` 是系统打印机名
class PrinterDevice {
  final String name;
  final String address;
  final PrintTransport transport;

  const PrinterDevice({
    required this.name,
    required this.address,
    this.transport = PrintTransport.bluetooth,
  });

  @override
  String toString() => '$name ($address)';
}

/// 打印失败的原因（用于 UI 提示）。
enum PrintError {
  noPrinter,
  notConnected,
  ioError,
  unsupported,
}

/// 打印服务接口。
///
/// 具体走哪条通道由 [Settings.transport] 决定（蓝牙 / 网络 / Windows 系统打印机），
/// 由 `print_service.dart` 里的统一实现分发。界面只依赖这个接口。
abstract class ReceiptPrintService {
  /// 扫描当前通道可用的设备（蓝牙设备 / Windows 已安装打印机；网络返回空，由用户填 IP）。
  Future<List<PrinterDevice>> scanDevices(Settings settings);

  /// 选中设备（蓝牙会真正建立连接；网络/Windows 仅记录，打印时再连）。
  Future<bool> connect(PrinterDevice device);

  /// 断开（蓝牙）。
  Future<void> disconnect();

  bool get isConnected;
  PrinterDevice? get connectedDevice;

  /// 打印「厨房单」：下单/追单时给厨房看（只有菜名+数量+桌号）。
  Future<PrintError?> printKitchenTicket(
    Order order,
    Settings settings, {
    bool isAppend = false,
  });

  /// 打印「顾客小票」：结账时给客人（含单价/金额/支付方式）。
  Future<PrintError?> printReceipt(Order order, Settings settings);

  /// 打印一张测试页（验证通道、中文编码、纸宽）。
  Future<PrintError?> printTestPage(Settings settings);

  /// 释放资源。
  Future<void> dispose();
}
