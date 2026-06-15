/// 冲突解决器（Conflict Resolver）
///
/// 在多端同步过程中，本地与远端的同一笔记块可能产生内容冲突（如双端同时编辑、
/// 一端移动/删除而另一端修改等），本类提供对这些冲突的检测、分类与解决能力，
/// 并支持自动 / 手动 / 偏好策略三种解决路径。
///
/// ## 借鉴的开源项目
/// - **Git** ([官网](https://git-scm.com/)): 借鉴其 **三方合并（Three-way Merge）** 算法思想，
///   通过 `local`（本地）/ `remote`（远端）/ `base`（共同祖先）三方内容对比生成合并结果；
///   本类中 `mergeWithCrdt` 的策略与之同源：能自动合则自动合，不能合则进入 `manualRequired`。
/// - **Yjs / CRDT 理论** ([GitHub](https://github.com/yjs/yjs)): 借鉴 CRDT（Conflict-free
///   Replicated Data Type）协同编辑理论中的"无冲突复制数据类型"思想；
///   本类中 `_tryAutoMerge` 在 `contentConflict` 时对两端内容进行等价比较，本质上是一种
///   简化的基于 Operation Transform（OT）的合并结果判断。
/// - **Google Docs** ([说明](https://workspace.google.com/resources/learning/collaboration/)): 借鉴其
///   "冲突解决策略（Conflict Resolution Strategy）"分类：auto / preferLocal / preferRemote / manual，
///   允许用户按场景选择不同的合并倾向，同时将"无法自动解决"的冲突以 UI 高亮形式交由用户决定。
///
/// ## 实现说明
/// - `ConflictType` 区分三类冲突：
///   1. `contentConflict`: 双端都修改了内容（最常见）。
///   2. `moveConflict`: 一端移动块而另一端修改内容。
///   3. `deleteModifyConflict`: 一端删除而另一端修改（最危险，需要人工介入）。
/// - `MergeStrategy` 提供四类策略：auto / preferLocal / preferRemote / manual。
/// - 内部 `_resolutions` Map 以 `blockId` 为 key，记录每个冲突块的最终内容。
/// - `computeDiff` 提供简单的逐行 Diff（equal / added / removed），用于在 `DiffViewer` 中展示。
library;

/// 冲突类型枚举
///
/// 借鉴 Google Docs 的冲突分类：内容冲突、位置冲突、删除-修改冲突。
enum ConflictType {
  /// 双方均修改了同一块的内容（最常见）
  contentConflict,
  /// 一端移动块位置、另一端修改内容
  moveConflict,
  /// 一端删除块、另一端修改了块内容（不可自动解决）
  deleteModifyConflict,
}

/// 冲突信息数据模型
///
/// 借鉴 Git 的"冲突块（Conflict Block）"概念：将一次冲突所需的全部信息（双方内容、
/// 双方操作 ID、冲突类型）聚合为一个不可变值对象，便于在 UI / 网络层传递。
class ConflictInfo {
  /// 冲突所在块（block）的唯一 ID
  final String blockId;
  /// 本地内容
  final String localContent;
  /// 远端内容
  final String remoteContent;
  /// 本地操作 ID（用于 CRDT 回溯 / 操作日志）
  final String localOperationId;
  /// 远端操作 ID（用于 CRDT 回溯 / 操作日志）
  final String remoteOperationId;
  /// 冲突类型
  final ConflictType conflictType;

  const ConflictInfo({
    required this.blockId,
    required this.localContent,
    required this.remoteContent,
    required this.localOperationId,
    required this.remoteOperationId,
    required this.conflictType,
  });

  /// 从 JSON 反序列化（用于跨语言桥接 / 网络层传输）
  factory ConflictInfo.fromJson(Map<String, dynamic> json) {
    return ConflictInfo(
      blockId: json['block_id'] as String,
      localContent: json['local_content'] as String,
      remoteContent: json['remote_content'] as String,
      localOperationId: json['local_operation_id'] as String,
      remoteOperationId: json['remote_operation_id'] as String,
      conflictType: _parseConflictType(json['conflict_type'] as String),
    );
  }

  /// 将字符串类型的冲突类型反序列化为枚举
  static ConflictType _parseConflictType(String type) {
    switch (type) {
      case 'ContentConflict':
        return ConflictType.contentConflict;
      case 'MoveConflict':
        return ConflictType.moveConflict;
      case 'DeleteModifyConflict':
        return ConflictType.deleteModifyConflict;
      default:
        return ConflictType.contentConflict;
    }
  }
}

