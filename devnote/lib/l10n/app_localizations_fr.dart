// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'Notes';

  @override
  String get editor => 'Éditeur';

  @override
  String get search => 'Rechercher';

  @override
  String get settings => 'Paramètres';

  @override
  String get knowledgeGraph => 'Graphe de connaissances';

  @override
  String get noteList => 'Liste des notes';

  @override
  String get editNote => 'Modifier la note';

  @override
  String get newNote => 'Nouvelle note';

  @override
  String get untitled => 'Sans titre';

  @override
  String get noContent => 'Aucun contenu';

  @override
  String get noNotes => 'Aucune note pour le moment';

  @override
  String get noFolders => 'Aucun dossier pour le moment';

  @override
  String get newFolder => 'Nouveau dossier';

  @override
  String get newSubFolder => 'Nouveau sous-dossier';

  @override
  String get folderName => 'Nom du dossier';

  @override
  String get create => 'Créer';

  @override
  String get cancel => 'Annuler';

  @override
  String get confirm => 'Confirmer';

  @override
  String get delete => 'Supprimer';

  @override
  String get rename => 'Renommer';

  @override
  String get renameFolder => 'Renommer le dossier';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Enregistrer';

  @override
  String get open => 'Ouvrir';

  @override
  String get expand => 'Développer';

  @override
  String get darkMode => 'Mode sombre';

  @override
  String get darkModeSubtitle => 'Basculer entre thème sombre/clair';

  @override
  String get fontSize => 'Taille de police';

  @override
  String get autoSave => 'Enregistrement automatique';

  @override
  String get autoSaveSubtitle => 'Enregistrer les notes pendant l\'édition';

  @override
  String get defaultEditMode => 'Mode d\'édition par défaut';

  @override
  String get richText => 'Texte enrichi';

  @override
  String get syncSettings => 'Paramètres de synchronisation';

  @override
  String get syncSettingsSubtitle => 'Configurer la synchronisation et la résolution des conflits';

  @override
  String get cryptoSettings => 'Paramètres de chiffrement';

  @override
  String get cryptoSettingsSubtitle => 'Gérer le chiffrement des notes et le mot de passe';

  @override
  String get p2pSync => 'Synchronisation P2P';

  @override
  String get p2pSyncSubtitle => 'Synchroniser les données directement entre appareils';

  @override
  String get pluginMarketplace => 'Catalogue de plugins';

  @override
  String get pluginMarketplaceSubtitle => 'Parcourir et installer des plugins';

  @override
  String get pluginManagement => 'Gestion des plugins';

  @override
  String get pluginManagementSubtitle => 'Gérer les plugins installés';

  @override
  String get importExport => 'Importer/Exporter';

  @override
  String get importExportSubtitle => 'Importer ou exporter des données de notes';

  @override
  String get dataBackup => 'Sauvegarde des données';

  @override
  String get dataBackupSubtitle => 'Exporter les données des notes';

  @override
  String get clearCache => 'Vider le cache';

  @override
  String get clearCacheSubtitle => 'Effacer les données en cache local';

  @override
  String get version => 'Version';

  @override
  String get openSourceLicenses => 'Licences open source';

  @override
  String get appearance => 'Apparence';

  @override
  String get data => 'Données';

  @override
  String get about => 'À propos';

  @override
  String get gridView => 'Vue grille';

  @override
  String get listView => 'Vue liste';

  @override
  String get sort => 'Trier';

  @override
  String get sortByUpdatedAt => 'Par date de modification';

  @override
  String get sortByCreatedAt => 'Par date de création';

  @override
  String get sortByTitle => 'Par titre';

  @override
  String get paragraph => 'Paragraphe';

  @override
  String get heading => 'Titre';

  @override
  String get codeBlock => 'Bloc de code';

  @override
  String get bulletList => 'Liste à puces';

  @override
  String get quote => 'Citation';

  @override
  String get noteType => 'Note';

  @override
  String get tagType => 'Étiquette';

  @override
  String get folderType => 'Dossier';

  @override
  String get canvasType => 'Canevas';

  @override
  String get centralityAnalysis => 'Analyse de centralité';

  @override
  String get clusterDetection => 'Détection de clusters';

  @override
  String get enableEncryption => 'Activer le chiffrement';

  @override
  String get disableEncryption => 'Désactiver le chiffrement';

  @override
  String get lock => 'Verrouiller';

  @override
  String get unlock => 'Déverrouiller';

  @override
  String get changePassword => 'Changer le mot de passe';

  @override
  String get setEncryptionPassword => 'Définir le mot de passe de chiffrement';

  @override
  String get verifyPassword => 'Vérifier le mot de passe';

  @override
  String get enterCurrentPassword => 'Saisir le mot de passe actuel';

  @override
  String get setNewPassword => 'Définir un nouveau mot de passe';

  @override
  String get enterPasswordToUnlock => 'Saisir le mot de passe pour déverrouiller';

  @override
  String get encryptionEnabled => 'Chiffrement activé';

  @override
  String get encryptionDisabled => 'Chiffrement désactivé';

  @override
  String get passwordChanged => 'Mot de passe modifié';

  @override
  String get wrongPassword => 'Mot de passe incorrect';

  @override
  String get enableEncryptionFailed => 'Échec de l\'activation du chiffrement, le mot de passe doit contenir au moins 6 caractères';

  @override
  String get wrongPasswordCannotDisable => 'Mot de passe incorrect, impossible de désactiver le chiffrement';

  @override
  String get passwordChangeFailed => 'Échec du changement de mot de passe, veuillez vérifier votre mot de passe actuel';

  @override
  String get encryptionControl => 'Contrôle du chiffrement';

  @override
  String get encryptionAlgorithm => 'Algorithme de chiffrement';

  @override
  String get standard => 'Standard';

  @override
  String get standardSubtitle => 'Argon2id 3 itérations, adapté à un usage quotidien';

  @override
  String get highStrength => 'Haute sécurité';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 itérations, sécurité accrue';

  @override
  String get encryptionInstructions => 'Instructions de chiffrement';

  @override
  String get encryptionDescription => '• Après activation du chiffrement, le contenu des notes sera chiffré avec XChaCha20-Poly1305\n• Le mot de passe utilise l\'algorithme Argon2id pour dériver la clé\n• Conservez votre mot de passe en sécurité, sa perte entraîne la perte des données\n• Pour modifier la force du chiffrement, vous devez le désactiver puis le réactiver';

  @override
  String get import => 'Importer';

  @override
  String get export => 'Exporter';

  @override
  String get markdownFolder => 'Dossier Markdown';

  @override
  String get obsidianVault => 'Coffre Obsidian';

  @override
  String get joplinExport => 'Export Joplin';

  @override
  String get conflictResolution => 'Résolution des conflits';

  @override
  String get skip => 'Ignorer';

  @override
  String get overwrite => 'Écraser';

  @override
  String get startImport => 'Démarrer l\'import';

  @override
  String get startExport => 'Démarrer l\'export';

  @override
  String get allNotes => 'Toutes les notes';

  @override
  String get specifiedFolder => 'Dossier spécifié';

  @override
  String get specifiedTag => 'Étiquette spécifiée';

  @override
  String get conflictHandling => 'Gestion des conflits';

  @override
  String get conflictResolutionTitle => 'Résolution des conflits';

  @override
  String get noConflicts => 'Aucun conflit à résoudre';

  @override
  String get allConflictsResolved => 'Tous les conflits sont résolus';

  @override
  String get keepLocalVersion => 'Garder toutes les versions locales';

  @override
  String get keepRemoteVersion => 'Garder toutes les versions distantes';

  @override
  String get conflict => 'Conflit';

  @override
  String get contentConflict => 'Conflit de contenu';

  @override
  String get moveConflict => 'Conflit de déplacement';

  @override
  String get deleteModifyConflict => 'Conflit suppression/modification';

  @override
  String get diffComparison => 'Comparaison des différences';

  @override
  String get localVersion => 'Version locale';

  @override
  String get remoteVersion => 'Version distante';

  @override
  String get quickActions => 'Actions rapides';

  @override
  String get keepLocal => 'Garder local';

  @override
  String get keepRemote => 'Garder distant';

  @override
  String get customMerge => 'Fusion personnalisée';

  @override
  String get noContentDifference => 'Aucune différence de contenu';

  @override
  String get blockDifferences => 'blocs de différence';

  @override
  String get unresolvedBlocks => 'Il reste des blocs de différence non résolus';

  @override
  String get resolve => 'Résoudre';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Distant';

  @override
  String get empty => '(vide)';

  @override
  String get error => 'Erreur';
}
