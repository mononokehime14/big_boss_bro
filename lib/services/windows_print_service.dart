import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'receipt_print_service.dart';

// ---------------------------------------------------------------------------
// Windows 系统打印机（USB 等）：通过后台打印程序（spooler）以 RAW 方式，
// 把 ESC/POS 字节原样交给打印机驱动。
//
// 用 Windows 自带的 winspool.drv，直接 dart:ffi 调用，不依赖第三方包：
//   OpenPrinterW → StartDocPrinterW(RAW) → StartPagePrinter
//   → WritePrinter → EndPagePrinter → EndDocPrinter → ClosePrinter
//
// 注意：内存释放用分配器自己的方法 —— `calloc.free(ptr)` / `malloc.free(ptr)`
//（package:ffi 里已经没有顶层 `free()` 了）。
// ---------------------------------------------------------------------------

typedef _OpenPrinterNative = Int32 Function(
    Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>);
typedef _OpenPrinterDart = int Function(
    Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>);

typedef _StartDocPrinterNative = Int32 Function(IntPtr, Uint32, Pointer<Uint8>);
typedef _StartDocPrinterDart = int Function(int, int, Pointer<Uint8>);

typedef _BoolHandleNative = Int32 Function(IntPtr);
typedef _BoolHandleDart = int Function(int);

typedef _WritePrinterNative = Int32 Function(
    IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>);
typedef _WritePrinterDart = int Function(
    int, Pointer<Uint8>, int, Pointer<Uint32>);

typedef _GetDefaultPrinterNative = Int32 Function(
    Pointer<Utf16>, Pointer<Uint32>);
typedef _GetDefaultPrinterDart = int Function(
    Pointer<Utf16>, Pointer<Uint32>);

final class _DocInfo1W extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

class WindowsPrintService {
  static _OpenPrinterDart? _openPrinter;
  static _StartDocPrinterDart? _startDocPrinter;
  static _BoolHandleDart? _startPagePrinter;
  static _WritePrinterDart? _writePrinter;
  static _BoolHandleDart? _endPagePrinter;
  static _BoolHandleDart? _endDocPrinter;
  static _BoolHandleDart? _closePrinter;
  static _GetDefaultPrinterDart? _getDefaultPrinter;

  static bool get _supported => Platform.isWindows;

  static void _ensureLoaded() {
    if (_openPrinter != null) return;
    final lib = DynamicLibrary.open('winspool.drv');
    _openPrinter = lib.lookupFunction<_OpenPrinterNative, _OpenPrinterDart>(
        'OpenPrinterW');
    _startDocPrinter = lib.lookupFunction<_StartDocPrinterNative,
        _StartDocPrinterDart>('StartDocPrinterW');
    _startPagePrinter = lib
        .lookupFunction<_BoolHandleNative, _BoolHandleDart>('StartPagePrinter');
    _writePrinter = lib.lookupFunction<_WritePrinterNative, _WritePrinterDart>(
        'WritePrinter');
    _endPagePrinter = lib
        .lookupFunction<_BoolHandleNative, _BoolHandleDart>('EndPagePrinter');
    _endDocPrinter =
        lib.lookupFunction<_BoolHandleNative, _BoolHandleDart>('EndDocPrinter');
    _closePrinter =
        lib.lookupFunction<_BoolHandleNative, _BoolHandleDart>('ClosePrinter');
    _getDefaultPrinter = lib.lookupFunction<_GetDefaultPrinterNative,
        _GetDefaultPrinterDart>('GetDefaultPrinterW');
  }

  /// 列出 Windows 里已安装的打印机名（用 PowerShell 的 Get-Printer）。
  static Future<List<String>> listPrinters() async {
    if (!_supported) return const [];
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-Printer | Select-Object -ExpandProperty Name',
      ]);
      if (r.exitCode != 0) return const [];
      final out = r.stdout.toString();
      return out
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 取 Windows 默认打印机名。
  static String? defaultPrinter() {
    if (!_supported) return null;
    try {
      _ensureLoaded();
      final size = calloc<Uint32>();
      final buf = calloc<Uint16>(512); // 打印机名一般不超过 512 字符
      try {
        size.value = 512;
        final ok = _getDefaultPrinter!(buf.cast<Utf16>(), size);
        if (ok == 0) return null;
        return buf.cast<Utf16>().toDartString();
      } finally {
        calloc.free(buf);
        calloc.free(size);
      }
    } catch (_) {
      return null;
    }
  }

  /// 以 RAW 方式把字节发给指定打印机。成功返回 null。
  static PrintError? printRaw(String printerName, List<int> bytes) {
    if (!_supported) return PrintError.unsupported;
    if (printerName.isEmpty) return PrintError.noPrinter;
    if (bytes.isEmpty) return PrintError.ioError;
    try {
      _ensureLoaded();
    } catch (_) {
      return PrintError.unsupported;
    }

    // 先把要用的内存一次分配好，最后统一释放。
    final hPrinter = calloc<IntPtr>();
    final namePtr = printerName.toNativeUtf16(); // 用 malloc
    final docInfo = calloc<_DocInfo1W>();
    final docNamePtr = 'Receipt'.toNativeUtf16(); // 用 malloc
    final dataTypePtr = 'RAW'.toNativeUtf16(); // 用 malloc
    final buf = calloc<Uint8>(bytes.length);
    final written = calloc<Uint32>();
    var handle = 0;

    try {
      if (_openPrinter!(namePtr, hPrinter, nullptr) == 0) {
        return PrintError.notConnected;
      }
      handle = hPrinter.value;

      docInfo.ref.pDocName = docNamePtr;
      docInfo.ref.pOutputFile = nullptr;
      docInfo.ref.pDatatype = dataTypePtr;

      final job = _startDocPrinter!(handle, 1, docInfo.cast<Uint8>());
      if (job == 0) return PrintError.ioError;

      if (_startPagePrinter!(handle) == 0) {
        _endDocPrinter!(handle);
        return PrintError.ioError;
      }

      buf.asTypedList(bytes.length).setAll(0, bytes);
      final ok = _writePrinter!(handle, buf, bytes.length, written);

      _endPagePrinter!(handle);
      _endDocPrinter!(handle);

      return ok == 0 ? PrintError.ioError : null;
    } catch (_) {
      return PrintError.ioError;
    } finally {
      if (handle != 0) {
        try {
          _closePrinter!(handle);
        } catch (_) {}
      }
      calloc.free(buf);
      calloc.free(written);
      calloc.free(docInfo);
      malloc.free(docNamePtr);
      malloc.free(dataTypePtr);
      malloc.free(namePtr);
      calloc.free(hPrinter);
    }
  }
}
