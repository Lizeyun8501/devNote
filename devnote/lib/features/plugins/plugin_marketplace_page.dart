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
  String _selectedCategory = '全部';

  static const _categories = ['全部', '效率', '编辑器', '同步', '主题', '工具', '开发'];

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
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = category == _selectedCategory;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _selectedCategory = category;
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

          if (_selectedCategory != '全部') {
            plugins = plugins
                .where((p) => p.category == _selectedCategory)
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
