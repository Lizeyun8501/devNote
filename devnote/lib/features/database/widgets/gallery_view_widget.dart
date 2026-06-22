// Gallery（画廊）视图 —— 以卡片网格形式展示数据库记录
// 借鉴 Notion 的 Gallery 视图设计
// 来源: https://www.notion.so
// 借鉴内容: 卡片网格布局、封面图片展示、字段预览、新建按钮

import 'package:flutter/material.dart';
import 'package:devnote/features/database/bloc/database_state.dart';

/// Gallery（画廊）视图
/// 以卡片网格形式展示数据库记录，每张卡片显示记录的封面图片和关键字段
class GalleryViewWidget extends StatelessWidget {
  final List<DatabaseRowModel> records;
  final List<DatabaseFieldModel> fields;
  final String? coverFieldId; // 封面图片字段 ID
  final String? titleFieldId; // 标题字段 ID
  final Function(String recordId)? onRecordTap;
  final Function(String recordId)? onRecordLongPress;
  final VoidCallback? onAddRecord;

  const GalleryViewWidget({
    super.key,
    required this.records,
    required this.fields,
    this.coverFieldId,
    this.titleFieldId,
    this.onRecordTap,
    this.onRecordLongPress,
    this.onAddRecord,
  });

  /// 从行中获取指定字段的值
  dynamic _getCellValue(DatabaseRowModel record, String? fieldId) {
    if (fieldId == null) return null;
    final cell = record.cells.where((c) => c.fieldId == fieldId).firstOrNull;
    return cell?.value;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: records.length + 1, // +1 为添加按钮
      itemBuilder: (context, index) {
        if (index == records.length) {
          return _buildAddCard(context);
        }
        return _buildRecordCard(context, records[index]);
      },
    );
  }

  Widget _buildAddCard(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAddRecord,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.39),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 8),
              Text(
                '新建',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordCard(BuildContext context, DatabaseRowModel record) {
    final coverUrl = _getCellValue(record, coverFieldId);
    final title = _getCellValue(record, titleFieldId)?.toString() ?? '未命名';

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () => onRecordTap?.call(record.id),
        onLongPress: () => onRecordLongPress?.call(record.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图片
            if (coverUrl != null && coverUrl.toString().isNotEmpty)
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage(coverUrl.toString()),
                      fit: BoxFit.cover,
                      onError: (_, __) {},
                    ),
                  ),
                ),
              )
            else
              Expanded(
                flex: 3,
                child: Container(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: const Center(
                    child: Icon(Icons.note, size: 40),
                  ),
                ),
              ),
            // 标题和字段
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 显示前 2 个非封面/标题字段
                    ..._buildFieldPreview(context, record),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFieldPreview(BuildContext context, DatabaseRowModel record) {
    final previewFields = fields
        .where((f) => f.id != coverFieldId && f.id != titleFieldId)
        .take(2)
        .toList();

    return previewFields.map((field) {
      final value = _getCellValue(record, field.id);
      if (value == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Text(
              '${field.name}: ',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            Expanded(
              child: Text(
                value.toString(),
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
