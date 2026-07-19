import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/todo_model.dart';

/// 通知服务
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// 请求通知权限
  Future<bool> requestPermissions() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return true;
  }

  /// 调度待办提醒
  Future<void> scheduleTodoReminder(TodoItem todo) async {
    await init();

    if (todo.reminderTime == null) return;
    if (todo.reminderTime!.isBefore(DateTime.now())) return;

    final scheduledDate = tz.TZDateTime.from(todo.reminderTime!, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'todo_reminders',
      '待办提醒',
      channelDescription: '待办事项到期提醒',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    // 使用 todo.id 的 hashCode 作为通知 ID
    final notificationId = todo.id.hashCode;

    await _plugin.zonedSchedule(
      id: notificationId,
      title: '待办提醒',
      body: todo.title,
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// 取消待办提醒
  Future<void> cancelTodoReminder(String todoId) async {
    await _plugin.cancel(id: todoId.hashCode);
  }

  /// 取消所有提醒
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// 立即显示通知
  Future<void> showNotification({
    required String title,
    required String body,
    int id = 0,
  }) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'general_notifications',
      '通用通知',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
