import 'package:flutter/services.dart';
import 'dart:developer';

/// DevNote 平台通道 —— Flutter 与原生平台（iOS/Android）的通信桥梁
///
/// 提供生物识别认证、设备信息、推送通知等原生平台能力的 Dart 接口。
/// 使用 MethodChannel 与原生代码双向通信。
class DevNotePlatformChannel {
  static const MethodChannel _channel = MethodChannel('com.devnote.app/platform');

  /// 请求生物识别认证
  ///
  /// 调用原生平台的生物识别 API（Face ID / 指纹识别）。
  /// 返回 true 表示认证成功，false 表示认证失败。
  Future<bool> requestBiometricAuth() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestBiometricAuth');
      return result ?? false;
    } on PlatformException catch (e) {
      log('Biometric auth failed: ${e.code} - ${e.message}', name: 'PlatformChannel');
      return false;
    }
  }

  /// 获取设备信息
  ///
  /// 返回包含设备型号、操作系统版本、唯一标识符等信息的 Map。
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getDeviceInfo');
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      log('Get device info failed: ${e.code} - ${e.message}', name: 'PlatformChannel');
      return {};
    }
  }

  /// 注册推送通知
  ///
  /// 向原生平台请求推送通知权限并注册远程通知。
  /// 返回设备推送令牌，失败时返回 null。
  Future<String?> registerPushNotification() async {
    try {
      final result = await _channel.invokeMethod<String>('registerPushNotification');
      return result;
    } on PlatformException catch (e) {
      log('Register push notification failed: ${e.code} - ${e.message}', name: 'PlatformChannel');
      return null;
    }
  }
}
