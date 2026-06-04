import 'package:flutter/material.dart';

class TableBlockWidget extends StatefulWidget {
  final String content;
  final ValueChanged<String> onContentChanged;

  const TableBlockWidget({
    super.key,
    required this.content,
    required this.onContentChanged,
  });

  @override
  State<TableBlockWidget> createState() => _TableBlockWidgetState();
}

class _TableBlockWidgetState extends State<TableBlockWidget> {
  late List<String> _headers;
  late List<List<String>> _rows;
  late List<_Alignment> _alignments;

  @override
  void initState() {
    super.initState();
    _parseTable();
  }

  @override
  void didUpdateWidget(covariant TableBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _parseTable();
    }
  }

  void _parseTable() {
    final lines = widget.content.split('\n');
    if (lines.length < 2) {
      _headers = ['Column'];
      _rows = [[]];
      _alignments = [_Alignment.left];
      return;
    }

    _headers = _parseRow(lines[0]);
    _alignments = _parseAlignments(lines[1]);
    _rows = [];

    for (var i = 2; i < lines.length; i++) {
      final row = _parseRow(lines[i]);
      if (row.isNotEmpty) {
        while (row.length < _headers.length) {
          row.add('');
        }
        _rows.add(row);
      }
    }

    while (_alignments.length < _headers.length) {
      _alignments.add(_Alignment.left);
    }
  }

  List<String> _parseRow(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) return [];
    final inner = trimmed.substring(1, trimmed.length - 1);
    return inner.split('|').map((c) => c.trim()).toList();
  }

  List<_Alignment> _parseAlignments(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) return [];
    final inner = trimmed.substring(1, trimmed.length - 1);
    return inner.split('|').map((c) {
      final cell = c.trim();
      if (cell.startsWith(':') && cell.endsWith(':')) return _Alignment.center;
      if (cell.endsWith(':')) return _Alignment.right;
      return _Alignment.left;
    }).toList();
  }

  String _serializeTable() {
    final buffer = StringBuffer();
    buffer.write('| ${_headers.join(' | ')} |');
    buffer.writeln();
    final sepCells = _alignments.map((a) {
      switch (a) {
        case _Alignment.left:
          return '---';
        case _Alignment.center:
          return ':---:';
        case _Alignment.right:
          return '---:';
      }
    }).toList();
    buffer.write('| ${sepCells.join(' | ')} |');
    buffer.writeln();
    for (final row in _rows) {
      buffer.write('| ${row.join(' | ')} |');
      if (row != _rows.last) buffer.writeln();
    }
    return buffer.toString();
  }

  void _addRow() {
    setState(() {
      _rows.add(List.filled(_headers.length, ''));
    });
    widget.onContentChanged(_serializeTable());
  }

  void _addColumn() {
    setState(() {
      _headers.add('Column ${_headers.length + 1}');
      _alignments.add(_Alignment.left);
      for (final row in _rows) {
        row.add('');
      }
    });
    widget.onContentChanged(_serializeTable());
  }

  void _deleteRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(index);
    });
    widget.onContentChanged(_serializeTable());
  }

  void _deleteColumn(int index) {
    if (_headers.length <= 1) return;
    setState(() {
      _headers.removeAt(index);
      _alignments.removeAt(index);
      for (final row in _rows) {
        row.removeAt(index);
      }
    });
    widget.onContentChanged(_serializeTable());
  }

  void _updateCell(int row, int col, String value) {
    setState(() {
      _rows[row][col] = value;
    });
    widget.onContentChanged(_serializeTable());
  }

  void _updateHeader(int index, String value) {
    setState(() {
      _headers[index] = value;
    });
    widget.onContentChanged(_serializeTable());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E32) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF2D2D44) : const Color(0xFFE5E7EB),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.table_chart,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Table ${_rows.length}×${_headers.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                tooltip: 'Add Row',
                onPressed: _addRow,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                icon: const Icon(Icons.view_column, size: 16),
                tooltip: 'Add Column',
                onPressed: _addColumn,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildTable(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cellPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final headerBg = isDark ? const Color(0xFF2D2D44) : const Color(0xFFE5E7EB);
    final borderColor = isDark ? const Color(0xFF3D3D55) : const Color(0xFFD1D5DB);

    return Table(
      border: TableBorder.all(color: borderColor, width: 1),
      columnWidths: {
        for (var i = 0; i < _headers.length; i++)
          i: const IntrinsicColumnWidth(),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: headerBg),
          children: [
            for (var i = 0; i < _headers.length; i++)
              GestureDetector(
                onDoubleTap: () => _editHeader(context, i),
                child: Padding(
                  padding: cellPadding,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _headers[i],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _deleteColumn(i),
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        for (var r = 0; r < _rows.length; r++)
          TableRow(
            children: [
              for (var c = 0; c < _headers.length; c++)
                GestureDetector(
                  onDoubleTap: () => _editCell(context, r, c),
                  child: Padding(
                    padding: cellPadding,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _rows[r][c],
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (c == _headers.length - 1)
                          InkWell(
                            onTap: () => _deleteRow(r),
                            child: Icon(
                              Icons.close,
                              size: 12,
                              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  void _editHeader(BuildContext context, int index) {
    final controller = TextEditingController(text: _headers[index]);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Header'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Header text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _updateHeader(index, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editCell(BuildContext context, int row, int col) {
    final controller = TextEditingController(text: _rows[row][col]);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Cell (${row + 1}, ${col + 1})'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Cell content'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _updateCell(row, col, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

enum _Alignment { left, center, right }
