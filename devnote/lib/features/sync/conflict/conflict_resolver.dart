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
/// - `VectorClock` 跟踪每个设备的操作顺序，`mergeWithVectorClocks` 基于向量时钟实现
///   CRDT 风格的自动合并（因果排序 + 并发字符级合并 / last-write-wins）。
library;

import 'dart:math';

import 'package:devnote/features/editor/models/block_model.dart';

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

/// 向量时钟（Vector Clock）—— 跟踪每个设备的操作顺序
///
/// 借鉴 AppFlowy 的 CRDT 协作引擎与 Anytype 的 any-sync DAG：为每个设备维护一个
/// 单调递增的逻辑时钟分量，通过逐分量比较判定两个操作的因果关系（before / after /
/// concurrent）。向量时钟是 CRDT 风格自动合并的基础——只有"并发"操作才需要合并策略，
/// 存在因果先后关系的操作可直接采用较新的一方。
class VectorClock {
  final Map<String, int> _clocks;

  VectorClock([Map<String, int>? initial]) : _clocks = initial ?? {};

  /// 递增指定设备的时钟
  void increment(String deviceId) {
    _clocks[deviceId] = (_clocks[deviceId] ?? 0) + 1;
  }

  /// 获取指定设备的时钟值
  int get(String deviceId) => _clocks[deviceId] ?? 0;

  /// 合并另一个向量时钟（取各设备最大值）
  void merge(VectorClock other) {
    for (final entry in other._clocks.entries) {
      _clocks[entry.key] = max(_clocks[entry.key] ?? 0, entry.value);
    }
  }

  /// 判断本时钟是否在 other 之前（所有分量都 <=）
  bool isBefore(VectorClock other) {
    for (final key in _clocks.keys) {
      if ((_clocks[key] ?? 0) > other.get(key)) return false;
    }
    return true;
  }

  /// 判断本时钟是否与 other 并发（既不在前也不在后）
  bool isConcurrent(VectorClock other) =>
      !isBefore(other) && !other.isBefore(this);

  /// 序列化
  Map<String, int> toJson() => Map.from(_clocks);

  factory VectorClock.fromJson(Map<String, dynamic> json) {
    return VectorClock(json.map((k, v) => MapEntry(k, v as int)));
  }

  VectorClock copy() => VectorClock(Map.from(_clocks));
}

/// 冲突解决器
///
/// 提供冲突的注册、批量自动合并、策略化解决与差异计算能力。
///
/// ## 借鉴的开源项目
/// - **Git** ([官网](https://git-scm.com/)): 三方合并（three-way merge）思想。
/// - **Yjs / CRDT** ([GitHub](https://github.com/yjs/yjs)): 协同编辑无冲突理论。
/// - **Google Docs** ([说明](https://workspace.google.com/)): 冲突解决策略分类。
/// - **AppFlowy / Anytype**: 向量时钟（Vector Clock）与 CRDT 风格自动合并。
///
/// ## 向量时钟集成
/// - `mergeWithCrdt` 保持原有签名以兼容旧调用方，内部在已注册向量时钟时
///   优先按因果关系（before / after / concurrent）解决，未注册时回退到三路合并。
/// - `mergeWithVectorClocks` 提供基于 `BlockModel` 与 `VectorClock` 的完整
///   CRDT 风格合并入口。
class ConflictResolver {
  /// 内部维护的待解决冲突列表
  final List<ConflictInfo> _conflicts = [];
  /// 内部维护的解决结果表（key: blockId, value: 最终内容）
  final Map<String, String> _resolutions = {};
  /// 块级本地向量时钟表（key: blockId, value: 该块本地操作的向量时钟）
  final Map<String, VectorClock> _localVectorClocks = {};
  /// 块级远端向量时钟表（key: blockId, value: 该块远端操作的向量时钟）
  final Map<String, VectorClock> _remoteVectorClocks = {};

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

  /// 注册块级向量时钟，供 `mergeWithCrdt` 内部按因果关系解决冲突
  ///
  /// 调用方在同步过程中可为每个冲突块附带本地 / 远端操作的向量时钟；
  /// 未注册的块将回退到原有的三路合并逻辑。
  void setVectorClocks(
    Map<String, VectorClock> localClocks,
    Map<String, VectorClock> remoteClocks,
  ) {
    _localVectorClocks
      ..clear()
      ..addAll(localClocks);
    _remoteVectorClocks
      ..clear()
      ..addAll(remoteClocks);
  }

  /// P1 修复 (INC-04): 合并块级向量时钟，而非覆盖。
  ///
  /// 原实现 setVectorClocks 每次 clear() 后 addAll()，导致多 block 场景下
  /// 后续调用会清空之前注册的 block 向量时钟。此方法改为合并模式，
  /// 保留已注册的 block 向量时钟，仅更新/添加当前 block 的时钟。
  void mergeVectorClocks(
    Map<String, VectorClock> localClocks,
    Map<String, VectorClock> remoteClocks,
  ) {
    _localVectorClocks.addAll(localClocks);
    _remoteVectorClocks.addAll(remoteClocks);
  }

