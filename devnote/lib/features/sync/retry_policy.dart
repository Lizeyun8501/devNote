class RetryPolicy {
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;

  const RetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  });

  /// 修复：防止整数溢出
  /// 原代码 `baseDelay * (1 << attempt)` 当 attempt >= 60 时，
  /// `1 << attempt` 会溢出 int 范围（Dart int 是 64 位，1 << 63 为负数），
  /// 导致计算出负数延迟或异常行为
  Duration delayForAttempt(int attempt) {
    // 限制 attempt 最大值为 30，避免 1 << attempt 溢出
    final safeAttempt = attempt.clamp(0, 30);
    final multiplier = 1 << safeAttempt;
    final exponential = baseDelay * multiplier;
    return exponential > maxDelay ? maxDelay : exponential;
  }
}
