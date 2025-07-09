import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'Data/etc.dart';
import 'Data/userData.dart';
import 'Data/appinfo.dart';
import 'Data/ics.dart';
import 'package:flutter/material.dart';
import 'package:plato_calendar/logger.dart';

class Notify {
  static int _notificationId = 0;
  static late Logger _logger;
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _notificationDetails = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    ),
  );

  /// 시간대 초기화 (최초 한 번만 호출)
  static void initializeTimeZone() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
  }

  /// 알림 초기화
  static Future<bool> notificationInit() async {
    try {
      // 시간대 초기화
      initializeTimeZone();

      const initSettings = InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        ),
      );

      final iosImplementation = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      // iOS 권한 확인 및 요청
      debugPrint('iOS 알림 권한 확인 시작');
      final iosPermission = await iosImplementation?.checkPermissions();
      if (iosPermission?.isEnabled != true) {
        debugPrint('iOS 알림 권한 요청 시작');
        final granted = await iosImplementation?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (granted != true) {
          debugPrint('iOS 알림 권한 거부됨');
          return false;
        }
        debugPrint('iOS 알림 권한 허용됨');
      } else {
        debugPrint('iOS 알림 권한 이미 허용됨');
      }

      // 알림 초기화
      final success = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) =>
            _onNotificationDisplayed(response),
      );

      if (!success!) {
        debugPrint('알림 초기화 실패');
        return false;
      }

      _logger = Logger();
      debugPrint('알림 초기화 완료');
      return true;
    } catch (e, stackTrace) {
      debugPrint('알림 초기화 오류: $e\n$stackTrace');
      return false;
    }
  }

  /// 알림 표시 후 재예약
  static Future<void> _onNotificationDisplayed(
      NotificationResponse response) async {
    debugPrint('알림 표시됨: ${response.payload} (ID: ${response.id})');
    // 다음 날 알림 재예약
    final now = tz.TZDateTime.now(tz.getLocation('Asia/Seoul'));
    final nextMidnight =
        tz.TZDateTime(tz.local, now.year, now.month, now.day + 1);
    final delay = nextMidnight.difference(now);
    if (delay.inSeconds > 0) {
      Future.delayed(delay, () async {
        debugPrint('다음 날 자정 알림 재예약 시작: ${nextMidnight.toString()}');
        await scheduleEventReminderNotifications();
        debugPrint('알림 재예약 완료');
      });
      debugPrint('재예약 예약됨: ${nextMidnight.toString()} (지연: ${delay.inSeconds}초)');
    } else {
      debugPrint('재예약 스킵: 이미 지난 시간');
    }
  }

  /// 시간 단위 텍스트 변환
  static String formatReminderTime(int minutes) {
    final duration = Duration(minutes: minutes);
    final days = duration.inDays;
    final hours = duration.inHours % 24;

    if (days > 0) {
      return '$days일 ${hours}시간 전';
    } else {
      return '${hours}시간 전';
    }
  }

  /// 모든 일정에 대한 알림 예약
  static Future<void> scheduleEventReminderNotifications() async {
    try {
      // 사용자 설정에서 알림 시간(분 단위) 가져오기
      final int reminderMinutes = UserData.notificationBeforeMinutes ?? 60; // 기본값 60분
      final now = tz.TZDateTime.now(tz.getLocation('Asia/Seoul'));

      // 유효한 일정 확인 (현재 이후 마감)
      final validEvents = UserData.data.where((e) =>
          !e.disable &&
          !e.finished &&
          e.end.isAfter(now)).toList();

      if (validEvents.isEmpty) {
        debugPrint('유효한 일정 없음 - 알림 예약 스킵');
        await _cancelEventReminderNotifications(); // 기존 알림 취소
        return;
      }

      debugPrint('일정 알림 예약 시작: 현재 시간 ${now.toString()}, 알림 시간: $reminderMinutes 분 전');

      // 기존 알림 취소 (ID 1번부터 사용)
      await _cancelEventReminderNotifications();
      debugPrint('기존 일정 알림 모두 취소 완료');

      int notificationId = 1; // ID 1부터 시작
      for (var element in validEvents) {
        final reminderTime = tz.TZDateTime.from(
          element.end.subtract(Duration(minutes: reminderMinutes)),
          tz.getLocation('Asia/Seoul'),
        );

        // 이미 지난 시간이라면 스킵
        if (reminderTime.isBefore(now)) {
          debugPrint('알림 시간 이미 지남: ${element.className}, 마감: ${element.end}');
          continue;
        }

        final className = element.className.isNotEmpty ? element.className : element.classCode;
        final contents = element.summary.length >= 25
            ? '${element.summary.substring(0, 24)}..'
            : element.summary;

        final timeString = formatReminderTime(reminderMinutes);
        final body = '• $contents';

        await _plugin.zonedSchedule(
          notificationId,
          '$className ($timeString)',
          body,
          reminderTime,
          _notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        debugPrint('알림 예약 완료: $className, ID: $notificationId, 시간: ${reminderTime.toString()}');
        notificationId++;
      }

      debugPrint('일정 알림 예약 완료: 총 ${notificationId - 1}개 알림');
    } catch (e, stackTrace) {
      debugPrint('일정 알림 예약 오류: $e\n$stackTrace');
      await notifyDebugInfo('일정 알림 예약 오류: $e', sendLog: true, trace: stackTrace);
    }
  }

  /// 기존 일정 알림 취소
  static Future<void> _cancelEventReminderNotifications() async {
    // ID 1 이상의 모든 알림 취소
    for (int id = 1; id <= _notificationId; id++) {
      await _plugin.cancel(id);
    }
    debugPrint('ID 1 이상의 모든 알림 취소 완료');
  }

  /// 사용자 설정 변경 시 알림 재예약
  static Future<void> updateEventReminderNotifications() async {
    debugPrint('알림 설정 변경 감지, 알림 재예약 시작');
    await scheduleEventReminderNotifications();
  }

  /// 오늘 일정 즉시 알림
  static Future<void> notifyTodaySchedule() async {
    final now = DateTime.now();
    debugPrint('수동 알림 시도: ${now.day}일');

    if (UserData.notificationDay == now.day) {
      debugPrint('오늘 알림 이미 보냄');
      return;
    }

    final body = await _buildNotificationBody(
      targetDate: tz.TZDateTime.now(tz.getLocation('Asia/Seoul')),
    );
    if (body.isEmpty || body == '예정된 일정이 없습니다.') {
      debugPrint('알림 내용 없음');
      return;
    }

    UserData.notificationDay = now.day; // setter를 통해 Hive에 저장

    await _plugin.show(
      _generateUniqueId(),
      '오늘의 일정',
      body,
      _notificationDetails,
      payload: 'today_schedule',
    );
    debugPrint('수동 알림 표시 완료');
  }

  /// 알림 내용 생성 (notifyTodaySchedule용)
  static Future<String> _buildNotificationBody(
      {required tz.TZDateTime targetDate}) async {
    final targetMonth = targetDate.month;
    final targetDay = targetDate.day;
    final buffer = StringBuffer();
    var count = 1;

    debugPrint('알림 내용 생성: ${targetDate.year}-$targetMonth-$targetDay');

    for (var element in UserData.data.where((e) =>
        !e.disable &&
        !e.finished &&
        e.end.month == targetMonth &&
        e.end.day == targetDay)) {
      final className =
          element.className.isNotEmpty ? element.className : element.classCode;
      final contents = element.summary.length >= 25
          ? '${element.summary.substring(0, 24)}..'
          : element.summary;
      final timeInfo = element.start.day != element.end.day
          ? '~ ${getTimeLocaleKR(element.end)}'
          : '${getTimeLocaleKR(element.end)}까지';

      buffer
        ..writeln('$count. $className ($timeInfo)')
        ..writeln('   - $contents');
      count++;
    }

    final body = buffer.toString().trim();
    if (body.isEmpty) {
      debugPrint('일정 없음 - 기본 내용 반환');
      return '예정된 일정이 없습니다.';
    }
    debugPrint('알림 내용: $body');
    return body;
  }

  /// 디버그 알림
  static Future<void> notifyDebugInfo(
    String error, {
    bool sendLog = false,
    StackTrace? trace,
    String additionalInfo = '',
  }) async {
    if (sendLog) {
      _logger.sendEmail(error, trace?.toString() ?? '', additionalInfo);
    }

    if (Appinfo.buildType == BuildType.release) {
      debugPrint('릴리스 모드 - 디버그 알림 무시');
      return;
    }

    const debugDetails = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final id = _generateUniqueId();
    await _plugin.show(
      id,
      'Error',
      '$id. $error',
      debugDetails,
      payload: 'error_$id',
    );
    debugPrint('디버그 알림 표시: $error (ID: $id)');
  }

  /// 고유 알림 ID 생성
  static int _generateUniqueId() {
    _notificationId++;
    return _notificationId;
  }

  /// 즉시 알림 표시
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final id = _generateUniqueId();
      await _plugin.show(
        id,
        title,
        body,
        _notificationDetails,
        payload: payload,
      );
      debugPrint('즉시 알림 표시: $title (ID: $id)');
    } catch (e) {
      debugPrint('즉시 알림 표시 실패: $e');
    }
  }

  /// 새로운 일정 알림
  static Future<void> notifyNewEvent(CalendarData event) async {
    try {
      final id = _generateUniqueId();
      final title = '새로운 일정: ${event.summary}';
      final body = '${event.className} - ${event.description.isNotEmpty ? event.description : '새로운 일정이 추가되었습니다'}';
      
      await _plugin.show(
        id,
        title,
        body,
        _notificationDetails,
        payload: 'new_event_${event.uid}',
      );
      debugPrint('새 일정 알림 표시: $title (ID: $id)');
    } catch (e) {
      debugPrint('새 일정 알림 표시 실패: $e');
    }
  }
}