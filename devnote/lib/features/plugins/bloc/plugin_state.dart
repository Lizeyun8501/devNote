import 'package:equatable/equatable.dart';
import 'package:devnote/features/plugins/plugin_service.dart';

abstract class PluginsState extends Equatable {
  const PluginsState();

  @override
  List<Object?> get props => [];
}

class PluginsInitial extends PluginsState {
  const PluginsInitial();
}

class PluginsLoaded extends PluginsState {
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

  @override
  List<Object?> get props => [plugins, marketplacePlugins];
}

class PluginError extends PluginsState {
  final String message;

  const PluginError(this.message);

  @override
  List<Object?> get props => [message];
}
