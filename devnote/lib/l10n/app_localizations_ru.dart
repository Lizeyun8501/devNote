// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'Заметки';

  @override
  String get editor => 'Редактор';

  @override
  String get search => 'Поиск';

  @override
  String get settings => 'Настройки';

  @override
  String get knowledgeGraph => 'Граф знаний';

  @override
  String get noteList => 'Список заметок';

  @override
  String get editNote => 'Редактировать заметку';

  @override
  String get newNote => 'Новая заметка';

  @override
  String get untitled => 'Без названия';

  @override
  String get noContent => 'Нет содержимого';

  @override
  String get noNotes => 'Заметок пока нет';

  @override
  String get noFolders => 'Папок пока нет';

  @override
  String get newFolder => 'Новая папка';

  @override
  String get newSubFolder => 'Новая подпапка';

  @override
  String get folderName => 'Имя папки';

  @override
  String get create => 'Создать';

  @override
  String get cancel => 'Отмена';

  @override
  String get confirm => 'Подтвердить';

  @override
  String get delete => 'Удалить';

  @override
  String get rename => 'Переименовать';

  @override
  String get renameFolder => 'Переименовать папку';

  @override
  String get ok => 'ОК';

  @override
  String get save => 'Сохранить';

  @override
  String get open => 'Открыть';

  @override
  String get expand => 'Развернуть';

  @override
  String get darkMode => 'Тёмная тема';

  @override
  String get darkModeSubtitle => 'Переключить тёмную/светлую тему';

  @override
  String get fontSize => 'Размер шрифта';

  @override
  String get autoSave => 'Автосохранение';

  @override
  String get autoSaveSubtitle => 'Автоматически сохранять заметки при редактировании';

  @override
  String get defaultEditMode => 'Режим редактирования по умолчанию';

  @override
  String get richText => 'Форматированный текст';

  @override
  String get syncSettings => 'Настройки синхронизации';

  @override
  String get syncSettingsSubtitle => 'Настройка синхронизации данных и разрешения конфликтов';

  @override
  String get cryptoSettings => 'Настройки шифрования';

  @override
  String get cryptoSettingsSubtitle => 'Управление шифрованием заметок и паролем';

  @override
  String get p2pSync => 'P2P-синхронизация';

  @override
  String get p2pSyncSubtitle => 'Прямая синхронизация данных между устройствами';

  @override
  String get pluginMarketplace => 'Магазин плагинов';

  @override
  String get pluginMarketplaceSubtitle => 'Просмотр и установка плагинов';

  @override
  String get pluginManagement => 'Управление плагинами';

  @override
  String get pluginManagementSubtitle => 'Управление установленными плагинами';

  @override
  String get importExport => 'Импорт/Экспорт';

  @override
  String get importExportSubtitle => 'Импорт или экспорт данных заметок';

  @override
  String get dataBackup => 'Резервное копирование';

  @override
  String get dataBackupSubtitle => 'Экспорт данных заметок';

  @override
  String get clearCache => 'Очистить кэш';

  @override
  String get clearCacheSubtitle => 'Очистить локальные кэшированные данные';

  @override
  String get version => 'Версия';

  @override
  String get openSourceLicenses => 'Открытые лицензии';

  @override
  String get appearance => 'Внешний вид';

  @override
  String get data => 'Данные';

  @override
  String get about => 'О приложении';

  @override
  String get gridView => 'Сетка';

  @override
  String get listView => 'Список';

  @override
  String get sort => 'Сортировка';

  @override
  String get sortByUpdatedAt => 'По времени изменения';

  @override
  String get sortByCreatedAt => 'По времени создания';

  @override
  String get sortByTitle => 'По названию';

  @override
  String get paragraph => 'Абзац';

  @override
  String get heading => 'Заголовок';

  @override
  String get codeBlock => 'Блок кода';

  @override
  String get bulletList => 'Маркированный список';

  @override
  String get quote => 'Цитата';

  @override
  String get noteType => 'Заметка';

  @override
  String get tagType => 'Тег';

  @override
  String get folderType => 'Папка';

  @override
  String get canvasType => 'Холст';

  @override
  String get centralityAnalysis => 'Анализ центральности';

  @override
  String get clusterDetection => 'Обнаружение кластеров';

  @override
  String get enableEncryption => 'Включить шифрование';

  @override
  String get disableEncryption => 'Отключить шифрование';

  @override
  String get lock => 'Заблокировать';

  @override
  String get unlock => 'Разблокировать';

  @override
  String get changePassword => 'Изменить пароль';

  @override
  String get setEncryptionPassword => 'Установить пароль шифрования';

  @override
  String get verifyPassword => 'Подтвердить пароль';

  @override
  String get enterCurrentPassword => 'Введите текущий пароль';

  @override
  String get setNewPassword => 'Установите новый пароль';

  @override
  String get enterPasswordToUnlock => 'Введите пароль для разблокировки';

  @override
  String get encryptionEnabled => 'Шифрование включено';

  @override
  String get encryptionDisabled => 'Шифрование отключено';

  @override
  String get passwordChanged => 'Пароль изменён';

  @override
  String get wrongPassword => 'Неверный пароль';

  @override
  String get enableEncryptionFailed => 'Не удалось включить шифрование, пароль должен содержать не менее 6 символов';

  @override
  String get wrongPasswordCannotDisable => 'Неверный пароль, невозможно отключить шифрование';

  @override
  String get passwordChangeFailed => 'Не удалось изменить пароль, проверьте текущий пароль';

  @override
  String get encryptionControl => 'Управление шифрованием';

  @override
  String get encryptionAlgorithm => 'Алгоритм шифрования';

  @override
  String get standard => 'Стандартный';

  @override
  String get standardSubtitle => 'Argon2id 3 итерации, подходит для повседневного использования';

  @override
  String get highStrength => 'Высокая надёжность';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 итераций, повышенная безопасность';

  @override
  String get encryptionInstructions => 'Инструкции по шифрованию';

  @override
  String get encryptionDescription => '• После включения шифрования содержимое заметок будет зашифровано с помощью XChaCha20-Poly1305\n• Пароль используется для вывода ключа алгоритмом Argon2id\n• Храните пароль в надёжном месте, его потеря означает потерю данных\n• Для изменения надёжности шифрования необходимо отключить и заново включить шифрование';

  @override
  String get import => 'Импорт';

  @override
  String get export => 'Экспорт';

  @override
  String get markdownFolder => 'Папка Markdown';

  @override
  String get obsidianVault => 'Хранилище Obsidian';

  @override
  String get joplinExport => 'Экспорт Joplin';

  @override
  String get conflictResolution => 'Разрешение конфликтов';

  @override
  String get skip => 'Пропустить';

  @override
  String get overwrite => 'Перезаписать';

  @override
  String get startImport => 'Начать импорт';

  @override
  String get startExport => 'Начать экспорт';

  @override
  String get allNotes => 'Все заметки';

  @override
  String get specifiedFolder => 'Указанная папка';

  @override
  String get specifiedTag => 'Указанный тег';

  @override
  String get conflictHandling => 'Обработка конфликтов';

  @override
  String get conflictResolutionTitle => 'Разрешение конфликтов';

  @override
  String get noConflicts => 'Конфликтов для разрешения нет';

  @override
  String get allConflictsResolved => 'Все конфликты разрешены';

  @override
  String get keepLocalVersion => 'Сохранить все локальные версии';

  @override
  String get keepRemoteVersion => 'Сохранить все удалённые версии';

  @override
  String get conflict => 'Конфликт';

  @override
  String get contentConflict => 'Конфликт содержимого';

  @override
  String get moveConflict => 'Конфликт перемещения';

  @override
  String get deleteModifyConflict => 'Конфликт удаления/изменения';

  @override
  String get diffComparison => 'Сравнение различий';

  @override
  String get localVersion => 'Локальная версия';

  @override
  String get remoteVersion => 'Удалённая версия';

  @override
  String get quickActions => 'Быстрые действия';

  @override
  String get keepLocal => 'Сохранить локальную';

  @override
  String get keepRemote => 'Сохранить удалённую';

  @override
  String get customMerge => 'Пользовательское слияние';

  @override
  String get noContentDifference => 'Нет различий в содержимом';

  @override
  String get blockDifferences => 'блоков различий';

  @override
  String get unresolvedBlocks => 'Есть неразрешённые блоки различий';

  @override
  String get resolve => 'Разрешить';

  @override
  String get local => 'Локально';

  @override
  String get remote => 'Удалённо';

  @override
  String get empty => '(пусто)';

  @override
  String get error => 'Ошибка';
}
