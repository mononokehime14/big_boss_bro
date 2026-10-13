import 'dart:io';

import '../data/settings_store.dart';
import '../models/order.dart';
import 'bluetooth_print_service.dart';
import 'escpos.dart';
import 'network_print_service.dart';
import 'receipt_layout.dart';
import 'receipt_print_service.dart';
import 'ticket_builder.dart';
import 'windows_print_service.dart';

/// 统一打印服务：按 [Settings.transport] 把同一张小票分发给
/// 蓝牙（安卓）/ 网络（TCP 9100）/ Windows 系统打印机（USB 等）。
///
/// 界面只依赖 [ReceiptPrintService] 接口，不关心底层是哪条通道。
class UnifiedPrintService implements ReceiptPrintService {
  // 蓝牙服务按需创建：Windows 上不选蓝牙就完全不碰蓝牙插件。
  BluetoothPrintService? _btInstance;
  BluetoothPrintService get _bt => _btInstance ??= BluetoothPrintService();

  final NetworkPrintService _net = NetworkPrintService();

  // ---------- 设备发现 ----------

  @override
  Future<List<PrinterDevice>> scanDevices(Settings settings) async {
    switch (settings.transport) {
      case PrintTransport.bluetooth:
        return _bt.scanDevices(settings);
      case PrintTransport.windows:
        final names = await WindowsPrintService.listPrinters();
        return names
            .map((n) => PrinterDevice(
                  name: n,
                  address: n,
                  transport: PrintTransport.windows,
                ))
            .toList();
      case PrintTransport.network:
        // 网络打印机不需要扫描，用户直接填 IP + 端口
        return const [];
    }
  }

  @override
  Future<bool> connect(PrinterDevice device) async {
    if (device.transport == PrintTransport.bluetooth) {
      return _bt.connect(device);
    }
    // 网络 / Windows 不需要事先“连接”，打印时才连
    return true;
  }

  @override
  Future<void> disconnect() async {
    await _btInstance?.disconnect();
  }

  @override
  bool get isConnected => _btInstance?.isConnected ?? false;

  @override
  PrinterDevice? get connectedDevice => _btInstance?.connectedDevice;

  // ---------- 打印 ----------

  /// **厨房单：默认打两张**（一张厨师看、一张出餐服务员看），
  /// 票面上用「厨师单 1 / 厨师单 2」区分（份数见 `Settings.kitchenCopies`）。
  ///
  /// 两张**一次发出去**（不是打两次）：一次连接、一次送完，比中途重连稳
  /// （蓝牙/网络打印机中途重连一次就可能丢一张）。
  ///
  /// 行距用 **`ESC J`（每行后额外走纸）** 撑开，见 `escpos.dart` 的
  /// [kKitchenExtraFeedDots]：实测这台机器在放大字行上会忽略 `ESC 3`（设行距那条），
  /// 所以只有"直接走纸"才真的看得出变化。
  @override
  Future<PrintError?> printKitchenTicket(
    Order order,
    Settings settings, {
    bool isAppend = false,
  }) {
    final copies = settings.kitchenCopies < 1 ? 1 : settings.kitchenCopies;
    final bytes = <int>[];
    for (var i = 1; i <= copies; i++) {
      bytes.addAll(buildEscPosBytes(
        TicketBuilder.kitchenLines(
          order,
          settings,
          isAppend: isAppend,
          copyIndex: i,
          copyTotal: copies,
        ),
        codec: settings.receiptCodec,
        fontA: settings.useFontA,
        // ⚠️ 故意**不传** lineSpacingDots：`ESC 3` 在这台机器上被忽略（见上面的注释）。
        //    想给"认 ESC 3 的机器"也用上，就把下面这行打开：
        // lineSpacingDots: kKitchenLineSpacingDots,
        extraFeedDots: kKitchenExtraFeedDots,
      ));
    }
    return _sendBytes(settings, bytes);
  }

  /// 打「顾客小票 / 单子」：结账窗口里点「打印单子」就打了（明细 + 合计）。
  /// 订单这时还没收款，所以纸上没有支付方式/实收/找零 —— 这是有意的（打纸和收款分开）。
  @override
  Future<PrintError?> printReceipt(Order order, Settings settings) {
    return _write(settings, TicketBuilder.receiptLines(order, settings));
  }

  @override
  Future<PrintError?> printTestPage(Settings settings) {
    return _write(settings, TicketBuilder.testLines(settings));
  }

  @override
  Future<PrintError?> printSummary(SummaryData data, Settings settings) {
    return _write(settings, TicketBuilder.summaryLines(data));
  }

  /// 把行文本按当前通道发出去（编码/字体取自设置）。
  Future<PrintError?> _write(Settings settings, List<TicketLine> lines) =>
      _sendBytes(
        settings,
        buildEscPosBytes(
          lines,
          codec: settings.receiptCodec,
          fontA: settings.useFontA,
        ),
      );

  /// 把**已经编好的 ESC/POS 字节**按当前通道发出去。
  Future<PrintError?> _sendBytes(Settings settings, List<int> bytes) async {
    switch (settings.transport) {
      case PrintTransport.bluetooth:
        return _bt.printBytes(settings, bytes);

      case PrintTransport.network:
        return _net.printBytes(settings, bytes);

      case PrintTransport.windows:
        if (!Platform.isWindows) return PrintError.unsupported;
        return WindowsPrintService.printRaw(
          settings.windowsPrinterName,
          bytes,
        );
    }
  }

  @override
  Future<void> dispose() async {
    await _btInstance?.dispose();
  }
}
