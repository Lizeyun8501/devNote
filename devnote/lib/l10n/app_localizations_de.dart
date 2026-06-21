// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'Notizen';

  @override
  String get editor => 'Editor';

  @override
  String get search => 'Suchen';

  @override
  String get settings => 'Einstellungen';

  @override
  String get knowledgeGraph => 'Wissensgraph';

  @override
  String get noteList => 'Notizliste';

  @override
  String get editNote => 'Notiz bearbeiten';

  @override
  String get newNote => 'Neue Notiz';

  @override
  String get untitled => 'Unbenannt';

  @override
  String get noContent => 'Kein Inhalt';

  @override
  String get noNotes => 'Noch keine Notizen';

  @override
  String get noFolders => 'Noch keine Ordner';

  @override
  String get newFolder => 'Neuer Ordner';

  @override
  String get newSubFolder => 'Neuer Unterordner';

  @override
  String get folderName => 'Ordnername';

  @override
  String get create => 'Erstellen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get confirm => 'Bestätigen';

  @override
  String get delete => 'Löschen';

  @override
  String get rename => 'Umbenennen';

  @override
  String get renameFolder => 'Ordner umbenennen';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Speichern';

  @override
  String get open => 'Öffnen';

  @override
  String get expand => 'Ausklappen';

  @override
  String get darkMode => 'Dunkelmodus';

  @override
  String get darkModeSubtitle => 'Zwischen dunklem/hellem Thema wechseln';

  @override
  String get fontSize => 'Schriftgröße';

  @override
  String get autoSave => 'Automatisch speichern';

  @override
  String get autoSaveSubtitle => 'Notizen beim Bearbeiten automatisch speichern';

  @override
  String get defaultEditMode => 'Standard-Bearbeitungsmodus';

  @override
  String get richText => 'Rich-Text';

  @override
  String get syncSettings => 'Synchronisierungseinstellungen';

  @override
  String get syncSettingsSubtitle => 'Datensynchronisierung und Konfliktlösung konfigurieren';

  @override
  String get cryptoSettings => 'Verschlüsselungseinstellungen';

  @override
  String get cryptoSettingsSubtitle => 'Notizverschlüsselung und Passwort verwalten';

  @override
  String get p2pSync => 'P2P-Synchronisierung';

  @override
  String get p2pSyncSubtitle => 'Daten direkt zwischen Geräten synchronisieren';

  @override
  String get pluginMarketplace => 'Plugin-Marktplatz';

  @override
  String get pluginMarketplaceSubtitle => 'Plugins durchsuchen und installieren';

  @override
  String get pluginManagement => 'Plugin-Verwaltung';

  @override
  String get pluginManagementSubtitle => 'Installierte Plugins verwalten';

  @override
  String get importExport => 'Import/Export';

  @override
  String get importExportSubtitle => 'Notizdaten importieren oder exportieren';

  @override
  String get dataBackup => 'Datensicherung';

  @override
  String get dataBackupSubtitle => 'Notizdaten exportieren';

  @override
  String get clearCache => 'Cache leeren';

  @override
  String get clearCacheSubtitle => 'Lokale zwischengespeicherte Daten löschen';

  @override
  String get version => 'Version';

  @override
  String get openSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get appearance => 'Erscheinungsbild';

  @override
  String get data => 'Daten';

  @override
  String get about => 'Über';

  @override
  String get gridView => 'Gitteransicht';

  @override
  String get listView => 'Listenansicht';

  @override
  String get sort => 'Sortieren';

  @override
  String get sortByUpdatedAt => 'Nach Änderungszeit';

  @override
  String get sortByCreatedAt => 'Nach Erstellungszeit';

  @override
  String get sortByTitle => 'Nach Titel';

  @override
  String get paragraph => 'Absatz';

  @override
  String get heading => 'Überschrift';

  @override
  String get codeBlock => 'Codeblock';

  @override
  String get bulletList => 'Aufzählungsliste';

  @override
  String get quote => 'Zitat';

  @override
  String get noteType => 'Notiz';

  @override
  String get tagType => 'Tag';

  @override
  String get folderType => 'Ordner';

  @override
  String get canvasType => 'Leinwand';

  @override
  String get centralityAnalysis => 'Zentralitätsanalyse';

  @override
  String get clusterDetection => 'Clustererkennung';

  @override
  String get enableEncryption => 'Verschlüsselung aktivieren';

  @override
  String get disableEncryption => 'Verschlüsselung deaktivieren';

  @override
  String get lock => 'Sperren';

  @override
  String get unlock => 'Entsperren';

  @override
  String get changePassword => 'Passwort ändern';

  @override
  String get setEncryptionPassword => 'Verschlüsselungspasswort festlegen';

  @override
  String get verifyPassword => 'Passwort bestätigen';

  @override
  String get enterCurrentPassword => 'Aktuelles Passwort eingeben';

  @override
  String get setNewPassword => 'Neues Passwort festlegen';

  @override
  String get enterPasswordToUnlock => 'Passwort zum Entsperren eingeben';

  @override
  String get encryptionEnabled => 'Verschlüsselung aktiviert';

  @override
  String get encryptionDisabled => 'Verschlüsselung deaktiviert';

  @override
  String get passwordChanged => 'Passwort geändert';

  @override
  String get wrongPassword => 'Falsches Passwort';

  @override
  String get enableEncryptionFailed => 'Aktivierung der Verschlüsselung fehlgeschlagen, das Passwort muss mindestens 6 Zeichen lang sein';

  @override
  String get wrongPasswordCannotDisable => 'Falsches Passwort, Verschlüsselung kann nicht deaktiviert werden';

  @override
  String get passwordChangeFailed => 'Passwortänderung fehlgeschlagen, bitte überprüfen Sie Ihr aktuelles Passwort';

  @override
  String get encryptionControl => 'Verschlüsselungssteuerung';

  @override
  String get encryptionAlgorithm => 'Verschlüsselungsalgorithmus';

  @override
  String get standard => 'Standard';

  @override
  String get standardSubtitle => 'Argon2id 3 Iterationen, für tägliche Nutzung geeignet';

  @override
  String get highStrength => 'Hohe Sicherheit';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 Iterationen, höhere Sicherheit';

  @override
  String get encryptionInstructions => 'Verschlüsselungshinweise';

  @override
  String get encryptionDescription => '• Nach Aktivierung der Verschlüsselung wird der Notizinhalt mit XChaCha20-Poly1305 verschlüsselt\n• Das Passwort leitet den Schlüssel mit dem Argon2id-Algorithmus ab\n• Bitte bewahren Sie Ihr Passwort sicher auf, ein verlorenes Passwort bedeutet verlorene Daten\n• Um die Verschlüsselungsstärke zu ändern, müssen Sie die Verschlüsselung deaktivieren und erneut aktivieren';

  @override
  String get import => 'Importieren';

  @override
  String get export => 'Exportieren';

  @override
  String get markdownFolder => 'Markdown-Ordner';

  @override
  String get obsidianVault => 'Obsidian-Tresor';

  @override
  String get joplinExport => 'Joplin-Export';

  @override
  String get conflictResolution => 'Konfliktlösung';

  @override
  String get skip => 'Überspringen';

  @override
  String get overwrite => 'Überschreiben';

  @override
  String get startImport => 'Import starten';

  @override
  String get startExport => 'Export starten';

  @override
  String get allNotes => 'Alle Notizen';

  @override
  String get specifiedFolder => 'Bestimmter Ordner';

  @override
  String get specifiedTag => 'Bestimmtes Tag';

  @override
  String get conflictHandling => 'Konfliktbehandlung';

  @override
  String get conflictResolutionTitle => 'Konfliktlösung';

  @override
  String get noConflicts => 'Keine Konflikte zu lösen';

  @override
  String get allConflictsResolved => 'Alle Konflikte gelöst';

  @override
  String get keepLocalVersion => 'Alle lokalen Versionen behalten';

  @override
  String get keepRemoteVersion => 'Alle entfernten Versionen behalten';

  @override
  String get conflict => 'Konflikt';

  @override
  String get contentConflict => 'Inhaltskonflikt';

  @override
  String get moveConflict => 'Verschiebungskonflikt';

  @override
  String get deleteModifyConflict => 'Lösch-/Änderungskonflikt';

  @override
  String get diffComparison => 'Diff-Vergleich';

  @override
  String get localVersion => 'Lokale Version';

  @override
  String get remoteVersion => 'Entfernte Version';

  @override
  String get quickActions => 'Schnellaktionen';

  @override
  String get keepLocal => 'Lokal behalten';

  @override
  String get keepRemote => 'Entfernt behalten';

  @override
  String get customMerge => 'Benutzerdefinierte Zusammenführung';

  @override
  String get noContentDifference => 'Kein Inhaltsunterschied';

  @override
  String get blockDifferences => 'Blockunterschiede';

  @override
  String get unresolvedBlocks => 'Es gibt ungelöste Differenzblöcke';

  @override
  String get resolve => 'Lösen';

  @override
  String get local => 'Lokal';

  @override
  String get remote => 'Entfernt';

  @override
  String get empty => '(leer)';

  @override
  String get error => 'Fehler';
}
