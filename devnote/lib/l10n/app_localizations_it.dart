// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'Note';

  @override
  String get editor => 'Editor';

  @override
  String get search => 'Cerca';

  @override
  String get settings => 'Impostazioni';

  @override
  String get knowledgeGraph => 'Grafo della conoscenza';

  @override
  String get noteList => 'Elenco note';

  @override
  String get editNote => 'Modifica nota';

  @override
  String get newNote => 'Nuova nota';

  @override
  String get untitled => 'Senza titolo';

  @override
  String get noContent => 'Nessun contenuto';

  @override
  String get noNotes => 'Nessuna nota';

  @override
  String get noFolders => 'Nessuna cartella';

  @override
  String get newFolder => 'Nuova cartella';

  @override
  String get newSubFolder => 'Nuova sottocartella';

  @override
  String get folderName => 'Nome cartella';

  @override
  String get create => 'Crea';

  @override
  String get cancel => 'Annulla';

  @override
  String get confirm => 'Conferma';

  @override
  String get delete => 'Elimina';

  @override
  String get rename => 'Rinomina';

  @override
  String get renameFolder => 'Rinomina cartella';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Salva';

  @override
  String get open => 'Apri';

  @override
  String get expand => 'Espandi';

  @override
  String get darkMode => 'Modalità scura';

  @override
  String get darkModeSubtitle => 'Passa tra tema scuro/chiaro';

  @override
  String get fontSize => 'Dimensione carattere';

  @override
  String get autoSave => 'Salvataggio automatico';

  @override
  String get autoSaveSubtitle => 'Salva le note durante la modifica';

  @override
  String get defaultEditMode => 'Modalità di modifica predefinita';

  @override
  String get richText => 'Testo formattato';

  @override
  String get syncSettings => 'Impostazioni di sincronizzazione';

  @override
  String get syncSettingsSubtitle => 'Configura sincronizzazione dati e risoluzione conflitti';

  @override
  String get cryptoSettings => 'Impostazioni di crittografia';

  @override
  String get cryptoSettingsSubtitle => 'Gestisci crittografia note e password';

  @override
  String get p2pSync => 'Sincronizzazione P2P';

  @override
  String get p2pSyncSubtitle => 'Sincronizza i dati direttamente tra dispositivi';

  @override
  String get pluginMarketplace => 'Marketplace plugin';

  @override
  String get pluginMarketplaceSubtitle => 'Sfoglia e installa plugin';

  @override
  String get pluginManagement => 'Gestione plugin';

  @override
  String get pluginManagementSubtitle => 'Gestisci i plugin installati';

  @override
  String get importExport => 'Importa/Esporta';

  @override
  String get importExportSubtitle => 'Importa o esporta dati delle note';

  @override
  String get dataBackup => 'Backup dati';

  @override
  String get dataBackupSubtitle => 'Esporta dati delle note';

  @override
  String get clearCache => 'Svuota cache';

  @override
  String get clearCacheSubtitle => 'Elimina i dati memorizzati nella cache locale';

  @override
  String get version => 'Versione';

  @override
  String get openSourceLicenses => 'Licenze open source';

  @override
  String get appearance => 'Aspetto';

  @override
  String get data => 'Dati';

  @override
  String get about => 'Informazioni';

  @override
  String get gridView => 'Vista griglia';

  @override
  String get listView => 'Vista elenco';

  @override
  String get sort => 'Ordina';

  @override
  String get sortByUpdatedAt => 'Per data di modifica';

  @override
  String get sortByCreatedAt => 'Per data di creazione';

  @override
  String get sortByTitle => 'Per titolo';

  @override
  String get paragraph => 'Paragrafo';

  @override
  String get heading => 'Intestazione';

  @override
  String get codeBlock => 'Blocco di codice';

  @override
  String get bulletList => 'Elenco puntato';

  @override
  String get quote => 'Citazione';

  @override
  String get noteType => 'Nota';

  @override
  String get tagType => 'Etichetta';

  @override
  String get folderType => 'Cartella';

  @override
  String get canvasType => 'Tela';

  @override
  String get centralityAnalysis => 'Analisi di centralità';

  @override
  String get clusterDetection => 'Rilevamento cluster';

  @override
  String get enableEncryption => 'Abilita crittografia';

  @override
  String get disableEncryption => 'Disabilita crittografia';

  @override
  String get lock => 'Blocca';

  @override
  String get unlock => 'Sblocca';

  @override
  String get changePassword => 'Cambia password';

  @override
  String get setEncryptionPassword => 'Imposta password di crittografia';

  @override
  String get verifyPassword => 'Verifica password';

  @override
  String get enterCurrentPassword => 'Inserisci password attuale';

  @override
  String get setNewPassword => 'Imposta nuova password';

  @override
  String get enterPasswordToUnlock => 'Inserisci password per sbloccare';

  @override
  String get encryptionEnabled => 'Crittografia abilitata';

  @override
  String get encryptionDisabled => 'Crittografia disabilitata';

  @override
  String get passwordChanged => 'Password modificata';

  @override
  String get wrongPassword => 'Password errata';

  @override
  String get enableEncryptionFailed => 'Impossibile abilitare la crittografia, la password deve contenere almeno 6 caratteri';

  @override
  String get wrongPasswordCannotDisable => 'Password errata, impossibile disabilitare la crittografia';

  @override
  String get passwordChangeFailed => 'Modifica password fallita, controlla la password attuale';

  @override
  String get encryptionControl => 'Controllo crittografia';

  @override
  String get encryptionAlgorithm => 'Algoritmo di crittografia';

  @override
  String get standard => 'Standard';

  @override
  String get standardSubtitle => 'Argon2id 3 iterazioni, adatto all\'uso quotidiano';

  @override
  String get highStrength => 'Alta sicurezza';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 iterazioni, sicurezza maggiore';

  @override
  String get encryptionInstructions => 'Istruzioni di crittografia';

  @override
  String get encryptionDescription => '• Dopo aver abilitato la crittografia, il contenuto delle note verrà crittografato con XChaCha20-Poly1305\n• La password deriva la chiave con l\'algoritmo Argon2id\n• Conserva la password in modo sicuro, perderla significa perdere i dati\n• Per modificare la sicurezza della crittografia devi disabilitarla e riabilitarla';

  @override
  String get import => 'Importa';

  @override
  String get export => 'Esporta';

  @override
  String get markdownFolder => 'Cartella Markdown';

  @override
  String get obsidianVault => 'Caveau Obsidian';

  @override
  String get joplinExport => 'Esportazione Joplin';

  @override
  String get conflictResolution => 'Risoluzione conflitti';

  @override
  String get skip => 'Salta';

  @override
  String get overwrite => 'Sovrascrivi';

  @override
  String get startImport => 'Avvia importazione';

  @override
  String get startExport => 'Avvia esportazione';

  @override
  String get allNotes => 'Tutte le note';

  @override
  String get specifiedFolder => 'Cartella specificata';

  @override
  String get specifiedTag => 'Etichetta specificata';

  @override
  String get conflictHandling => 'Gestione conflitti';

  @override
  String get conflictResolutionTitle => 'Risoluzione conflitti';

  @override
  String get noConflicts => 'Nessun conflitto da risolvere';

  @override
  String get allConflictsResolved => 'Tutti i conflitti risolti';

  @override
  String get keepLocalVersion => 'Mantieni tutte le versioni locali';

  @override
  String get keepRemoteVersion => 'Mantieni tutte le versioni remote';

  @override
  String get conflict => 'Conflitto';

  @override
  String get contentConflict => 'Conflitto di contenuto';

  @override
  String get moveConflict => 'Conflitto di spostamento';

  @override
  String get deleteModifyConflict => 'Conflitto eliminazione/modifica';

  @override
  String get diffComparison => 'Confronto differenze';

  @override
  String get localVersion => 'Versione locale';

  @override
  String get remoteVersion => 'Versione remota';

  @override
  String get quickActions => 'Azioni rapide';

  @override
  String get keepLocal => 'Mantieni locale';

  @override
  String get keepRemote => 'Mantieni remota';

  @override
  String get customMerge => 'Unione personalizzata';

  @override
  String get noContentDifference => 'Nessuna differenza di contenuto';

  @override
  String get blockDifferences => 'blocchi di differenza';

  @override
  String get unresolvedBlocks => 'Ci sono blocchi di differenza non risolti';

  @override
  String get resolve => 'Risolvi';

  @override
  String get local => 'Locale';

  @override
  String get remote => 'Remoto';

  @override
  String get empty => '(vuoto)';

  @override
  String get error => 'Errore';
}
