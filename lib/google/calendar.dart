import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:plato_calendar/Data/ics.dart';
import 'package:plato_calendar/utility.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Data/privateKey.dart';

import '../Data/database/database.dart';
import '../Data/userData.dart';
import '../notify.dart';
import '../main.dart';

part 'calendar.g.dart';

void prompt(String url) async {
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}

class GoogleCalendarToken {
  // AccessCredentials

  //AcessToken
  late String type;
  late String data;
  late DateTime expiry;

  late String refreshToken;
  late List<String> scopes;

  // token 갱신 여부 check하고 update
  // late Stream<AccessCredentials> tokenStream;
  late AccessCredentials token;
  late AuthClient client;

  /// Google API 통신담당 queue
  ///
  /// Queue에 Event calendar를 넣으면
  ///
  /// 1초에 하나씩 처리함(Rate Limit Exceeded 방지)
  ///
  /// 실패할 때마다 대기시간을 2의 지수승으로 증가시킴.
  late StreamController<CalendarData> googleAsyncQueue;

  /// googleAsyncQueue open
  void openStream() {
    googleAsyncQueue = StreamController<CalendarData>();
    googleAsyncQueue.stream.asyncMap((CalendarData data) async {
      bool result;
      if (data.disable ||
          data.finished) // (UserData.showFinished && data.finished)
        result = await UserData.googleCalendar.deleteCalendar(data.toEvent());
      else
        result = await UserData.googleCalendar.updateCalendar(data.toEvent());
      if (!result) {
        if (UserData.googleCalendar.failCount >= 9) {
          UserData.googleCalendar.googleAsyncQueue.close();
          Notify.notifyDebugInfo("googleCalendar.failCount is exceeded limit.",
              sendLog: true);
        } else {
          UserData.googleCalendar.googleAsyncQueue.add(data);
          UserData.googleCalendar.asyncQueueSize++;
        }
      }
      UserData.googleCalendar.asyncQueueSize--;
      await Future.delayed(
          Duration(seconds: UserData.googleCalendar.delayTime));
    }).listen((event) {});
  }

  /// googleAsyncQueue close
  Future<void> closeStream() async {
    await googleAsyncQueue.close();
  }

  // db에서 null 체크하고 null일 경우 UserData.isSaveGoogleToken = false로 변경필요.
  GoogleCalendarToken(
    this.type,
    this.data,
    this.expiry,
    this.refreshToken,
    this.scopes,
  );

  /// Must call this function after DB restores GoogleCalendarToken Data
  Future<bool> restoreAutoRefreshingAuthClient() async {
    try {
      if (!UserData.isSaveGoogleToken) return false;
      final GoogleSignIn googleSignIn = GoogleSignIn(
        // Google Cloud Console에서 생성한 OAuth 2.0 클라이언트 ID의 스코프를 지정하세요.
        scopes: <String>[calendar.CalendarApi.calendarScope],
      );
      await googleSignIn.signInSilently();
      final client = await googleSignIn.authenticatedClient();
      if (client != null) {
        this.client = client;
      } else {
        logOutGoogleAccount();
      }
      // token = AccessCredentials(AccessToken(this.type, this.data, this.expiry),
      //     this.refreshToken, this.scopes);

      // client = autoRefreshingClient(
      //     ClientId(PrivateKey.clientIDIdentifier, ""), token, Client());
      // token = client.credentials;
    } catch (e, trace) {
      Notify.notifyDebugInfo(e.toString(), sendLog: true, trace: trace);
      return false;
    }
    return true;
  }