  /// 清空所有冲突与已记录的解决结果
  void clear() {
    _conflicts.clear();
    _resolutions.clear();
    _localVectorClocks.clear();
    _remoteVectorClocks.clear();
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
  /// 优先使用向量时钟判定操作因果关系（借鉴 AppFlowy CRDT / Anytype any-sync DAG）：
  /// - 若 local 向量时钟在 remote 之前 → 采用 remote（remote 因果在后）。
  /// - 若 remote 向量时钟在 local 之前 → 采用 local（local 因果在后）。
  /// - 若两者并发 → 对 `contentConflict` 进行字符级合并；其余类型回退到下方逻辑。
  ///
  /// 未注册向量时钟时回退到 Git 风格的"自动合并（auto-merge）"判定：
  /// - `moveConflict`: 一端移动了位置而另一端未移动，则接受移动后的位置（取远端内容）。
  /// - `deleteModifyConflict`: 删除-修改冲突无法自动判定，必须由用户介入。
  /// - `contentConflict`: 若两端内容去除首尾空白后完全相同，则视为等价，取其一；
  ///   否则交给用户手动合并。
  String? _tryAutoMerge(ConflictInfo conflict) {
    // 向量时钟路径：已注册本地 / 远端时钟时按因果关系解决
    final localClock = _localVectorClocks[conflict.blockId];
    final remoteClock = _remoteVectorClocks[conflict.blockId];
    if (localClock != null && remoteClock != null) {
      if (localClock.isBefore(remoteClock) && !remoteClock.isBefore(localClock)) {
        // local 因果在 remote 之前 → 使用 remote
        return conflict.remoteContent;
      }
      if (remoteClock.isBefore(localClock) && !localClock.isBefore(remoteClock)) {
        // remote 因果在 local 之前 → 使用 local
        return conflict.localContent;
      }
      // 并发：内容冲突进行字符级合并
      if (conflict.conflictType == ConflictType.contentConflict) {
        return _charLevelMerge(conflict.localContent, conflict.remoteContent);
      }
      // 并发的非内容冲突（移动 / 删除-修改）回退到下方三路合并逻辑
    }

    // 回退路径：三路合并逻辑（无向量时钟或并发非内容冲突）
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

  /// 使用向量时钟合并块列表
  ///
  /// 借鉴 Yjs / Automerge 的 CRDT 合并策略，基于向量时钟判定每个块的因果关系：
  /// - 仅存在于一端 → 直接采用该端版本。
  /// - 两端内容一致 → 无冲突，采用本地版本。
  /// - local 向量时钟在 remote 之前 → 采用 remote（remote 因果在后）。
  /// - remote 向量时钟在 local 之前 → 采用 local（local 因果在后）。
  /// - 两者并发：
  ///   - 文本块（段落 / 标题 / 列表 / 引用 / 任务）→ 字符级合并。
  ///   - 非文本块（代码 / 表格 / 图片 / 公式）→ 基于时间戳 last-write-wins。
  ///
  /// [baseClock] 为共同祖先的向量时钟，当前实现中保留用于未来基于 base 的
  /// 三路增量合并扩展。
  List<BlockConflict> mergeWithVectorClocks(
    List<BlockModel> localBlocks,
    List<BlockModel> remoteBlocks,
    VectorClock localClock,
    VectorClock remoteClock,
    VectorClock baseClock,
  ) {
    final results = <BlockConflict>[];
    final localMap = {for (final b in localBlocks) b.id: b};
    final remoteMap = {for (final b in remoteBlocks) b.id: b};
    final allIds = <String>{...localMap.keys, ...remoteMap.keys};

    for (final id in allIds) {
      final local = localMap[id];
      final remote = remoteMap[id];

      // 两端均存在：基于向量时钟进行 CRDT 风格合并
      if (local != null && remote != null) {
        // 内容一致则无冲突
        if (local.content == remote.content) {
          results.add(BlockConflict(
            block: local,
            action: BlockResolutionAction.noConflict,
            source: 'local',
            reason: '两端内容一致',
          ));
          continue;
        }

        // 基于向量时钟判定因果关系
        final localBeforeRemote =
            localClock.isBefore(remoteClock) && !remoteClock.isBefore(localClock);
        final remoteBeforeLocal =
            remoteClock.isBefore(localClock) && !localClock.isBefore(remoteClock);

        if (localBeforeRemote) {
          // local 因果在 remote 之前 → 使用 remote
          results.add(BlockConflict(
            block: remote,
            action: BlockResolutionAction.keepRemote,
            source: 'remote',
            reason: '本地向量时钟在远端之前，采用远端版本',
          ));
        } else if (remoteBeforeLocal) {
          // remote 因果在 local 之前 → 使用 local
          results.add(BlockConflict(
            block: local,
            action: BlockResolutionAction.keepLocal,
            source: 'local',
            reason: '远端向量时钟在本地之前，采用本地版本',
          ));
        } else if (_isTextBlock(local.blockType)) {
          // 并发冲突：文本块字符级合并
          final mergedContent = _charLevelMerge(local.content, remote.content);
          final mergedBlock = local.copyWith(
            content: mergedContent,
            updatedAt: DateTime.now(),
          );
          results.add(BlockConflict(
            block: mergedBlock,
            action: BlockResolutionAction.charMerged,
            source: 'merged',
            reason: '并发编辑，文本块字符级合并',
          ));
        } else {
          // 并发冲突：非文本块基于时间戳 last-write-wins
          final localWins = !local.updatedAt.isBefore(remote.updatedAt);
          final winner = localWins ? local : remote;
          results.add(BlockConflict(
            block: winner,
            action: BlockResolutionAction.lastWriteWins,
            source: localWins ? 'local' : 'remote',
            reason: '并发编辑非文本块，基于时间戳 last-write-wins',
          ));
        }
        continue;
      }

      // 仅存在于一端（allIds 为两端并集，故必有一端非空）
      if (local != null) {
        results.add(BlockConflict(
          block: local,
          action: BlockResolutionAction.keepLocal,
          source: 'local',
          reason: '块仅存在于本地',
        ));
      } else {
        results.add(BlockConflict(
          block: remote!,
          action: BlockResolutionAction.keepRemote,
          source: 'remote',
          reason: '块仅存在于远端',
        ));
      }
    }

    return results;
  }

  /// 判断块类型是否为文本块（可进行字符级合并）
  ///
  /// 段落 / 标题 / 列表 / 有序列表 / 引用 / 任务视为文本块；
  /// 代码块 / 表格 / 图片 / 公式视为非文本块（结构敏感，采用 last-write-wins）。
  bool _isTextBlock(BlockType type) {
    switch (type) {
      case BlockType.paragraph:
      case BlockType.heading1:
      case BlockType.heading2:
      case BlockType.heading3:
      case BlockType.heading4:
      case BlockType.heading5:
      case BlockType.heading6:
      case BlockType.list:
      case BlockType.orderedList:
      case BlockType.quote:
      case BlockType.taskListBlock:
        return true;
      case BlockType.codeBlock:
      case BlockType.tableBlock:
      case BlockType.image:
      case BlockType.latexBlock:
      case BlockType.pdf:
      case BlockType.whiteboard:
        return false;
    }
  }

  /// 字符级合并两段文本（CRDT 风格）
  ///
  /// 提取公共前缀与公共后缀，将两端各自独有的中间部分顺序拼接
  /// （先 local 后 remote），从而在并发插入场景下保留双方新增内容。
  /// 该策略与 Yjs / Automerge 的"保留双方插入"语义一致。
  String _charLevelMerge(String local, String remote) {
    if (local == remote) return local;
    if (local.isEmpty) return remote;
    if (remote.isEmpty) return local;

    // 公共前缀
    var prefixLen = 0;
    final minLen = local.length < remote.length ? local.length : remote.length;
    while (prefixLen < minLen && local[prefixLen] == remote[prefixLen]) {
      prefixLen++;
    }

    // 公共后缀（不能与前缀重叠）
    var suffixLen = 0;
    while (suffixLen < minLen - prefixLen &&
        local[local.length - 1 - suffixLen] ==
            remote[remote.length - 1 - suffixLen]) {
      suffixLen++;
    }

    final prefix = local.substring(0, prefixLen);
    final suffix = local.substring(local.length - suffixLen);
    final localMiddle = local.substring(prefixLen, local.length - suffixLen);
    final remoteMiddle =
        remote.substring(prefixLen, remote.length - suffixLen);

    return '$prefix$localMiddle$remoteMiddle$suffix';
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

/// 块冲突解决方式
///
/// 描述 `mergeWithVectorClocks` 对单个块采用的合并策略，便于上层 UI / 日志
/// 呈现"为何如此合并"的因果依据。
enum BlockResolutionAction {
  /// 保留本地版本（本地因果在后，或块仅存在于本地）
  keepLocal,
  /// 保留远端版本（远端因果在后，或块仅存在于远端）
  keepRemote,
  /// 字符级合并（并发编辑的文本块）
  charMerged,
  /// 基于时间戳的 last-write-wins（并发编辑的非文本块）
  lastWriteWins,
  /// 无冲突（两端内容一致）
  noConflict,
}

/// 块冲突解决结果
///
/// 借鉴 Yjs / Automerge 的 CRDT 合并结果模型：将合并后的块与"如何合并"的
/// 元数据（解决方式 / 来源 / 原因）聚合为一个值对象，便于调用方审计与展示。
class BlockConflict {
  /// 解决后的块
  final BlockModel block;
  /// 解决方式
  final BlockResolutionAction action;
  /// 来源标识（local / remote / merged）
  final String source;
  /// 解决原因说明
  final String? reason;

  const BlockConflict({
    required this.block,
    required this.action,
    required this.source,
    this.reason,
  });
}
