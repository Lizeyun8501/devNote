/// FFI 错误处理模块 —— 统一 FFI 通信错误类型
///
/// ## 设计来源
/// 借鉴 AppFlowy 的 FlowyResult / FlowyError 模式，提供类型安全的 FFI 错误处理。
///
/// ## 核心类型
/// - `FFIStatusCode`: 标准 FFI 状态码枚举
/// - `FlowyInternalError`: FFI 内部错误
/// - `FlowyResult<S, F>`: 密封类，表示成功或失败结果
///
/// ## 使用示例
/// ```dart
/// final note = await dispatch.createNote(title: 'xxx', content: 'xxx', folderId: 'xxx');
/// ```

/// FFI 通信标准状态码
enum FFIStatusCode {
  ok,
  err,
  internal,
  network,
  unauthorized,
}

/// FFI 内部错误
class FlowyInternalError implements Exception {
  final int code;
  final String message;

  const FlowyInternalError({
    required this.code,
    required this.message,
  });

  factory FlowyInternalError.fromCode(int code) {
    final status = FFIStatusCode.values.firstWhere(
      (e) => e.index == code,
      orElse: () => FFIStatusCode.internal,
    );
    return FlowyInternalError(
      code: code,
      message: _defaultMessage(status),
    );
  }

  static String _defaultMessage(FFIStatusCode status) {
    switch (status) {
      case FFIStatusCode.ok:
        return '';
      case FFIStatusCode.err:
        return 'General error';
      case FFIStatusCode.internal:
        return 'Internal error';
      case FFIStatusCode.network:
        return 'Network error';
      case FFIStatusCode.unauthorized:
        return 'Unauthorized';
    }
  }

  @override
  String toString() => 'FlowyInternalError(code: $code, message: $message)';
}

/// 密封类：表示 FFI 操作的结果（成功或失败）
///
/// 使用 Dart 3 sealed class 提供编译时穷举检查，
/// 替代原 dispatch.dart 中内联的简单 FlowyResult 实现。
sealed class FlowyResult<S, F> {
  const FlowyResult();
}

class Success<S, F> extends FlowyResult<S, F> {
  final S value;
  const Success(this.value);
}

class Failure<S, F> extends FlowyResult<S, F> {
  final F error;
  const Failure(this.error);
}

/// 标准错误类型 —— 替代原始的 FFI 数字错误码
///
/// 使用 Dart 3 sealed class 提供编译时穷举检查，
/// 每个错误子类包含语义化的错误信息。
sealed class DevNoteError implements Exception {
  final String message;
  const DevNoteError(this.message);

  factory DevNoteError.from(dynamic error) {
    // 修复: 原代码引用未定义的 DatabaseError/NetworkError/ValidationError/
    // AuthError/SyncError,改用 sealed class 的具体子类判断,保持类型安全
    if (error is DevNoteDatabaseError) return error;
    if (error is DevNoteNetworkError) return error;
    if (error is DevNoteValidationError) return error;
    if (error is DevNoteAuthError) return error;
    if (error is DevNoteSyncError) return error;
    return DevNoteUnknownError(error.toString());
  }
}

class DevNoteDatabaseError extends DevNoteError {
  const DevNoteDatabaseError(super.message);
}

class DevNoteNetworkError extends DevNoteError {
  const DevNoteNetworkError(super.message);
}

class DevNoteValidationError extends DevNoteError {
  const DevNoteValidationError(super.message);
}

class DevNoteAuthError extends DevNoteError {
  const DevNoteAuthError(super.message);
}

class DevNoteSyncError extends DevNoteError {
  const DevNoteSyncError(super.message);
}

class DevNoteUnknownError extends DevNoteError {
  const DevNoteUnknownError(super.message);
}