import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note_template.dart';
import '../builtin_templates.dart';

class TemplateService {
  static const _customTemplatesKey = 'custom_templates';

  /// 获取所有模板（内置 + 自定义）
  Future<List<NoteTemplate>> getAllTemplates() async {
    final builtin = BuiltinTemplates.getAll();
    final custom = await getCustomTemplates();
    return [...builtin, ...custom];
  }

  /// 获取内置模板
  List<NoteTemplate> getBuiltinTemplates() {
    return BuiltinTemplates.getAll();
  }

  /// 获取自定义模板
  Future<List<NoteTemplate>> getCustomTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_customTemplatesKey);
    if (jsonStr == null) return [];
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => NoteTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 保存自定义模板
  Future<void> saveCustomTemplate(NoteTemplate template) async {
    final templates = await getCustomTemplates();
    final index = templates.indexWhere((t) => t.id == template.id);
    if (index >= 0) {
      templates[index] = template;
    } else {
      templates.add(template);
    }
    await _saveCustomTemplates(templates);
  }

  /// 删除自定义模板
  Future<void> deleteCustomTemplate(String templateId) async {
    final templates = await getCustomTemplates();
    templates.removeWhere((t) => t.id == templateId);
    await _saveCustomTemplates(templates);
  }

  /// 从现有笔记创建模板
  Future<NoteTemplate> createTemplateFromNote({
    required String name,
    required String description,
    required TemplateCategory category,
    required List<Map<String, dynamic>> blocksData,
  }) async {
    final template = NoteTemplate(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      category: category,
      isCustom: true,
      createdAt: DateTime.now(),
      blocks: blocksData
          .map((b) => TemplateBlock(
                type: b['type'] as String? ?? 'paragraph',
                content: b['content'] as String? ?? '',
                properties: b['properties'] as Map<String, dynamic>?,
              ))
          .toList(),
    );
    await saveCustomTemplate(template);
    return template;
  }

  Future<void> _saveCustomTemplates(List<NoteTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(templates.map((t) => t.toJson()).toList());
    await prefs.setString(_customTemplatesKey, jsonStr);
  }
}