  Future<bool> authUsingGoogleAccount() async {
    final GoogleSignIn googleSignIn = GoogleSignIn(
      // Google Cloud Console에서 생성한 OAuth 2.0 클라이언트 ID의 스코프를 지정하세요.
      scopes: <String>[calendar.CalendarApi.calendarScope],
    );
    googleSignIn.onCurrentUserChanged
        .listen((GoogleSignInAccount? account) async {
      print('login sucess : ${account?.email ?? 'empty'}');
      try {
        final client = await googleSignIn.authenticatedClient();
        if (client != null) {
          // final authClient = await account.

          final newToken = client.credentials;
          this.type = newToken.accessToken.type;
          this.data = newToken.accessToken.data;
          this.expiry = newToken.accessToken.expiry;
          this.refreshToken = newToken.refreshToken ?? "test";
          this.scopes = newToken.scopes;
          // this.tokenStream = newClient.credentialUpdates;
          this.token = newToken;
          this.client = client;

          print('get client success');

          //prompt("app://com.seunggil.plato_calendar/");
          UserData.isSaveGoogleToken = true;
          UserData.googleFirstLogin = true;
          await UserData.writeDatabase.googleDataSave();
          await Future.delayed(Duration(seconds: 2));
          pnuStream.sink.add(true);
          await updateCalendarFull();
          // 로그인 완료 후 앱으로 화면 전환이 안됨.
          // 따라서 로그인 토큰 기록후 어플 종료.
          // 다음 실행 때 Google Calendar로 일정 업로드 시작.
          // if (Platform.isAndroid)
          //   SystemNavigator.pop();
          // else if (Platform.isIOS) exit(0);
        }
      } catch (e, trace) {
        Notify.notifyDebugInfo(e.toString(), sendLog: true, trace: trace);
      }
    });
    try {
      await googleSignIn.signIn();
    } catch (e) {
      print(e);
    }

    return true;
  }

  Future<void> logOutGoogleAccount() async {
    UserData.isSaveGoogleToken = false;
    this.type = "";
    this.data = "";
    this.expiry = DateTime(1990);
    this.refreshToken = "";
    this.scopes = [];
    final GoogleSignIn googleSignIn = GoogleSignIn(
      // Google Cloud Console에서 생성한 OAuth 2.0 클라이언트 ID의 스코프를 지정하세요.
      scopes: <String>[calendar.CalendarApi.calendarScope],
    );
    await googleSignIn.signOut();
    await UserData.writeDatabase.googleDataSave();
  }

  /// Google Calendar 업데이트를 delayTime 초 마다 한번 씩 진행.
  ///
  /// success면 delayTime이 1초로,
  ///
  /// Fail처리가 될 경우 delayTime이 2의 지수 승으로 증가함.
  int delayTime = 1;

  /// Google Calendar 업데이트를 연속으로 failCount만큼 실패함.
  ///
  /// Fail처리가 될 경우 delayTime이 2의 지수 승으로 증가함.
  int failCount = 0;

  /// asyncQueueSize에 들어있는 데이터 갯수.
  int asyncQueueSize = 0;

