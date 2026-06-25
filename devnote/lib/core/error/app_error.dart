// 统一错误处理类型 —— 借鉴 Rust 的 Result<T, E> 模式与 fpdart 的 Either 实现
//
// 设计目标:
// 1. 统一三层（Rust / Flutter / Go）的错误处理语义，避免各层自定义错误类型导致对接困难。
// 2. 使用 Dart 3 sealed class 模式实现穷尽式模式匹配，编译器保证所有错误分支都被处理。
// 3. AppError 分类覆盖常见业务错误场景，便于 UI 层按错误类型展示差异化提示。
//
// 借鉴来源:
// - Rust std::result::Result<T, E>（穷尽式错误处理）
// - fpdart Either<L, R>（Dart 函数式错误传递）
// - AppFlowy 的 FlowyError 分类设计
//
// 使用方式:
// ```dart
// Future<AppResult<Note>> loadNote(String id) async {
//   try {
//     final note = await repo.get(id);
//     if (note == null) {
//       return AppResult.failure(AppError.notFound('笔记不存在: $id'));
//     }
//     return AppResult.success(note);
//   } catch (e) {
//     return AppResult.failure(AppError.unknown('加载笔记失败', e));
//   }
// }
//
// // 调用方穷尽式匹配
// final result = await loadNote(id);
// switch (result) {
//   case AppSuccess(:final value):
//     renderNote(value);
//   case AppFailure(:final error):
//     handleError(error);
// }
// ```

/// 应用统一错误类型
///
/// 使用 sealed class 保证 switch 穷尽性检查：
/// 编译器会强制要求所有子类型都被处理，避免遗漏错误分支。
///
/// 错误分类借鉴 HTTP 状态码语义：
/// - network: 网络层错误（连接超时、DNS 失败等）
/// - database: 本地持久化错误（SQLite 读写失败、迁移失败等）
/// - validation: 输入校验错误（字段格式不合法、必填项缺失等）
/// - notFound: 资源不存在（笔记/文件夹/标签未找到）
/// - unauthorized: 鉴权失败（token 过期、权限不足）
/// - unknown: 未分类错误（兜底，保留原始异常对象便于排查）
sealed class AppError {
  const AppError(this.message);

  /// 人类可读的错误描述（已脱敏，可直接展示给用户）
  final String message;

  /// 网络错误 —— 连接超时、DNS 解析失败、HTTP 5xx 等
  const factory AppError.network(String message) = NetworkError;

  /// 数据库错误 —— SQLite 读写失败、迁移失败、约束冲突等
  const factory AppError.database(String message) = DatabaseError;

  /// 校验错误 —— 输入字段格式不合法、必填项缺失等
  const factory AppError.validation(String message) = ValidationError;

  /// 资源不存在 —— 笔记/文件夹/标签未找到
  const factory AppError.notFound(String message) = NotFoundError;

  /// 鉴权失败 —— token 过期、权限不足、未登录
  const factory AppError.unauthorized(String message) = UnauthorizedError;

  /// 未知错误 —— 兜底分类，保留原始异常对象便于 Sentry 上报与排查
  const factory AppError.unknown(String message, Object? error) = UnknownError;
}

/// 网络错误
final class NetworkError extends AppError {
  const NetworkError(super.message);
}

/// 数据库错误
final class DatabaseError extends AppError {
  const DatabaseError(super.message);
}

/// 校验错误
final class ValidationError extends AppError {
  const ValidationError(super.message);
}

/// 资源不存在错误
final class NotFoundError extends AppError {
  const NotFoundError(super.message);
}

/// 鉴权失败错误
final class UnauthorizedError extends AppError {
  const UnauthorizedError(super.message);
}

/// 未知错误 —— 保留原始异常对象，便于日志与 Sentry 上报
final class UnknownError extends AppError {
  /// 原始异常对象（可能为 null，例如由 String 构造的未知错误）
  final Object? error;

  const UnknownError(super.message, this.error);
}

/// 统一结果类型 —— 借鉴 Rust `Result<T, E>`
///
/// 用 sealed class 替代 fpdart Either，避免引入额外依赖。
/// 调用方通过 switch 模式匹配处理成功与失败两种情况，编译器保证穷尽性。
///
/// 示例:
/// ```dart
/// final result = await service.fetch();
/// switch (result) {
///   case AppSuccess(:final value):
///     print('成功: $value');
///   case AppFailure(:final error):
///     print('失败: ${error.message}');
/// }
/// ```
sealed class AppResult<T> {
  const AppResult();

  /// 构造成功结果
  const factory AppResult.success(T value) = AppSuccess<T>;

  /// 构造失败结果
  const factory AppResult.failure(AppError error) = AppFailure<T>;

  /// 成功时返回 value，失败时返回 null
  ///
  /// 适用于不需要区分"成功但值为 null"与"失败"的简单场景。
  /// 需要精确错误处理时请使用 switch 模式匹配。
  T? get valueOrNull => switch (this) {
        AppSuccess<T>(:final value) => value,
        AppFailure<T>() => null,
      };

  /// 成功时返回 true
  bool get isSuccess => this is AppSuccess<T>;

  /// 失败时返回 true
  bool get isFailure => this is AppFailure<T>;

  /// 成功时返回 value，失败时返回 [fallback]
  T valueOr(T fallback) => switch (this) {
        AppSuccess<T>(:final value) => value,
        AppFailure<T>() => fallback,
      };
}

/// 成功结果
final class AppSuccess<T> extends AppResult<T> {
  final T value;

  const AppSuccess(this.value);
}

/// 失败结果
final class AppFailure<T> extends AppResult<T> {
  final AppError error;

  const AppFailure(this.error);
}
