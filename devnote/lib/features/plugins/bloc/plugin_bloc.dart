import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/plugins/bloc/plugin_event.dart';
import 'package:devnote/features/plugins/bloc/plugin_state.dart';
import 'package:devnote/features/plugins/plugin_service.dart';

class PluginBloc extends Bloc<PluginEvent, PluginsState> {
  final PluginService _pluginService;

  PluginBloc(this._pluginService) : super(const PluginsInitial()) {
    on<LoadPlugins>(_onLoadPlugins);
    on<InstallPlugin>(_onInstallPlugin);
    on<UninstallPlugin>(_onUninstallPlugin);
    on<EnablePlugin>(_onEnablePlugin);
    on<DisablePlugin>(_onDisablePlugin);
    on<GrantPermission>(_onGrantPermission);
    on<RevokePermission>(_onRevokePermission);
  }

  Future<void> _onLoadPlugins(
    LoadPlugins event,
    Emitter<PluginsState> emit,
  ) async {
    try {
      final plugins = _pluginService.listPlugins();
      final marketplacePlugins =
          await _pluginService.fetchMarketplacePlugins();
      emit(PluginsLoaded(
        plugins: plugins,
        marketplacePlugins: marketplacePlugins,
      ));
    } catch (e) {
      emit(PluginError(e.toString()));
    }
  }

  Future<void> _onInstallPlugin(
    InstallPlugin event,
    Emitter<PluginsState> emit,
  ) async {
    try {
      await _pluginService.loadPlugin(
        event.id,
        event.wasmBytes,
        event.manifest,
      );
      final plugins = _pluginService.listPlugins();
      final currentState = state;
      final marketplacePlugins = currentState is PluginsLoaded
          ? currentState.marketplacePlugins
          : <MarketplacePlugin>[];
      emit(PluginsLoaded(
        plugins: plugins,
        marketplacePlugins: marketplacePlugins,
      ));
    } catch (e) {
      emit(PluginError(e.toString()));
    }
  }

  Future<void> _onUninstallPlugin(
    UninstallPlugin event,
    Emitter<PluginsState> emit,
  ) async {
    try {
      await _pluginService.unloadPlugin(event.id);
      final plugins = _pluginService.listPlugins();
      final currentState = state;
      final marketplacePlugins = currentState is PluginsLoaded
          ? currentState.marketplacePlugins
          : <MarketplacePlugin>[];
      emit(PluginsLoaded(
        plugins: plugins,
        marketplacePlugins: marketplacePlugins,
      ));
    } catch (e) {
      emit(PluginError(e.toString()));
    }
  }

  Future<void> _onEnablePlugin(
    EnablePlugin event,
    Emitter<PluginsState> emit,
  ) async {
    try {
      await _pluginService.enablePlugin(event.id);
      final plugins = _pluginService.listPlugins();
      final currentState = state;
      final marketplacePlugins = currentState is PluginsLoaded
          ? currentState.marketplacePlugins
          : <MarketplacePlugin>[];
      emit(PluginsLoaded(
        plugins: plugins,
        marketplacePlugins: marketplacePlugins,
      ));
    } catch (e) {
      emit(PluginError(e.toString()));
    }
  }

  Future<void> _onDisablePlugin(
    DisablePlugin event,
    Emitter<PluginsState> emit,
  ) async {
    try {
      await _pluginService.disablePlugin(event.id);
      final plugins = _pluginService.listPlugins();
      final currentState = state;
      final marketplacePlugins = currentState is PluginsLoaded
          ? currentState.marketplacePlugins
          : <MarketplacePlugin>[];
      emit(PluginsLoaded(
        plugins: plugins,
        marketplacePlugins: marketplacePlugins,
      ));
    } catch (e) {
      emit(PluginError(e.toString()));
    }
  }

  Future<void> _onGrantPermission(
    GrantPermission event,
    Emitter<PluginsState> emit,
  ) async {
    try {
      await _pluginService.grantPermission(event.id, event.permission);
      final plugins = _pluginService.listPlugins();
      final currentState = state;
      final marketplacePlugins = currentState is PluginsLoaded
          ? currentState.marketplacePlugins
          : <MarketplacePlugin>[];
      emit(PluginsLoaded(
        plugins: plugins,
        marketplacePlugins: marketplacePlugins,
      ));
    } catch (e) {
      emit(PluginError(e.toString()));
    }
  }

  Future<void> _onRevokePermission(
    RevokePermission event,
    Emitter<PluginsState> emit,
  ) async {
    try {
      await _pluginService.revokePermission(event.id, event.permission);
      final plugins = _pluginService.listPlugins();
      final currentState = state;
      final marketplacePlugins = currentState is PluginsLoaded
          ? currentState.marketplacePlugins
          : <MarketplacePlugin>[];
      emit(PluginsLoaded(
        plugins: plugins,
        marketplacePlugins: marketplacePlugins,
      ));
    } catch (e) {
      emit(PluginError(e.toString()));
    }
  }
}
