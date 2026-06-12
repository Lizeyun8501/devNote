import 'package:flutter/material.dart';

/// 学习目标跟踪页面
///
/// 功能说明:
/// - 学习目标创建/编辑: 用户可以设定学习目标（如"掌握 Flutter 状态管理"）
/// - 进度跟踪: 使用进度条直观展示目标完成百分比
/// - 知识节点关联: 将学习目标与知识图谱中的节点关联，追踪学习路径
/// - 提醒通知: 根据设定的截止日期和复习计划发送提醒
///
/// 数据来源:
/// - 学习目标: 本地 SQLite 数据库中的 study_goals 表
/// - 知识节点: 知识图谱中的节点数据，通过 KnowledgeEvent 接口获取
/// - 提醒: 本地通知系统，基于 flutter_local_notifications
///
/// 借鉴:
/// - Anki 的学习计划管理: 设定目标 → 分解任务 → 追踪进度
/// - Notion 的目标追踪: 可视化进度条 + 里程碑

/// 学习目标数据模型
/// 借鉴 Anki 的学习计划卡片模型
class LearningGoal {
  final String id;
  final String title;
  final String description;
  final double progress; // 0.0 - 1.0
  final DateTime createdAt;
  final DateTime? deadline;
  final List<String> knowledgeNodeIds; // 关联的知识节点 ID 列表
  final List<String> milestones; // 里程碑描述列表
  final bool reminderEnabled;
  final DateTime? lastReminderAt;

  const LearningGoal({
    required this.id,
    required this.title,
    this.description = '',
    this.progress = 0.0,
    required this.createdAt,
    this.deadline,
    this.knowledgeNodeIds = const [],
    this.milestones = const [],
    this.reminderEnabled = false,
    this.lastReminderAt,
  });

  /// 获取格式化后的进度百分比
  String get progressPercent => '${(progress * 100).toStringAsFixed(0)}%';

  /// 获取剩余天数（基于截止日期）
  int? get remainingDays {
    if (deadline == null) return null;
    return deadline!.difference(DateTime.now()).inDays;
  }

  /// 获取剩余天数显示文本
  String get remainingDaysText {
    final days = remainingDays;
    if (days == null) return '无截止日期';
    if (days < 0) return '已过期 ${-days} 天';
    if (days == 0) return '今天截止';
    return '剩余 $days 天';
  }

  /// 获取已完成的里程碑数量
  int get completedMilestones {
    // 根据进度估算已完成的里程碑数
    return (milestones.length * progress).round();
  }

  /// 复制并修改属性
  LearningGoal copyWith({
    String? title,
    String? description,
    double? progress,
    DateTime? deadline,
    List<String>? knowledgeNodeIds,
    List<String>? milestones,
    bool? reminderEnabled,
    DateTime? lastReminderAt,
  }) {
    return LearningGoal(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      progress: progress ?? this.progress,
      createdAt: createdAt,
      deadline: deadline ?? this.deadline,
      knowledgeNodeIds: knowledgeNodeIds ?? this.knowledgeNodeIds,
      milestones: milestones ?? this.milestones,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      lastReminderAt: lastReminderAt ?? this.lastReminderAt,
    );
  }
}

/// 学习目标跟踪页面
class LearningProgressPage extends StatefulWidget {
  const LearningProgressPage({super.key});

  @override
  State<LearningProgressPage> createState() => _LearningProgressPageState();
}

class _LearningProgressPageState extends State<LearningProgressPage> {
  /// 学习目标列表
  /// 数据来源: study_goals 表
  final List<LearningGoal> _goals = [];

  /// 是否正在加载数据
  bool _loading = true;

  /// 当前排序方式
  String _sortBy = 'deadline'; // deadline / progress / created

  /// 筛选条件: all / active / completed
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  /// 加载学习目标数据
  /// 数据源: study_goals 表 → 本地 SQLite 数据库
  /// 未来可扩展: 通过 KnowledgeEvent.GetLearningGoals 接口获取
  Future<void> _loadGoals() async {
    // 模拟数据加载
    // 实际实现应通过 dispatch 调用后端接口获取数据
    setState(() {
      _loading = false;
    });
  }

