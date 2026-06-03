import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Provider for runtime locale switching.
/// Use [LocaleProvider.instance] as a singleton [ValueNotifier<Locale>].
class LocaleProvider extends ValueNotifier<Locale> {
  LocaleProvider._() : super(const Locale('en'));

  static final LocaleProvider instance = LocaleProvider._();

  /// List of supported locales
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('zh'),
  ];

  /// Switch to the given locale
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
