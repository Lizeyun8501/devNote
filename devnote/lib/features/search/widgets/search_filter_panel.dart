import 'package:flutter/material.dart';

class SearchFilterPanel extends StatefulWidget {
  final String? selectedFolderId;
  final List<String> selectedTags;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<String?> onFolderChanged;
  final ValueChanged<List<String>> onTagsChanged;
  final ValueChanged<DateTime?> onStartDateChanged;
  final ValueChanged<DateTime?> onEndDateChanged;
  final VoidCallback onReset;

  const SearchFilterPanel({
    super.key,
    this.selectedFolderId,
    this.selectedTags = const [],
    this.startDate,
    this.endDate,
    required this.onFolderChanged,
    required this.onTagsChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.onReset,
  });

  @override
  State<SearchFilterPanel> createState() => _SearchFilterPanelState();
}

class _SearchFilterPanelState extends State<SearchFilterPanel> {
  final List<_FolderOption> _folders = const [
    _FolderOption(id: '1', name: '我的笔记'),
    _FolderOption(id: '2', name: '工作'),
    _FolderOption(id: '3', name: '个人'),
  ];

  final List<String> _availableTags = const ['重要', '待办', '参考', '想法', '项目'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '筛选条件',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              TextButton(
                onPressed: widget.onReset,
                child: const Text('重置'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFolderFilter(context),
          const SizedBox(height: 12),
          _buildTagFilter(context),
          const SizedBox(height: 12),
          _buildDateFilter(context),
        ],
      ),
    );
  }

  Widget _buildFolderFilter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '文件夹',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: widget.selectedFolderId,
          decoration: InputDecoration(
            hintText: '选择文件夹',
            filled: true,
            fillColor: Theme.of(context).inputDecorationTheme.fillColor,
            border: Theme.of(context).inputDecorationTheme.border,
            focusedBorder: Theme.of(context).inputDecorationTheme.focusedBorder,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('全部文件夹'),
            ),
            ..._folders.map((folder) => DropdownMenuItem<String>(
                  value: folder.id,
                  child: Text(folder.name),
                )),
          ],
          onChanged: widget.onFolderChanged,
        ),
      ],
    );
  }

  Widget _buildTagFilter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '标签',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _availableTags.map((tag) {
            final isSelected = widget.selectedTags.contains(tag);
            return FilterChip(
              label: Text(tag),
              selected: isSelected,
              onSelected: (selected) {
                final newTags = List<String>.from(widget.selectedTags);
                if (selected) {
                  newTags.add(tag);
                } else {
                  newTags.remove(tag);
                }
                widget.onTagsChanged(newTags);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDateFilter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '日期范围',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: '开始日期',
                value: widget.startDate,
                onChanged: widget.onStartDateChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DateField(
                label: '结束日期',
                value: widget.endDate,
                onChanged: widget.onEndDateChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _DateField({
    required this.label,
    this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: label,
          filled: true,
          fillColor: Theme.of(context).inputDecorationTheme.fillColor,
          border: Theme.of(context).inputDecorationTheme.border,
          focusedBorder: Theme.of(context).inputDecorationTheme.focusedBorder,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: Text(
          value != null
              ? '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}'
              : label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: value != null ? null : Theme.of(context).hintColor,
              ),
        ),
      ),
    );
  }
}

class _FolderOption {
  final String id;
  final String name;

  const _FolderOption({required this.id, required this.name});
}
