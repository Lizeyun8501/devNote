class RetryPolicy {
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;

  const RetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  });

  Duration delayForAttempt(int attempt) {
    final exponential = baseDelay * (1 << attempt); // 2^attempt
    return exponential > maxDelay ? maxDelay : exponential;
  }
}
