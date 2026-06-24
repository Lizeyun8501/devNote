/// 应用全局配置常量
///
/// 集中管理服务器地址、SharedPreferences 键名等散落常量的单一来源。
/// P3-2 修复: 消除硬编码服务器地址（sync.devnote.app）的 7 处分散引用。
library;

/// 默认同步服务器地址
const String defaultSyncServerUrl = 'https://sync.devnote.app';

/// 默认业务服务器地址
/// P1-1: DevNoteApiClient 注册时需要 businessServerUrl
const String defaultBusinessServerUrl = 'https://business.devnote.app';

/// 默认实时协作 WebSocket 地址
const String defaultRealtimeServerUrl = 'wss://sync.devnote.app/realtime';

/// SharedPreferences 中存储同步服务器地址的键名
const String syncServerUrlKey = 'sync_server_url';

/// SharedPreferences 中存储认证令牌的键名
const String syncAuthTokenKey = 'sync_auth_token';