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
      // 修复：marketplace 获取失败时不应隐藏本地已安装的插件
      // 原代码 marketplace fetch 失败会直接 emit PluginError，
      // 导致用户连本地插件都看不到
      List<MarketplacePlugin> marketplacePlugins = <MarketplacePlugin>[];
      try {
        marketplacePlugins = await _pluginService.fetchMarketplacePlugins();
      } catch (_) {
        // marketplace 获取失败时，本地插件仍可正常使用
      }
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
      await _pluginService.installPlugin(
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
      await _pluginService.uninstallPlugin(event.id);
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
