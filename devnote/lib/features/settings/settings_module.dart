// 修复(P1): 将 features 层的依赖注册从 core/di/injection.dart 迁移至此，
// 消除 core → features 的反向依赖。

import 'package:devnote/core/di/injection.dart';
import 'package:devnote/core/persistence/database_helper.dart';
import 'package:devnote/core/persistence/folder_repository.dart';
import 'package:devnote/core/persistence/note_repository.dart';
import 'package:devnote/features/settings/crypto/crypto_service.dart';
import 'package:devnote/features/settings/import_export/onenote_import_service.dart';

/// 注册 Settings 模块依赖
Future<void> registerSettingsDependencies() async {
  getIt.registerLazySingleton<CryptoService>(() => CryptoService());

  // P2-8: OneNote 导入工具
  // OneNoteGraphImporter: 通过 Microsoft Graph API 导入（OAuth2 授权流程）
  // OneNoteHtmlImporter: 通过导出的 HTML 文件导入（本地文件解析）
  if (!getIt.isRegistered<OneNoteGraphImporter>()) {
    getIt.registerLazySingleton<OneNoteGraphImporter>(() => OneNoteGraphImporter());
  }
  if (!getIt.isRegistered<OneNoteHtmlImporter>()) {
    getIt.registerLazySingleton<OneNoteHtmlImporter>(() {
      final dbHelper = getIt<DatabaseHelper>();
      return OneNoteHtmlImporter(
        noteRepository: SqliteNoteRepository(dbHelper),
        folderRepository: SqliteFolderRepository(dbHelper),
      );
    });
  }
}
