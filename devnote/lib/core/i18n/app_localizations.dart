import 'package:flutter/material.dart';
import 'package:devnote/l10n/app_localizations.dart';

export 'package:devnote/l10n/app_localizations.dart' show AppLocalizations;

/// Provider for runtime locale switching.
/// Use [LocaleProvider.instance] as a singleton [ValueNotifier<Locale>].
///
/// P2-7: 多语言扩展 —— 支持的 locale 列表扩展到 20 种语言。
class LocaleProvider extends ValueNotifier<Locale> {
  LocaleProvider._() : super(const Locale('en'));

  static final LocaleProvider instance = LocaleProvider._();

  /// List of supported locales (20 languages)
  /// 顺序与 LocaleService._supportedLocales 保持一致。
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'),
    Locale('ja'),
    Locale('ko'),
    Locale('fr'),
    Locale('de'),
    Locale('es'),
    Locale('pt'),
    Locale('ru'),
    Locale('it'),
    Locale('nl'),
    Locale('pl'),
    Locale('tr'),
    Locale('ar'),
    Locale('hi'),
    Locale('th'),
    Locale('vi'),
    Locale('id'),
    Locale('uk'),
  ];

  /// 切换到指定 locale。
  /// 若 locale 不在支持列表中则忽略，避免传入非法值导致本地化缺失。
  void setLocale(Locale locale) {
    if (supportedLocales.contains(locale) && locale != value) {
      value = locale;
    }
  }

  /// Get current language code
  String get languageCode => value.languageCode;

  /// Whether the current locale is Chinese
  bool get isChinese => languageCode == 'zh';

  /// Whether the current locale is English
  bool get isEnglish => languageCode == 'en';

  /// 当前 locale 是否需要 RTL 布局（阿拉伯语、希伯来语等）。
  bool get isRTL {
    final lang = value.languageCode.toLowerCase();
    return lang == 'ar' || lang == 'he' || lang == 'fa' || lang == 'ur';
  }
}

/// Extension to provide convenient access to localized strings.
///
/// Usage:
/// ```dart
/// context.l10n.appName  // Returns localized app name
/// context.l10n.notes    // Returns "Notes" or "笔记"
/// ```
extension AppLocalizationsX on BuildContext {
  /// Access the generated [AppLocalizations] instance
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  /// Get current locale
  Locale get currentLocale => Localizations.localeOf(this);
}
