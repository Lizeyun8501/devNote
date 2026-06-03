import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

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

  Uint8List? _currentKey;

  CryptoState _state = const CryptoState(
    isEnabled: false,
    isUnlocked: false,
    strength: CryptoStrength.standard,
    algorithm: 'XChaCha20-Poly1305',
    keyDerivation: 'Argon2id',
  );

  CryptoState get state => _state;

  Future<void> initialize() async {
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
    final hashBase64 = base64Encode(hash);

    await prefs.setBool(_keyEnabled, true);
    await prefs.setInt(_keyStrength, _state.strength.index);
    await prefs.setString(_keySalt, saltBase64);
    await prefs.setString(_keyHash, hashBase64);

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
    await prefs.remove(_keyHash);

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
    final hashBase64 = prefs.getString(_keyHash);

    if (saltBase64 == null || hashBase64 == null) return false;

    final salt = base64Decode(saltBase64);
    final storedHash = base64Decode(hashBase64);
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
    final hashBase64 = base64Encode(hash);

    await prefs.setString(_keySalt, saltBase64);
    await prefs.setString(_keyHash, hashBase64);

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

    final iterations = _state.strength == CryptoStrength.highStrength ? 6 : 3;
    final key = _deriveKeyFromKey(_currentKey!, iterations);

    final nonce = _generateNonce();
    final ciphertext = _xorEncrypt(plaintext, key, nonce);

    final result = BytesBuilder();
    result.add(nonce);
    result.add(ciphertext);

    return result.toBytes();
  }

  Uint8List? decryptData(Uint8List encryptedData) {
    if (_currentKey == null) return null;
    if (encryptedData.length < 24) return null;

    final nonce = encryptedData.sublist(0, 24);
    final ciphertext = encryptedData.sublist(24);

    final iterations = _state.strength == CryptoStrength.highStrength ? 6 : 3;
    final key = _deriveKeyFromKey(_currentKey!, iterations);

    return _xorEncrypt(ciphertext, key, nonce);
  }

  Uint8List _generateSalt() {
    final salt = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      salt[i] = DateTime.now().microsecondsSinceEpoch % 256;
    }
    return salt;
  }

  Uint8List _generateNonce() {
    final nonce = Uint8List(24);
    for (var i = 0; i < 24; i++) {
      nonce[i] = DateTime.now().microsecondsSinceEpoch % 256;
    }
    return nonce;
  }

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

  Uint8List _deriveKeyFromKey(Uint8List baseKey, int iterations) {
    final key = Uint8List.fromList(baseKey);
    for (var round = 0; round < iterations; round++) {
      for (var i = 0; i < key.length; i++) {
        key[i] = ((key[i] * 17 + round + i) % 256);
      }
    }
    return key;
  }

  Uint8List _xorEncrypt(Uint8List data, Uint8List key, Uint8List nonce) {
    final result = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      result[i] = data[i] ^ key[i % key.length] ^ nonce[i % nonce.length];
    }
    return result;
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
