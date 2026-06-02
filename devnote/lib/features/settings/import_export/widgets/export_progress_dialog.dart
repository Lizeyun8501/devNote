import 'package:flutter/material.dart';
import 'package:devnote/features/settings/import_export/export_service.dart';

class ExportProgressDialog extends StatelessWidget {
  final ExportService exportService;

  const ExportProgressDialog({super.key, required this.exportService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ExportProgress>(
      stream: exportService.progressStream,
      initialData: const ExportProgress(),
      builder: (context, snapshot) {
        final progress = snapshot.data ?? const ExportProgress();
        return AlertDialog(
          title: const Text('导出中'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress.isComplete ? 1.0 : progress.progress,
              ),
              const SizedBox(height: 16),
              Text(progress.isComplete
                  ? '导出完成'
                  : '正在导出: ${progress.currentFile}'),
              const SizedBox(height: 8),
              Text('${progress.current} / ${progress.total}'),
            ],
          ),
          actions: [
            if (progress.isComplete)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
          ],
        );
      },
    );
  }
}
