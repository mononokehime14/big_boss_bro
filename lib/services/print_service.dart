import 'dart:io';

import '../data/settings_store.dart';
import '../models/order.dart';
import 'bluetooth_print_service.dart';
import 'escpos.dart';
import 'network_print_service.dart';
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

  @override
  Future<PrintError?> printKitchenTicket(
    Order order,
    Settings settings, {
    bool isAppend = false,
  }) {
    return _write(
      settings,
      TicketBuilder.kitchenLines(order, settings, isAppend: isAppend),
    );
  }

  @override
  Future<PrintError?> printReceipt(Order order, Settings settings) {
    return _write(settings, TicketBuilder.receiptLines(order, settings));
  }

  @override
  Future<PrintError?> printTestPage(Settings settings) {
    return _write(settings, TicketBuilder.testLines(settings));
  }

  /// 把行文本按当前通道发出去。
  Future<PrintError?> _write(Settings settings, List<String> lines) async {
    switch (settings.transport) {
      case PrintTransport.bluetooth:
        return _bt.printBytes(settings, buildEscPosBytes(lines));

      case PrintTransport.network:
        return _net.printBytes(settings, buildEscPosBytes(lines));

      case PrintTransport.windows:
        if (!Platform.isWindows) return PrintError.unsupported;
        return WindowsPrintService.printRaw(
          settings.windowsPrinterName,
          buildEscPosBytes(lines),
        );
    }
  }

  @override
  Future<void> dispose() async {
    await _btInstance?.dispose();
  }
}
