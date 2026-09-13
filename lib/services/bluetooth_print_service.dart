import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/settings_store.dart';
import 'receipt_print_service.dart';

/// 蓝牙热敏打印机（经典蓝牙 SPP；安卓）。
///
/// 这里**只负责传输**：扫描设备、连接、把字节写出去。
/// 小票怎么排版、字节怎么编码，由上层（ticket_builder / escpos）负责。
class BluetoothPrintService {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;

  BluetoothConnection? _connection;
  PrinterDevice? _connectedDevice;
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySub;

  bool get isConnected => _connection != null && _connection!.isConnected;
  PrinterDevice? get connectedDevice => _connectedDevice;

  // ---------- 扫描 ----------

  Future<List<PrinterDevice>> scanDevices(Settings settings) async {
    if (!await _grantPermissions()) return const [];

    // 先列出已配对设备
    final found = <String, PrinterDevice>{};
    final bonded = await _bluetooth.getBondedDevices();
    for (final d in bonded) {
      found[d.address] = PrinterDevice(
        name: d.name ?? d.address,
        address: d.address,
        transport: PrintTransport.bluetooth,
      );
    }

    // 再扫描一段时间，收进附近的打印机
    try {
      _discoverySub = _bluetooth.startDiscovery().listen((result) {
        final d = result.device;
        if (d.address.isEmpty) return;
        found[d.address] = PrinterDevice(
          name: (d.name == null || d.name!.isEmpty) ? d.address : d.name!,
          address: d.address,
          transport: PrintTransport.bluetooth,
        );
      });
      await Future<void>.delayed(const Duration(seconds: 4));
    } catch (_) {
      // 扫描失败不致命，仍有已配对设备可用
    } finally {
      await _discoverySub?.cancel();
      _discoverySub = null;
      try {
        await _bluetooth.cancelDiscovery();
      } catch (_) {}
    }

    return found.values.toList();
  }

  // ---------- 连接 / 断开 ----------

  Future<bool> connect(PrinterDevice device) async {
    try {
      if (!await _grantPermissions()) return false;
      await disconnect();
      final conn = await BluetoothConnection.toAddress(device.address);
      _connection = conn;
      _connectedDevice = device;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      _connection?.close();
    } catch (_) {}
    _connection = null;
    _connectedDevice = null;
  }

  Future<bool> _ensureConnected(Settings settings) async {
    if (isConnected) return true;
    if (settings.printerAddress.isEmpty) return false;
    return connect(PrinterDevice(
      name: settings.printerName,
      address: settings.printerAddress,
      transport: PrintTransport.bluetooth,
    ));
  }

  // ---------- 写出 ----------

  Future<PrintError?> printBytes(Settings settings, List<int> bytes) async {
    if (!await _ensureConnected(settings)) return PrintError.notConnected;
    try {
      // flutter_bluetooth_serial 0.4.0 的 output 是 StreamSink<Uint8List>：
      //   add(...) 需要 Uint8List；等数据发完用 output.allSent（没有 flush()）。
      _connection!.output.add(Uint8List.fromList(bytes));
      await _connection!.output.allSent;
      return null;
    } catch (_) {
      return PrintError.ioError;
    }
  }

  // ---------- Android 12+ 权限 ----------

  Future<bool> _grantPermissions() async {
    try {
      if (await Permission.bluetoothScan.isDenied) {
        if (await Permission.bluetoothScan.request() != PermissionStatus.granted) {
          return false;
        }
      }
      if (await Permission.bluetoothConnect.isDenied) {
        if (await Permission.bluetoothConnect.request() !=
            PermissionStatus.granted) {
          return false;
        }
      }
      if (await Permission.location.isDenied) {
        if (await Permission.location.request() != PermissionStatus.granted) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> dispose() async {
    await _discoverySub?.cancel();
    await disconnect();
  }
}
