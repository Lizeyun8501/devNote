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

final class FolderLoaded extends FolderState {
  final List<FolderNode> rootNodes;
  final String? selectedFolderId;
  final Set<String> expandedFolderIds;

  const FolderLoaded({
    required this.rootNodes,
    this.selectedFolderId,
    this.expandedFolderIds = const {},
  });

  FolderLoaded copyWith({
    List<FolderNode>? rootNodes,
    String? selectedFolderId,
    Set<String>? expandedFolderIds,
  }) {
    return FolderLoaded(
      rootNodes: rootNodes ?? this.rootNodes,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      expandedFolderIds: expandedFolderIds ?? this.expandedFolderIds,
    );
  }
}

final class FolderError extends FolderState {
  final String message;

  const FolderError(this.message);
}
