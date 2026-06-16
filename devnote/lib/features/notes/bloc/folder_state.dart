import 'package:equatable/equatable.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';

class FolderNode extends Equatable {
  final FolderModel folder;
  final List<FolderNode> children;
  final bool isExpanded;

  const FolderNode({
    required this.folder,
    this.children = const [],
    this.isExpanded = false,
  });

  FolderNode copyWith({
    FolderModel? folder,
    List<FolderNode>? children,
    bool? isExpanded,
  }) {
    return FolderNode(
      folder: folder ?? this.folder,
      children: children ?? this.children,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }

  @override
  List<Object?> get props => [folder, children, isExpanded];
}

sealed class FolderState {
  const FolderState();
}

final class FolderInitial extends FolderState {
  const FolderInitial();
}

/// Sentinel 值用于区分"未传参"和"显式传 null"
const _folderSentinel = Object();

final class FolderLoaded extends FolderState {
  final List<FolderNode> rootNodes;
  final String? selectedFolderId;
  final Set<String> expandedFolderIds;

  const FolderLoaded({
    required this.rootNodes,
    this.selectedFolderId,
    this.expandedFolderIds = const {},
  });

  /// 修复：copyWith 使用 sentinel 模式支持清除 selectedFolderId
  /// 原代码 `selectedFolderId ?? this.selectedFolderId` 无法传 null 清除选中，
  /// 导致删除已选中的文件夹后 selectedFolderId 仍指向已删除的文件夹
  FolderLoaded copyWith({
    List<FolderNode>? rootNodes,
    Object? selectedFolderId = _folderSentinel,
    Set<String>? expandedFolderIds,
  }) {
    return FolderLoaded(
      rootNodes: rootNodes ?? this.rootNodes,
      selectedFolderId: selectedFolderId == _folderSentinel ? this.selectedFolderId : selectedFolderId as String?,
      expandedFolderIds: expandedFolderIds ?? this.expandedFolderIds,
    );
  }
}

final class FolderError extends FolderState {
  final String message;

  const FolderError(this.message);
}
