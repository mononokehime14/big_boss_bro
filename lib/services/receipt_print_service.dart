import '../data/settings_store.dart';
import '../models/order.dart';
import 'receipt_layout.dart';

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

  /// 打印「厨房单」：下单/追单时给厨房看（桌号 / 外卖名字 + 菜名 + 数量，不含价格）。
  ///
  /// 版式见 `receipt_layout.dart` 的 `buildKitchenRows` 和 `kitchen_ticket.md` §0：
  /// 上面留别针区 → 票号 + 时间 → 桌号/名字（特大）→ 菜品 → **底部堂食/外卖徽标（西文 + 中文）**。
  ///
  /// [drinksFrom] = **第一道饮料在第几行**（`-1` = 没有饮料）：行要由调用方排成
  /// 「餐品在前、饮料在后」，这里会在饮料前面打一条虚线（见 `PosController.kitchenTicketLines`）。
  Future<PrintError?> printKitchenTicket(
    Order order,
    Settings settings, {
    bool isAppend = false,
    int drinksFrom = -1,
  });

  /// 打印「顾客小票 / 单子」：结账窗口里点「打印单子 / 再打一张」时打给客人
  /// （明细 + 单价/金额 + 折扣/税 + 合计）。
  ///
  /// 注意：这时订单还是**进行中**（还没收款），所以纸上**不会**有
  /// 「支付方式 / 实收 / 找零」那几行 —— 打纸和收款是分开的：
  /// 想打就打（可以打多次），点「确认收款」才落账，那一步**不出纸**。
  Future<PrintError?> printReceipt(Order order, Settings settings);

  /// 打印一张测试页（验证通道、中文编码、纸宽）。
  Future<PrintError?> printTestPage(Settings settings);

  /// 打印一张「日结」每日汇总。
  Future<PrintError?> printSummary(SummaryData data, Settings settings);

  /// 释放资源。
  Future<void> dispose();
}
