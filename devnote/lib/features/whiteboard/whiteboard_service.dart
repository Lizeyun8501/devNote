import 'package:shared_preferences/shared_preferences.dart';
import 'package:devnote/features/whiteboard/models/whiteboard_element.dart';

/// 白板持久化服务 —— 使用 SharedPreferences 按 noteId 存储白板 JSON
///
/// key 格式：`whiteboard_$noteId`
/// value：WhiteboardSerializer.encode(elements) 输出的 JSON 字符串
class WhiteboardService {
  static const String _keyPrefix = 'whiteboard_';

  /// 保存白板元素到本地存储
  Future<void> saveWhiteboard(
      String noteId, List<WhiteboardElement> elements) async {
    final prefs = await SharedPreferences.getInstance();
    final json = WhiteboardSerializer.encode(elements);
    await prefs.setString('$_keyPrefix$noteId', json);
  }

  /// 从本地存储加载白板元素
  Future<List<WhiteboardElement>> loadWhiteboard(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_keyPrefix$noteId') ?? '';
    if (json.isEmpty) return const [];
    return WhiteboardSerializer.decode(json);
  }

  /// 删除指定笔记的白板数据
  Future<void> deleteWhiteboard(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$noteId');
  }

  /// 序列化元素列表为 JSON 字符串（不写入存储）
  String exportToJson(List<WhiteboardElement> elements) {
    return WhiteboardSerializer.encode(elements);
  }

  /// 从 JSON 字符串反序列化为元素列表
  List<WhiteboardElement> importFromJson(String jsonString) {
    return WhiteboardSerializer.decode(jsonString);
  }
}
