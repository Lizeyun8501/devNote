import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

enum E2ECryptoStatus {
  notConfigured,
  configured,
  active,
  keyRotating,
  error,
}

class KeyInfo {
  final String keyId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isActive;

  const KeyInfo({
    required this.keyId,
    required this.createdAt,
    this.expiresAt,
    this.isActive = false,
  });
}

class E2ECryptoState {
  final E2ECryptoStatus status;
  final KeyInfo? currentKey;
  final KeyInfo? previousKey;
  final String algorithm;
  final int keyRotationIntervalDays;
  final DateTime? lastKeyRotation;

  const E2ECryptoState({
    required this.status,
    this.currentKey,
    this.previousKey,
    this.algorithm = 'XChaCha20-Poly1305',
    this.keyRotationIntervalDays = 30,
    this.lastKeyRotation,
  });

  E2ECryptoState copyWith({
    E2ECryptoStatus? status,
    KeyInfo? currentKey,
    KeyInfo? previousKey,
    String? algorithm,
    int? keyRotationIntervalDays,
    DateTime? lastKeyRotation,
  }) {
    return E2ECryptoState(
      status: status ?? this.status,
      currentKey: currentKey ?? this.currentKey,
      previousKey: previousKey ?? this.previousKey,
      algorithm: algorithm ?? this.algorithm,
      keyRotationIntervalDays: keyRotationIntervalDays ?? this.keyRotationIntervalDays,
      lastKeyRotation: lastKeyRotation ?? this.lastKeyRotation,
    );
  }
}

class E2ECryptoService {
  E2ECryptoService();

  static const String _keyE2EEnabled = 'e2e_crypto_enabled';
  static const String _keyCurrentKeyId = 'e2e_current_key_id';
  static const String _keyCurrentKeyData = 'e2e_current_key_data';
  static const String _keyCurrentKeyCreatedAt = 'e2e_current_key_created';
  static const String _keyPreviousKeyId = 'e2e_previous_key_id';
  static const String _keyPreviousKeyData = 'e2e_previous_key_data';
  static const String _keyPublicKey = 'e2e_public_key';
  static const String _keyEncryptedPrivateKey = 'e2e_encrypted_private_key';
  static const String _keySalt = 'e2e_salt';
  static const String _keyRotationInterval = 'e2e_rotation_interval';
  static const String _keyLastRotation = 'e2e_last_rotation';

  Uint8List? _sessionKey;
  Uint8List? _previousSessionKey;

  E2ECryptoState _state = const E2ECryptoState(
    status: E2ECryptoStatus.notConfigured,
  );

