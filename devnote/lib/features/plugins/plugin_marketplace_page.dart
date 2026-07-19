import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:devnote/features/plugins/bloc/plugin_bloc.dart';
import 'package:devnote/features/plugins/bloc/plugin_event.dart';
import 'package:devnote/features/plugins/bloc/plugin_state.dart';
import 'package:devnote/features/plugins/widgets/plugin_card.dart';

class PluginMarketplacePage extends StatefulWidget {
  const PluginMarketplacePage({super.key});

  @override
  State<PluginMarketplacePage> createState() => _PluginMarketplacePageState();
}

class _PluginMarketplacePageState extends State<PluginMarketplacePage> {
  String _searchQuery = '';
  // 内部统一使用英文 key 作为筛选标识，避免与数据源（MarketplacePlugin.category
  // 全部为英文 key 如 'productivity'/'theme'）做字符串比较时不匹配。
  // null 表示"全部"分类。
  String? _selectedCategoryKey;

  /// 分类英文 key → 中文显示文本的映射。
  /// 数据源（plugin_service.dart 中的 mock 数据）使用英文 key，因此筛选时
  /// 必须使用同一份 key；UI 显示则统一查表，未命中的 key 退化为枚举字符串本身。
  static const Map<String, String> _categoryLabels = {
    'productivity': '效率',
    'learning': '学习',
    'workflow': '工作流',
    'data': '数据',
    'appearance': '美化',
    'other': '其他',
    // 以下分类对应现有 mock 数据源
    'theme': '主题',
    'tool': '工具',
    'integration': '同步',
    'export': '导出',
    'visualization': '可视化',
    'editor': '编辑器',
    'development': '开发',
  };

  /// 用于展示的分类项：第一项为"全部"，后续按 _categoryLabels 顺序。
  /// 第一个元素用 null 表示"全部"分类。
  static const List<String?> _categoryKeys = [
    null,
    'productivity',
    'learning',
    'workflow',
    'data',
    'appearance',
    'other',
    'theme',
    'tool',
    'integration',
    'export',
    'visualization',
    'editor',
    'development',
  ];

  String _labelForKey(String? key) {
    if (key == null) return '全部';
    return _categoryLabels[key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    context.read<PluginBloc>().add(const LoadPlugins());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件市场'),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildCategoryTabs(),
          Expanded(child: _buildPluginList()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索插件',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _categoryKeys.length,
        itemBuilder: (context, index) {
          final key = _categoryKeys[index];
          final isSelected = key == _selectedCategoryKey;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_labelForKey(key)),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _selectedCategoryKey = key;
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPluginList() {
    return BlocBuilder<PluginBloc, PluginsState>(
      // P2-4: 仅在 state 类型变化或 marketplacePlugins 列表变化时重建，
      // 避免 plugins（已安装列表）变化触发市场列表重建。
      buildWhen: (previous, current) {
        if (previous.runtimeType != current.runtimeType) return true;
        if (previous is PluginsLoaded && current is PluginsLoaded) {
          return previous.marketplacePlugins != current.marketplacePlugins;
        }
        return false;
      },
      builder: (context, state) {
        if (state is PluginsLoaded) {
          var plugins = state.marketplacePlugins;

          if (_selectedCategoryKey != null) {
            final key = _selectedCategoryKey!;
            plugins = plugins
                .where((p) => p.category.toLowerCase() == key.toLowerCase())
                .toList();
          }

          if (_searchQuery.isNotEmpty) {
            plugins = plugins
                .where((p) =>
                    p.manifest.name
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()) ||
                    p.manifest.description
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()))
                .toList();
          }

          if (plugins.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.extension_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无插件', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: plugins.length,
            itemBuilder: (context, index) {
              final plugin = plugins[index];
              return PluginCard(
                name: plugin.manifest.name,
                description: plugin.manifest.description,
                author: plugin.manifest.author,
                version: plugin.manifest.version,
                rating: plugin.rating,
                downloadCount: plugin.downloadCount,
                isInstalled: plugin.isInstalled,
                onInstall: () {
                  context.read<PluginBloc>().add(InstallPlugin(
                        id: plugin.manifest.id,
                        wasmBytes: [],
                        manifest: plugin.manifest,
                      ));
                },
              );
            },
          );
        }

        if (state is PluginError) {
          return Center(child: Text('加载失败: ${state.message}'));
        }

        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
