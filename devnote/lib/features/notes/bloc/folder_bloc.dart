import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:devnote/features/notes/bloc/folder_event.dart';
import 'package:devnote/features/notes/bloc/folder_state.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/models/folder_model.dart';

class FolderBloc extends Bloc<FolderEvent, FolderState> {
  final FolderRepository _folderRepository;
  final _uuid = const Uuid();

  FolderBloc(this._folderRepository) : super(const FolderInitial()) {
    on<LoadFolders>(_onLoadFolders);
    on<CreateFolder>(_onCreateFolder);
    on<DeleteFolder>(_onDeleteFolder);
    on<RenameFolder>(_onRenameFolder);
    on<SelectFolder>(_onSelectFolder);
    on<ExpandFolder>(_onExpandFolder);
  }

  Future<void> _onLoadFolders(LoadFolders event, Emitter<FolderState> emit) async {
    try {
      final rootFolders = await _folderRepository.listFolders(null);
      final rootNodes = await _buildTree(rootFolders);
      emit(FolderLoaded(rootNodes: rootNodes));
    } catch (e) {
      emit(FolderError(e.toString()));
    }
  }

  Future<void> _onCreateFolder(CreateFolder event, Emitter<FolderState> emit) async {
    try {
      final now = DateTime.now();
      final folder = FolderModel(
        id: _uuid.v4(),
        name: event.name,
        parentId: event.parentId,
        createdAt: now,
        updatedAt: now,
      );
      // 修复：使用 repository 返回的模型，而非本地创建的对象
      // FFI 模式下 Rust 端可能返回不同的时间戳或 ID，使用本地对象会导致数据不一致
      final created = await _folderRepository.createFolder(folder);
      final currentState = state;
      if (currentState is FolderLoaded) {
        final newNode = FolderNode(folder: created);
        List<FolderNode> updatedNodes;
        if (event.parentId == null) {
          updatedNodes = List<FolderNode>.from(currentState.rootNodes)..add(newNode);
        } else {
          updatedNodes = _insertNode(currentState.rootNodes, event.parentId!, newNode);
        }
        emit(currentState.copyWith(rootNodes: updatedNodes));
      }
    } catch (e) {
      emit(FolderError(e.toString()));
    }
  }

  Future<void> _onDeleteFolder(DeleteFolder event, Emitter<FolderState> emit) async {
    try {
      await _folderRepository.deleteFolder(event.folderId);
      final currentState = state;
      if (currentState is FolderLoaded) {
        final updatedNodes = _removeNode(currentState.rootNodes, event.folderId);
        emit(currentState.copyWith(
          rootNodes: updatedNodes,
          selectedFolderId: currentState.selectedFolderId == event.folderId
              ? null
              : currentState.selectedFolderId,
        ));
      }
    } catch (e) {
      emit(FolderError(e.toString()));
    }
  }

  Future<void> _onRenameFolder(RenameFolder event, Emitter<FolderState> emit) async {
    try {
      final currentState = state;
      if (currentState is FolderLoaded) {
        final folder = _findFolder(currentState.rootNodes, event.folderId);
        if (folder != null) {
          final updated = folder.copyWith(name: event.newName, updatedAt: DateTime.now());
          await _folderRepository.updateFolder(updated);
          final updatedNodes = _updateNode(currentState.rootNodes, event.folderId, updated);
          emit(currentState.copyWith(rootNodes: updatedNodes));
        }
      }
    } catch (e) {
      emit(FolderError(e.toString()));
    }
  }

  Future<void> _onSelectFolder(SelectFolder event, Emitter<FolderState> emit) async {
    final currentState = state;
    if (currentState is FolderLoaded) {
      emit(currentState.copyWith(selectedFolderId: event.folderId));
    }
  }

  Future<void> _onExpandFolder(ExpandFolder event, Emitter<FolderState> emit) async {
    final currentState = state;
    if (currentState is FolderLoaded) {
      final expandedIds = Set<String>.from(currentState.expandedFolderIds);
      if (event.isExpanded) {
        expandedIds.add(event.folderId);
      } else {
        expandedIds.remove(event.folderId);
      }
      emit(currentState.copyWith(expandedFolderIds: expandedIds));
    }
  }

  Future<List<FolderNode>> _buildTree(List<FolderModel> folders) async {
    final nodes = <FolderNode>[];
    for (final folder in folders) {
      final children = await _folderRepository.listFolders(folder.id);
      final childNodes = await _buildTree(children);
      nodes.add(FolderNode(folder: folder, children: childNodes));
    }
    return nodes;
  }

  List<FolderNode> _insertNode(List<FolderNode> nodes, String parentId, FolderNode newNode) {
    return nodes.map((node) {
      if (node.folder.id == parentId) {
        return node.copyWith(children: [...node.children, newNode]);
      }
      return node.copyWith(children: _insertNode(node.children, parentId, newNode));
    }).toList();
  }

  List<FolderNode> _removeNode(List<FolderNode> nodes, String folderId) {
    return nodes.where((node) => node.folder.id != folderId).map((node) {
      return node.copyWith(children: _removeNode(node.children, folderId));
    }).toList();
  }

  FolderModel? _findFolder(List<FolderNode> nodes, String folderId) {
    for (final node in nodes) {
      if (node.folder.id == folderId) return node.folder;
      final found = _findFolder(node.children, folderId);
      if (found != null) return found;
    }
    return null;
  }

  List<FolderNode> _updateNode(List<FolderNode> nodes, String folderId, FolderModel updated) {
    return nodes.map((node) {
      if (node.folder.id == folderId) {
        return node.copyWith(folder: updated);
      }
      return node.copyWith(children: _updateNode(node.children, folderId, updated));
    }).toList();
  }
}