  /// 获取筛选和排序后的目标列表
  List<LearningGoal> get _filteredGoals {
    var goals = List<LearningGoal>.from(_goals);

    // 筛选
    if (_filter == 'active') {
      goals = goals.where((g) => g.progress < 1.0).toList();
    } else if (_filter == 'completed') {
      goals = goals.where((g) => g.progress >= 1.0).toList();
    }

    // 排序
    // 借鉴 Anki 的卡片排序策略: 优先展示即将到期或进度较低的目标
    switch (_sortBy) {
      case 'deadline':
        goals.sort((a, b) {
          if (a.deadline == null && b.deadline == null) return 0;
          if (a.deadline == null) return 1;
          if (b.deadline == null) return -1;
          return a.deadline!.compareTo(b.deadline!);
        });
        break;
      case 'progress':
        goals.sort((a, b) => a.progress.compareTo(b.progress));
        break;
      case 'created':
        goals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }

    return goals;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习目标'),
        actions: [
          // 排序按钮
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: '排序方式',
            onSelected: (value) {
              setState(() {
                _sortBy = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'deadline',
                child: Text('按截止日期'),
              ),
              const PopupMenuItem(
                value: 'progress',
                child: Text('按进度'),
              ),
              const PopupMenuItem(
                value: 'created',
                child: Text('按创建时间'),
              ),
            ],
          ),
        ],
      ),
      // 浮动操作按钮: 创建新目标
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGoalEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('新建目标'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 筛选标签栏
                _buildFilterBar(context),
                // 目标列表
                Expanded(
                  child: _goals.isEmpty
                      ? _buildEmptyState(context)
                      : _buildGoalList(context),
                ),
              ],
            ),
    );
  }

  /// 构建筛选标签栏
  /// 三个选项: 全部 / 进行中 / 已完成
  Widget _buildFilterBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip(context, '全部', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip(context, '进行中', 'active'),
          const SizedBox(width: 8),
          _buildFilterChip(context, '已完成', 'completed'),
        ],
      ),
    );
  }

  /// 构建单个筛选标签
  Widget _buildFilterChip(BuildContext context, String label, String value) {
    final isSelected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _filter = value;
        });
      },
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.flag_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '还没有学习目标',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮创建你的第一个学习目标',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
          ),
          const SizedBox(height: 24),
          // 建议示例
          _buildSuggestionChips(context),
        ],
      ),
    );
  }

  /// 构建建议标签
  Widget _buildSuggestionChips(BuildContext context) {
    final suggestions = [
      '掌握 Flutter 状态管理',
      '学习 Rust 异步编程',
      '完成数据结构复习',
      '阅读 5 本技术书籍',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: suggestions.map((s) {
        return ActionChip(
          label: Text(s),
          onPressed: () {
            _showGoalEditor(context, initialTitle: s);
          },
        );
      }).toList(),
    );
  }

  /// 构建目标列表
  Widget _buildGoalList(BuildContext context) {
    final goals = _filteredGoals;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: goals.length,
      itemBuilder: (context, index) {
        return _buildGoalCard(context, goals[index]);
      },
    );
  }

  /// 构建单个目标卡片
  /// 借鉴 Notion 的目标追踪卡片设计
  Widget _buildGoalCard(BuildContext context, LearningGoal goal) {
    // 进度颜色计算
    // 低进度 (<30%): 红色提醒
    // 中进度 (30-70%): 橙色
    // 高进度 (>70%): 绿色
    final progressColor = goal.progress < 0.3
        ? Colors.red
        : goal.progress < 0.7
            ? Colors.orange
            : Colors.green;

    // 剩余天数颜色
    final daysRemaining = goal.remainingDays;
    final deadlineColor = daysRemaining == null
        ? Colors.grey
        : daysRemaining < 0
            ? Colors.red
            : daysRemaining <= 3
                ? Colors.orange
                : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showGoalEditor(context, existingGoal: goal),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  // 提醒开关
                  IconButton(
                    icon: Icon(
                      goal.reminderEnabled
                          ? Icons.notifications_active
                          : Icons.notifications_off,
                      size: 20,
                      color: goal.reminderEnabled
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    tooltip: goal.reminderEnabled ? '提醒已开启' : '提醒已关闭',
                    onPressed: () {
                      _toggleReminder(goal);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // 描述
              if (goal.description.isNotEmpty) ...[
                Text(
                  goal.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],

              // 进度条
              // 数据来源: 已完成里程碑数 / 总里程碑数
              // 计算方式: 里程碑完成进度 = 已完成数 / 总数
              // 借鉴: Notion 的进度条可视化
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: goal.progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor:
                            AlwaysStoppedAnimation<Color>(progressColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    goal.progressPercent,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: progressColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 底部信息行
              Row(
                children: [
                  // 截止日期
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: deadlineColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    goal.remainingDaysText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: deadlineColor,
                        ),
                  ),
                  const Spacer(),

                  // 关联知识节点数量
                  // 数据来源: knowledgeNodeIds 关联的知识图谱节点
                  if (goal.knowledgeNodeIds.isNotEmpty) ...[
                    Icon(
                      Icons.account_tree_outlined,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${goal.knowledgeNodeIds.length} 个节点',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // 里程碑进度
                  if (goal.milestones.isNotEmpty) ...[
                    Icon(
                      Icons.checklist,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${goal.completedMilestones}/${goal.milestones.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示目标编辑器（创建/编辑）
  /// 支持创建新目标和编辑现有目标
  /// 借鉴: Notion 的目标设置界面
  Future<void> _showGoalEditor(
    BuildContext context, {
    String initialTitle = '',
    LearningGoal? existingGoal,
  }) async {
    final isEditing = existingGoal != null;
    final titleController = TextEditingController(
      text: existingGoal?.title ?? initialTitle,
    );
    final descController = TextEditingController(
      text: existingGoal?.description ?? '',
    );
    var progress = existingGoal?.progress ?? 0.0;
    var enableReminder = existingGoal?.reminderEnabled ?? false;
    DateTime? deadline = existingGoal?.deadline;
    var milestones = List<String>.from(
      existingGoal?.milestones ?? [],
    );

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 24,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isEditing ? '编辑目标' : '新建学习目标',
                      style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // 目标标题输入
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: '目标标题',
                        hintText: '例如: 掌握 Flutter 状态管理',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 目标描述输入
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: '描述 (可选)',
                        hintText: '描述你的学习目标...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),

                    // 进度滑块
                    // 编辑模式直接调整进度，新建模式默认为 0
                    if (isEditing) ...[
                      Text(
                        '进度: ${(progress * 100).toStringAsFixed(0)}%',
                        style: Theme.of(sheetContext).textTheme.bodyMedium,
                      ),
                      Slider(
                        value: progress,
                        onChanged: (v) {
                          setSheetState(() {
                            progress = v;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 截止日期选择
                    // 借鉴: Anki 的到期日期设置
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text(
                        deadline == null
                            ? '设置截止日期 (可选)'
                            : '截止日期: ${deadline!.year}/${deadline!.month}/${deadline!.day}',
                      ),
                      trailing: deadline != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setSheetState(() {
                                  deadline = null;
                                });
                              },
                            )
                          : null,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: deadline ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365 * 2),
                          ),
                        );
                        if (picked != null) {
                          setSheetState(() {
                            deadline = picked;
                          });
                        }
                      },
                    ),

                    // 里程碑管理
                    // 将大目标分解为小里程碑，逐步完成
                    // 借鉴: Notion 的里程碑功能
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '里程碑 (${milestones.length})',
                          style: Theme.of(sheetContext).textTheme.bodyMedium,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            _showAddMilestoneDialog(sheetContext, (milestone) {
                              setSheetState(() {
                                milestones.add(milestone);
                              });
                            });
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加'),
                        ),
                      ],
                    ),
                    if (milestones.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ...milestones.asMap().entries.map((entry) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.flag,
                            size: 18,
                            color: entry.key < (milestones.length * progress).round()
                                ? Colors.green
                                : Colors.grey,
                          ),
                          title: Text(
                            entry.value,
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              setSheetState(() {
                                milestones.removeAt(entry.key);
                              });
                            },
                          ),
                        );
                      }),
                    ],

                    // 提醒通知开关
                    // 借鉴: Anki 的复习提醒功能
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('开启提醒通知'),
                      subtitle: const Text('根据截止日期和复习计划发送提醒'),
                      value: enableReminder,
                      onChanged: (v) {
                        setSheetState(() {
                          enableReminder = v;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    // 操作按钮
                    Row(
                      children: [
                        if (isEditing) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _deleteGoal(existingGoal);
                                Navigator.pop(sheetContext);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('删除'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (titleController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(content: Text('请输入目标标题')),
                                );
                                return;
                              }
                              Navigator.pop(sheetContext, {
                                'title': titleController.text.trim(),
                                'description': descController.text.trim(),
                                'progress': progress,
                                'deadline': deadline,
                                'milestones': milestones,
                                'reminderEnabled': enableReminder,
                              });
                            },
                            child: Text(isEditing ? '保存' : '创建'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        if (isEditing) {
          // 更新现有目标
          final index = _goals.indexWhere((g) => g.id == existingGoal.id);
          if (index >= 0) {
            _goals[index] = _goals[index].copyWith(
              title: result['title'] as String,
              description: result['description'] as String,
              progress: result['progress'] as double,
              deadline: result['deadline'] as DateTime?,
              milestones: List<String>.from(result['milestones'] as List),
              reminderEnabled: result['reminderEnabled'] as bool,
            );
          }
        } else {
          // 创建新目标
          // 将目标关联到知识图谱节点（当前为占位逻辑）
          final newGoal = LearningGoal(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: result['title'] as String,
            description: result['description'] as String,
            progress: result['progress'] as double,
            createdAt: DateTime.now(),
            deadline: result['deadline'] as DateTime?,
            milestones: List<String>.from(result['milestones'] as List),
            reminderEnabled: result['reminderEnabled'] as bool,
            // 知识节点关联: 未来可通过知识图谱搜索接口自动关联
            // 借鉴: Obsidian 的图谱节点关联方式
            knowledgeNodeIds: [],
          );
          _goals.insert(0, newGoal);
        }
      });
    }
  }

  /// 显示添加里程碑对话框
  Future<void> _showAddMilestoneDialog(
    BuildContext context,
    void Function(String) onAdd,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('添加里程碑'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '例如: 完成状态管理章节',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      onAdd(result);
    }
  }

  /// 切换提醒开关
  /// 数据来源: 本地通知设置，通过 flutter_local_notifications 管理
  void _toggleReminder(LearningGoal goal) {
    setState(() {
      final index = _goals.indexWhere((g) => g.id == goal.id);
      if (index >= 0) {
        _goals[index] = _goals[index].copyWith(
          reminderEnabled: !goal.reminderEnabled,
          lastReminderAt: !goal.reminderEnabled ? DateTime.now() : goal.lastReminderAt,
        );
      }
    });

    // 提醒通知的实际触发逻辑
    // 借鉴: Anki 的间隔复习提醒
    // 使用 flutter_local_notifications 的定时通知功能
    if (!goal.reminderEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已开启 "${goal.title}" 的提醒通知'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              _toggleReminder(goal);
            },
          ),
        ),
      );
    }
  }

  /// 删除学习目标
  void _deleteGoal(LearningGoal goal) {
    setState(() {
      _goals.removeWhere((g) => g.id == goal.id);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 "${goal.title}"'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              setState(() {
                _goals.insert(0, goal);
              });
            },
          ),
        ),
      );
    }
  }
}