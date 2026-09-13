import '../data/settings_store.dart';
import '../models/order.dart';
import 'receipt_print_service.dart';

/// 不做任何事情的打印实现。
///
/// 用在测试里（例如 widget 冒烟测试），避免在非目标平台上碰真实打印通道。
class UnsupportedPrintService implements ReceiptPrintService {
  @override
  Future<List<PrinterDevice>> scanDevices(Settings settings) async => const [];

  @override
  Future<bool> connect(PrinterDevice device) async => false;

  @override
  Future<void> disconnect() async {}

  @override
  bool get isConnected => false;

  @override
  PrinterDevice? get connectedDevice => null;

  @override
  Future<PrintError?> printKitchenTicket(
    Order order,
    Settings settings, {
    bool isAppend = false,
  }) async =>
      PrintError.unsupported;

  @override
  Future<PrintError?> printReceipt(Order order, Settings settings) async =>
      PrintError.unsupported;

  @override
  Future<PrintError?> printTestPage(Settings settings) async =>
      PrintError.unsupported;

  @override
  Future<void> dispose() async {}
}
