import 'package:flutter/material.dart';
import 'package:devnote/features/object/object_service.dart';
import 'package:devnote/features/object/widgets/object_node_widget.dart';
import 'package:devnote/features/object/widgets/object_edge_widget.dart';

class ObjectGraphPage extends StatefulWidget {
  const ObjectGraphPage({super.key});

  @override
  State<ObjectGraphPage> createState() => _ObjectGraphPageState();
}

class _ObjectGraphPageState extends State<ObjectGraphPage> {
  final ObjectService _service = ObjectService();
  List<ObjectTypeModel> _objectTypes = [];
  List<ObjectModel> _objects = [];
  String? _selectedTypeId;
  Offset _offset = Offset.zero;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<ObjectRelationEntry> _relations = [];

  Future<void> _loadData() async {
    final types = await _service.listObjectTypes();
    final objects = await _service.listObjects(typeId: _selectedTypeId);
    final relations = await _service.allRelations();
    setState(() {
      _objectTypes = types;
      _objects = objects;
      _relations = relations;
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
        title: const Text('对象关系图'),
        actions: [
          PopupMenuButton<String?>(
            onSelected: (value) {
              setState(() {
                _selectedTypeId = value;
              });
              _loadData();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('全部类型')),
              ..._objectTypes.map((t) => PopupMenuItem(value: t.id, child: Text('${t.icon} ${t.name}'))),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        onScaleUpdate: (details) {
          setState(() {
            _scale = (_scale * details.scale).clamp(0.3, 3.0);
            _offset += details.focalPointDelta;
          });
        },
        child: CustomPaint(
          painter: _GraphPainter(
            objects: _objects,
            relations: _relations,
            objectTypes: _objectTypes,
            offset: _offset,
            scale: _scale,
            selectedTypeId: _selectedTypeId,
          ),
          size: Size.infinite,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddObjectDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddObjectDialog() {
    if (_objectTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建对象类型')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加对象'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: '对象类型'),
              items: _objectTypes.map((t) => DropdownMenuItem(value: t.id, child: Text('${t.icon} ${t.name}'))).toList(),
              onChanged: (v) {},
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _loadData();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<ObjectModel> objects;
  final List<dynamic> relations;
  final List<ObjectTypeModel> objectTypes;
  final Offset offset;
  final double scale;
  final String? selectedTypeId;

  _GraphPainter({
    required this.objects,
    required this.relations,
    required this.objectTypes,
    required this.offset,
    required this.scale,
    this.selectedTypeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    final positions = <String, Offset>{};
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 200.0;

    for (var i = 0; i < objects.length; i++) {
      positions[objects[i].id] = Offset(
        center.dx + radius * 1.5 * (i % 5 - 2),
        center.dy + radius * (i ~/ 5),
      );
    }

    for (final rel in relations) {
      final sourcePos = positions[rel.sourceId];
      final targetPos = positions[rel.targetId];
      if (sourcePos != null && targetPos != null) {
        ObjectEdgeWidget.paintEdge(canvas, sourcePos, targetPos);
      }
    }

    for (final obj in objects) {
      final pos = positions[obj.id];
      if (pos != null) {
        final type = objectTypes.where((t) => t.id == obj.objectTypeId).firstOrNull;
        ObjectNodeWidget.paintNode(canvas, pos, obj, type);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
