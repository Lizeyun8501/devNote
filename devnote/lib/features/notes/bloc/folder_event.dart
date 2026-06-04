import 'package:equatable/equatable.dart';

abstract class FolderEvent extends Equatable {
  const FolderEvent();

  @override
  List<Object?> get props => [];
}

class LoadFolders extends FolderEvent {
  const LoadFolders();
}

class CreateFolder extends FolderEvent {
  final String name;
  final String? parentId;

  const CreateFolder({required this.name, this.parentId});

  @override
  List<Object?> get props => [name, parentId];
}

class DeleteFolder extends FolderEvent {
  final String folderId;

  const DeleteFolder(this.folderId);

  @override
  List<Object?> get props => [folderId];
}

class RenameFolder extends FolderEvent {
  final String folderId;
  final String newName;

  const RenameFolder({required this.folderId, required this.newName});

  @override
  List<Object?> get props => [folderId, newName];
}

class SelectFolder extends FolderEvent {
  final String? folderId;

  const SelectFolder(this.folderId);

  @override
  List<Object?> get props => [folderId];
}

class ExpandFolder extends FolderEvent {
  final String folderId;
  final bool isExpanded;

  const ExpandFolder({required this.folderId, required this.isExpanded});

  @override
  List<Object?> get props => [folderId, isExpanded];
}
