enum ConflictType {
  contentConflict,
  moveConflict,
  deleteModifyConflict,
}

class ConflictInfo {
  final String blockId;
  final String localContent;
  final String remoteContent;
  final String localOperationId;
  final String remoteOperationId;
  final ConflictType conflictType;

  const ConflictInfo({
    required this.blockId,
    required this.localContent,
    required this.remoteContent,
    required this.localOperationId,
    required this.remoteOperationId,
    required this.conflictType,
  });

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

enum MergeStrategy {
  auto,
  preferLocal,
  preferRemote,
  manual,
}

class ConflictResolver {
  final List<ConflictInfo> _conflicts = [];
  final Map<String, String> _resolutions = {};

  List<ConflictInfo> get conflicts => List.unmodifiable(_conflicts);
  Map<String, String> get resolutions => Map.unmodifiable(_resolutions);
  bool get hasConflicts => _conflicts.isNotEmpty;
  bool get allResolved =>
      _conflicts.every((c) => _resolutions.containsKey(c.blockId));

  void addConflicts(List<ConflictInfo> conflicts) {
    _conflicts.addAll(conflicts);
  }

  void clear() {
    _conflicts.clear();
    _resolutions.clear();
  }

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

    _conflicts.addAll(manualRequired);

    return MergeResult(
      autoResolved: autoResolved,
      manualRequired: manualRequired,
    );
  }

  String? _tryAutoMerge(ConflictInfo conflict) {
    switch (conflict.conflictType) {
      case ConflictType.moveConflict:
        return conflict.remoteContent;
      case ConflictType.deleteModifyConflict:
        return null;
      case ConflictType.contentConflict:
        if (conflict.localContent.trim() == conflict.remoteContent.trim()) {
          return conflict.localContent;
        }
        return null;
    }
  }

  void resolveConflict(String blockId, String resolvedContent) {
    _resolutions[blockId] = resolvedContent;
  }

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

enum DiffType {
  equal,
  added,
  removed,
}

class DiffLine {
  final DiffType type;
  final String? localLine;
  final String? remoteLine;
  final int lineNumber;

  const DiffLine({
    required this.type,
    this.localLine,
    this.remoteLine,
    required this.lineNumber,
  });
}

class MergeResult {
  final List<ConflictInfo> autoResolved;
  final List<ConflictInfo> manualRequired;

  const MergeResult({
    required this.autoResolved,
    required this.manualRequired,
  });

  bool get hasManualConflicts => manualRequired.isNotEmpty;
}
