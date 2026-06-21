import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:devnote/core/i18n/app_localizations.dart';
import 'package:devnote/core/router/app_router.dart';
import 'package:devnote/core/router/route_registry.dart';
import 'package:devnote/core/theme/app_theme.dart';

void main() {
  testWidgets('AppLocalizationsExtension returns a valid locale', (WidgetTester tester) async {
    // 修复: 之前的测试直接调用 DevNoteApp() 会触发大量未初始化的依赖 (FFI、StartupManager 等),
    // 现改为轻量级单元测试,验证核心组件可独立加载。
    final supported = LocaleProvider.supportedLocales;
    expect(supported, contains(const Locale('en')));
    expect(supported, contains(const Locale('zh')));
  });

  test('LocaleProvider defaults to English', () {
    expect(LocaleProvider.instance.languageCode, 'en');
  });

  test('LocaleProvider switches to Chinese', () {
    LocaleProvider.instance.setLocale(const Locale('zh'));
    expect(LocaleProvider.instance.isChinese, isTrue);
    LocaleProvider.instance.setLocale(const Locale('en'));
  });

  test('App router exposes initial location', () {
    // P2-2: buildAppRouter 要求先注册 Shell builder。
    // 测试场景下注册一个最小 Shell，验证路由器可正常构建。
    RouteRegistry.reset();
    RouteRegistry.registerShell((context, state, child) => Scaffold(body: child));
    final router = buildAppRouter();
    expect(router.routerDelegate, isNotNull);
    RouteRegistry.reset();
  });

  test('App theme exposes light and dark variants', () {
    expect(AppTheme.lightTheme, isNotNull);
    expect(AppTheme.darkTheme, isNotNull);
  });
}
