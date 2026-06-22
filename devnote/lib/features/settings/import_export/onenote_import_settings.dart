// OneNote 导入设置 —— 数据类与配置 UI 组件
//
// 提供导入行为的可配置选项，包括目标文件夹、结构保留、图片/附件导入、
// 表格格式转换等。借鉴 Obsidian Importer 插件的设置面板设计：
// https://help.obsidian.md/import

import 'package:flutter/material.dart';

/// OneNote 导入设置数据类
class OneNoteImportSettings {
  /// 导入到哪个文件夹（空字符串表示根目录）
  final String targetFolderId;

  /// 是否保留 OneNote 的笔记本/分区结构
  ///
  /// 为 true 时，会按 OneNote 的笔记本/分区层级在 DevNote 中创建对应文件夹。
  /// 为 false 时，所有笔记平铺导入到 [targetFolderId] 下。
  final bool preserveOriginalStructure;

  /// 是否导入图片
  ///
  /// 为 true 时，OneNote 页面中的图片会被复制到 DevNote 媒体目录。
  /// 为 false 时，图片引用将被丢弃。
  final bool importImages;

  /// 是否导入附件
  ///
  /// 为 true 时，OneNote 页面中的附件（PDF、Office 文档等）会被复制到 DevNote。
  /// 为 false 时，附件引用将被丢弃。
  final bool importAttachments;

  /// 表格是否转为 Markdown
  ///
  /// 为 true 时，OneNote 表格会被转换为 Markdown 表格语法。
  /// 为 false 时，表格保留为 HTML 片段存储在 block 内容中。
  final bool convertTablesToMarkdown;

  const OneNoteImportSettings({
    this.targetFolderId = '',
    this.preserveOriginalStructure = true,
    this.importImages = true,
    this.importAttachments = true,
    this.convertTablesToMarkdown = true,
  });

  OneNoteImportSettings copyWith({
    String? targetFolderId,
    bool? preserveOriginalStructure,
    bool? importImages,
    bool? importAttachments,
    bool? convertTablesToMarkdown,
  }) {
    return OneNoteImportSettings(
      targetFolderId: targetFolderId ?? this.targetFolderId,
      preserveOriginalStructure:
          preserveOriginalStructure ?? this.preserveOriginalStructure,
      importImages: importImages ?? this.importImages,
      importAttachments: importAttachments ?? this.importAttachments,
      convertTablesToMarkdown:
          convertTablesToMarkdown ?? this.convertTablesToMarkdown,
    );
  }
}

/// OneNote 导入设置配置组件
///
/// 提供导入选项的可视化配置界面，允许用户在导入前调整设置。
class OneNoteImportSettingsWidget extends StatefulWidget {
  final OneNoteImportSettings settings;
  final ValueChanged<OneNoteImportSettings> onChanged;

  const OneNoteImportSettingsWidget({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<OneNoteImportSettingsWidget> createState() =>
      _OneNoteImportSettingsWidgetState();
}

class _OneNoteImportSettingsWidgetState
    extends State<OneNoteImportSettingsWidget> {
  late OneNoteImportSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(OneNoteImportSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    widget.onChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '导入设置',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        SwitchListTile(
          title: const Text('保留原始结构'),
          subtitle: const Text('按 OneNote 笔记本/分区层级创建文件夹'),
          value: _settings.preserveOriginalStructure,
          onChanged: (value) {
            _update(_settings.copyWith(preserveOriginalStructure: value));
          },
        ),
        SwitchListTile(
          title: const Text('导入图片'),
          subtitle: const Text('将 OneNote 图片复制到 DevNote 媒体目录'),
          value: _settings.importImages,
          onChanged: (value) {
            _update(_settings.copyWith(importImages: value));
          },
        ),
        SwitchListTile(
          title: const Text('导入附件'),
          subtitle: const Text('将 OneNote 附件（PDF、文档等）复制到 DevNote'),
          value: _settings.importAttachments,
          onChanged: (value) {
            _update(_settings.copyWith(importAttachments: value));
          },
        ),
        SwitchListTile(
          title: const Text('表格转为 Markdown'),
          subtitle: const Text('将 OneNote 表格转换为 Markdown 表格语法'),
          value: _settings.convertTablesToMarkdown,
          onChanged: (value) {
            _update(_settings.copyWith(convertTablesToMarkdown: value));
          },
        ),
      ],
    );
  }
}
