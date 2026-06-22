/// 笔记模板
class NoteTemplate {
  final String id;
  final String name;
  final String description;
  final TemplateCategory category;
  final String icon; // 图标名称
  final List<TemplateBlock> blocks;
  final Map<String, dynamic> metadata;
  final bool isBuiltIn;
  final bool isCustom;
  final DateTime? createdAt;

  NoteTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.icon = 'description',
    required this.blocks,
    this.metadata = const {},
    this.isBuiltIn = false,
    this.isCustom = false,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category.name,
        'icon': icon,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'metadata': metadata,
        'is_builtin': isBuiltIn,
        'is_custom': isCustom,
        'created_at': createdAt?.toIso8601String(),
      };

  factory NoteTemplate.fromJson(Map<String, dynamic> json) => NoteTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        category: TemplateCategory.values
            .byName(json['category'] as String? ?? 'other'),
        icon: json['icon'] as String? ?? 'description',
        blocks: (json['blocks'] as List? ?? [])
            .map((b) => TemplateBlock.fromJson(b as Map<String, dynamic>))
            .toList(),
        metadata: json['metadata'] as Map<String, dynamic>? ?? {},
        isBuiltIn: json['is_builtin'] as bool? ?? false,
        isCustom: json['is_custom'] as bool? ?? false,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : null,
      );
}

/// 模板块定义
class TemplateBlock {
  final String type; // paragraph/heading1/heading2/codeBlock/list/quote/tableBlock/image/taskListBlock
  final String content;
  final Map<String, dynamic>? properties;

  TemplateBlock({
    required this.type,
    required this.content,
    this.properties,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'content': content,
        'properties': properties,
      };

  factory TemplateBlock.fromJson(Map<String, dynamic> json) => TemplateBlock(
        type: json['type'] as String,
        content: json['content'] as String? ?? '',
        properties: json['properties'] as Map<String, dynamic>?,
      );
}

/// 模板分类
enum TemplateCategory {
  meeting, // 会议纪要
  reading, // 读书笔记
  project, // 项目计划
  daily, // 日记/每日笔记
  todo, // 待办清单
  study, // 学习笔记
  research, // 研究记录
  other, // 其他
}

extension TemplateCategoryExtension on TemplateCategory {
  String get displayName {
    switch (this) {
      case TemplateCategory.meeting:
        return '会议纪要';
      case TemplateCategory.reading:
        return '读书笔记';
      case TemplateCategory.project:
        return '项目计划';
      case TemplateCategory.daily:
        return '每日笔记';
      case TemplateCategory.todo:
        return '待办清单';
      case TemplateCategory.study:
        return '学习笔记';
      case TemplateCategory.research:
        return '研究记录';
      case TemplateCategory.other:
        return '其他';
    }
  }

  String get icon {
    switch (this) {
      case TemplateCategory.meeting:
        return 'groups';
      case TemplateCategory.reading:
        return 'menu_book';
      case TemplateCategory.project:
        return 'assignment';
      case TemplateCategory.daily:
        return 'calendar_today';
      case TemplateCategory.todo:
        return 'checklist';
      case TemplateCategory.study:
        return 'school';
      case TemplateCategory.research:
        return 'science';
      case TemplateCategory.other:
        return 'description';
    }
  }
}
