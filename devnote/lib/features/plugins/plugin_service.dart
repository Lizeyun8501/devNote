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

  // 修改原因：原实现返回空列表，导致插件市场页面无数据展示。
  // 现提供一组跨分类的模拟插件，用于本地开发与界面联调。
  Future<List<MarketplacePlugin>> fetchMarketplacePlugins({
    String? category,
    String? query,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    // 构建 6 个跨分类的模拟插件，覆盖 productivity / theme / tool /
    // integration / export / visualization 六大类，便于 UI 验证。
    final mockPlugins = <MarketplacePlugin>[
      MarketplacePlugin(
        manifest: PluginManifest(
          id: 'com.devnote.markdown-formatter',
          name: 'Markdown Formatter',
          version: '1.2.0',
          description: '一键整理与美化 Markdown 文档结构，自动规范化标题层级。',
          author: 'DevNote Team',
          permissions: [PluginPermission.readNotes, PluginPermission.writeNotes],
          apiVersion: '1.0.0',
        ),
        category: 'productivity',
        rating: 4.7,
        downloadCount: 12850,
      ),
      MarketplacePlugin(
        manifest: PluginManifest(
          id: 'com.devnote.solarized-theme',
          name: 'Solarized Theme',
          version: '2.0.1',
          description: '经典 Solarized 配色方案，为编辑器与代码块提供护眼主题。',
          author: 'Ethan Schoonover',
          permissions: [PluginPermission.accessUI],
          apiVersion: '1.0.0',
        ),
        category: 'theme',
        rating: 4.9,
        downloadCount: 25630,
      ),
      MarketplacePlugin(
        manifest: PluginManifest(
          id: 'com.devnote.code-runner',
          name: 'Code Runner',
          version: '3.1.4',
          description: '在笔记中直接运行多种编程语言代码块并显示结果。',
          author: 'DevNote Labs',
          permissions: [
            PluginPermission.readNotes,
            PluginPermission.accessUI,
            PluginPermission.accessFileSystem,
          ],
          apiVersion: '1.0.0',
        ),
        category: 'tool',
        rating: 4.5,
        downloadCount: 9870,
      ),
      MarketplacePlugin(
        manifest: PluginManifest(
          id: 'com.devnote.github-sync',
          name: 'GitHub Sync',
          version: '1.5.0',
          description: '将笔记与 GitHub 仓库双向同步，支持 Gist 与完整仓库模式。',
          author: 'Open Source Contributors',
          permissions: [
            PluginPermission.readNotes,
            PluginPermission.writeNotes,
            PluginPermission.accessNetwork,
            PluginPermission.accessFileSystem,
          ],
          apiVersion: '1.0.0',
        ),
        category: 'integration',
        rating: 4.3,
        downloadCount: 7320,
      ),
      MarketplacePlugin(
        manifest: PluginManifest(
          id: 'com.devnote.pdf-export-pro',
          name: 'PDF Export Pro',
          version: '2.3.2',
          description: '将笔记导出为高质量 PDF，支持自定义模板、页眉页脚与目录。',
          author: 'Export Studio',
          permissions: [
            PluginPermission.readNotes,
            PluginPermission.accessFileSystem,
          ],
          apiVersion: '1.0.0',
        ),
        category: 'export',
        rating: 4.6,
        downloadCount: 18420,
      ),
      MarketplacePlugin(
        manifest: PluginManifest(
          id: 'com.devnote.mermaid-enhanced',
          name: 'Mermaid Enhanced',
          version: '1.0.7',
          description: '增强的 Mermaid 图表渲染，支持更多图表类型与交互。',
          author: 'Visualization Community',
          permissions: [
            PluginPermission.readNotes,
            PluginPermission.accessUI,
            PluginPermission.accessCanvas,
          ],
          apiVersion: '1.0.0',
        ),
        category: 'visualization',
        rating: 4.4,
        downloadCount: 5610,
      ),
    ];

    Iterable<MarketplacePlugin> result = mockPlugins;
    if (category != null && category.isNotEmpty) {
      // 按分类过滤（不区分大小写）
      result = result.where((p) => p.category.toLowerCase() == category.toLowerCase());
    }
    if (query != null && query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      // 按名称或描述模糊匹配
      result = result.where(
        (p) =>
            p.manifest.name.toLowerCase().contains(lowerQuery) ||
            p.manifest.description.toLowerCase().contains(lowerQuery),
      );
    }
    return result.toList();
  }
}
