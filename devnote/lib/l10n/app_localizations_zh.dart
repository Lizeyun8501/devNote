// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => '笔记';

  @override
  String get editor => '编辑器';

  @override
  String get search => '搜索';

  @override
  String get settings => '设置';

  @override
  String get knowledgeGraph => '知识图谱';

  @override
  String get noteList => '笔记列表';

  @override
  String get editNote => '编辑笔记';

  @override
  String get newNote => '新建笔记';

  @override
  String get untitled => '无标题';

  @override
  String get noContent => '暂无内容';

  @override
  String get noNotes => '暂无笔记';

  @override
  String get noFolders => '暂无文件夹';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get newSubFolder => '新建子文件夹';

  @override
  String get folderName => '文件夹名称';

  @override
  String get create => '创建';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get delete => '删除';

  @override
  String get rename => '重命名';

  @override
  String get renameFolder => '重命名文件夹';

  @override
  String get ok => '确定';

  @override
  String get save => '保存';

  @override
  String get open => '打开';

  @override
  String get expand => '展开';

  @override
  String get darkMode => '深色模式';

  @override
  String get darkModeSubtitle => '切换深色/浅色主题';

  @override
  String get fontSize => '字体大小';

  @override
  String get autoSave => '自动保存';

  @override
  String get autoSaveSubtitle => '编辑时自动保存笔记';

  @override
  String get defaultEditMode => '默认编辑模式';

  @override
  String get richText => '富文本';

  @override
  String get syncSettings => '同步设置';

  @override
  String get syncSettingsSubtitle => '配置数据同步和冲突解决';

  @override
  String get cryptoSettings => '加密设置';

  @override
  String get cryptoSettingsSubtitle => '管理笔记加密和密码';

  @override
  String get p2pSync => 'P2P 同步';

  @override
  String get p2pSyncSubtitle => '设备间直接同步数据';

  @override
  String get pluginMarketplace => '插件市场';

  @override
  String get pluginMarketplaceSubtitle => '浏览和安装插件';

  @override
  String get pluginManagement => '插件管理';

  @override
  String get pluginManagementSubtitle => '管理已安装的插件';

  @override
  String get importExport => '导入导出';

  @override
  String get importExportSubtitle => '导入或导出笔记数据';

  @override
  String get dataBackup => '数据备份';

  @override
  String get dataBackupSubtitle => '导出笔记数据';

  @override
  String get clearCache => '清除缓存';

  @override
  String get clearCacheSubtitle => '清除本地缓存数据';

  @override
  String get version => '版本';

  @override
  String get openSourceLicenses => '开源许可';

  @override
  String get appearance => '外观';

  @override
  String get data => '数据';

  @override
  String get about => '关于';

  @override
  String get gridView => '网格视图';

  @override
  String get listView => '列表视图';

  @override
  String get sort => '排序';

  @override
  String get sortByUpdatedAt => '按修改时间';

  @override
  String get sortByCreatedAt => '按创建时间';

  @override
  String get sortByTitle => '按标题';

  @override
  String get paragraph => '段落';

  @override
  String get heading => '标题';

  @override
  String get codeBlock => '代码块';

  @override
  String get bulletList => '无序列表';

  @override
  String get quote => '引用';

  @override
  String get noteType => '笔记';

  @override
  String get tagType => '标签';

  @override
  String get folderType => '文件夹';

  @override
  String get canvasType => '画布';

  @override
  String get centralityAnalysis => '中心度分析';

  @override
  String get clusterDetection => '聚类检测';

  @override
  String get enableEncryption => '启用加密';

  @override
  String get disableEncryption => '禁用加密';

  @override
  String get lock => '锁定';

  @override
  String get unlock => '解锁';

  @override
  String get changePassword => '修改密码';

  @override
  String get setEncryptionPassword => '设置加密密码';

  @override
  String get verifyPassword => '验证密码';

  @override
  String get enterCurrentPassword => '输入当前密码';

  @override
  String get setNewPassword => '设置新密码';

  @override
  String get enterPasswordToUnlock => '输入密码解锁';

  @override
  String get encryptionEnabled => '加密已启用';

  @override
  String get encryptionDisabled => '加密已禁用';

  @override
  String get passwordChanged => '密码已修改';

  @override
  String get wrongPassword => '密码错误';

  @override
  String get enableEncryptionFailed => '启用加密失败，密码长度至少6位';

  @override
  String get wrongPasswordCannotDisable => '密码错误，无法禁用加密';

  @override
  String get passwordChangeFailed => '密码修改失败，请检查当前密码是否正确';

  @override
  String get encryptionControl => '加密控制';

  @override
  String get encryptionAlgorithm => '加密算法';

  @override
  String get standard => '标准';

  @override
  String get standardSubtitle => 'Argon2id 3次迭代，适合日常使用';

  @override
  String get highStrength => '高强度';

  @override
  String get highStrengthSubtitle => 'Argon2id 6次迭代，更高安全性';

  @override
  String get encryptionInstructions => '加密说明';

  @override
  String get encryptionDescription => '• 启用加密后，笔记内容将以 XChaCha20-Poly1305 算法加密存储\n• 密码使用 Argon2id 算法派生密钥\n• 请妥善保管密码，忘记密码将无法恢复数据\n• 修改加密强度需要先禁用再重新启用加密';

  @override
  String get import => '导入';

  @override
  String get export => '导出';

  @override
  String get markdownFolder => 'Markdown 文件夹';

  @override
  String get obsidianVault => 'Obsidian Vault';

  @override
  String get joplinExport => 'Joplin 导出';

  @override
  String get conflictResolution => '冲突处理';

  @override
  String get skip => '跳过';

  @override
  String get overwrite => '覆盖';

  @override
  String get startImport => '开始导入';

  @override
  String get startExport => '开始导出';

  @override
  String get allNotes => '全部笔记';

  @override
  String get specifiedFolder => '指定文件夹';

  @override
  String get specifiedTag => '指定标签';

  @override
  String get conflictHandling => '冲突处理方式';

  @override
  String get conflictResolutionTitle => '冲突解决';

  @override
  String get noConflicts => '没有需要解决的冲突';

  @override
  String get allConflictsResolved => '所有冲突已解决';

  @override
  String get keepLocalVersion => '全部保留本地版本';

  @override
  String get keepRemoteVersion => '全部保留远程版本';

  @override
  String get conflict => '冲突';

  @override
  String get contentConflict => '内容冲突';

  @override
  String get moveConflict => '移动冲突';

  @override
  String get deleteModifyConflict => '删除/修改冲突';

  @override
  String get diffComparison => '差异对比';

  @override
  String get localVersion => '本地版本';

  @override
  String get remoteVersion => '远程版本';

  @override
  String get quickActions => '快速操作';

  @override
  String get keepLocal => '保留本地';

  @override
  String get keepRemote => '保留远程';

  @override
  String get customMerge => '自定义合并';

  @override
  String get noContentDifference => '无内容差异';

  @override
  String get blockDifferences => '处差异';

  @override
  String get unresolvedBlocks => '还有未选择的差异块';

  @override
  String get resolve => '解决';

  @override
  String get local => '本地';

  @override
  String get remote => '远程';

  @override
  String get empty => '（空）';

  @override
  String get error => '错误';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw(): super('zh_TW');

  @override
  String get appName => 'DevNote';

  @override
  String get notes => '筆記';

  @override
  String get editor => '編輯器';

  @override
  String get search => '搜尋';

  @override
  String get settings => '設定';

  @override
  String get knowledgeGraph => '知識圖譜';

  @override
  String get noteList => '筆記清單';

  @override
  String get editNote => '編輯筆記';

  @override
  String get newNote => '新增筆記';

  @override
  String get untitled => '無標題';

  @override
  String get noContent => '無內容';

  @override
  String get noNotes => '尚無筆記';

  @override
  String get noFolders => '尚無資料夾';

  @override
  String get newFolder => '新增資料夾';

  @override
  String get newSubFolder => '新增子資料夾';

  @override
  String get folderName => '資料夾名稱';

  @override
  String get create => '建立';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '確認';

  @override
  String get delete => '刪除';

  @override
  String get rename => '重新命名';

  @override
  String get renameFolder => '重新命名資料夾';

  @override
  String get ok => '確定';

  @override
  String get save => '儲存';

  @override
  String get open => '開啟';

  @override
  String get expand => '展開';

  @override
  String get darkMode => '深色模式';

  @override
  String get darkModeSubtitle => '切換深色/淺色主題';

  @override
  String get fontSize => '字型大小';

  @override
  String get autoSave => '自動儲存';

  @override
  String get autoSaveSubtitle => '編輯時自動儲存筆記';

  @override
  String get defaultEditMode => '預設編輯模式';

  @override
  String get richText => '富文本';

  @override
  String get syncSettings => '同步設定';

  @override
  String get syncSettingsSubtitle => '設定資料同步與衝突解決';

  @override
  String get cryptoSettings => '加密設定';

  @override
  String get cryptoSettingsSubtitle => '管理筆記加密與密碼';

  @override
  String get p2pSync => 'P2P 同步';

  @override
  String get p2pSyncSubtitle => '裝置間直接同步資料';

  @override
  String get pluginMarketplace => '外掛市集';

  @override
  String get pluginMarketplaceSubtitle => '瀏覽並安裝外掛';

  @override
  String get pluginManagement => '外掛管理';

  @override
  String get pluginManagementSubtitle => '管理已安裝的外掛';

  @override
  String get importExport => '匯入/匯出';

  @override
  String get importExportSubtitle => '匯入或匯出筆記資料';

  @override
  String get dataBackup => '資料備份';

  @override
  String get dataBackupSubtitle => '匯出筆記資料';

  @override
  String get clearCache => '清除快取';

  @override
  String get clearCacheSubtitle => '清除本機快取資料';

  @override
  String get version => '版本';

  @override
  String get openSourceLicenses => '開源授權';

  @override
  String get appearance => '外觀';

  @override
  String get data => '資料';

  @override
  String get about => '關於';

  @override
  String get gridView => '網格檢視';

  @override
  String get listView => '清單檢視';

  @override
  String get sort => '排序';

  @override
  String get sortByUpdatedAt => '依修改時間';

  @override
  String get sortByCreatedAt => '依建立時間';

  @override
  String get sortByTitle => '依標題';

  @override
  String get paragraph => '段落';

  @override
  String get heading => '標題';

  @override
  String get codeBlock => '程式碼區塊';

  @override
  String get bulletList => '項目符號清單';

  @override
  String get quote => '引用';

  @override
  String get noteType => '筆記';

  @override
  String get tagType => '標籤';

  @override
  String get folderType => '資料夾';

  @override
  String get canvasType => '畫布';

  @override
  String get centralityAnalysis => '中心性分析';

  @override
  String get clusterDetection => '叢集偵測';

  @override
  String get enableEncryption => '啟用加密';

  @override
  String get disableEncryption => '停用加密';

  @override
  String get lock => '鎖定';

  @override
  String get unlock => '解鎖';

  @override
  String get changePassword => '變更密碼';

  @override
  String get setEncryptionPassword => '設定加密密碼';

  @override
  String get verifyPassword => '驗證密碼';

  @override
  String get enterCurrentPassword => '輸入目前密碼';

  @override
  String get setNewPassword => '設定新密碼';

  @override
  String get enterPasswordToUnlock => '輸入密碼以解鎖';

  @override
  String get encryptionEnabled => '加密已啟用';

  @override
  String get encryptionDisabled => '加密已停用';

  @override
  String get passwordChanged => '密碼已變更';

  @override
  String get wrongPassword => '密碼錯誤';

  @override
  String get enableEncryptionFailed => '啟用加密失敗，密碼長度至少需 6 位';

  @override
  String get wrongPasswordCannotDisable => '密碼錯誤，無法停用加密';

  @override
  String get passwordChangeFailed => '密碼變更失敗，請確認目前密碼是否正確';

  @override
  String get encryptionControl => '加密控制';

  @override
  String get encryptionAlgorithm => '加密演算法';

  @override
  String get standard => '標準';

  @override
  String get standardSubtitle => 'Argon2id 3 次迭代，適合日常使用';

  @override
  String get highStrength => '高強度';

  @override
  String get highStrengthSubtitle => 'Argon2id 6 次迭代，安全性更高';

  @override
  String get encryptionInstructions => '加密說明';

  @override
  String get encryptionDescription => '• 啟用加密後，筆記內容將以 XChaCha20-Poly1305 演算法加密儲存\n• 密碼使用 Argon2id 演算法衍生金鑰\n• 請妥善保管密碼，忘記密碼將無法復原資料\n• 修改加密強度需先停用再重新啟用加密';

  @override
  String get import => '匯入';

  @override
  String get export => '匯出';

  @override
  String get markdownFolder => 'Markdown 資料夾';

  @override
  String get obsidianVault => 'Obsidian Vault';

  @override
  String get joplinExport => 'Joplin 匯出';

  @override
  String get conflictResolution => '衝突解決';

  @override
  String get skip => '略過';

  @override
  String get overwrite => '覆寫';

  @override
  String get startImport => '開始匯入';

  @override
  String get startExport => '開始匯出';

  @override
  String get allNotes => '全部筆記';

  @override
  String get specifiedFolder => '指定資料夾';

  @override
  String get specifiedTag => '指定標籤';

  @override
  String get conflictHandling => '衝突處理方式';

  @override
  String get conflictResolutionTitle => '衝突解決';

  @override
  String get noConflicts => '沒有需要解決的衝突';

  @override
  String get allConflictsResolved => '所有衝突已解決';

  @override
  String get keepLocalVersion => '全部保留本機版本';

  @override
  String get keepRemoteVersion => '全部保留遠端版本';

  @override
  String get conflict => '衝突';

  @override
  String get contentConflict => '內容衝突';

  @override
  String get moveConflict => '移動衝突';

  @override
  String get deleteModifyConflict => '刪除/修改衝突';

  @override
  String get diffComparison => '差異比較';

  @override
  String get localVersion => '本機版本';

  @override
  String get remoteVersion => '遠端版本';

  @override
  String get quickActions => '快速操作';

  @override
  String get keepLocal => '保留本機';

  @override
  String get keepRemote => '保留遠端';

  @override
  String get customMerge => '自訂合併';

  @override
  String get noContentDifference => '無內容差異';

  @override
  String get blockDifferences => '處差異';

  @override
  String get unresolvedBlocks => '尚有未選擇的差異區塊';

  @override
  String get resolve => '解決';

  @override
  String get local => '本機';

  @override
  String get remote => '遠端';

  @override
  String get empty => '（空）';

  @override
  String get error => '錯誤';
}
