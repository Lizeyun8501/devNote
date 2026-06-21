// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'Notatki';

  @override
  String get editor => 'Edytor';

  @override
  String get search => 'Szukaj';

  @override
  String get settings => 'Ustawienia';

  @override
  String get knowledgeGraph => 'Graf wiedzy';

  @override
  String get noteList => 'Lista notatek';

  @override
  String get editNote => 'Edytuj notatkę';

  @override
  String get newNote => 'Nowa notatka';

  @override
  String get untitled => 'Bez tytułu';

  @override
  String get noContent => 'Brak treści';

  @override
  String get noNotes => 'Brak notatek';

  @override
  String get noFolders => 'Brak folderów';

  @override
  String get newFolder => 'Nowy folder';

  @override
  String get newSubFolder => 'Nowy podfolder';

  @override
  String get folderName => 'Nazwa folderu';

  @override
  String get create => 'Utwórz';

  @override
  String get cancel => 'Anuluj';

  @override
  String get confirm => 'Potwierdź';

  @override
  String get delete => 'Usuń';

  @override
  String get rename => 'Zmień nazwę';

  @override
  String get renameFolder => 'Zmień nazwę folderu';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Zapisz';

  @override
  String get open => 'Otwórz';

  @override
  String get expand => 'Rozwiń';

  @override
  String get darkMode => 'Tryb ciemny';

  @override
  String get darkModeSubtitle => 'Przełącz motyw ciemny/jasny';

  @override
  String get fontSize => 'Rozmiar czcionki';

  @override
  String get autoSave => 'Autozapis';

  @override
  String get autoSaveSubtitle => 'Automatycznie zapisuj notatki podczas edycji';

  @override
  String get defaultEditMode => 'Domyślny tryb edycji';

  @override
  String get richText => 'Tekst sformatowany';

  @override
  String get syncSettings => 'Ustawienia synchronizacji';

  @override
  String get syncSettingsSubtitle => 'Konfiguracja synchronizacji danych i rozwiązywania konfliktów';

  @override
  String get cryptoSettings => 'Ustawienia szyfrowania';

  @override
  String get cryptoSettingsSubtitle => 'Zarządzaj szyfrowaniem notatek i hasłem';

  @override
  String get p2pSync => 'Synchronizacja P2P';

  @override
  String get p2pSyncSubtitle => 'Synchronizuj dane bezpośrednio między urządzeniami';

  @override
  String get pluginMarketplace => 'Marketplace wtyczek';

  @override
  String get pluginMarketplaceSubtitle => 'Przeglądaj i instaluj wtyczki';

  @override
  String get pluginManagement => 'Zarządzanie wtyczkami';

  @override
  String get pluginManagementSubtitle => 'Zarządzaj zainstalowanymi wtyczkami';

  @override
  String get importExport => 'Import/Eksport';

  @override
  String get importExportSubtitle => 'Importuj lub eksportuj dane notatek';

  @override
  String get dataBackup => 'Kopia zapasowa';

  @override
  String get dataBackupSubtitle => 'Eksportuj dane notatek';

  @override
  String get clearCache => 'Wyczyść pamięć podręczną';

  @override
  String get clearCacheSubtitle => 'Wyczyść lokalne dane w pamięci podręcznej';

  @override
  String get version => 'Wersja';

  @override
  String get openSourceLicenses => 'Licencje open source';

  @override
  String get appearance => 'Wygląd';

  @override
  String get data => 'Dane';

  @override
  String get about => 'O aplikacji';

  @override
  String get gridView => 'Widok siatki';

  @override
  String get listView => 'Widok listy';

  @override
  String get sort => 'Sortuj';

  @override
  String get sortByUpdatedAt => 'Według daty modyfikacji';

  @override
  String get sortByCreatedAt => 'Według daty utworzenia';

  @override
  String get sortByTitle => 'Według tytułu';

  @override
  String get paragraph => 'Akapit';

  @override
  String get heading => 'Nagłówek';

  @override
  String get codeBlock => 'Blok kodu';

  @override
  String get bulletList => 'Lista punktowana';

  @override
  String get quote => 'Cytat';

  @override
  String get noteType => 'Notatka';

  @override
  String get tagType => 'Tag';

  @override
  String get folderType => 'Folder';

  @override
  String get canvasType => 'Obszar roboczy';

  @override
  String get centralityAnalysis => 'Analiza centralności';

  @override
  String get clusterDetection => 'Wykrywanie klastrów';

  @override
  String get enableEncryption => 'Włącz szyfrowanie';

  @override
  String get disableEncryption => 'Wyłącz szyfrowanie';

  @override
  String get lock => 'Zablokuj';

  @override
  String get unlock => 'Odblokuj';

  @override
  String get changePassword => 'Zmień hasło';

  @override
  String get setEncryptionPassword => 'Ustaw hasło szyfrowania';

  @override
  String get verifyPassword => 'Potwierdź hasło';

  @override
  String get enterCurrentPassword => 'Wprowadź aktualne hasło';

  @override
  String get setNewPassword => 'Ustaw nowe hasło';

  @override
  String get enterPasswordToUnlock => 'Wprowadź hasło, aby odblokować';

  @override
  String get encryptionEnabled => 'Szyfrowanie włączone';

  @override
  String get encryptionDisabled => 'Szyfrowanie wyłączone';

  @override
  String get passwordChanged => 'Hasło zmienione';

  @override
  String get wrongPassword => 'Nieprawidłowe hasło';

  @override
  String get enableEncryptionFailed => 'Nie udało się włączyć szyfrowania, hasło musi mieć co najmniej 6 znaków';

  @override
  String get wrongPasswordCannotDisable => 'Nieprawidłowe hasło, nie można wyłączyć szyfrowania';

  @override
  String get passwordChangeFailed => 'Zmiana hasła nie powiodła się, sprawdź aktualne hasło';

  @override
  String get encryptionControl => 'Kontrola szyfrowania';

  @override
  String get encryptionAlgorithm => 'Algorytm szyfrowania';

  @override
  String get standard => 'Standardowy';

  @override
  String get standardSubtitle => 'Argon2id 3 iteracje, odpowiedni do codziennego użytku';

  @override
  String get highStrength => 'Wysokie bezpieczeństwo';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 iteracji, wyższe bezpieczeństwo';

  @override
  String get encryptionInstructions => 'Instrukcje szyfrowania';

  @override
  String get encryptionDescription => '• Po włączeniu szyfrowania treść notatek będzie szyfrowana za pomocą XChaCha20-Poly1305\n• Hasło służy do wyprowadzenia klucza algorytmem Argon2id\n• Przechowuj hasło bezpiecznie, jego utrata oznacza utratę danych\n• Aby zmienić siłę szyfrowania, musisz je wyłączyć i włączyć ponownie';

  @override
  String get import => 'Importuj';

  @override
  String get export => 'Eksportuj';

  @override
  String get markdownFolder => 'Folder Markdown';

  @override
  String get obsidianVault => 'Magazyn Obsidian';

  @override
  String get joplinExport => 'Eksport Joplin';

  @override
  String get conflictResolution => 'Rozwiązywanie konfliktów';

  @override
  String get skip => 'Pomiń';

  @override
  String get overwrite => 'Zastąp';

  @override
  String get startImport => 'Rozpocznij import';

  @override
  String get startExport => 'Rozpocznij eksport';

  @override
  String get allNotes => 'Wszystkie notatki';

  @override
  String get specifiedFolder => 'Określony folder';

  @override
  String get specifiedTag => 'Określony tag';

  @override
  String get conflictHandling => 'Obsługa konfliktów';

  @override
  String get conflictResolutionTitle => 'Rozwiązywanie konfliktów';

  @override
  String get noConflicts => 'Brak konfliktów do rozwiązania';

  @override
  String get allConflictsResolved => 'Wszystkie konflikty rozwiązane';

  @override
  String get keepLocalVersion => 'Zachowaj wszystkie wersje lokalne';

  @override
  String get keepRemoteVersion => 'Zachowaj wszystkie wersje zdalne';

  @override
  String get conflict => 'Konflikt';

  @override
  String get contentConflict => 'Konflikt treści';

  @override
  String get moveConflict => 'Konflikt przeniesienia';

  @override
  String get deleteModifyConflict => 'Konflikt usunięcia/modyfikacji';

  @override
  String get diffComparison => 'Porównanie różnic';

  @override
  String get localVersion => 'Wersja lokalna';

  @override
  String get remoteVersion => 'Wersja zdalna';

  @override
  String get quickActions => 'Szybkie akcje';

  @override
  String get keepLocal => 'Zachowaj lokalną';

  @override
  String get keepRemote => 'Zachowaj zdalną';

  @override
  String get customMerge => 'Niestandardowe scalanie';

  @override
  String get noContentDifference => 'Brak różnic w treści';

  @override
  String get blockDifferences => 'różnic bloków';

  @override
  String get unresolvedBlocks => 'Istnieją nierozwiązane bloki różnic';

  @override
  String get resolve => 'Rozwiąż';

  @override
  String get local => 'Lokalnie';

  @override
  String get remote => 'Zdalnie';

  @override
  String get empty => '(puste)';

  @override
  String get error => 'Błąd';
}
