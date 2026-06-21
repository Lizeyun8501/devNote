// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'Нотатки';

  @override
  String get editor => 'Редактор';

  @override
  String get search => 'Пошук';

  @override
  String get settings => 'Налаштування';

  @override
  String get knowledgeGraph => 'Граф знань';

  @override
  String get noteList => 'Список нотаток';

  @override
  String get editNote => 'Редагувати нотатку';

  @override
  String get newNote => 'Нова нотатка';

  @override
  String get untitled => 'Без назви';

  @override
  String get noContent => 'Немає вмісту';

  @override
  String get noNotes => 'Ще немає нотаток';

  @override
  String get noFolders => 'Ще немає папок';

  @override
  String get newFolder => 'Нова папка';

  @override
  String get newSubFolder => 'Новий підкаталог';

  @override
  String get folderName => 'Назва папки';

  @override
  String get create => 'Створити';

  @override
  String get cancel => 'Скасувати';

  @override
  String get confirm => 'Підтвердити';

  @override
  String get delete => 'Видалити';

  @override
  String get rename => 'Перейменувати';

  @override
  String get renameFolder => 'Перейменувати папку';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Зберегти';

  @override
  String get open => 'Відкрити';

  @override
  String get expand => 'Розгорнути';

  @override
  String get darkMode => 'Темний режим';

  @override
  String get darkModeSubtitle => 'Перемикнути темну/світлу тему';

  @override
  String get fontSize => 'Розмір шрифту';

  @override
  String get autoSave => 'Автозбереження';

  @override
  String get autoSaveSubtitle => 'Автоматично зберігати нотатки під час редагування';

  @override
  String get defaultEditMode => 'Режим редагування за замовчуванням';

  @override
  String get richText => 'Форматований текст';

  @override
  String get syncSettings => 'Налаштування синхронізації';

  @override
  String get syncSettingsSubtitle => 'Налаштування синхронізації даних і вирішення конфліктів';

  @override
  String get cryptoSettings => 'Налаштування шифрування';

  @override
  String get cryptoSettingsSubtitle => 'Керування шифруванням нотаток і паролем';

  @override
  String get p2pSync => 'P2P-синхронізація';

  @override
  String get p2pSyncSubtitle => 'Пряма синхронізація даних між пристроями';

  @override
  String get pluginMarketplace => 'Магазин плагінів';

  @override
  String get pluginMarketplaceSubtitle => 'Перегляд і встановлення плагінів';

  @override
  String get pluginManagement => 'Керування плагінами';

  @override
  String get pluginManagementSubtitle => 'Керування встановленими плагінами';

  @override
  String get importExport => 'Імпорт/Експорт';

  @override
  String get importExportSubtitle => 'Імпорт або експорт даних нотаток';

  @override
  String get dataBackup => 'Резервне копіювання';

  @override
  String get dataBackupSubtitle => 'Експорт даних нотаток';

  @override
  String get clearCache => 'Очистити кеш';

  @override
  String get clearCacheSubtitle => 'Очистити локальні кешовані дані';

  @override
  String get version => 'Версія';

  @override
  String get openSourceLicenses => 'Відкриті ліцензії';

  @override
  String get appearance => 'Вигляд';

  @override
  String get data => 'Дані';

  @override
  String get about => 'Про застосунок';

  @override
  String get gridView => 'Сітка';

  @override
  String get listView => 'Список';

  @override
  String get sort => 'Сортування';

  @override
  String get sortByUpdatedAt => 'За часом зміни';

  @override
  String get sortByCreatedAt => 'За часом створення';

  @override
  String get sortByTitle => 'За назвою';

  @override
  String get paragraph => 'Абзац';

  @override
  String get heading => 'Заголовок';

  @override
  String get codeBlock => 'Блок коду';

  @override
  String get bulletList => 'Маркований список';

  @override
  String get quote => 'Цитата';

  @override
  String get noteType => 'Нотатка';

  @override
  String get tagType => 'Тег';

  @override
  String get folderType => 'Папка';

  @override
  String get canvasType => 'Полотно';

  @override
  String get centralityAnalysis => 'Аналіз центральності';

  @override
  String get clusterDetection => 'Виявлення кластерів';

  @override
  String get enableEncryption => 'Увімкнути шифрування';

  @override
  String get disableEncryption => 'Вимкнути шифрування';

  @override
  String get lock => 'Заблокувати';

  @override
  String get unlock => 'Розблокувати';

  @override
  String get changePassword => 'Змінити пароль';

  @override
  String get setEncryptionPassword => 'Встановити пароль шифрування';

  @override
  String get verifyPassword => 'Підтвердити пароль';

  @override
  String get enterCurrentPassword => 'Введіть поточний пароль';

  @override
  String get setNewPassword => 'Встановіть новий пароль';

  @override
  String get enterPasswordToUnlock => 'Введіть пароль для розблокування';

  @override
  String get encryptionEnabled => 'Шифрування увімкнено';

  @override
  String get encryptionDisabled => 'Шифрування вимкнено';

  @override
  String get passwordChanged => 'Пароль змінено';

  @override
  String get wrongPassword => 'Невірний пароль';

  @override
  String get enableEncryptionFailed => 'Не вдалося увімкнути шифрування, пароль має містити щонайменше 6 символів';

  @override
  String get wrongPasswordCannotDisable => 'Невірний пароль, неможливо вимкнути шифрування';

  @override
  String get passwordChangeFailed => 'Не вдалося змінити пароль, перевірте поточний пароль';

  @override
  String get encryptionControl => 'Керування шифруванням';

  @override
  String get encryptionAlgorithm => 'Алгоритм шифрування';

  @override
  String get standard => 'Стандартний';

  @override
  String get standardSubtitle => 'Argon2id 3 ітерації, підходить для щоденного використання';

  @override
  String get highStrength => 'Висока надійність';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 ітерацій, підвищена безпека';

  @override
  String get encryptionInstructions => 'Інструкції з шифрування';

  @override
  String get encryptionDescription => '• Після увімкнення шифрування вміст нотаток буде зашифровано за допомогою XChaCha20-Poly1305\n• Пароль використовується для виведення ключа алгоритмом Argon2id\n• Зберігайте пароль у надійному місці, його втрата означає втрату даних\n• Щоб змінити надійність шифрування, необхідно вимкнути та знову увімкнути шифрування';

  @override
  String get import => 'Імпорт';

  @override
  String get export => 'Експорт';

  @override
  String get markdownFolder => 'Тека Markdown';

  @override
  String get obsidianVault => 'Сховище Obsidian';

  @override
  String get joplinExport => 'Експорт Joplin';

  @override
  String get conflictResolution => 'Вирішення конфліктів';

  @override
  String get skip => 'Пропустити';

  @override
  String get overwrite => 'Перезаписати';

  @override
  String get startImport => 'Почати імпорт';

  @override
  String get startExport => 'Почати експорт';

  @override
  String get allNotes => 'Усі нотатки';

  @override
  String get specifiedFolder => 'Вказана папка';

  @override
  String get specifiedTag => 'Вказаний тег';

  @override
  String get conflictHandling => 'Обробка конфліктів';

  @override
  String get conflictResolutionTitle => 'Вирішення конфліктів';

  @override
  String get noConflicts => 'Конфліктів для вирішення немає';

  @override
  String get allConflictsResolved => 'Усі конфлікти вирішено';

  @override
  String get keepLocalVersion => 'Зберегти всі локальні версії';

  @override
  String get keepRemoteVersion => 'Зберегти всі віддалені версії';

  @override
  String get conflict => 'Конфлікт';

  @override
  String get contentConflict => 'Конфлікт вмісту';

  @override
  String get moveConflict => 'Конфлікт переміщення';

  @override
  String get deleteModifyConflict => 'Конфлікт видалення/зміни';

  @override
  String get diffComparison => 'Порівняння різниць';

  @override
  String get localVersion => 'Локальна версія';

  @override
  String get remoteVersion => 'Віддалена версія';

  @override
  String get quickActions => 'Швидкі дії';

  @override
  String get keepLocal => 'Зберегти локальну';

  @override
  String get keepRemote => 'Зберегти віддалену';

  @override
  String get customMerge => 'Користувацьке злиття';

  @override
  String get noContentDifference => 'Немає різниці у вмісті';

  @override
  String get blockDifferences => 'блоків різниці';

  @override
  String get unresolvedBlocks => 'Є нерозв\'язані блоки різниці';

  @override
  String get resolve => 'Вирішити';

  @override
  String get local => 'Локально';

  @override
  String get remote => 'Віддалено';

  @override
  String get empty => '(порожньо)';

  @override
  String get error => 'Помилка';
}
