class AppConstants {
  const AppConstants._();

  static const String appName = 'DevNote';
  static const String appVersion = '0.1.0';
  static const String appDescription = 'A cloud-based note-taking application';

  static const String defaultDatabaseName = 'devnote.db';
  static const int defaultDatabaseVersion = 1;

  static const String notesBoxName = 'notes';
  static const String settingsBoxName = 'settings';

  static const Duration animationDuration = Duration(milliseconds: 200);
  static const double sidebarWidth = 260.0;
  static const double sidebarMinWidth = 200.0;
  static const double sidebarMaxWidth = 400.0;
  static const double editorMinWidth = 400.0;

  // 响应式布局断点：< 600 走移动端抽屉模式，>= 600 走桌面双栏模式
  static const double mobileBreakpoint = 600.0;
  // 移动端抽屉宽度：屏幕宽 80%，上限 304dp（Material 规范）
  static const double drawerWidthMobile = 304.0;

  static const int maxRecentNotes = 10;
  static const int maxAutoSaveInterval = 30;
}