  E2ECryptoState get state => _state;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyE2EEnabled) ?? false;

    if (!enabled) {
      _state = _state.copyWith(status: E2ECryptoStatus.notConfigured);
      return;
    }

    final currentKeyId = prefs.getString(_keyCurrentKeyId);
    final currentKeyDataBase64 = prefs.getString(_keyCurrentKeyData);
    final currentKeyCreatedAtMs = prefs.getInt(_keyCurrentKeyCreatedAt);
    final rotationInterval = prefs.getInt(_keyRotationInterval) ?? 30;
    final lastRotationMs = prefs.getInt(_keyLastRotation);

    if (currentKeyId != null && currentKeyDataBase64 != null) {
      final keyData = base64Decode(currentKeyDataBase64);
      _sessionKey = keyData;

      DateTime? createdAt;
      if (currentKeyCreatedAtMs != null) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(currentKeyCreatedAtMs);
      }

      DateTime? lastRotation;
      if (lastRotationMs != null) {
        lastRotation = DateTime.fromMillisecondsSinceEpoch(lastRotationMs);
      }

      _state = _state.copyWith(
        status: E2ECryptoStatus.configured,
        currentKey: KeyInfo(
          keyId: currentKeyId,
          createdAt: createdAt ?? DateTime.now(),
          isActive: true,
        ),
        keyRotationIntervalDays: rotationInterval,
        lastKeyRotation: lastRotation,
      );

      _loadPreviousKey(prefs);
    }
  }

  Future<void> _loadPreviousKey(SharedPreferences prefs) async {
    final previousKeyId = prefs.getString(_keyPreviousKeyId);
    final previousKeyDataBase64 = prefs.getString(_keyPreviousKeyData);

    if (previousKeyId != null && previousKeyDataBase64 != null) {
      _previousSessionKey = base64Decode(previousKeyDataBase64);
      _state = _state.copyWith(
        previousKey: KeyInfo(
          keyId: previousKeyId,
          createdAt: DateTime.now(),
          isActive: false,
        ),
      );
    }
  }

  Future<bool> generateKeyPair(String password) async {
    if (password.length < 6) return false;

    final prefs = await SharedPreferences.getInstance();

    final salt = _generateRandomBytes(32);
    final keyData = _deriveKey(password, salt);

    final publicKey = _generateRandomBytes(32);
    final encryptedPrivateKey = _encryptWithKey(_generateRandomBytes(32), keyData);

    final keyId = _generateKeyId();

    await prefs.setBool(_keyE2EEnabled, true);
    await prefs.setString(_keyCurrentKeyId, keyId);
    await prefs.setString(_keyCurrentKeyData, base64Encode(keyData));
    await prefs.setInt(_keyCurrentKeyCreatedAt, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(_keyPublicKey, base64Encode(publicKey));
    await prefs.setString(_keyEncryptedPrivateKey, base64Encode(encryptedPrivateKey));
    await prefs.setString(_keySalt, base64Encode(salt));
    await prefs.setInt(_keyRotationInterval, 30);
    await prefs.setInt(_keyLastRotation, DateTime.now().millisecondsSinceEpoch);

    _sessionKey = keyData;

    _state = _state.copyWith(
      status: E2ECryptoStatus.configured,
      currentKey: KeyInfo(
        keyId: keyId,
        createdAt: DateTime.now(),
        isActive: true,
      ),
      keyRotationIntervalDays: 30,
      lastKeyRotation: DateTime.now(),
    );

    return true;
  }

  Uint8List? encryptSyncData(Uint8List data) {
    if (_sessionKey == null) return null;

    final nonce = _generateRandomBytes(24);
    final ciphertext = _xorEncrypt(data, _sessionKey!, nonce);

    final result = BytesBuilder();
    result.add(nonce);
    result.add(ciphertext);

    return result.toBytes();
  }

  Uint8List? decryptSyncData(Uint8List encryptedData) {
    if (_sessionKey == null) return null;
    if (encryptedData.length < 24) return null;

    final nonce = encryptedData.sublist(0, 24);
    final ciphertext = encryptedData.sublist(24);

    final decrypted = _xorEncrypt(ciphertext, _sessionKey!, nonce);
    if (decrypted.isNotEmpty) return decrypted;

    if (_previousSessionKey != null) {
      return _xorEncrypt(ciphertext, _previousSessionKey!, nonce);
    }

    return null;
  }

  Future<bool> rotateKey(String password) async {
    if (_sessionKey == null) return false;
    if (password.length < 6) return false;

    final prefs = await SharedPreferences.getInstance();

    final currentKeyId = prefs.getString(_keyCurrentKeyId);
    final currentKeyDataBase64 = prefs.getString(_keyCurrentKeyData);

    if (currentKeyId != null && currentKeyDataBase64 != null) {
      await prefs.setString(_keyPreviousKeyId, currentKeyId);
      await prefs.setString(_keyPreviousKeyData, currentKeyDataBase64);
      _previousSessionKey = _sessionKey;

      _state = _state.copyWith(
        previousKey: KeyInfo(
          keyId: currentKeyId,
          createdAt: _state.currentKey?.createdAt ?? DateTime.now(),
          isActive: false,
        ),
      );
    }

    final salt = _generateRandomBytes(32);
    final newKeyData = _deriveKey(password, salt);
    final newKeyId = _generateKeyId();

    await prefs.setString(_keyCurrentKeyId, newKeyId);
    await prefs.setString(_keyCurrentKeyData, base64Encode(newKeyData));
    await prefs.setInt(_keyCurrentKeyCreatedAt, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(_keySalt, base64Encode(salt));
    await prefs.setInt(_keyLastRotation, DateTime.now().millisecondsSinceEpoch);

    _sessionKey = newKeyData;

    _state = _state.copyWith(
      status: E2ECryptoStatus.active,
      currentKey: KeyInfo(
        keyId: newKeyId,
        createdAt: DateTime.now(),
        isActive: true,
      ),
      lastKeyRotation: DateTime.now(),
    );

    return true;
  }

  bool needsKeyRotation() {
    if (_state.lastKeyRotation == null) return true;
    final daysSinceRotation = DateTime.now().difference(_state.lastKeyRotation!).inDays;
    return daysSinceRotation >= _state.keyRotationIntervalDays;
  }

  Future<String?> exportKeyBackup(String encryptionPassword) async {
    if (_sessionKey == null) return null;
    if (encryptionPassword.length < 6) return null;

    final prefs = await SharedPreferences.getInstance();

    final backupData = <String, dynamic>{
      'key_id': prefs.getString(_keyCurrentKeyId),
      'key_data': prefs.getString(_keyCurrentKeyData),
      'public_key': prefs.getString(_keyPublicKey),
      'encrypted_private_key': prefs.getString(_keyEncryptedPrivateKey),
      'salt': prefs.getString(_keySalt),
      'rotation_interval': prefs.getInt(_keyRotationInterval),
      'created_at': prefs.getInt(_keyCurrentKeyCreatedAt),
    };

    final jsonStr = jsonEncode(backupData);
    final jsonBytes = utf8.encode(jsonStr);

    final backupSalt = _generateRandomBytes(32);
    final backupKey = _deriveKey(encryptionPassword, backupSalt);
    final encrypted = _encryptWithKey(Uint8List.fromList(jsonBytes), backupKey);

    final result = BytesBuilder();
    result.add(backupSalt);
    result.add(encrypted);

    return base64Encode(result.toBytes());
  }

  Future<bool> importKeyBackup(String backupBase64, String decryptionPassword) async {
    if (decryptionPassword.length < 6) return false;

    try {
      final backupBytes = base64Decode(backupBase64);
      if (backupBytes.length < 32) return false;

      final backupSalt = backupBytes.sublist(0, 32);
      final encryptedData = backupBytes.sublist(32);

      final backupKey = _deriveKey(decryptionPassword, backupSalt);
      final decrypted = _decryptWithKey(Uint8List.fromList(encryptedData), backupKey);

      final jsonStr = utf8.decode(decrypted);
      final backupData = jsonDecode(jsonStr) as Map<String, dynamic>;

      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(_keyE2EEnabled, true);
      await prefs.setString(_keyCurrentKeyId, backupData['key_id'] as String);
      await prefs.setString(_keyCurrentKeyData, backupData['key_data'] as String);
      await prefs.setString(_keyPublicKey, backupData['public_key'] as String);
      await prefs.setString(_keyEncryptedPrivateKey, backupData['encrypted_private_key'] as String);
      await prefs.setString(_keySalt, backupData['salt'] as String);
      await prefs.setInt(_keyRotationInterval, backupData['rotation_interval'] as int);
      await prefs.setInt(_keyCurrentKeyCreatedAt, backupData['created_at'] as int);

      _sessionKey = base64Decode(backupData['key_data'] as String);

      _state = _state.copyWith(
        status: E2ECryptoStatus.configured,
        currentKey: KeyInfo(
          keyId: backupData['key_id'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(backupData['created_at'] as int),
          isActive: true,
        ),
        keyRotationIntervalDays: backupData['rotation_interval'] as int,
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyE2EEnabled);
    await prefs.remove(_keyCurrentKeyId);
    await prefs.remove(_keyCurrentKeyData);
    await prefs.remove(_keyCurrentKeyCreatedAt);
    await prefs.remove(_keyPreviousKeyId);
    await prefs.remove(_keyPreviousKeyData);
    await prefs.remove(_keyPublicKey);
    await prefs.remove(_keyEncryptedPrivateKey);
    await prefs.remove(_keySalt);
    await prefs.remove(_keyRotationInterval);
    await prefs.remove(_keyLastRotation);

    _sessionKey = null;
    _previousSessionKey = null;

    _state = const E2ECryptoState(
      status: E2ECryptoStatus.notConfigured,
    );
  }

  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  String _generateKeyId() {
    final bytes = _generateRandomBytes(16);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 密钥派生函数
  ///
  /// 安全警告：当前实现使用自定义 XOR+迭代哈希，仅用于原型阶段。
  /// 生产环境应替换为标准 KDF（如 Argon2id、PBKDF2、scrypt），
  /// 通过 FFI 调用 Rust 的 ring/argon2 库实现。
  /// 自定义实现的问题：
  /// 1. 迭代次数仅 10 次，远低于 OWASP 推荐的 600,000+ 次（PBKDF2-SHA256）
  /// 2. XOR 运算不提供雪崩效应，密钥分布不均匀
  /// 3. 无内存硬性要求，易受 GPU/ASIC 暴力破解
  Uint8List _deriveKey(String password, Uint8List salt) {
    final key = Uint8List(32);
    final passwordBytes = utf8.encode(password);

    for (var i = 0; i < 32; i++) {
      key[i] = i < passwordBytes.length
          ? (passwordBytes[i] ^ salt[i % salt.length])
          : salt[i % salt.length];
    }

    for (var round = 0; round < 10; round++) {
      for (var i = 0; i < 32; i++) {
        key[i] = ((key[i] * 31 + salt[i % salt.length] + round) % 256);
      }
    }

    return key;
  }

  Uint8List _encryptWithKey(Uint8List data, Uint8List key) {
    final nonce = _generateRandomBytes(24);
    final ciphertext = _xorEncrypt(data, key, nonce);

    final result = BytesBuilder();
    result.add(nonce);
    result.add(ciphertext);

    return result.toBytes();
  }

  Uint8List _decryptWithKey(Uint8List encryptedData, Uint8List key) {
    if (encryptedData.length < 24) return Uint8List(0);

    final nonce = encryptedData.sublist(0, 24);
    final ciphertext = encryptedData.sublist(24);

    return _xorEncrypt(ciphertext, key, nonce);
  }

  /// 加密/解密核心函数
  ///
  /// 安全警告：当前使用 XOR 流密码，仅用于原型阶段。
  /// XOR 加密不提供语义安全性（SEM），相同明文+密钥产生相同密文，
  /// 且无法抵抗已知明文攻击。生产环境应替换为 XChaCha20-Poly1305
  /// 或 AES-256-GCM，通过 FFI 调用 Rust 加密库实现。
  Uint8List _xorEncrypt(Uint8List data, Uint8List key, Uint8List nonce) {
    final result = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] ^ key[i % key.length] ^ nonce[i % nonce.length];
    }
    return result;
  }
}
