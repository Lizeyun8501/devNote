// P1-7: Vault 保险库服务
// 对标 Notesnook 的 Vault 功能：对标记为敏感的笔记在应用内二次加密，需独立密码解锁。
// Vault 密码不存储明文，只存储加密后的测试向量用于验证。
// Vault 加密使用与主加密相同的 XChaCha20-Poly1305 + Argon2id 方案。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/bridge/ffi_bridge.dart';
import '../../../core/di/injection.dart';

/// Vault 保险库服务
/// 管理敏感笔记的二次加密
class VaultService {
  final FfiBridge _ffiBridge = getIt<FfiBridge>();

  static const _vaultPasswordHashKey = 'vault_password_hash';
  static const _vaultNotesKey = 'vault_notes';

  bool _isUnlocked = false;
  String? _currentPassword;
  DateTime? _unlockTime;
  static const _lockTimeoutMinutes = 15;

  bool get isUnlocked => _isUnlocked;
  DateTime? get unlockTime => _unlockTime;

  /// 检查是否已设置 Vault 密码
  Future<bool> isVaultSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_vaultPasswordHashKey);
  }

  /// 设置 Vault 密码（首次设置）
  Future<bool> setupVault(String password) async {
    if (await isVaultSet()) {
      return false; // 已设置，不能重复设置
    }

    // 加密一个测试向量作为密码验证
    final testEncrypted = await _ffiBridge.vaultEncrypt(
      password: password,
      plaintext: 'vault-test',
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vaultPasswordHashKey, jsonEncode(testEncrypted.toJson()));

    _currentPassword = password;
    _isUnlocked = true;
    _unlockTime = DateTime.now();
    return true;
  }

  /// 解锁 Vault
  Future<bool> unlock(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final hashStr = prefs.getString(_vaultPasswordHashKey);
    if (hashStr == null) return false;

    final encrypted = VaultEncryptedData.fromJson(
      jsonDecode(hashStr) as Map<String, dynamic>,
    );

    if (_ffiBridge.vaultVerifyPassword(
      password: password,
      encrypted: encrypted,
    )) {
      _currentPassword = password;
      _isUnlocked = true;
      _unlockTime = DateTime.now();
      return true;
    }
    return false;
  }

  /// 锁定 Vault
  void lock() {
    _isUnlocked = false;
    _currentPassword = null;
    _unlockTime = null;
  }

  /// 检查是否需要自动锁定
  void checkAutoLock() {
    if (!_isUnlocked || _unlockTime == null) return;
    final elapsed = DateTime.now().difference(_unlockTime!);
    if (elapsed.inMinutes >= _lockTimeoutMinutes) {
      lock();
    }
  }

  /// 修改 Vault 密码
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (!await unlock(oldPassword)) return false;

    // 重新加密所有 Vault 笔记
    final notes = await getVaultNotes();
    final prefs = await SharedPreferences.getInstance();

    final reEncryptedNotes = <VaultNote>[];
    for (final note in notes) {
      // 用旧密码解密
      final plaintext = await _ffiBridge.vaultDecrypt(
        password: oldPassword,
        encrypted: note.encryptedData,
      );
      // 用新密码加密
      final newEncrypted = await _ffiBridge.vaultEncrypt(
        password: newPassword,
        plaintext: plaintext,
      );
      reEncryptedNotes.add(note.copyWith(encryptedData: newEncrypted));
    }

    await prefs.setString(
      _vaultNotesKey,
      jsonEncode(reEncryptedNotes.map((n) => n.toJson()).toList()),
    );

    // 更新密码哈希
    final testEncrypted = await _ffiBridge.vaultEncrypt(
      password: newPassword,
      plaintext: 'vault-test',
    );
    await prefs.setString(_vaultPasswordHashKey, jsonEncode(testEncrypted.toJson()));

    _currentPassword = newPassword;
    _unlockTime = DateTime.now();
    return true;
  }

  /// 加密笔记并存入 Vault
  Future<void> addToVault({
    required String noteId,
    required String title,
    required String content,
  }) async {
    if (!_isUnlocked || _currentPassword == null) {
      throw Exception('Vault is locked');
    }

    final encrypted = await _ffiBridge.vaultEncrypt(
      password: _currentPassword!,
      plaintext: content,
    );

    final vaultNote = VaultNote(
      id: noteId,
      title: title,
      encryptedData: encrypted,
      addedAt: DateTime.now(),
    );

    final notes = await getVaultNotes();
    notes.add(vaultNote);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _vaultNotesKey,
      jsonEncode(notes.map((n) => n.toJson()).toList()),
    );
  }

  /// 从 Vault 获取并解密笔记
  Future<String?> getFromVault(String noteId) async {
    if (!_isUnlocked || _currentPassword == null) return null;

    final notes = await getVaultNotes();
    VaultNote? note;
    for (final n in notes) {
      if (n.id == noteId) {
        note = n;
        break;
      }
    }
    if (note == null) return null;

    return _ffiBridge.vaultDecrypt(
      password: _currentPassword!,
      encrypted: note.encryptedData,
    );
  }

  /// 获取 Vault 中所有笔记（元数据，不含解密内容）
  Future<List<VaultNote>> getVaultNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_vaultNotesKey);
    if (jsonStr == null) return [];
    final list = jsonDecode(jsonStr) as List;
    return list.map((e) => VaultNote.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 从 Vault 移除笔记
  Future<void> removeFromVault(String noteId) async {
    final notes = await getVaultNotes();
    notes.removeWhere((n) => n.id == noteId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _vaultNotesKey,
      jsonEncode(notes.map((n) => n.toJson()).toList()),
    );
  }
}

/// Vault 笔记（元数据 + 加密数据）
class VaultNote {
  final String id;
  final String title;
  final VaultEncryptedData encryptedData;
  final DateTime addedAt;

  VaultNote({
    required this.id,
    required this.title,
    required this.encryptedData,
    required this.addedAt,
  });

  VaultNote copyWith({
    String? title,
    VaultEncryptedData? encryptedData,
  }) => VaultNote(
    id: id,
    title: title ?? this.title,
    encryptedData: encryptedData ?? this.encryptedData,
    addedAt: addedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'encrypted_data': encryptedData.toJson(),
    'added_at': addedAt.toIso8601String(),
  };

  factory VaultNote.fromJson(Map<String, dynamic> json) => VaultNote(
    id: json['id'] as String,
    title: json['title'] as String,
    encryptedData: VaultEncryptedData.fromJson(
      json['encrypted_data'] as Map<String, dynamic>,
    ),
    addedAt: DateTime.parse(json['added_at'] as String),
  );
}
