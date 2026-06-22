// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => 'ノート';

  @override
  String get editor => 'エディタ';

  @override
  String get search => '検索';

  @override
  String get settings => '設定';

  @override
  String get knowledgeGraph => 'ナレッジグラフ';

  @override
  String get noteList => 'ノート一覧';

  @override
  String get editNote => 'ノートを編集';

  @override
  String get newNote => '新規ノート';

  @override
  String get untitled => '無題';

  @override
  String get noContent => '内容なし';

  @override
  String get noNotes => 'ノートがありません';

  @override
  String get noFolders => 'フォルダがありません';

  @override
  String get newFolder => '新規フォルダ';

  @override
  String get newSubFolder => '新規サブフォルダ';

  @override
  String get folderName => 'フォルダ名';

  @override
  String get create => '作成';

  @override
  String get cancel => 'キャンセル';

  @override
  String get confirm => '確認';

  @override
  String get delete => '削除';

  @override
  String get rename => '名前を変更';

  @override
  String get renameFolder => 'フォルダ名を変更';

  @override
  String get ok => 'OK';

  @override
  String get save => '保存';

  @override
  String get open => '開く';

  @override
  String get expand => '展開';

  @override
  String get darkMode => 'ダークモード';

  @override
  String get darkModeSubtitle => 'ダーク/ライトテーマを切り替え';

  @override
  String get fontSize => 'フォントサイズ';

  @override
  String get autoSave => '自動保存';

  @override
  String get autoSaveSubtitle => '編集中のノートを自動保存';

  @override
  String get defaultEditMode => 'デフォルト編集モード';

  @override
  String get richText => 'リッチテキスト';

  @override
  String get syncSettings => '同期設定';

  @override
  String get syncSettingsSubtitle => 'データ同期と競合解決を設定';

  @override
  String get cryptoSettings => '暗号化設定';

  @override
  String get cryptoSettingsSubtitle => 'ノートの暗号化とパスワードを管理';

  @override
  String get p2pSync => 'P2P 同期';

  @override
  String get p2pSyncSubtitle => 'デバイス間で直接データを同期';

  @override
  String get pluginMarketplace => 'プラグインマーケット';

  @override
  String get pluginMarketplaceSubtitle => 'プラグインの閲覧とインストール';

  @override
  String get pluginManagement => 'プラグイン管理';

  @override
  String get pluginManagementSubtitle => 'インストール済みプラグインを管理';

  @override
  String get importExport => 'インポート/エクスポート';

  @override
  String get importExportSubtitle => 'ノートデータのインポート/エクスポート';

  @override
  String get dataBackup => 'データバックアップ';

  @override
  String get dataBackupSubtitle => 'ノートデータをエクスポート';

  @override
  String get clearCache => 'キャッシュクリア';

  @override
  String get clearCacheSubtitle => 'ローカルキャッシュをクリア';

  @override
  String get version => 'バージョン';

  @override
  String get openSourceLicenses => 'オープンソースライセンス';

  @override
  String get appearance => '外観';

  @override
  String get data => 'データ';

  @override
  String get about => '情報';

  @override
  String get gridView => 'グリッド表示';

  @override
  String get listView => 'リスト表示';

  @override
  String get sort => '並び替え';

  @override
  String get sortByUpdatedAt => '更新日時順';

  @override
  String get sortByCreatedAt => '作成日時順';

  @override
  String get sortByTitle => 'タイトル順';

  @override
  String get paragraph => '段落';

  @override
  String get heading => '見出し';

  @override
  String get codeBlock => 'コードブロック';

  @override
  String get bulletList => '箇条書き';

  @override
  String get quote => '引用';

  @override
  String get noteType => 'ノート';

  @override
  String get tagType => 'タグ';

  @override
  String get folderType => 'フォルダ';

  @override
  String get canvasType => 'キャンバス';

  @override
  String get centralityAnalysis => '中心性分析';

  @override
  String get clusterDetection => 'クラスタ検出';

  @override
  String get enableEncryption => '暗号化を有効化';

  @override
  String get disableEncryption => '暗号化を無効化';

  @override
  String get lock => 'ロック';

  @override
  String get unlock => 'ロック解除';

  @override
  String get changePassword => 'パスワード変更';

  @override
  String get setEncryptionPassword => '暗号化パスワードを設定';

  @override
  String get verifyPassword => 'パスワード確認';

  @override
  String get enterCurrentPassword => '現在のパスワードを入力';

  @override
  String get setNewPassword => '新しいパスワードを設定';

  @override
  String get enterPasswordToUnlock => 'パスワードを入力してロック解除';

  @override
  String get encryptionEnabled => '暗号化が有効です';

  @override
  String get encryptionDisabled => '暗号化が無効です';

  @override
  String get passwordChanged => 'パスワードが変更されました';

  @override
  String get wrongPassword => 'パスワードが間違っています';

  @override
  String get enableEncryptionFailed => '暗号化の有効化に失敗しました。パスワードは6文字以上必要です';

  @override
  String get wrongPasswordCannotDisable => 'パスワードが間違っているため、暗号化を無効化できません';

  @override
  String get passwordChangeFailed => 'パスワードの変更に失敗しました。現在のパスワードをご確認ください';

  @override
  String get encryptionControl => '暗号化制御';

  @override
  String get encryptionAlgorithm => '暗号化アルゴリズム';

  @override
  String get standard => '標準';

  @override
  String get standardSubtitle => 'Argon2id 3回反復、日常使用向け';

  @override
  String get highStrength => '高強度';

  @override
  String get highStrengthSubtitle => 'Argon2id 6回反復、より高いセキュリティ';

  @override
  String get encryptionInstructions => '暗号化の説明';

  @override
  String get encryptionDescription => '• 暗号化を有効にすると、ノート内容は XChaCha20-Poly1305 で暗号化されます\n• パスワードは Argon2id アルゴリズムで鍵を導出します\n• パスワードは安全に保管してください。紛失するとデータは復元できません\n• 暗号化強度を変更するには、一度無効化してから再度有効化してください';

  @override
  String get import => 'インポート';

  @override
  String get export => 'エクスポート';

  @override
  String get markdownFolder => 'Markdown フォルダ';

  @override
  String get obsidianVault => 'Obsidian Vault';

  @override
  String get joplinExport => 'Joplin エクスポート';

  @override
  String get conflictResolution => '競合解決';

  @override
  String get skip => 'スキップ';

  @override
  String get overwrite => '上書き';

  @override
  String get startImport => 'インポート開始';

  @override
  String get startExport => 'エクスポート開始';

  @override
  String get allNotes => 'すべてのノート';

  @override
  String get specifiedFolder => '指定フォルダ';

  @override
  String get specifiedTag => '指定タグ';

  @override
  String get conflictHandling => '競合処理';

  @override
  String get conflictResolutionTitle => '競合解決';

  @override
  String get noConflicts => '解決すべき競合はありません';

  @override
  String get allConflictsResolved => 'すべての競合が解決されました';

  @override
  String get keepLocalVersion => 'すべてローカル版を保持';

  @override
  String get keepRemoteVersion => 'すべてリモート版を保持';

  @override
  String get conflict => '競合';

  @override
  String get contentConflict => '内容の競合';

  @override
  String get moveConflict => '移動の競合';

  @override
  String get deleteModifyConflict => '削除/変更の競合';

  @override
  String get diffComparison => '差分比較';

  @override
  String get localVersion => 'ローカル版';

  @override
  String get remoteVersion => 'リモート版';

  @override
  String get quickActions => 'クイック操作';

  @override
  String get keepLocal => 'ローカルを保持';

  @override
  String get keepRemote => 'リモートを保持';

  @override
  String get customMerge => 'カスタムマージ';

  @override
  String get noContentDifference => '内容の差分はありません';

  @override
  String get blockDifferences => '件の差分';

  @override
  String get unresolvedBlocks => '未選択の差分ブロックがあります';

  @override
  String get resolve => '解決';

  @override
  String get local => 'ローカル';

  @override
  String get remote => 'リモート';

  @override
  String get empty => '（空）';

  @override
  String get error => 'エラー';
}
