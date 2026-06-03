import 'package:devnote/features/plugins/plugin_service.dart';

sealed class PluginsState {
  const PluginsState();
}

final class PluginsInitial extends PluginsState {
  const PluginsInitial();
}

final class PluginsLoaded extends PluginsState {
  final List<PluginEntry> plugins;
  final List<MarketplacePlugin> marketplacePlugins;

  const PluginsLoaded({
    required this.plugins,
    this.marketplacePlugins = const [],
  });

  PluginsLoaded copyWith({
    List<PluginEntry>? plugins,
    List<MarketplacePlugin>? marketplacePlugins,
  }) {
    return PluginsLoaded(
      plugins: plugins ?? this.plugins,
      marketplacePlugins: marketplacePlugins ?? this.marketplacePlugins,
    );
  }
}

final class PluginError extends PluginsState {
  final String message;

  const PluginError(this.message);
}
