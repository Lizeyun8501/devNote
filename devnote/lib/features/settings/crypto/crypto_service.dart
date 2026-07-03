import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/core/security/secure_key_storage.dart';

enum CryptoStrength {
  standard,
  highStrength,
}

class CryptoState {
  final bool isEnabled;
  final bool isUnlocked;
  final CryptoStrength strength;
  final String algorithm;
  final String keyDerivation;

  const CryptoState({
    required this.isEnabled,
    required this.isUnlocked,
    required this.strength,
    required this.algorithm,
    required this.keyDerivation,
  });

  CryptoState copyWith({
    bool? isEnabled,
    bool? isUnlocked,
    CryptoStrength? strength,
    String? algorithm,
    String? keyDerivation,
  }) {
    return CryptoState(
      isEnabled: isEnabled ?? this.isEnabled,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      strength: strength ?? this.strength,
      algorithm: algorithm ?? this.algorithm,
      keyDerivation: keyDerivation ?? this.keyDerivation,
    );
  }
}

class CryptoService {
  CryptoService();

  static const String _keyEnabled = 'crypto_enabled';
  static const String _keyStrength = 'crypto_strength';
  static const String _keySalt = 'crypto_salt';
  static const String _keyHash = 'crypto_hash';

  /// PBKDF2-HMAC-SHA256 迭代次数（OWASP 2023 建议 600,000 次）
  /// P0 修复 (ENC-07): 从 100,000 提升至 600,000，符合 OWASP 2023 最低标准
  static const int _pbkdf2Iterations = 600000;

  Uint8List? _currentKey;

  /// P0 修复 (ENC-06): 验证哈希不再明文存 SharedPreferences，改用 SecureKeyStorage
  /// （平台 KeyStore/Keychain，桌面端兜底为应用层加密 SharedPreferences）
  late final SecureKeyStorage _secureStorage;

  CryptoState _state = const CryptoState(
    isEnabled: false,
    isUnlocked: false,
    strength: CryptoStrength.standard,
    algorithm: 'AES-256-GCM',
    keyDerivation: 'PBKDF2-SHA256',
  );

  CryptoState get state => _state;

  Future<void> initialize() async {
    _secureStorage = await SecureKeyStorageFactory.getInstance();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? false;
    final strengthIndex = prefs.getInt(_keyStrength) ?? 0;
    final strength = CryptoStrength.values[strengthIndex];

    _state = _state.copyWith(
      isEnabled: enabled,
      strength: strength,
      isUnlocked: false,
    );
  }

  Future<bool> enableEncryption(String password) async {
    if (password.length < 6) return false;

    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    final hash = _deriveKey(password, salt);

    final saltBase64 = base64Encode(salt);
    // P0 修复: 验证哈希存入 SecureKeyStorage，不再明文存 SharedPreferences
    await _secureStorage.write(_keyHash, hash);

    await prefs.setBool(_keyEnabled, true);
    await prefs.setInt(_keyStrength, _state.strength.index);
    await prefs.setString(_keySalt, saltBase64);

    _currentKey = hash;

    _state = _state.copyWith(
      isEnabled: true,
      isUnlocked: true,
    );

    return true;
  }

  Future<bool> disableEncryption(String password) async {
    final verified = await unlock(password);
    if (!verified) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEnabled);
    await prefs.remove(_keySalt);
    // P0 修复: 从 SecureKeyStorage 删除验证哈希
    await _secureStorage.delete(_keyHash);

    _currentKey = null;

    _state = _state.copyWith(
      isEnabled: false,
      isUnlocked: false,
    );

    return true;
  }

  Future<bool> unlock(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final saltBase64 = prefs.getString(_keySalt);

    if (saltBase64 == null) return false;

    // P0 修复: 从 SecureKeyStorage 读取验证哈希
    final storedHash = await _secureStorage.read(_keyHash);
    if (storedHash == null) return false;

    final salt = base64Decode(saltBase64);
    final computedHash = _deriveKey(password, salt);

    final matches = _constantTimeEquals(computedHash, storedHash);
    if (matches) {
      _currentKey = computedHash;
      _state = _state.copyWith(isUnlocked: true);
    }

    return matches;
  }

  void lock() {
    _currentKey = null;
    _state = _state.copyWith(isUnlocked: false);
  }

  Future<bool> changePassword(String oldPassword, String newPassword) async {
    final unlocked = await unlock(oldPassword);
    if (!unlocked) return false;

    if (newPassword.length < 6) return false;

    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    final hash = _deriveKey(newPassword, salt);

    final saltBase64 = base64Encode(salt);
    // P0 修复: 新验证哈希存入 SecureKeyStorage
    await _secureStorage.write(_keyHash, hash);

    await prefs.setString(_keySalt, saltBase64);

    _currentKey = hash;

    return true;
  }

  Future<void> setStrength(CryptoStrength strength) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyStrength, strength.index);
    _state = _state.copyWith(strength: strength);
  }

  Uint8List? encryptData(Uint8List plaintext) {
    if (_currentKey == null) return null;

    final nonce = _generateNonce();
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_currentKey!), 128, nonce, Uint8List(0)));
    final ciphertextWithTag = cipher.process(plaintext);

    final result = BytesBuilder();
    result.add(nonce);
    result.add(ciphertextWithTag);

    return result.toBytes();
  }

  Uint8List? decryptData(Uint8List encryptedData) {
    if (_currentKey == null) return null;
    if (encryptedData.length < 12 + 16) return null;

    try {
      final nonce = encryptedData.sublist(0, 12);
      final ciphertextWithTag = encryptedData.sublist(12);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(_currentKey!), 128, nonce, Uint8List(0)));
      return cipher.process(ciphertextWithTag);
    } catch (_) {
      return null;
    }
  }

  Uint8List _generateSalt() {
    // 修复：原代码使用 DateTime.now().microsecondsSinceEpoch % 256 生成盐值，
    // 导致所有字节几乎相同且完全可预测，严重不安全。
    // 改为使用 dart:math 的 Random.secure() 生成密码学安全的随机盐值
    final random = Random.secure();
    final salt = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      salt[i] = random.nextInt(256);
    }
    return salt;
  }

  Uint8List _generateNonce() {
    // AES-256-GCM 标准 nonce 长度为 12 字节
    // 使用 Random.secure() 生成密码学安全的随机 nonce
    final random = Random.secure();
    final nonce = Uint8List(12);
    for (var i = 0; i < 12; i++) {
      nonce[i] = random.nextInt(256);
    }
    return nonce;
  }

  /// 密钥派生函数 —— PBKDF2-HMAC-SHA256
  ///
  /// 使用 pointycastle 标准 PBKDF2 实现，迭代 100,000 次，
  /// 派生 256 位密钥用于 AES-256-GCM。
  Uint8List _deriveKey(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
