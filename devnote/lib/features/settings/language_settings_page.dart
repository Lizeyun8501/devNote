import 'package:flutter/material.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/i18n/app_localizations.dart';
import 'package:devnote/core/services/locale_service.dart';

/// P2-7: 多语言扩展 —— 语言选择页面
///
/// 展示所有支持的语言（国旗 emoji + 语言名称 + 当前选中标记），
/// 支持搜索过滤。选择后保存到 SharedPreferences 并通过 LocaleProvider
/// 实时切换，同时提示用户重启应用以完整应用更改（部分原生组件需重启生效）。
class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key});

  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  final LocaleService _localeService = getIt<LocaleService>();
  final TextEditingController _searchController = TextEditingController();

  late List<SupportedLocale> _allLocales;
  List<SupportedLocale> _filteredLocales = [];
  String? _currentLocaleCode;

  @override
  void initState() {
    super.initState();
    _allLocales = _localeService.getSupportedLocales();
    _filteredLocales = List.of(_allLocales);
    _searchController.addListener(_applyFilter);
    _loadCurrentLocale();
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentLocale() async {
    final locale = await _localeService.getCurrentLocale();
    final code = locale == null
        ? 'en'
        : (locale.countryCode != null && locale.countryCode!.isNotEmpty
            ? '${locale.languageCode}_${locale.countryCode}'
            : locale.languageCode);
    if (!mounted) return;
    setState(() {
      _currentLocaleCode = code;
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredLocales = List.of(_allLocales);
      });
      return;
    }
    setState(() {
      _filteredLocales = _allLocales
          .where((l) =>
              l.nativeName.toLowerCase().contains(query) ||
              l.englishName.toLowerCase().contains(query) ||
              l.localeCode.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _selectLocale(SupportedLocale supported) async {
    if (supported.localeCode == _currentLocaleCode) return;

    await _localeService.setCurrentLocale(supported.localeCode);
    LocaleProvider.instance.setLocale(supported.locale);

    if (!mounted) return;
    setState(() {
      _currentLocaleCode = supported.localeCode;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${supported.nativeName} ✓'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.search,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: _filteredLocales.isEmpty
                ? Center(
                    child: Text(
                      l10n.noContent,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: _filteredLocales.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final supported = _filteredLocales[index];
                      final isSelected =
                          supported.localeCode == _currentLocaleCode;
                      return ListTile(
                        leading: Text(
                          supported.flagEmoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                        title: Text(supported.nativeName),
                        subtitle: Text(supported.englishName),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : const Icon(Icons.radio_button_unchecked),
                        onTap: () => _selectLocale(supported),
                      );
                    },
                  ),
          ),
          const _RestartHintBanner(),
        ],
      ),
    );
  }
}

/// 底部提示条：告知用户部分更改需重启应用以完整生效。
class _RestartHintBanner extends StatelessWidget {
  const _RestartHintBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '部分原生组件需重启应用以完整应用语言更改',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
