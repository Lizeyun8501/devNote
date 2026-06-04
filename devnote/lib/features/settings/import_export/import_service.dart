import 'dart:async';

enum ImportSource {
  markdownFolder,
  obsidianVault,
  joplinExport,
}

enum ConflictResolution {
  skip,
  overwrite,
  rename,
}

class ImportProgress {
  final int current;
  final int total;
  final String currentFile;
  final bool isComplete;

  const ImportProgress({
    this.current = 0,
    this.total = 0,
    this.currentFile = '',
    this.isComplete = false,
  });

  double get progress => total > 0 ? current / total : 0.0;
}

class ImportedNote {
  final String title;
  final String content;
  final String folderPath;
  final List<String> tags;
  final List<String> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ImportedNote({
    required this.title,
    required this.content,
    this.folderPath = '',
    this.tags = const [],
    this.attachments = const [],
    required this.createdAt,
    required this.updatedAt,
  });
}

class ImportService {
  final _progressController = StreamController<ImportProgress>.broadcast();

  Stream<ImportProgress> get progressStream => _progressController.stream;

  Future<List<ImportedNote>> import({
    required ImportSource source,
    required String sourcePath,
    required String targetFolderId,
    ConflictResolution conflictResolution = ConflictResolution.skip,
  }) async {
    _progressController.add(const ImportProgress());

    _progressController.add(const ImportProgress(isComplete: true));
    return <ImportedNote>[];
  }

  void dispose() {
    _progressController.close();
  }
}