/// 冲突解决策略枚举
///
/// 借鉴 Google Docs 的冲突解决选项：自动 / 偏好本地 / 偏好远端 / 手动。
enum MergeStrategy {
  /// 尝试自动解决（依赖 `_tryAutoMerge`）
  auto,
  /// 总是选择本地版本
  preferLocal,
  /// 总是选择远端版本
  preferRemote,
  /// 不自动解决，留给用户手动处理
  manual,
}

/// 冲突解决器
///
/// 提供冲突的注册、批量自动合并、策略化解决与差异计算能力。
///
/// ## 借鉴的开源项目
/// - **Git** ([官网](https://git-scm.com/)): 三方合并（three-way merge）思想。
/// - **Yjs / CRDT** ([GitHub](https://github.com/yjs/yjs)): 协同编辑无冲突理论。
/// - **Google Docs** ([说明](https://workspace.google.com/)): 冲突解决策略分类。
class ConflictResolver {
  /// 内部维护的待解决冲突列表
  final List<ConflictInfo> _conflicts = [];
  /// 内部维护的解决结果表（key: blockId, value: 最终内容）
  final Map<String, String> _resolutions = {};

  /// 对外暴露的冲突列表（只读）
  List<ConflictInfo> get conflicts => List.unmodifiable(_conflicts);
  /// 对外暴露的解决结果表（只读）
  Map<String, String> get resolutions => Map.unmodifiable(_resolutions);
  /// 是否存在未解决的冲突
  bool get hasConflicts => _conflicts.isNotEmpty;
  /// 是否所有冲突都已得到解决
  bool get allResolved =>
      _conflicts.every((c) => _resolutions.containsKey(c.blockId));

  /// 批量注册待解决的冲突
  void addConflicts(List<ConflictInfo> conflicts) {
    _conflicts.addAll(conflicts);
  }

  /// 清空所有冲突与已记录的解决结果
  void clear() {
    _conflicts.clear();
    _resolutions.clear();
  }

  /// 使用 CRDT / 自动合并策略对一组冲突进行批量合并
  ///
  /// 借鉴 CRDT（Yjs）的"无冲突合并"思想：
  /// - 对于可确定的合并（移动冲突、内容等价的内容冲突）直接写入 `_resolutions`。
  /// - 对于不可自动合并（如 `deleteModifyConflict`、内容不一致的 `contentConflict`）
  ///   保留在 `_conflicts` 列表中，等待用户手动解决。
  ///
  /// **算法来源**:
  /// - Yjs / CRDT 协同编辑理论 ([GitHub](https://github.com/yjs/yjs))
  /// - Git 三方合并思想 ([git-scm.com](https://git-scm.com/))
  MergeResult mergeWithCrdt(List<ConflictInfo> conflicts) {
    final autoResolved = <ConflictInfo>[];
    final manualRequired = <ConflictInfo>[];

    for (final conflict in conflicts) {
      final result = _tryAutoMerge(conflict);
      if (result != null) {
        _resolutions[conflict.blockId] = result;
        autoResolved.add(conflict);
      } else {
        manualRequired.add(conflict);
      }
    }

    // 修复：只添加未在 _conflicts 中的冲突，避免重复添加
    // 原代码直接 _conflicts.addAll(manualRequired)，如果同一冲突
    // 被 mergeWithCrdt 调用多次，会导致 _conflicts 中出现重复条目
    for (final conflict in manualRequired) {
      if (!_conflicts.any((c) => c.blockId == conflict.blockId)) {
        _conflicts.add(conflict);
      }
    }

    return MergeResult(
      autoResolved: autoResolved,
      manualRequired: manualRequired,
    );
  }

  /// 尝试对单个冲突进行自动合并
  ///
  /// 借鉴 Git 的"自动合并（auto-merge）"判定逻辑：
  /// - `moveConflict`: 一端移动了位置而另一端未移动，则接受移动后的位置（取远端内容）。
  /// - `deleteModifyConflict`: 删除-修改冲突无法自动判定，必须由用户介入。
  /// - `contentConflict`: 若两端内容去除首尾空白后完全相同，则视为等价，取其一；
  ///   否则交给用户手动合并。
  String? _tryAutoMerge(ConflictInfo conflict) {
    switch (conflict.conflictType) {
      case ConflictType.moveConflict:
        // 移动冲突：以远端位置为准
        return conflict.remoteContent;
      case ConflictType.deleteModifyConflict:
        // 删除-修改冲突：必须人工介入
        return null;
      case ConflictType.contentConflict:
        // 内容冲突：若两端去除空白后等价，则视为一致
        if (conflict.localContent.trim() == conflict.remoteContent.trim()) {
          return conflict.localContent;
        }
        return null;
    }
  }

