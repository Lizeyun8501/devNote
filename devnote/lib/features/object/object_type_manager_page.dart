import 'package:flutter/material.dart';
import 'package:devnote/core/di/injection.dart';
import 'package:devnote/features/object/object_service.dart';

class ObjectTypeManagerPage extends StatefulWidget {
  const ObjectTypeManagerPage({super.key});

  @override
  State<ObjectTypeManagerPage> createState() => _ObjectTypeManagerPageState();
}

class _ObjectTypeManagerPageState extends State<ObjectTypeManagerPage> {
  final ObjectService _service = getIt<ObjectService>();
  List<ObjectTypeModel> _objectTypes = [];

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final types = await _service.listObjectTypes();
    setState(() {
      _objectTypes = types;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('对象类型管理'),
      ),
      body: _objectTypes.isEmpty
          ? const Center(child: Text('暂无对象类型'))
          : ListView.builder(
              itemCount: _objectTypes.length,
              itemBuilder: (context, index) {
                final type = _objectTypes[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Text(type.icon, style: const TextStyle(fontSize: 24)),
                    title: Text(type.name),
                    subtitle: Text('${type.properties.length} 个属性, ${type.relations.length} 个关系'),
                    trailing: PopupMenuButton(
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                      onSelected: (value) {
                        if (value == 'edit') {
                          _showEditDialog(type);
                        } else if (value == 'delete') {
                          _deleteType(type.id);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateDialog() {
    final nameController = TextEditingController();
    final iconController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建对象类型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '名称')),
            const SizedBox(height: 8),
            TextField(controller: iconController, decoration: const InputDecoration(labelText: '图标 (emoji)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await _service.createObjectType(nameController.text, iconController.text, []);
              if (ctx.mounted) Navigator.of(ctx).pop();
              _loadTypes();
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(ObjectTypeModel type) {
    final nameController = TextEditingController(text: type.name);
    final iconController = TextEditingController(text: type.icon);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑对象类型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '名称')),
            const SizedBox(height: 8),
            TextField(controller: iconController, decoration: const InputDecoration(labelText: '图标 (emoji)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await _service.updateObjectType(type.id, nameController.text, iconController.text);
              if (ctx.mounted) Navigator.of(ctx).pop();
              _loadTypes();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteType(String typeId) async {
    await _service.deleteObjectType(typeId);
    _loadTypes();
  }
}
