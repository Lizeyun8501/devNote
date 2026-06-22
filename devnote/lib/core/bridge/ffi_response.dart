import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// FFI C 结构体 —— 用于 native 库返回的响应
///
/// 字段顺序与 Rust 端 `devnote-ffi/src/lib.rs` 的 `#[repr(C)] FFIResponse`
/// 及 C 头文件 `devnote_ffi.h` 严格一致：
///   Rust:  { code: i32, message: *mut c_char, data: *mut c_char }
///   C:     { int32_t code, char *message, char *data }
///   Dart:  { @Int32 code, Pointer<Utf8> message, Pointer<Utf8> data }
///
/// 修复(P0): 旧定义字段顺序为 data/data_len/code/message，与 Rust/C 不一致，
/// 且多出 data_len 字段（Rust 从未写入），导致读取未初始化内存。
/// 现统一为 code/message/data 三字段顺序，移除 data_len。
/// data 为 CString（null-terminated），通过 toDartString() 读取长度。
base class FFIResponseC extends Struct {
  @Int32()
  external int code;
  external Pointer<Utf8> message;
  external Pointer<Utf8> data;
}

class FFIResponse {
  final int code;
  final String message;
  final Uint8List? data;

  const FFIResponse({
    required this.code,
    required this.message,
    this.data,
  });

  factory FFIResponse.fromBuffer(Uint8List buffer) {
    final json = jsonDecode(utf8.decode(buffer)) as Map<String, dynamic>;
    final dataRaw = json['data'];
    Uint8List? data;
    if (dataRaw != null && dataRaw is List) {
      data = Uint8List.fromList(dataRaw.cast<int>());
    }
    return FFIResponse(
      code: json['code'] as int,
      message: json['message'] as String? ?? '',
      data: data,
    );
  }

  bool get isOk => code == 0;

  @override
  String toString() => 'FFIResponse(code: $code, message: $message, hasData: ${data != null})';
}
