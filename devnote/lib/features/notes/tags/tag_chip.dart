import 'package:flutter/material.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';

class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.tag,
    this.onTap,
    this.onDelete,
    this.isSelected = false,
  });

  final TagModel tag;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Chip(
        label: Text(tag.name),
        labelStyle: TextStyle(
          fontSize: 12,
          color: isSelected
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        side: isSelected
            ? BorderSide.none
            : BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
        deleteIcon: onDelete != null
            ? Icon(Icons.close, size: 14, color: isSelected ? Theme.of(context).colorScheme.onPrimary : null)
            : null,
        onDeleted: onDelete,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