  /// 手动指定某个冲突块的最终内容
  void resolveConflict(String blockId, String resolvedContent) {
    _resolutions[blockId] = resolvedContent;
  }

  /// 按指定策略批量解决所有尚未解决的冲突
  ///
  /// 借鉴 Google Docs 的策略化解决：用户可一次性选择"以本地为准"或"以远端为准"，
  /// 也可以选择"自动"让系统尝试合并，或保持 `manual` 不做任何处理。
  void resolveAll(MergeStrategy strategy) {
    for (final conflict in _conflicts) {
      if (!_resolutions.containsKey(conflict.blockId)) {
        switch (strategy) {
          case MergeStrategy.preferLocal:
            _resolutions[conflict.blockId] = conflict.localContent;
            break;
          case MergeStrategy.preferRemote:
            _resolutions[conflict.blockId] = conflict.remoteContent;
            break;
          case MergeStrategy.auto:
            final result = _tryAutoMerge(conflict);
            if (result != null) {
              _resolutions[conflict.blockId] = result;
            }
            break;
          case MergeStrategy.manual:
            break;
        }
      }
    }
  }

  /// 计算两份文本之间的逐行差异
  ///
  /// 实现为最朴素的逐行 LCS-free 对齐：相同行 -> `equal`，本地有 / 远端无 -> `removed`，
  /// 远端有 / 本地无 -> `added`。该方法在 `DiffViewer` 中以双栏并排视图呈现。
  ///
  /// 注：真正的协同编辑场景下可替换为 Myers Diff（`git diff` 所用算法）以获得更优 diff。
  List<DiffLine> computeDiff(String local, String remote) {
    final localLines = local.split('\n');
    final remoteLines = remote.split('\n');
    final diffLines = <DiffLine>[];

    final maxLen = localLines.length > remoteLines.length
        ? localLines.length
        : remoteLines.length;

    for (var i = 0; i < maxLen; i++) {
      final localLine = i < localLines.length ? localLines[i] : null;
      final remoteLine = i < remoteLines.length ? remoteLines[i] : null;

      if (localLine == remoteLine) {
        diffLines.add(DiffLine(
          type: DiffType.equal,
          localLine: localLine,
          remoteLine: remoteLine,
          lineNumber: i + 1,
        ));
      } else {
        if (localLine != null) {
          diffLines.add(DiffLine(
            type: DiffType.removed,
            localLine: localLine,
            remoteLine: null,
            lineNumber: i + 1,
          ));
        }
        if (remoteLine != null) {
          diffLines.add(DiffLine(
            type: DiffType.added,
            localLine: null,
            remoteLine: remoteLine,
            lineNumber: i + 1,
          ));
        }
      }
    }

    return diffLines;
  }
}

/// 差异行类型
///
/// 借鉴 Git `diff` 输出中的行类型：相同 / 新增 / 删除。
enum DiffType {
  /// 两端内容相同
  equal,
  /// 仅远端存在的行（远端新增 / 本地未变）
  added,
  /// 仅本地存在的行（本地有但远端已删除 / 未同步）
  removed,
}

/// 单行差异的不可变数据模型
class DiffLine {
  /// 差异类型（equal / added / removed）
  final DiffType type;
  /// 本地内容（仅在 `equal` 或 `removed` 时非空）
  final String? localLine;
  /// 远端内容（仅在 `equal` 或 `added` 时非空）
  final String? remoteLine;
  /// 行号（基于 1 的索引）
  final int lineNumber;

  const DiffLine({
    required this.type,
    this.localLine,
    this.remoteLine,
    required this.lineNumber,
  });
}

/// 合并结果
///
/// 借鉴 Git 合并命令的退出码语义：返回"自动合并成功"与"需手动解决"两个集合，
/// 调用方可基于 `hasManualConflicts` 决定是否进入冲突解决 UI。
class MergeResult {
  /// 已自动解决的冲突列表
  final List<ConflictInfo> autoResolved;
  /// 需用户手动解决的冲突列表
  final List<ConflictInfo> manualRequired;

  const MergeResult({
    required this.autoResolved,
    required this.manualRequired,
  });

  /// 是否存在需要用户手动解决的冲突
  bool get hasManualConflicts => manualRequired.isNotEmpty;
}
