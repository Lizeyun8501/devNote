// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'Notes';

  @override
  String get editor => 'Editor';

  @override
  String get search => 'Search';

  @override
  String get settings => 'Settings';

  @override
  String get knowledgeGraph => 'Knowledge Graph';

  @override
  String get noteList => 'Note List';

  @override
  String get editNote => 'Edit Note';

  @override
  String get newNote => 'New Note';

  @override
  String get untitled => 'Untitled';

  @override
  String get noContent => 'No content';

  @override
  String get noNotes => 'No notes yet';

  @override
  String get noFolders => 'No folders yet';

  @override
  String get newFolder => 'New Folder';

  @override
  String get newSubFolder => 'New Subfolder';

  @override
  String get folderName => 'Folder name';

  @override
  String get create => 'Create';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get renameFolder => 'Rename Folder';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Save';

  @override
  String get open => 'Open';

  @override
  String get expand => 'Expand';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get darkModeSubtitle => 'Toggle dark/light theme';

  @override
  String get fontSize => 'Font Size';

  @override
  String get autoSave => 'Auto Save';

  @override
  String get autoSaveSubtitle => 'Auto-save notes while editing';

  @override
  String get defaultEditMode => 'Default Edit Mode';

  @override
  String get richText => 'Rich Text';

  @override
  String get syncSettings => 'Sync Settings';

  @override
  String get syncSettingsSubtitle => 'Configure data sync and conflict resolution';

  @override
  String get cryptoSettings => 'Crypto Settings';

  @override
  String get cryptoSettingsSubtitle => 'Manage note encryption and password';

  @override
  String get p2pSync => 'P2P Sync';

  @override
  String get p2pSyncSubtitle => 'Sync data directly between devices';

  @override
  String get pluginMarketplace => 'Plugin Marketplace';

  @override
  String get pluginMarketplaceSubtitle => 'Browse and install plugins';

  @override
  String get pluginManagement => 'Plugin Management';

  @override
  String get pluginManagementSubtitle => 'Manage installed plugins';

  @override
  String get importExport => 'Import/Export';

  @override
  String get importExportSubtitle => 'Import or export note data';

  @override
  String get dataBackup => 'Data Backup';

  @override
  String get dataBackupSubtitle => 'Export note data';

  @override
  String get clearCache => 'Clear Cache';

  @override
  String get clearCacheSubtitle => 'Clear local cached data';

  @override
  String get version => 'Version';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String get appearance => 'Appearance';

  @override
  String get data => 'Data';

  @override
  String get about => 'About';

  @override
  String get gridView => 'Grid View';

  @override
  String get listView => 'List View';

  @override
  String get sort => 'Sort';

  @override
  String get sortByUpdatedAt => 'By Modified Time';

  @override
  String get sortByCreatedAt => 'By Created Time';

  @override
  String get sortByTitle => 'By Title';

  @override
  String get paragraph => 'Paragraph';

  @override
  String get heading => 'Heading';

  @override
  String get codeBlock => 'Code Block';

  @override
  String get bulletList => 'Bullet List';

  @override
  String get quote => 'Quote';

  @override
  String get noteType => 'Note';

  @override
  String get tagType => 'Tag';

  @override
  String get folderType => 'Folder';

  @override
  String get canvasType => 'Canvas';

  @override
  String get centralityAnalysis => 'Centrality Analysis';

  @override
  String get clusterDetection => 'Cluster Detection';

  @override
  String get enableEncryption => 'Enable Encryption';

  @override
  String get disableEncryption => 'Disable Encryption';

  @override
  String get lock => 'Lock';

  @override
  String get unlock => 'Unlock';

  @override
  String get changePassword => 'Change Password';

  @override
  String get setEncryptionPassword => 'Set Encryption Password';

  @override
  String get verifyPassword => 'Verify Password';

  @override
  String get enterCurrentPassword => 'Enter Current Password';

  @override
  String get setNewPassword => 'Set New Password';

  @override
  String get enterPasswordToUnlock => 'Enter Password to Unlock';

  @override
  String get encryptionEnabled => 'Encryption enabled';

  @override
  String get encryptionDisabled => 'Encryption disabled';

  @override
  String get passwordChanged => 'Password changed';

  @override
  String get wrongPassword => 'Wrong password';

  @override
  String get enableEncryptionFailed => 'Failed to enable encryption, password must be at least 6 characters';

  @override
  String get wrongPasswordCannotDisable => 'Wrong password, cannot disable encryption';

  @override
  String get passwordChangeFailed => 'Password change failed, please check your current password';

  @override
  String get encryptionControl => 'Encryption Control';

  @override
  String get encryptionAlgorithm => 'Encryption Algorithm';

  @override
  String get standard => 'Standard';

  @override
  String get standardSubtitle => 'Argon2id 3 iterations, suitable for daily use';

  @override
  String get highStrength => 'High Strength';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 iterations, higher security';

  @override
  String get encryptionInstructions => 'Encryption Instructions';

  @override
  String get encryptionDescription => '• After enabling encryption, note content will be encrypted using XChaCha20-Poly1305\n• Passwords use Argon2id algorithm to derive keys\n• Please keep your password safe, lost password means lost data\n• To change encryption strength, you must disable and re-enable encryption';

  @override
  String get import => 'Import';

  @override
  String get export => 'Export';

  @override
  String get markdownFolder => 'Markdown Folder';

  @override
  String get obsidianVault => 'Obsidian Vault';

  @override
  String get joplinExport => 'Joplin Export';

  @override
  String get conflictResolution => 'Conflict Resolution';

  @override
  String get skip => 'Skip';

  @override
  String get overwrite => 'Overwrite';

  @override
  String get startImport => 'Start Import';

  @override
  String get startExport => 'Start Export';

  @override
  String get allNotes => 'All Notes';

  @override
  String get specifiedFolder => 'Specified Folder';

  @override
  String get specifiedTag => 'Specified Tag';

  @override
  String get conflictHandling => 'Conflict Handling';

  @override
  String get conflictResolutionTitle => 'Conflict Resolution';

  @override
  String get noConflicts => 'No conflicts to resolve';

  @override
  String get allConflictsResolved => 'All conflicts resolved';

  @override
  String get keepLocalVersion => 'Keep All Local Versions';

  @override
  String get keepRemoteVersion => 'Keep All Remote Versions';

  @override
  String get conflict => 'Conflict';

  @override
  String get contentConflict => 'Content Conflict';

  @override
  String get moveConflict => 'Move Conflict';

  @override
  String get deleteModifyConflict => 'Delete/Modify Conflict';

  @override
  String get diffComparison => 'Diff Comparison';

  @override
  String get localVersion => 'Local Version';

  @override
  String get remoteVersion => 'Remote Version';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get keepLocal => 'Keep Local';

  @override
  String get keepRemote => 'Keep Remote';

  @override
  String get customMerge => 'Custom Merge';

  @override
  String get noContentDifference => 'No content difference';

  @override
  String get blockDifferences => 'block differences';

  @override
  String get unresolvedBlocks => 'There are unresolved difference blocks';

  @override
  String get resolve => 'Resolve';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Remote';

  @override
  String get empty => '(empty)';

  @override
  String get error => 'Error';
}
