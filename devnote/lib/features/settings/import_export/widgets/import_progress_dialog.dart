import 'package:flutter/material.dart';
import 'package:devnote/features/settings/import_export/import_service.dart';

class ImportProgressDialog extends StatelessWidget {
  final ImportService importService;

  const ImportProgressDialog({super.key, required this.importService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ImportProgress>(
      stream: importService.progressStream,
      initialData: const ImportProgress(),
      builder: (context, snapshot) {
        final progress = snapshot.data ?? const ImportProgress();
        return AlertDialog(
          title: const Text('导入中'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress.isComplete ? 1.0 : progress.progress,
              ),
              const SizedBox(height: 16),
              Text(progress.isComplete
                  ? '导入完成'
                  : '正在导入: ${progress.currentFile}'),
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
