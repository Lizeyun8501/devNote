import 'dart:convert';

enum PluginPermission {
  readNotes,
  writeNotes,
  accessNetwork,
  accessFileSystem,
  accessUI,
  accessCanvas,
  accessDatabase,
}

enum PluginLifecycleState {
  loaded,
  enabled,
  disabled,
}

class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final List<PluginPermission> permissions;
  final String apiVersion;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.permissions,
    required this.apiVersion,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String,
      author: json['author'] as String,
      permissions: (json['permissions'] as List<dynamic>)
          .map((p) => PluginPermission.values.firstWhere(
                (e) => e.name == p,
                orElse: () => PluginPermission.readNotes,
              ))
          .toList(),
      apiVersion: json['api_version'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'description': description,
      'author': author,
      'permissions': permissions.map((p) => p.name).toList(),
      'api_version': apiVersion,
    };
  }
}

class PluginEntry {
  final PluginManifest manifest;
  final PluginLifecycleState state;
  final List<PluginPermission> grantedPermissions;

  const PluginEntry({
    required this.manifest,
    required this.state,
    required this.grantedPermissions,
  });

  PluginEntry copyWith({
    PluginManifest? manifest,
    PluginLifecycleState? state,
    List<PluginPermission>? grantedPermissions,
  }) {
    return PluginEntry(
      manifest: manifest ?? this.manifest,
      state: state ?? this.state,
      grantedPermissions: grantedPermissions ?? this.grantedPermissions,
    );
  }
}

class PluginMethodResult {
  final bool success;
  final dynamic data;
  final String? error;

  const PluginMethodResult({
    required this.success,
    this.data,
    this.error,
  });

  factory PluginMethodResult.fromJson(Map<String, dynamic> json) {
    return PluginMethodResult(
      success: json['success'] as bool,
      data: json['data'],
      error: json['error'] as String?,
    );
  }
}

class MarketplacePlugin {
  final PluginManifest manifest;
  final String category;
  final double rating;
  final int downloadCount;
  final bool isInstalled;
  final String? installedVersion;

  const MarketplacePlugin({
    required this.manifest,
    required this.category,
    this.rating = 0.0,
    this.downloadCount = 0,
    this.isInstalled = false,
    this.installedVersion,
  });

  MarketplacePlugin copyWith({
    PluginManifest? manifest,
    String? category,
    double? rating,
    int? downloadCount,
    bool? isInstalled,
    String? installedVersion,
  }) {
    return MarketplacePlugin(
      manifest: manifest ?? this.manifest,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      downloadCount: downloadCount ?? this.downloadCount,
      isInstalled: isInstalled ?? this.isInstalled,
      installedVersion: installedVersion ?? this.installedVersion,
    );
  }
}

class PluginService {
  PluginService();

  final Map<String, PluginEntry> _plugins = {};
  final Map<String, List<int>> _wasmBytes = {};

  Future<void> loadPlugin(String id, List<int> wasmBytes, PluginManifest manifest) async {
    if (_plugins.containsKey(id)) {
      throw Exception('Plugin already loaded: $id');
    }
    _wasmBytes[id] = wasmBytes;
    _plugins[id] = PluginEntry(
      manifest: manifest,
      state: PluginLifecycleState.loaded,
      grantedPermissions: [],
    );
  }

  Future<void> unloadPlugin(String id) async {
    if (!_plugins.containsKey(id)) {
      throw Exception('Plugin not found: $id');
    }
    _plugins.remove(id);
    _wasmBytes.remove(id);
  }

  Future<void> enablePlugin(String id) async {
    final entry = _plugins[id];
    if (entry == null) {
      throw Exception('Plugin not found: $id');
    }
    _plugins[id] = entry.copyWith(state: PluginLifecycleState.enabled);
  }

  Future<void> disablePlugin(String id) async {
    final entry = _plugins[id];
    if (entry == null) {
      throw Exception('Plugin not found: $id');
    }
    _plugins[id] = entry.copyWith(state: PluginLifecycleState.disabled);
  }

  Future<PluginMethodResult> executePlugin(
    String id,
    String method,
    Map<String, dynamic> params,
  ) async {
    final entry = _plugins[id];
    if (entry == null) {
      return PluginMethodResult(success: false, error: 'Plugin not found: $id');
    }
    if (entry.state != PluginLifecycleState.enabled) {
      return PluginMethodResult(
        success: false,
        error: 'Plugin $id is not enabled',
      );
    }
    final payload = jsonEncode({'method': method, 'params': params});
    final _ = payload;
    return PluginMethodResult(success: true, data: params);
  }

  Future<void> grantPermission(String id, PluginPermission permission) async {
    final entry = _plugins[id];
    if (entry == null) {
      throw Exception('Plugin not found: $id');
    }
    if (!entry.grantedPermissions.contains(permission)) {
      _plugins[id] = entry.copyWith(
        grantedPermissions: [...entry.grantedPermissions, permission],
      );
    }
  }

  Future<void> revokePermission(String id, PluginPermission permission) async {
    final entry = _plugins[id];
    if (entry == null) {
      throw Exception('Plugin not found: $id');
    }
    _plugins[id] = entry.copyWith(
      grantedPermissions:
          entry.grantedPermissions.where((p) => p != permission).toList(),
    );
  }

  bool checkPermission(String id, PluginPermission permission) {
    final entry = _plugins[id];
    if (entry == null) return false;
    return entry.grantedPermissions.contains(permission);
  }

  PluginEntry? getPlugin(String id) => _plugins[id];

  List<PluginEntry> listPlugins() => _plugins.values.toList();

  List<PluginEntry> get enabledPlugins =>
      _plugins.values.where((e) => e.state == PluginLifecycleState.enabled).toList();

  Future<List<MarketplacePlugin>> fetchMarketplacePlugins({
    String? category,
    String? query,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return <MarketplacePlugin>[];
  }
}
