import 'package:equatable/equatable.dart';
import 'package:devnote/features/plugins/plugin_service.dart';

abstract class PluginEvent extends Equatable {
  const PluginEvent();

  @override
  List<Object?> get props => [];
}

class LoadPlugins extends PluginEvent {
  const LoadPlugins();
}

class InstallPlugin extends PluginEvent {
  final String id;
  final List<int> wasmBytes;
  final PluginManifest manifest;

  const InstallPlugin({
    required this.id,
    required this.wasmBytes,
    required this.manifest,
  });

  @override
  List<Object?> get props => [id, manifest];
}

class UninstallPlugin extends PluginEvent {
  final String id;

  const UninstallPlugin(this.id);

  @override
  List<Object?> get props => [id];
}

class EnablePlugin extends PluginEvent {
  final String id;

  const EnablePlugin(this.id);

  @override
  List<Object?> get props => [id];
}

class DisablePlugin extends PluginEvent {
  final String id;

  const DisablePlugin(this.id);

  @override
  List<Object?> get props => [id];
}

class GrantPermission extends PluginEvent {
  final String id;
  final PluginPermission permission;

  const GrantPermission({
    required this.id,
    required this.permission,
  });

  @override
  List<Object?> get props => [id, permission];
}

class RevokePermission extends PluginEvent {
  final String id;
  final PluginPermission permission;

  const RevokePermission({
    required this.id,
    required this.permission,
  });

  @override
  List<Object?> get props => [id, permission];
}
