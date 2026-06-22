import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_th.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uk.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('pl'),
    Locale('pt'),
    Locale('ru'),
    Locale('th'),
    Locale('tr'),
    Locale('uk'),
    Locale('vi'),
    Locale('zh'),
    Locale('zh', 'TW')
  ];

  /// The application name
  ///
  /// In en, this message translates to:
  /// **'DevNote'**
  String get appName;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @editor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editor;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @knowledgeGraph.
  ///
  /// In en, this message translates to:
  /// **'Knowledge Graph'**
  String get knowledgeGraph;

  /// No description provided for @noteList.
  ///
  /// In en, this message translates to:
  /// **'Note List'**
  String get noteList;

  /// No description provided for @editNote.
  ///
  /// In en, this message translates to:
  /// **'Edit Note'**
  String get editNote;

  /// No description provided for @newNote.
  ///
  /// In en, this message translates to:
  /// **'New Note'**
  String get newNote;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitled;

  /// No description provided for @noContent.
  ///
  /// In en, this message translates to:
  /// **'No content'**
  String get noContent;

  /// No description provided for @noNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get noNotes;

  /// No description provided for @noFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders yet'**
  String get noFolders;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @newSubFolder.
  ///
  /// In en, this message translates to:
  /// **'New Subfolder'**
  String get newSubFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename Folder'**
  String get renameFolder;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @expand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @darkModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Toggle dark/light theme'**
  String get darkModeSubtitle;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSize;

  /// No description provided for @autoSave.
  ///
  /// In en, this message translates to:
  /// **'Auto Save'**
  String get autoSave;

  /// No description provided for @autoSaveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-save notes while editing'**
  String get autoSaveSubtitle;

  /// No description provided for @defaultEditMode.
  ///
  /// In en, this message translates to:
  /// **'Default Edit Mode'**
  String get defaultEditMode;

  /// No description provided for @richText.
  ///
  /// In en, this message translates to:
  /// **'Rich Text'**
  String get richText;

  /// No description provided for @syncSettings.
  ///
  /// In en, this message translates to:
  /// **'Sync Settings'**
  String get syncSettings;

  /// No description provided for @syncSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure data sync and conflict resolution'**
  String get syncSettingsSubtitle;

  /// No description provided for @cryptoSettings.
  ///
  /// In en, this message translates to:
  /// **'Crypto Settings'**
  String get cryptoSettings;

  /// No description provided for @cryptoSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage note encryption and password'**
  String get cryptoSettingsSubtitle;

  /// No description provided for @p2pSync.
  ///
  /// In en, this message translates to:
  /// **'P2P Sync'**
  String get p2pSync;

  /// No description provided for @p2pSyncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync data directly between devices'**
  String get p2pSyncSubtitle;

  /// No description provided for @pluginMarketplace.
  ///
  /// In en, this message translates to:
  /// **'Plugin Marketplace'**
  String get pluginMarketplace;

  /// No description provided for @pluginMarketplaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse and install plugins'**
  String get pluginMarketplaceSubtitle;

  /// No description provided for @pluginManagement.
  ///
  /// In en, this message translates to:
  /// **'Plugin Management'**
  String get pluginManagement;

  /// No description provided for @pluginManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage installed plugins'**
  String get pluginManagementSubtitle;

  /// No description provided for @importExport.
  ///
  /// In en, this message translates to:
  /// **'Import/Export'**
  String get importExport;

  /// No description provided for @importExportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import or export note data'**
  String get importExportSubtitle;

  /// No description provided for @dataBackup.
  ///
  /// In en, this message translates to:
  /// **'Data Backup'**
  String get dataBackup;

  /// No description provided for @dataBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export note data'**
  String get dataBackupSubtitle;

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get clearCache;

  /// No description provided for @clearCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clear local cached data'**
  String get clearCacheSubtitle;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get openSourceLicenses;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid View'**
  String get gridView;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List View'**
  String get listView;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @sortByUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'By Modified Time'**
  String get sortByUpdatedAt;

  /// No description provided for @sortByCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'By Created Time'**
  String get sortByCreatedAt;

  /// No description provided for @sortByTitle.
  ///
  /// In en, this message translates to:
  /// **'By Title'**
  String get sortByTitle;

  /// No description provided for @paragraph.
  ///
  /// In en, this message translates to:
  /// **'Paragraph'**
  String get paragraph;

  /// No description provided for @heading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get heading;

  /// No description provided for @codeBlock.
  ///
  /// In en, this message translates to:
  /// **'Code Block'**
  String get codeBlock;

  /// No description provided for @bulletList.
  ///
  /// In en, this message translates to:
  /// **'Bullet List'**
  String get bulletList;

  /// No description provided for @quote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get quote;

  /// No description provided for @noteType.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteType;

  /// No description provided for @tagType.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tagType;

  /// No description provided for @folderType.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folderType;

  /// No description provided for @canvasType.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get canvasType;

  /// No description provided for @centralityAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Centrality Analysis'**
  String get centralityAnalysis;

  /// No description provided for @clusterDetection.
  ///
  /// In en, this message translates to:
  /// **'Cluster Detection'**
  String get clusterDetection;

  /// No description provided for @enableEncryption.
  ///
  /// In en, this message translates to:
  /// **'Enable Encryption'**
  String get enableEncryption;

  /// No description provided for @disableEncryption.
  ///
  /// In en, this message translates to:
  /// **'Disable Encryption'**
  String get disableEncryption;

  /// No description provided for @lock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lock;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @setEncryptionPassword.
  ///
  /// In en, this message translates to:
  /// **'Set Encryption Password'**
  String get setEncryptionPassword;

  /// No description provided for @verifyPassword.
  ///
  /// In en, this message translates to:
  /// **'Verify Password'**
  String get verifyPassword;

  /// No description provided for @enterCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter Current Password'**
  String get enterCurrentPassword;

  /// No description provided for @setNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set New Password'**
  String get setNewPassword;

  /// No description provided for @enterPasswordToUnlock.
  ///
  /// In en, this message translates to:
  /// **'Enter Password to Unlock'**
  String get enterPasswordToUnlock;

  /// No description provided for @encryptionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Encryption enabled'**
  String get encryptionEnabled;

  /// No description provided for @encryptionDisabled.
  ///
  /// In en, this message translates to:
  /// **'Encryption disabled'**
  String get encryptionDisabled;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get passwordChanged;

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get wrongPassword;

  /// No description provided for @enableEncryptionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to enable encryption, password must be at least 6 characters'**
  String get enableEncryptionFailed;

  /// No description provided for @wrongPasswordCannotDisable.
  ///
  /// In en, this message translates to:
  /// **'Wrong password, cannot disable encryption'**
  String get wrongPasswordCannotDisable;

  /// No description provided for @passwordChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Password change failed, please check your current password'**
  String get passwordChangeFailed;

  /// No description provided for @encryptionControl.
  ///
  /// In en, this message translates to:
  /// **'Encryption Control'**
  String get encryptionControl;

  /// No description provided for @encryptionAlgorithm.
  ///
  /// In en, this message translates to:
  /// **'Encryption Algorithm'**
  String get encryptionAlgorithm;

  /// No description provided for @standard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// No description provided for @standardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Argon2id 3 iterations, suitable for daily use'**
  String get standardSubtitle;

  /// No description provided for @highStrength.
  ///
  /// In en, this message translates to:
  /// **'High Strength'**
  String get highStrength;

  /// No description provided for @highStrengthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Argon2id 6 iterations, higher security'**
  String get highStrengthSubtitle;

  /// No description provided for @encryptionInstructions.
  ///
  /// In en, this message translates to:
  /// **'Encryption Instructions'**
  String get encryptionInstructions;

  /// No description provided for @encryptionDescription.
  ///
  /// In en, this message translates to:
  /// **'• After enabling encryption, note content will be encrypted using XChaCha20-Poly1305\n• Passwords use Argon2id algorithm to derive keys\n• Please keep your password safe, lost password means lost data\n• To change encryption strength, you must disable and re-enable encryption'**
  String get encryptionDescription;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @markdownFolder.
  ///
  /// In en, this message translates to:
  /// **'Markdown Folder'**
  String get markdownFolder;

  /// No description provided for @obsidianVault.
  ///
  /// In en, this message translates to:
  /// **'Obsidian Vault'**
  String get obsidianVault;

  /// No description provided for @joplinExport.
  ///
  /// In en, this message translates to:
  /// **'Joplin Export'**
  String get joplinExport;

  /// No description provided for @conflictResolution.
  ///
  /// In en, this message translates to:
  /// **'Conflict Resolution'**
  String get conflictResolution;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @overwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get overwrite;

  /// No description provided for @startImport.
  ///
  /// In en, this message translates to:
  /// **'Start Import'**
  String get startImport;

  /// No description provided for @startExport.
  ///
  /// In en, this message translates to:
  /// **'Start Export'**
  String get startExport;

  /// No description provided for @allNotes.
  ///
  /// In en, this message translates to:
  /// **'All Notes'**
  String get allNotes;

  /// No description provided for @specifiedFolder.
  ///
  /// In en, this message translates to:
  /// **'Specified Folder'**
  String get specifiedFolder;

  /// No description provided for @specifiedTag.
  ///
  /// In en, this message translates to:
  /// **'Specified Tag'**
  String get specifiedTag;

  /// No description provided for @conflictHandling.
  ///
  /// In en, this message translates to:
  /// **'Conflict Handling'**
  String get conflictHandling;

  /// No description provided for @conflictResolutionTitle.
  ///
  /// In en, this message translates to:
  /// **'Conflict Resolution'**
  String get conflictResolutionTitle;

  /// No description provided for @noConflicts.
  ///
  /// In en, this message translates to:
  /// **'No conflicts to resolve'**
  String get noConflicts;

  /// No description provided for @allConflictsResolved.
  ///
  /// In en, this message translates to:
  /// **'All conflicts resolved'**
  String get allConflictsResolved;

  /// No description provided for @keepLocalVersion.
  ///
  /// In en, this message translates to:
  /// **'Keep All Local Versions'**
  String get keepLocalVersion;

  /// No description provided for @keepRemoteVersion.
  ///
  /// In en, this message translates to:
  /// **'Keep All Remote Versions'**
  String get keepRemoteVersion;

  /// No description provided for @conflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get conflict;

  /// No description provided for @contentConflict.
  ///
  /// In en, this message translates to:
  /// **'Content Conflict'**
  String get contentConflict;

  /// No description provided for @moveConflict.
  ///
  /// In en, this message translates to:
  /// **'Move Conflict'**
  String get moveConflict;

  /// No description provided for @deleteModifyConflict.
  ///
  /// In en, this message translates to:
  /// **'Delete/Modify Conflict'**
  String get deleteModifyConflict;

  /// No description provided for @diffComparison.
  ///
  /// In en, this message translates to:
  /// **'Diff Comparison'**
  String get diffComparison;

  /// No description provided for @localVersion.
  ///
  /// In en, this message translates to:
  /// **'Local Version'**
  String get localVersion;

  /// No description provided for @remoteVersion.
  ///
  /// In en, this message translates to:
  /// **'Remote Version'**
  String get remoteVersion;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @keepLocal.
  ///
  /// In en, this message translates to:
  /// **'Keep Local'**
  String get keepLocal;

  /// No description provided for @keepRemote.
  ///
  /// In en, this message translates to:
  /// **'Keep Remote'**
  String get keepRemote;

  /// No description provided for @customMerge.
  ///
  /// In en, this message translates to:
  /// **'Custom Merge'**
  String get customMerge;

  /// No description provided for @noContentDifference.
  ///
  /// In en, this message translates to:
  /// **'No content difference'**
  String get noContentDifference;

  /// No description provided for @blockDifferences.
  ///
  /// In en, this message translates to:
  /// **'block differences'**
  String get blockDifferences;

  /// No description provided for @unresolvedBlocks.
  ///
  /// In en, this message translates to:
  /// **'There are unresolved difference blocks'**
  String get unresolvedBlocks;

  /// No description provided for @resolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get resolve;

  /// No description provided for @local.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local;

  /// No description provided for @remote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get remote;

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get empty;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'de', 'en', 'es', 'fr', 'hi', 'id', 'it', 'ja', 'ko', 'nl', 'pl', 'pt', 'ru', 'th', 'tr', 'uk', 'vi', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh': {
  switch (locale.countryCode) {
    case 'TW': return AppLocalizationsZhTw();
   }
  break;
   }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'de': return AppLocalizationsDe();
    case 'en': return AppLocalizationsEn();
    case 'es': return AppLocalizationsEs();
    case 'fr': return AppLocalizationsFr();
    case 'hi': return AppLocalizationsHi();
    case 'id': return AppLocalizationsId();
    case 'it': return AppLocalizationsIt();
    case 'ja': return AppLocalizationsJa();
    case 'ko': return AppLocalizationsKo();
    case 'nl': return AppLocalizationsNl();
    case 'pl': return AppLocalizationsPl();
    case 'pt': return AppLocalizationsPt();
    case 'ru': return AppLocalizationsRu();
    case 'th': return AppLocalizationsTh();
    case 'tr': return AppLocalizationsTr();
    case 'uk': return AppLocalizationsUk();
    case 'vi': return AppLocalizationsVi();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
