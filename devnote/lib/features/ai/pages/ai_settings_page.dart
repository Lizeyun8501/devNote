// AI 设置页面
//
// 借鉴 AppFlowy Vault 的本地 AI 配置界面：
// 提供 Ollama 服务器地址、生成模型、嵌入模型配置，连接测试，以及 AI 功能开关。
// 所有配置持久化到 SharedPreferences，应用重启后保持一致。

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/ai/ai_service.dart';
import 'package:devnote/features/ai/embedding_service.dart';
import 'package:devnote/features/ai/ollama_client.dart';
import 'package:devnote/features/ai/semantic_search_service.dart';

/// AI 设置页
class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  static const String _kBaseUrl = 'ai.ollama_base_url';
  static const String _kModel = 'ai.ollama_model';
  static const String _kEmbeddingModel = 'ai.embedding_model';
  static const String _kEnabled = 'ai.enabled';
  static const String _kSummarizeEnabled = 'ai.summarize_enabled';
  static const String _kRewriteEnabled = 'ai.rewrite_enabled';
  static const String _kCompleteEnabled = 'ai.complete_enabled';
  static const String _kTagSuggestEnabled = 'ai.tag_suggest_enabled';
  static const String _kHybridSearchEnabled = 'ai.hybrid_search_enabled';

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _embeddingModelController =
      TextEditingController();

  bool _enabled = false;
  bool _summarizeEnabled = true;
  bool _rewriteEnabled = true;
  bool _completeEnabled = true;
  bool _tagSuggestEnabled = true;
  bool _hybridSearchEnabled = true;

  List<String> _availableModels = [];
  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _embeddingModelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrlController.text =
        prefs.getString(_kBaseUrl) ?? 'http://localhost:11434';
    _modelController.text = prefs.getString(_kModel) ?? 'llama3';
    _embeddingModelController.text =
        prefs.getString(_kEmbeddingModel) ?? 'nomic-embed-text';
    _enabled = prefs.getBool(_kEnabled) ?? false;
    _summarizeEnabled = prefs.getBool(_kSummarizeEnabled) ?? true;
    _rewriteEnabled = prefs.getBool(_kRewriteEnabled) ?? true;
    _completeEnabled = prefs.getBool(_kCompleteEnabled) ?? true;
    _tagSuggestEnabled = prefs.getBool(_kTagSuggestEnabled) ?? true;
    _hybridSearchEnabled = prefs.getBool(_kHybridSearchEnabled) ?? true;

    // 将已保存的配置应用到运行中的服务实例
    _applyConfigToServices();

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }

    // 若已启用，自动拉取可用模型列表
    if (_enabled) {
      await _refreshModels();
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  /// 应用配置到运行中的服务实例
  void _applyConfigToServices() {
    final aiService = getIt<AIService>();
    final embeddingService = getIt<EmbeddingService>();
    final ollamaClient = getIt<OllamaClient>();

    ollamaClient.baseUrl = _baseUrlController.text.trim();
    ollamaClient.model = _modelController.text.trim();
    embeddingService.embeddingModel = _embeddingModelController.text.trim();
    aiService.setModel(_modelController.text.trim());
    aiService.setEnabled(_enabled);
    aiService.setSummarizeEnabled(_summarizeEnabled);
    aiService.setRewriteEnabled(_rewriteEnabled);
    aiService.setCompleteEnabled(_completeEnabled);
    aiService.setTagSuggestEnabled(_tagSuggestEnabled);
  }

  Future<void> _refreshModels() async {
    try {
      final ollamaClient = getIt<OllamaClient>();
      final models = await ollamaClient.listModels();
      if (mounted) {
        setState(() {
          _availableModels = models;
        });
      }
    } catch (_) {
      // 拉取失败时静默处理，用户可通过连接测试排查
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final ollamaClient = getIt<OllamaClient>();
      final ok = await ollamaClient.isAvailable();
      if (ok) {
        await _refreshModels();
        setState(() {
          _testSuccess = true;
          _testResult = '连接成功，发现 ${_availableModels.length} 个可用模型';
        });
      } else {
        setState(() {
          _testSuccess = false;
          _testResult = '无法连接到 Ollama，请确认服务已启动且地址正确';
        });
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = '连接测试失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
        });
      }
    }
  }

  Future<void> _onEnabledChanged(bool value) async {
    setState(() {
      _enabled = value;
    });
    await _saveSetting(_kEnabled, value);
    _applyConfigToServices();
    if (value) {
      await _refreshModels();
    }
  }

  Future<void> _onSaveBaseUrl() async {
    await _saveSetting(_kBaseUrl, _baseUrlController.text.trim());
    _applyConfigToServices();
  }

  Future<void> _onSaveModel() async {
    await _saveSetting(_kModel, _modelController.text.trim());
    _applyConfigToServices();
  }

  Future<void> _onSaveEmbeddingModel() async {
    await _saveSetting(_kEmbeddingModel, _embeddingModelController.text.trim());
    _applyConfigToServices();
  }

  Future<void> _rebuildIndex() async {
    final semanticSearch = getIt<SemanticSearchService>();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在重建向量索引...')),
    );
    final count = await semanticSearch.reindexAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('索引重建完成，共 $count 条笔记')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        children: [
          _Section(title: '总开关', children: [
            SwitchListTile(
              title: const Text('启用 AI 功能'),
              subtitle: const Text('开启后可通过本地 Ollama 使用 AI 能力'),
              value: _enabled,
              onChanged: _onEnabledChanged,
            ),
          ]),
          _Section(title: 'Ollama 服务', children: [
            ListTile(
              title: const Text('服务器地址'),
              subtitle: TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  hintText: 'http://localhost:11434',
                  isDense: true,
                ),
                onSubmitted: (_) => _onSaveBaseUrl(),
              ),
              trailing: TextButton(
                onPressed: _onSaveBaseUrl,
                child: const Text('保存'),
              ),
            ),
            ListTile(
              title: const Text('生成模型'),
              subtitle: _availableModels.isEmpty
                  ? TextField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        hintText: 'llama3',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _onSaveModel(),
                    )
                  : DropdownButton<String>(
                      value: _modelController.text.isEmpty
                          ? null
                          : _modelController.text,
                      hint: const Text('选择模型'),
                      items: _availableModels
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _modelController.text = value;
                        });
                        _onSaveModel();
                      },
                    ),
              trailing: _availableModels.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshModels,
                      tooltip: '刷新模型列表',
                    ),
            ),
            ListTile(
              title: const Text('嵌入模型'),
              subtitle: TextField(
                controller: _embeddingModelController,
                decoration: const InputDecoration(
                  hintText: 'nomic-embed-text',
                  isDense: true,
                ),
                onSubmitted: (_) => _onSaveEmbeddingModel(),
              ),
              trailing: TextButton(
                onPressed: _onSaveEmbeddingModel,
                child: const Text('保存'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FilledButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find),
                label: const Text('测试连接'),
              ),
            ),
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _testResult!,
                  style: TextStyle(
                    color: _testSuccess
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ]),
          _Section(title: 'AI 功能开关', children: [
            SwitchListTile(
              title: const Text('摘要'),
              subtitle: const Text('一键生成笔记摘要'),
              value: _summarizeEnabled,
              onChanged: (v) async {
                setState(() => _summarizeEnabled = v);
                await _saveSetting(_kSummarizeEnabled, v);
                _applyConfigToServices();
              },
            ),
            SwitchListTile(
              title: const Text('改写'),
              subtitle: const Text('选中文本后改写风格'),
              value: _rewriteEnabled,
              onChanged: (v) async {
                setState(() => _rewriteEnabled = v);
                await _saveSetting(_kRewriteEnabled, v);
                _applyConfigToServices();
              },
            ),
            SwitchListTile(
              title: const Text('自动补全'),
              subtitle: const Text('编辑时提供 AI 续写建议'),
              value: _completeEnabled,
              onChanged: (v) async {
                setState(() => _completeEnabled = v);
                await _saveSetting(_kCompleteEnabled, v);
                _applyConfigToServices();
              },
            ),
            SwitchListTile(
              title: const Text('标签推荐'),
              subtitle: const Text('基于笔记内容推荐标签'),
              value: _tagSuggestEnabled,
              onChanged: (v) async {
                setState(() => _tagSuggestEnabled = v);
                await _saveSetting(_kTagSuggestEnabled, v);
                _applyConfigToServices();
              },
            ),
          ]),
          _Section(title: '语义搜索', children: [
            SwitchListTile(
              title: const Text('混合检索 (Hybrid Retrieval)'),
              subtitle: const Text('BM25 关键词 + 向量语义 + RRF 融合'),
              value: _hybridSearchEnabled,
              onChanged: (v) async {
                setState(() => _hybridSearchEnabled = v);
                await _saveSetting(_kHybridSearchEnabled, v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.replay_circle_filled),
              title: const Text('重建向量索引'),
              subtitle: const Text('重新计算所有笔记的向量，模型切换后需要执行'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _rebuildIndex,
            ),
          ]),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '提示：AI 功能默认关闭，需先安装并启动 Ollama（https://ollama.com），'
              '拉取对应模型（如 ollama pull llama3）后在此页面配置。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}