  /// google 계정 연동 직후 데이터 전체 Google Calendar로 update
  /// 그 외의 경우 그냥 함수 종료.
  Future<bool> updateCalendarFull() async {
    if (!(UserData.isSaveGoogleToken && UserData.googleFirstLogin)) {
      return false;
    }

    int total = 0;
    int completed = 0;
    DateTime nowTime = DateTime.now();
    List<Future<bool>> futures = [];
    const int batchSize = 5; // 한 번에 처리할 작업 수 (Rate Limit에 맞게 조정)

    // 작업 큐 생성
    List<CalendarData> tasks = [];
    for (var data in UserData.data) {
      Duration diff = nowTime.difference(data.end);
      if (!data.disable && !data.finished && diff.inDays <= 5) {
        tasks.add(data);
        total++;
        asyncQueueSize++;
      }
    }

    if (total == 0) {
      showToastMessageCenter("동기화할 일정이 없습니다.");
      UserData.googleFirstLogin = false;
      return true;
    }

    // 진행 상황 표시용 타이머
    Timer? progressTimer;
    progressTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (asyncQueueSize > 0) {
        showToastMessageCenter(
            "Google 동기화를 진행중입니다. 앱을 종료하지 말아 주세요.($completed/$total)");
      } else {
        timer.cancel();
      }
    });

    // 배치 단위로 병렬 처리
    for (int i = 0; i < tasks.length; i += batchSize) {
      futures.clear();
      int end = (i + batchSize < tasks.length) ? i + batchSize : tasks.length;
      for (int j = i; j < end; j++) {
        futures.add(updateCalendar(tasks[j].toEvent()).then((result) {
          if (result) completed++;
          asyncQueueSize--;
          return result;
        }));
      }
      await Future.wait(futures, eagerError: true);
      await Future.delayed(Duration(milliseconds: 500)); // 배치 간 최소 대기
    }

    progressTimer?.cancel();
    UserData.googleFirstLogin = false;
    showToastMessageCenter("Google 동기화 완료! ($completed/$total)");
    return true;
  }

  Future<bool> updateCalendarRe() async {
    if (!(UserData.isSaveGoogleToken && !UserData.googleFirstLogin)) {
      return false;
    }

    int total = 0;
    int completed = 0;
    DateTime nowTime = DateTime.now();
    List<Future<bool>> futures = [];
    const int batchSize = 5; // 한 번에 처리할 작업 수 (Rate Limit에 맞게 조정)

    // 작업 큐 생성
    List<CalendarData> tasks = [];
    for (var data in UserData.data) {
      Duration diff = nowTime.difference(data.end);
      if (!data.disable && !data.finished && diff.inDays <= 5) {
        tasks.add(data);
        total++;
        asyncQueueSize++;
      }
    }

    if (total == 0) {
      showToastMessageCenter("동기화할 일정이 없습니다.");
      return true;
    }

    // 진행 상황 표시용 타이머
    Timer? progressTimer;
    progressTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (asyncQueueSize > 0) {
        showToastMessageCenter(
            "Google 동기화를 진행중입니다. 앱을 종료하지 말아 주세요.($completed/$total)");
      } else {
        timer.cancel();
      }
    });

    // 배치 단위로 병렬 처리
    for (int i = 0; i < tasks.length; i += batchSize) {
      futures.clear();
      int end = (i + batchSize < tasks.length) ? i + batchSize : tasks.length;
      for (int j = i; j < end; j++) {
        futures.add(updateCalendar(tasks[j].toEvent()).then((result) {
          if (result) completed++;
          asyncQueueSize--;
          return result;
        }));
      }
      await Future.wait(futures, eagerError: true);
      await Future.delayed(Duration(milliseconds: 500)); // 배치 간 최소 대기
    }

    progressTimer?.cancel();
    UserData.googleFirstLogin = false;
    showToastMessageCenter("Google 동기화 완료! ($completed/$total)");
    return true;
  }

  Future<bool> updateCalendar(calendar.Event newEvent) async {
    if (!UserData.isSaveGoogleToken) return true;

    try {
      calendar.CalendarApi mycalendar = calendar.CalendarApi(client);
      List<calendar.Event> searchResult = (await mycalendar.events
              .list("primary", iCalUID: newEvent.iCalUID, showDeleted: true))
          .items!;

      if (searchResult != null &&
          searchResult.length >= 1 &&
          searchResult[0].id != null)
        await mycalendar.events.patch(newEvent, "primary", searchResult[0].id!);
      else
        await mycalendar.events.insert(newEvent, "primary");
      delayTime = 1;
      failCount = 0;
      return true;
    } catch (e, trace) {
      Notify.notifyDebugInfo(e.toString(), sendLog: true, trace: trace);
      failCount += 1;
      delayTime *= 2;
      return false;
    }
  }

  Future<bool> deleteCalendar(calendar.Event newEvent) async {
    if (!UserData.isSaveGoogleToken) return true;

    try {
      calendar.CalendarApi mycalendar = calendar.CalendarApi(client);
      List<calendar.Event>? searchResult =
          (await mycalendar.events.list("primary", iCalUID: newEvent.iCalUID))
              .items;

      if (searchResult != null &&
          searchResult.isNotEmpty &&
          searchResult[0].id != null) {
        mycalendar.events.delete("primary", searchResult[0].id!);
      }

      delayTime = 1;
      failCount = 0;

      return true;
    } catch (e, trace) {
      Notify.notifyDebugInfo(e.toString(), sendLog: true, trace: trace);
      failCount += 1;
      delayTime *= 2;

      return false;
    }
  }
}
