// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => 'DevNote';

  @override
  String get notes => '노트';

  @override
  String get editor => '편집기';

  @override
  String get search => '검색';

  @override
  String get settings => '설정';

  @override
  String get knowledgeGraph => '지식 그래프';

  @override
  String get noteList => '노트 목록';

  @override
  String get editNote => '노트 편집';

  @override
  String get newNote => '새 노트';

  @override
  String get untitled => '제목 없음';

  @override
  String get noContent => '내용 없음';

  @override
  String get noNotes => '노트가 없습니다';

  @override
  String get noFolders => '폴더가 없습니다';

  @override
  String get newFolder => '새 폴더';

  @override
  String get newSubFolder => '새 하위 폴더';

  @override
  String get folderName => '폴더 이름';

  @override
  String get create => '만들기';

  @override
  String get cancel => '취소';

  @override
  String get confirm => '확인';

  @override
  String get delete => '삭제';

  @override
  String get rename => '이름 변경';

  @override
  String get renameFolder => '폴더 이름 변경';

  @override
  String get ok => '확인';

  @override
  String get save => '저장';

  @override
  String get open => '열기';

  @override
  String get expand => '펼치기';

  @override
  String get darkMode => '다크 모드';

  @override
  String get darkModeSubtitle => '다크/라이트 테마 전환';

  @override
  String get fontSize => '글꼴 크기';

  @override
  String get autoSave => '자동 저장';

  @override
  String get autoSaveSubtitle => '편집 중 노트 자동 저장';

  @override
  String get defaultEditMode => '기본 편집 모드';

  @override
  String get richText => '리치 텍스트';

  @override
  String get syncSettings => '동기화 설정';

  @override
  String get syncSettingsSubtitle => '데이터 동기화 및 충돌 해결 구성';

  @override
  String get cryptoSettings => '암호화 설정';

  @override
  String get cryptoSettingsSubtitle => '노트 암호화 및 비밀번호 관리';

  @override
  String get p2pSync => 'P2P 동기화';

  @override
  String get p2pSyncSubtitle => '기기 간 직접 데이터 동기화';

  @override
  String get pluginMarketplace => '플러그인 마켓';

  @override
  String get pluginMarketplaceSubtitle => '플러그인 탐색 및 설치';

  @override
  String get pluginManagement => '플러그인 관리';

  @override
  String get pluginManagementSubtitle => '설치된 플러그인 관리';

  @override
  String get importExport => '가져오기/내보내기';

  @override
  String get importExportSubtitle => '노트 데이터 가져오기 또는 내보내기';

  @override
  String get dataBackup => '데이터 백업';

  @override
  String get dataBackupSubtitle => '노트 데이터 내보내기';

  @override
  String get clearCache => '캐시 삭제';

  @override
  String get clearCacheSubtitle => '로컬 캐시 데이터 삭제';

  @override
  String get version => '버전';

  @override
  String get openSourceLicenses => '오픈소스 라이선스';

  @override
  String get appearance => '외관';

  @override
  String get data => '데이터';

  @override
  String get about => '정보';

  @override
  String get gridView => '그리드 보기';

  @override
  String get listView => '목록 보기';

  @override
  String get sort => '정렬';

  @override
  String get sortByUpdatedAt => '수정 시간순';

  @override
  String get sortByCreatedAt => '생성 시간순';

  @override
  String get sortByTitle => '제목순';

  @override
  String get paragraph => '단락';

  @override
  String get heading => '제목';

  @override
  String get codeBlock => '코드 블록';

  @override
  String get bulletList => '글머리 기호 목록';

  @override
  String get quote => '인용';

  @override
  String get noteType => '노트';

  @override
  String get tagType => '태그';

  @override
  String get folderType => '폴더';

  @override
  String get canvasType => '캔버스';

  @override
  String get centralityAnalysis => '중심성 분석';

  @override
  String get clusterDetection => '클러스터 감지';

  @override
  String get enableEncryption => '암호화 활성화';

  @override
  String get disableEncryption => '암호화 비활성화';

  @override
  String get lock => '잠금';

  @override
  String get unlock => '잠금 해제';

  @override
  String get changePassword => '비밀번호 변경';

  @override
  String get setEncryptionPassword => '암호화 비밀번호 설정';

  @override
  String get verifyPassword => '비밀번호 확인';

  @override
  String get enterCurrentPassword => '현재 비밀번호 입력';

  @override
  String get setNewPassword => '새 비밀번호 설정';

  @override
  String get enterPasswordToUnlock => '잠금 해제 비밀번호 입력';

  @override
  String get encryptionEnabled => '암호화가 활성화되었습니다';

  @override
  String get encryptionDisabled => '암호화가 비활성화되었습니다';

  @override
  String get passwordChanged => '비밀번호가 변경되었습니다';

  @override
  String get wrongPassword => '비밀번호가 틀렸습니다';

  @override
  String get enableEncryptionFailed => '암호화 활성화 실패, 비밀번호는 최소 6자 이상이어야 합니다';

  @override
  String get wrongPasswordCannotDisable => '비밀번호가 틀려 암호화를 비활성화할 수 없습니다';

  @override
  String get passwordChangeFailed => '비밀번호 변경 실패, 현재 비밀번호를 확인해 주세요';

  @override
  String get encryptionControl => '암호화 제어';

  @override
  String get encryptionAlgorithm => '암호화 알고리즘';

  @override
  String get standard => '표준';

  @override
  String get standardSubtitle => 'Argon2id 3회 반복, 일상 사용에 적합';

  @override
  String get highStrength => '고강도';

  @override
  String get highStrengthSubtitle => 'Argon2id 6회 반복, 더 높은 보안성';

  @override
  String get encryptionInstructions => '암호화 안내';

  @override
  String get encryptionDescription => '• 암호화를 활성화하면 노트 내용이 XChaCha20-Poly1305로 암호화됩니다\n• 비밀번호는 Argon2id 알고리즘으로 키를 파생합니다\n• 비밀번호를 안전하게 보관하세요. 분실 시 데이터를 복구할 수 없습니다\n• 암호화 강도를 변경하려면 비활성화 후 다시 활성화해야 합니다';

  @override
  String get import => '가져오기';

  @override
  String get export => '내보내기';

  @override
  String get markdownFolder => 'Markdown 폴더';

  @override
  String get obsidianVault => 'Obsidian Vault';

  @override
  String get joplinExport => 'Joplin 내보내기';

  @override
  String get conflictResolution => '충돌 해결';

  @override
  String get skip => '건너뛰기';

  @override
  String get overwrite => '덮어쓰기';

  @override
  String get startImport => '가져오기 시작';

  @override
  String get startExport => '내보내기 시작';

  @override
  String get allNotes => '모든 노트';

  @override
  String get specifiedFolder => '지정 폴더';

  @override
  String get specifiedTag => '지정 태그';

  @override
  String get conflictHandling => '충돌 처리';

  @override
  String get conflictResolutionTitle => '충돌 해결';

  @override
  String get noConflicts => '해결할 충돌이 없습니다';

  @override
  String get allConflictsResolved => '모든 충돌이 해결되었습니다';

  @override
  String get keepLocalVersion => '모두 로컬 버전 유지';

  @override
  String get keepRemoteVersion => '모두 원격 버전 유지';

  @override
  String get conflict => '충돌';

  @override
  String get contentConflict => '내용 충돌';

  @override
  String get moveConflict => '이동 충돌';

  @override
  String get deleteModifyConflict => '삭제/수정 충돌';

  @override
  String get diffComparison => '차이 비교';

  @override
  String get localVersion => '로컬 버전';

  @override
  String get remoteVersion => '원격 버전';

  @override
  String get quickActions => '빠른 작업';

  @override
  String get keepLocal => '로컬 유지';

  @override
  String get keepRemote => '원격 유지';

  @override
  String get customMerge => '사용자 지정 병합';

  @override
  String get noContentDifference => '내용 차이 없음';

  @override
  String get blockDifferences => '개 차이';

  @override
  String get unresolvedBlocks => '선택하지 않은 차이 블록이 있습니다';

  @override
  String get resolve => '해결';

  @override
  String get local => '로컬';

  @override
  String get remote => '원격';

  @override
  String get empty => '(비어 있음)';

  @override
  String get error => '오류';
}
