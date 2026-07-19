// E2ECryptoService 单元测试
//
// 测试端到端加密服务的密钥生成、加解密、密钥轮换、备份导入导出功能。
// 使用 SharedPreferences mock 避免持久化依赖。
// 验证 AES-256-GCM 加密的机密性、完整性、密钥轮换的向后兼容性。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/features/sync/crypto/e2e_crypto_service.dart';

void main() {
  late E2ECryptoService service;

  setUp(() {
    // 每个测试前重置 SharedPreferences mock
    SharedPreferences.setMockInitialValues({});
    service = E2ECryptoService();
  });

  group('E2ECryptoService - 初始化', () {
    test('未配置时状态为 notConfigured', () async {
      await service.initialize();
      expect(service.state.status, E2ECryptoStatus.notConfigured);
    });

    test('已配置时 initialize 恢复 configured 状态', () async {
      // 先生成密钥对
      await service.generateKeyPair('password123');
      // 重新创建服务实例并初始化
      service = E2ECryptoService();
      await service.initialize();
      expect(service.state.status, E2ECryptoStatus.configured);
      expect(service.state.currentKey, isNotNull);
    });
  });

  group('E2ECryptoService - generateKeyPair', () {
    test('密码长度不足 6 位时返回 false', () async {
      final result = await service.generateKeyPair('12345');
      expect(result, isFalse);
    });

    test('密码合法时生成密钥对并切换到 configured 状态', () async {
      final result = await service.generateKeyPair('securePassword123');
      expect(result, isTrue);
      expect(service.state.status, E2ECryptoStatus.configured);
      expect(service.state.currentKey, isNotNull);
      expect(service.state.currentKey!.isActive, isTrue);
      expect(service.state.currentKey!.keyId, isNotEmpty);
    });

    test('生成密钥对后持久化到 SharedPreferences', () async {
      await service.generateKeyPair('securePassword123');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('e2e_crypto_enabled'), isTrue);
      expect(prefs.getString('e2e_current_key_id'), isNotNull);
      expect(prefs.getString('e2e_current_key_data'), isNotNull);
      expect(prefs.getString('e2e_salt'), isNotNull);
      expect(prefs.getInt('e2e_rotation_interval'), 30);
    });
  });

  group('E2ECryptoService - 加解密', () {
    test('未配置时 encryptSyncData 返回 null', () {
      final data = Uint8List.fromList(utf8.encode('test data'));
      expect(service.encryptSyncData(data), isNull);
    });

    test('未配置时 decryptSyncData 返回 null', () {
      final data = Uint8List.fromList(utf8.encode('test data'));
      expect(service.decryptSyncData(data), isNull);
    });

    test('加密后解密应还原原始数据', () async {
      await service.generateKeyPair('securePassword123');
      final originalData = Uint8List.fromList(utf8.encode('这是机密同步数据'));
      final encrypted = service.encryptSyncData(originalData);
      expect(encrypted, isNotNull);
      // 密文应与明文不同
      expect(encrypted, isNot(equals(originalData)));
      final decrypted = service.decryptSyncData(encrypted!);
      expect(decrypted, isNotNull);
      expect(decrypted, equals(originalData));
    });

    test('空数据加解密应正常工作', () async {
      await service.generateKeyPair('securePassword123');
      final emptyData = Uint8List(0);
      final encrypted = service.encryptSyncData(emptyData);
      expect(encrypted, isNotNull);
      final decrypted = service.decryptSyncData(encrypted!);
      expect(decrypted, isNotNull);
      expect(decrypted!.length, 0);
    });

    test('篡改密文后解密应返回 null', () async {
      await service.generateKeyPair('securePassword123');
      final originalData = Uint8List.fromList(utf8.encode('机密数据'));
      final encrypted = service.encryptSyncData(originalData)!;
      // 篡改密文部分（跳过 nonce 的前 12 字节）
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 1] ^= 0xFF;
      final decrypted = service.decryptSyncData(tampered);
      expect(decrypted, isNull);
    });

    test('多次加密同一数据应产生不同密文（随机 nonce）', () async {
      await service.generateKeyPair('securePassword123');
      final data = Uint8List.fromList(utf8.encode('相同的数据'));
      final encrypted1 = service.encryptSyncData(data)!;
      final encrypted2 = service.encryptSyncData(data)!;
      // 由于 nonce 随机，两次密文应不同
      expect(encrypted1, isNot(equals(encrypted2)));
      // 但都能解密为同一明文
      expect(service.decryptSyncData(encrypted1), equals(data));
      expect(service.decryptSyncData(encrypted2), equals(data));
    });
  });

  group('E2ECryptoService - 密钥轮换', () {
    test('未配置时 rotateKey 返回 false', () async {
      final result = await service.rotateKey('newPassword123');
      expect(result, isFalse);
    });

    test('密码长度不足时 rotateKey 返回 false', () async {
      await service.generateKeyPair('oldPassword123');
      final result = await service.rotateKey('12345');
      expect(result, isFalse);
    });

    test('轮换密钥后旧密文仍可解密（向后兼容）', () async {
      await service.generateKeyPair('oldPassword123');
      final data = Uint8List.fromList(utf8.encode('旧密钥加密的数据'));
      final encryptedWithOldKey = service.encryptSyncData(data)!;

      // 轮换密钥
      final result = await service.rotateKey('newPassword123');
      expect(result, isTrue);
      expect(service.state.status, E2ECryptoStatus.active);
      expect(service.state.previousKey, isNotNull);

      // 旧密文应能用 previousSessionKey 解密
      final decrypted = service.decryptSyncData(encryptedWithOldKey);
      expect(decrypted, isNotNull);
      expect(decrypted, equals(data));
    });

    test('轮换密钥后新密文用新密钥加密', () async {
      await service.generateKeyPair('oldPassword123');
      await service.rotateKey('newPassword123');
      final data = Uint8List.fromList(utf8.encode('新密钥加密的数据'));
      final encrypted = service.encryptSyncData(data)!;
      final decrypted = service.decryptSyncData(encrypted);
      expect(decrypted, equals(data));
    });
  });

  group('E2ECryptoService - needsKeyRotation', () {
    test('未配置时需要轮换', () {
      expect(service.needsKeyRotation(), isTrue);
    });

    test('刚生成密钥时不需要轮换', () async {
      await service.generateKeyPair('securePassword123');
      expect(service.needsKeyRotation(), isFalse);
    });
  });

  group('E2ECryptoService - 备份导入导出', () {
    test('导出备份后导入应恢复密钥', () async {
      await service.generateKeyPair('originalPassword123');
      final originalKeyId = service.state.currentKey!.keyId;

      // 导出备份
      final backup = await service.exportKeyBackup('backupPassword123');
      expect(backup, isNotNull);

      // 禁用加密（清空当前密钥）
      await service.disable();
      expect(service.state.status, E2ECryptoStatus.notConfigured);

      // 导入备份
      final importResult =
          await service.importKeyBackup(backup!, 'backupPassword123');
      expect(importResult, isTrue);
      expect(service.state.status, E2ECryptoStatus.configured);
      expect(service.state.currentKey!.keyId, originalKeyId);
    });

    test('导出备份时密码不足 6 位返回 null', () async {
      await service.generateKeyPair('originalPassword123');
      final backup = await service.exportKeyBackup('12345');
      expect(backup, isNull);
    });

    test('导入备份时密码错误返回 false', () async {
      await service.generateKeyPair('originalPassword123');
      final backup = (await service.exportKeyBackup('correctPassword123'))!;
      await service.disable();
      final result = await service.importKeyBackup(backup, 'wrongPassword123');
      expect(result, isFalse);
    });

    test('导入备份时密码不足 6 位返回 false', () async {
      await service.generateKeyPair('originalPassword123');
      final backup = (await service.exportKeyBackup('correctPassword123'))!;
      await service.disable();
      final result = await service.importKeyBackup(backup, '12345');
      expect(result, isFalse);
    });
  });

  group('E2ECryptoService - disable', () {
    test('禁用后清空所有密钥和状态', () async {
      await service.generateKeyPair('securePassword123');
      expect(service.state.status, isNot(E2ECryptoStatus.notConfigured));

      await service.disable();
      expect(service.state.status, E2ECryptoStatus.notConfigured);
      expect(service.state.currentKey, isNull);

      // 加密应返回 null
      final data = Uint8List.fromList(utf8.encode('test'));
      expect(service.encryptSyncData(data), isNull);
    });

    test('禁用后清除 SharedPreferences 中的密钥数据', () async {
      await service.generateKeyPair('securePassword123');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('e2e_crypto_enabled'), isTrue);

      await service.disable();
      final prefsAfter = await SharedPreferences.getInstance();
      expect(prefsAfter.getBool('e2e_crypto_enabled'), isNull);
      expect(prefsAfter.getString('e2e_current_key_id'), isNull);
      expect(prefsAfter.getString('e2e_current_key_data'), isNull);
    });
  });
}
