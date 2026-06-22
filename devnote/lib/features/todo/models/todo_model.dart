/// 待办优先级
enum TodoPriority {
  none,     // 无
  low,      // 低
  medium,   // 中
  high,     // 高
  urgent,   // 紧急
}

extension TodoPriorityExtension on TodoPriority {
  int get value {
    switch (this) {
      case TodoPriority.none: return 0;
      case TodoPriority.low: return 1;
      case TodoPriority.medium: return 2;
      case TodoPriority.high: return 3;
      case TodoPriority.urgent: return 4;
    }
  }

  String get label {
    switch (this) {
      case TodoPriority.none: return '无';
      case TodoPriority.low: return '低';
      case TodoPriority.medium: return '中';
      case TodoPriority.high: return '高';
      case TodoPriority.urgent: return '紧急';
    }
  }

  int get color => switch (this) {
    TodoPriority.none => 0xFF9E9E9E,
    TodoPriority.low => 0xFF4CAF50,
    TodoPriority.medium => 0xFFFF9800,
    TodoPriority.high => 0xFFFF5722,
    TodoPriority.urgent => 0xFFF44336,
  };
}

/// 重复规则
enum TodoRepeat {
  none,       // 不重复
  daily,      // 每天
  weekly,     // 每周
  monthly,    // 每月
  yearly,     // 每年
  weekdays,   // 工作日
  weekends,   // 周末
}

extension TodoRepeatExtension on TodoRepeat {
  String get label {
    switch (this) {
      case TodoRepeat.none: return '不重复';
      case TodoRepeat.daily: return '每天';
      case TodoRepeat.weekly: return '每周';
      case TodoRepeat.monthly: return '每月';
      case TodoRepeat.yearly: return '每年';
      case TodoRepeat.weekdays: return '工作日';
      case TodoRepeat.weekends: return '周末';
    }
  }
}

/// 待办项
class TodoItem {
  final String id;
  final String title;
  final String? description;
  final String? noteId;        // 关联的笔记 ID
  final String? blockId;       // 关联的块 ID
  final bool completed;
  final DateTime? dueDate;     // 到期时间
  final DateTime? reminderTime; // 提醒时间
  final TodoPriority priority;
  final TodoRepeat repeat;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? updatedAt;

  TodoItem({
    required this.id,
    required this.title,
    this.description,
    this.noteId,
    this.blockId,
    this.completed = false,
    this.dueDate,
    this.reminderTime,
    this.priority = TodoPriority.none,
    this.repeat = TodoRepeat.none,
    this.tags = const [],
    DateTime? createdAt,
    this.completedAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  TodoItem copyWith({
    String? title,
    String? description,
    bool? completed,
    DateTime? dueDate,
    DateTime? reminderTime,
    TodoPriority? priority,
    TodoRepeat? repeat,
    List<String>? tags,
    DateTime? completedAt,
    DateTime? updatedAt,
    bool clearDueDate = false,
    bool clearReminder = false,
    bool clearCompleted = false,
  }) => TodoItem(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    noteId: noteId,
    blockId: blockId,
    completed: completed ?? this.completed,
    dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    reminderTime: clearReminder ? null : (reminderTime ?? this.reminderTime),
    priority: priority ?? this.priority,
    repeat: repeat ?? this.repeat,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
    updatedAt: updatedAt ?? DateTime.now(),
  );

  /// 是否已过期
  bool get isOverdue {
    if (dueDate == null || completed) return false;
    return dueDate!.isBefore(DateTime.now());
  }

  /// 是否今天到期
  bool get isDueToday {
    if (dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.year == now.year &&
        dueDate!.month == now.month &&
        dueDate!.day == now.day;
  }

  /// 计算下一次重复的到期时间
  DateTime? get nextRepeatDate {
    if (repeat == TodoRepeat.none || dueDate == null) return null;

    final now = DateTime.now();
    DateTime next = dueDate!;

    while (next.isBefore(now)) {
      next = _advanceByRepeat(next);
    }

    return next;
  }

  DateTime _advanceByRepeat(DateTime date) {
    switch (repeat) {
      case TodoRepeat.none:
        return date;
      case TodoRepeat.daily:
        return date.add(const Duration(days: 1));
      case TodoRepeat.weekly:
        return date.add(const Duration(days: 7));
      case TodoRepeat.monthly:
        return DateTime(date.year, date.month + 1, date.day, date.hour, date.minute);
      case TodoRepeat.yearly:
        return DateTime(date.year + 1, date.month, date.day, date.hour, date.minute);
      case TodoRepeat.weekdays:
        final next = date.add(const Duration(days: 1));
        // 跳过周末
        if (next.weekday == DateTime.saturday) {
          return next.add(const Duration(days: 2));
        } else if (next.weekday == DateTime.sunday) {
          return next.add(const Duration(days: 1));
        }
        return next;
      case TodoRepeat.weekends:
        final next = date.add(const Duration(days: 1));
        // 跳过工作日
        if (next.weekday >= DateTime.monday && next.weekday <= DateTime.friday) {
          // 找到下一个周六
          return next.add(Duration(days: DateTime.saturday - next.weekday));
        }
        return next;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'note_id': noteId,
    'block_id': blockId,
    'completed': completed,
    'due_date': dueDate?.toIso8601String(),
    'reminder_time': reminderTime?.toIso8601String(),
    'priority': priority.value,
    'repeat': repeat.name,
    'tags': tags,
    'created_at': createdAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    noteId: json['note_id'] as String?,
    blockId: json['block_id'] as String?,
    completed: json['completed'] as bool? ?? false,
    dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
    reminderTime: json['reminder_time'] != null
        ? DateTime.parse(json['reminder_time'] as String)
        : null,
    priority: TodoPriority.values.firstWhere(
      (p) => p.value == (json['priority'] as num?)?.toInt(),
      orElse: () => TodoPriority.none,
    ),
    repeat: TodoRepeat.values.byName(json['repeat'] as String? ?? 'none'),
    tags: (json['tags'] as List? ?? []).map((e) => e as String).toList(),
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.now(),
    completedAt: json['completed_at'] != null
        ? DateTime.parse(json['completed_at'] as String)
        : null,
    updatedAt: json['updated_at'] != null
        ? DateTime.parse(json['updated_at'] as String)
        : null,
  );
}
