import 'dart:async';

enum ExportRange {
  all,
  folder,
  tag,
}

enum ExportFormat {
  markdown,
  html,
}

class ExportProgress {
  final int current;
  final int total;
  final String currentFile;
  final bool isComplete;

  const ExportProgress({
    this.current = 0,
    this.total = 0,
    this.currentFile = '',
    this.isComplete = false,
  });

  double get progress => total > 0 ? current / total : 0.0;
}

class ExportService {
  final _progressController = StreamController<ExportProgress>.broadcast();

  Stream<ExportProgress> get progressStream => _progressController.stream;

  Future<void> export({
    required ExportRange range,
    required ExportFormat format,
    required String targetPath,
    String? folderId,
    String? tagName,
  }) async {
    _progressController.add(const ExportProgress());

    _progressController.add(const ExportProgress(isComplete: true));
  }

  void dispose() {
    _progressController.close();
  }
}
