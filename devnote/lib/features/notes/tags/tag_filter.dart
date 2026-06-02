import 'package:flutter/material.dart';
import 'package:devnote/core/persistence/models/tag_model.dart';
import 'package:devnote/features/notes/tags/tag_chip.dart';

class TagFilter extends StatelessWidget {
  const TagFilter({
    super.key,
    required this.tags,
    this.selectedTagId,
    this.onTagSelected,
  });

  final List<TagModel> tags;
  final String? selectedTagId;
  final ValueChanged<String?>? onTagSelected;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        FilterChip(
          label: const Text('全部'),
          selected: selectedTagId == null,
          onSelected: (_) => onTagSelected?.call(null),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        ...tags.map((tag) => TagChip(
              tag: tag,
              isSelected: selectedTagId == tag.id,
              onTap: () => onTagSelected?.call(tag.id),
            )),
      ],
    );
  }
}
