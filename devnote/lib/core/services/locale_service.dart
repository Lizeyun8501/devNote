import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// P2-7: 多语言扩展 —— 语言设置服务
///
/// 负责持久化用户选择的应用语言，并提供支持语言列表与 RTL 判断。
/// 借鉴 AppFlowy 的 LocaleService 设计：将语言偏好存储在 SharedPreferences，
/// 启动时读取并注入 MaterialApp。
class LocaleService {
  LocaleService();

  static const String _kLocaleKey = 'settings.locale';

  /// 支持的语言列表（locale code -> 显示信息）
  /// 顺序即语言选择页面的展示顺序。
  static const List<SupportedLocale> _supportedLocales = [
    SupportedLocale(
      localeCode: 'en',
      englishName: 'English',
      nativeName: 'English',
      flagEmoji: '🇺🇸',
    ),
    SupportedLocale(
      localeCode: 'zh',
      englishName: 'Chinese (Simplified)',
      nativeName: '简体中文',
      flagEmoji: '🇨🇳',
    ),
    SupportedLocale(
      localeCode: 'zh_TW',
      englishName: 'Chinese (Traditional)',
      nativeName: '繁體中文',
      flagEmoji: '🇹🇼',
    ),
    SupportedLocale(
      localeCode: 'ja',
      englishName: 'Japanese',
      nativeName: '日本語',
      flagEmoji: '🇯🇵',
    ),
    SupportedLocale(
      localeCode: 'ko',
      englishName: 'Korean',
      nativeName: '한국어',
      flagEmoji: '🇰🇷',
    ),
    SupportedLocale(
      localeCode: 'fr',
      englishName: 'French',
      nativeName: 'Français',
      flagEmoji: '🇫🇷',
    ),
    SupportedLocale(
      localeCode: 'de',
      englishName: 'German',
      nativeName: 'Deutsch',
      flagEmoji: '🇩🇪',
    ),
    SupportedLocale(
      localeCode: 'es',
      englishName: 'Spanish',
      nativeName: 'Español',
      flagEmoji: '🇪🇸',
    ),
    SupportedLocale(
      localeCode: 'pt',
      englishName: 'Portuguese',
      nativeName: 'Português',
      flagEmoji: '🇵🇹',
    ),
    SupportedLocale(
      localeCode: 'ru',
      englishName: 'Russian',
      nativeName: 'Русский',
      flagEmoji: '🇷🇺',
    ),
    SupportedLocale(
      localeCode: 'it',
      englishName: 'Italian',
      nativeName: 'Italiano',
      flagEmoji: '🇮🇹',
    ),
    SupportedLocale(
      localeCode: 'nl',
      englishName: 'Dutch',
      nativeName: 'Nederlands',
      flagEmoji: '🇳🇱',
    ),
    SupportedLocale(
      localeCode: 'pl',
      englishName: 'Polish',
      nativeName: 'Polski',
      flagEmoji: '🇵🇱',
    ),
    SupportedLocale(
      localeCode: 'tr',
      englishName: 'Turkish',
      nativeName: 'Türkçe',
      flagEmoji: '🇹🇷',
    ),
    SupportedLocale(
      localeCode: 'ar',
      englishName: 'Arabic',
      nativeName: 'العربية',
      flagEmoji: '🇸🇦',
    ),
    SupportedLocale(
      localeCode: 'hi',
      englishName: 'Hindi',
      nativeName: 'हिन्दी',
      flagEmoji: '🇮🇳',
    ),
    SupportedLocale(
      localeCode: 'th',
      englishName: 'Thai',
      nativeName: 'ไทย',
      flagEmoji: '🇹🇭',
    ),
    SupportedLocale(
      localeCode: 'vi',
      englishName: 'Vietnamese',
      nativeName: 'Tiếng Việt',
      flagEmoji: '🇻🇳',
    ),
    SupportedLocale(
      localeCode: 'id',
      englishName: 'Indonesian',
      nativeName: 'Bahasa Indonesia',
      flagEmoji: '🇮🇩',
    ),
    SupportedLocale(
      localeCode: 'uk',
      englishName: 'Ukrainian',
      nativeName: 'Українська',
      flagEmoji: '🇺🇦',
    ),
  ];

  /// 从 SharedPreferences 读取用户上次选择的语言。
  /// 未设置时返回 null，由调用方决定回退到系统语言或默认语言。
  Future<Locale?> getCurrentLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
    if (code == null) return null;
    return _parseLocaleCode(code);
  }

  /// 保存用户选择的语言到 SharedPreferences。
  /// localeCode 形如 "en"、"zh"、"zh_TW"。
  Future<void> setCurrentLocale(String localeCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, localeCode);
  }

  /// 返回所有支持的语言列表（含显示名称与国旗 emoji）。
  List<SupportedLocale> getSupportedLocales() {
    return List.unmodifiable(_supportedLocales);
  }

  /// 返回所有支持的 [Locale]（供 MaterialApp.supportedLocales 使用）。
  List<Locale> getSupportedLocaleObjects() {
    return _supportedLocales.map((l) => _parseLocaleCode(l.localeCode)!).toList();
  }

  /// 判断给定语言是否需要 RTL（从右到左）布局。
  /// 阿拉伯语和希伯来语返回 true。
  bool shouldUseRTL(String localeCode) {
    final lang = localeCode.split('_').first.toLowerCase();
    return lang == 'ar' || lang == 'he' || lang == 'fa' || lang == 'ur';
  }

  /// 根据 localeCode 查找对应的 [SupportedLocale]，找不到返回 null。
  SupportedLocale? findByCode(String localeCode) {
    for (final l in _supportedLocales) {
      if (l.localeCode == localeCode) return l;
    }
    return null;
  }

  /// 将 localeCode（如 "zh_TW"）解析为 [Locale]。
  /// "zh_TW" -> Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW')
  static Locale? _parseLocaleCode(String code) {
    if (code.isEmpty) return null;
    final parts = code.split('_');
    if (parts.length == 1) {
      return Locale(parts[0]);
    }
    return Locale.fromSubtags(languageCode: parts[0], countryCode: parts[1]);
  }
}

/// 单个支持语言的元信息。
class SupportedLocale {
  const SupportedLocale({
    required this.localeCode,
    required this.englishName,
    required this.nativeName,
    required this.flagEmoji,
  });

  /// locale 标识，如 "en"、"zh_TW"
  final String localeCode;

  /// 英文名称，用于搜索匹配
  final String englishName;

  /// 该语言的自称，用于展示
  final String nativeName;

  /// 国旗 emoji
  final String flagEmoji;

  /// 解析为 Flutter [Locale]
  Locale get locale {
    final parts = localeCode.split('_');
    if (parts.length == 1) return Locale(parts[0]);
    return Locale.fromSubtags(languageCode: parts[0], countryCode: parts[1]);
  }
}
