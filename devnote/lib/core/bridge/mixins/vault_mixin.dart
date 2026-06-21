// P1 修复 (P1-2): FFIBridge God Class 拆分 —— Vault 领域 Mixin
//
// 从 FFIBridge 中抽取的 Vault 加密 API。这是纯 Dart 实现（AES-256-GCM + PBKDF2），
// 完全不依赖 C ABI，与 FFIBridge 的核心 FFI 分发职责无关。
//
// 拆分理由:
// - Vault 是自包含的纯 Dart 加密模块，无 FFI 依赖
// - 含 3 个公开方法 + 2 个私有辅助方法 + 1 个数据类，约 80 行
// - vault_service.dart 是唯一调用方，影响面极小
// - 独立后便于单独测试加密逻辑，且未来可替换为 Argon2id 而不影响 FFIBridge

import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Vault 加密数据
///
/// memoryCost/timeCost/parallelism 保留用于未来 Argon2id 迁移，
/// 当前 PBKDF2 使用 timeCost 字段存储迭代次数。
class VaultEncryptedData {
  final String ciphertext;
  final String salt;
  final String nonce;
  final int memoryCost;
  final int timeCost;
  final int parallelism;

  VaultEncryptedData({
    required this.ciphertext,
    required this.salt,
    required this.nonce,
    required this.memoryCost,
    required this.timeCost,
    required this.parallelism,
  });

  Map<String, dynamic> toJson() => {
        'ciphertext': ciphertext,
        'salt': salt,
        'nonce': nonce,
        'memory_cost': memoryCost,
        'time_cost': timeCost,
        'parallelism': parallelism,
      };

  factory VaultEncryptedData.fromJson(Map<String, dynamic> json) =>
      VaultEncryptedData(
        ciphertext: json['ciphertext'] as String,
        salt: json['salt'] as String,
        nonce: json['nonce'] as String,
        memoryCost: (json['memory_cost'] as num).toInt(),
        timeCost: (json['time_cost'] as num).toInt(),
        parallelism: (json['parallelism'] as num).toInt(),
      );
}

/// Vault API Mixin —— Dart 端实现（Rust 端无对应 C ABI handler）
///
/// 使用 AES-256-GCM + PBKDF2-HMAC-SHA256（与 CryptoService 一致）。
/// P0 修复: PBKDF2 迭代次数 600,000 次（OWASP 2023 建议）。
mixin VaultMixin {
  // P0 修复: PBKDF2 迭代次数从 100,000 提升至 600,000
  // 符合 OWASP 2023 Password Storage Cheat Sheet 建议
  // (PBKDF2-HMAC-SHA256 至少 600,000 次迭代)
  static const int _vaultPbkdf2Iterations = 600000;

  Future<VaultEncryptedData> vaultEncrypt({
    required String password,
    required String plaintext,
  }) async {
    final salt = _generateSecureRandom(32);
    final nonce = _generateSecureRandom(12);
    final key = _deriveVaultKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final ciphertextWithTag =
        cipher.process(Uint8List.fromList(utf8.encode(plaintext)));

    return VaultEncryptedData(
      ciphertext: base64Encode(ciphertextWithTag),
      salt: base64Encode(salt),
      nonce: base64Encode(nonce),
      memoryCost: 0,
      timeCost: _vaultPbkdf2Iterations,
      parallelism: 1,
    );
  }

  Future<String> vaultDecrypt({
    required String password,
    required VaultEncryptedData encrypted,
  }) async {
    final salt = base64Decode(encrypted.salt);
    final nonce = base64Decode(encrypted.nonce);
    final ciphertextWithTag = base64Decode(encrypted.ciphertext);
    final key = _deriveVaultKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final plaintext = cipher.process(ciphertextWithTag);
    return utf8.decode(plaintext);
  }

  Future<bool> vaultVerifyPassword({
    required String password,
    required VaultEncryptedData encrypted,
  }) async {
    try {
      await vaultDecrypt(password: password, encrypted: encrypted);
      return true;
    } catch (_) {
      return false;
    }
  }

  Uint8List _generateSecureRandom(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  Uint8List _deriveVaultKey(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _vaultPbkdf2Iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }
}
