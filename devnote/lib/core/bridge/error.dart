enum FFIStatusCode {
  ok,
  err,
  internal,
  network,
  unauthorized,
}

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
