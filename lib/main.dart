import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plato_calendar/Page/widget/Loading.dart';
import 'package:plato_calendar/utility.dart';
import 'package:intl/intl.dart';
import 'Data/appinfo.dart';
import 'Data/database/database.dart';
import 'Data/database/foregroundDatabase.dart';
import 'Data/database/backgroundDatabase.dart';
import 'Data/ics.dart';
import 'Data/subjectCodeManager.dart';
import 'Page/settings.dart';
import 'Page/sfCalendar.dart';
import 'Page/toDoList.dart';

import 'Page/Food.dart';
import 'Data/userData.dart';
import 'pnu/pnu.dart';
import 'notify.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:syncfusion_localizations/syncfusion_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:background_fetch/background_fetch.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';

const Color _primaryAppColor = Color.fromARGB(255, 59, 113, 208);
const Color _darkPrimaryColor = Color(0xFF5B8DEF); // 더 밝은 파란색
const Color _darkBackgroundColor = Color(0xFF121212); // 진한 검정
const Color _darkCardColor = Color(0xFF1E1E1E); // 약간 밝은 검정

String? text;
List<String> imageUrls = [];
bool isLoading = true;
bool isRefreshingOnForeground = false; // 포그라운드 복귀 시 갱신 상태 (전역 변수)

// 앱 테마 모드를 저장하는 전역 변수
ThemeMode appThemeMode = ThemeMode.system; // 기본값은 시스템 설정 따르기

Future<Map<String, dynamic>> fetchGoogleDocAsTextAndImages() async {
  final url = 'https://docs.google.com/document/d/1H2T_Itf6EQm_6pJul5YepZTLgDHe9gTTx5mqe-LzBoA/export?format=txt';
  final response = await http.get(Uri.parse(url));

  if (response.statusCode == 200) {
    final content = response.body;
    String textContent = '';
    List<String> imageUrls = [];
    bool isTextSection = false;
    bool isImageSection = false;

    final lines = content.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line == '[공지사항]') {
        isTextSection = true;
        isImageSection = false;
        continue;
      } else if (line == '[이미지]') {
        isTextSection = false;
        isImageSection = true;
        continue;
      }

      if (isTextSection && line.isNotEmpty) {
        textContent += line + '\n';
      } else if (isImageSection && line.isNotEmpty && line.startsWith('https://drive.google.com/uc?export=view&id=')) {
        imageUrls.add(line);
      }
    }

    return {
      'text': textContent.trim(),
      'imageUrls': imageUrls,
    };
  } else {
    throw Exception('문서 불러오기 실패: ${response.statusCode}');
  }
}

StreamController<bool> pnuStream = StreamController<bool>.broadcast();

Stream<bool> timer(int seconds) =>
    Stream.periodic(Duration(seconds: seconds), (_) => true);

// 새로운 일정을 확인하고 알림을 발송하는 함수
Future<void> _checkAndNotifyNewEvents() async {
  try {
    // 마지막 확인 시간을 가져옴
    final prefs = await SharedPreferences.getInstance();
    final lastCheckTime = prefs.getString('last_event_check_time');
    final now = DateTime.now();
    
    // 현재 일정 목록을 가져옴
    final currentEvents = UserData.data.where((event) => 
      event.end != null && 
      event.end!.isAfter(now) && 
      !event.finished
    ).toList();
    
    // 마지막 확인 이후 새로 추가된 일정 찾기 (UID 기반)
    List<CalendarData> newEvents = [];
    if (lastCheckTime != null) {
      final lastCheck = DateTime.parse(lastCheckTime);
      final lastEventCount = prefs.getInt('last_event_count') ?? 0;
      
      // 이벤트 개수가 증가했거나, 새로운 이벤트가 있는지 확인
      if (currentEvents.length > lastEventCount) {
        // 새로 추가된 이벤트들을 찾기 위해 UID 비교
        final lastEventUids = prefs.getStringList('last_event_uids') ?? [];
        newEvents = currentEvents.where((event) => 
          !lastEventUids.contains(event.uid)
        ).toList();
      }
    }
    
    // 새로운 일정이 있으면 알림 발송
    if (newEvents.isNotEmpty) {
      // for (var event in newEvents) {
      //   await Notify.notifyNewEvent(event);
      // }
      print("✅ 새로운 일정 감지: ${newEvents.length}개 (알림은 발생시키지 않음)");
    }
    
    // 마지막 확인 정보 업데이트
    await prefs.setString('last_event_check_time', now.toIso8601String());
    await prefs.setInt('last_event_count', currentEvents.length);
    await prefs.setStringList('last_event_uids', currentEvents.map((e) => e.uid).toList());
    
  } catch (e) {
    print("⚠️ 새 일정 확인 중 오류: $e");
  }
}

void backgroundFetchHeadlessTask(HeadlessTask task) async {
  String taskId = task.taskId;
  bool isTimeout = task.timeout;
  if (isTimeout) {
    BackgroundFetch.finish(taskId);
    return;
  }

  try {
    await UserData.writeDatabase.updateTime();
  } catch (e) {
    print("🚨 백그라운드 작업 오류");
  }
  BackgroundFetch.finish(taskId);
}

class LoadingStatus {
  static String _currentStatus = "앱을 시작하는 중...";

  static String get currentStatus => _currentStatus;

  static void updateStatus(String newStatus) {
    _currentStatus = newStatus;
    print("LoadingStatus: $newStatus"); // 디버깅 로그
    pnuStream.add(true);
  }
}

// 앱 테마 모드를 로드하는 함수
Future<void> loadAppThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('app_theme_mode');
    
    if (themeModeString != null) {
      if (themeModeString == 'dark') {
        appThemeMode = ThemeMode.dark;
        print("✅ 앱 테마 로드: 다크모드");
      } else if (themeModeString == 'light') {
        appThemeMode = ThemeMode.light;
        print("✅ 앱 테마 로드: 라이트모드");
      } else {
        appThemeMode = ThemeMode.system;
        print("✅ 앱 테마 로드: 시스템 설정");
      }
    } else {
      // 저장된 테마 설정이 없으면 시스템 설정 사용
      appThemeMode = ThemeMode.system;
      print("ℹ️ 저장된 앱 테마 없음, 시스템 설정 사용");
    }
  } catch (e) {
    print("⚠️ 앱 테마 로드 실패: $e");
    appThemeMode = ThemeMode.system;
  }
}

Future<void> initializeApp() async {
  try {
    LoadingStatus.updateStatus("데이터베이스 초기화 중...");
    await Database.init().timeout(Duration(seconds: 10), onTimeout: () {
      throw TimeoutException("데이터베이스 초기화 시간 초과");
    });

    LoadingStatus.updateStatus("앱 정보 로드 중...");
    await Appinfo.loadAppinfo().timeout(Duration(seconds: 5));

    LoadingStatus.updateStatus("백그라운드 데이터베이스 준비 중...");
    var mutex = BackgroundDatabase();
    await mutex.lock().timeout(Duration(seconds: 5));
    await mutex.release();

    UserData.writeDatabase = ForegroundDatabase();
    UserData.readDatabase =
        await Database.recentlyUsedDatabase().timeout(Duration(seconds: 5));

    LoadingStatus.updateStatus("데이터베이스 로드 중...");
    await UserData.readDatabase.lock().timeout(Duration(seconds: 5));
    await UserData.writeDatabase.loadDatabase().timeout(Duration(seconds: 10));
    await UserData.readDatabase.loadDatabase().timeout(Duration(seconds: 10));

    LoadingStatus.updateStatus("사용자 데이터 로드 중...");
    UserData.readDatabase.userDataLoad();
    UserData.readDatabase.calendarDataLoad();
    await UserData.readDatabase.googleDataLoad().timeout(Duration(seconds: 10));

    LoadingStatus.updateStatus("데이터 저장 중...");
    await Future.wait([
      UserData.writeDatabase
          .subjectCodeThisSemesterSave()
          .timeout(Duration(seconds: 5)),
      UserData.writeDatabase.defaultColorSave().timeout(Duration(seconds: 5)),
      UserData.writeDatabase.uidSetSave().timeout(Duration(seconds: 5)),
      UserData.writeDatabase
          .calendarDataFullSave()
          .timeout(Duration(seconds: 10)),
      UserData.writeDatabase.googleDataSave().timeout(Duration(seconds: 10)),
    ]);
    await UserData.readDatabase.release();

    if (UserData.readDatabase is BackgroundDatabase) {
      await UserData.readDatabase.closeDatabase().timeout(Duration(seconds: 5));
    }

    LoadingStatus.updateStatus("날짜 형식 초기화 중...");
    await initializeDateFormatting('ko_KR', null).timeout(Duration(seconds: 5));

    Intl.defaultLocale = 'ko_KR';
    
    LoadingStatus.updateStatus("과목 코드 초기화 중...");
    await SubjectCodeManager.initialize().timeout(Duration(seconds: 10));
 
    LoadingStatus.updateStatus("백그라운드 작업 설정 중...");
    try {
      await BackgroundFetch.configure(
        BackgroundFetchConfig(
          minimumFetchInterval: 60, // 60분마다 실행 (1시간)
          stopOnTerminate: false,
          enableHeadless: true,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresStorageNotLow: false,
          requiresDeviceIdle: false,
          startOnBoot: true,  
        ),
        (String taskId) async {
          try {
            final now = DateTime.now();
            print("🔄 백그라운드 작업 시작: ${now.toString()}");
            
            // 자정에 알림 재예약
            if (now.hour == 0 && now.minute == 0) {
              await Notify.notificationInit();
              await Notify.scheduleEventReminderNotifications();
              print("✅ 자정 알림 재예약 성공");
            }
            
            // 데이터 갱신 (네트워크 상태 확인 후)
            try {
              print("🔄 백그라운드 데이터 갱신 시작");
              await Loading.refresh();
              await Calendar.saveAppointmentCounts();
              // await UserData.writeDatabase.updateTime(); // 자동 새로고침에서는 갱신 시간 기록하지 않음
              print("✅ 백그라운드 데이터 갱신 완료");
            } catch (e) {
              print("⚠️ 백그라운드 데이터 갱신 실패: $e");
            }
            
            // 위젯 업데이트
            try {
              print("🔄 위젯 업데이트 시작");
              await HomeWidget.updateWidget(
                androidName: 'CalendarWidgetProvider',
                iOSName: 'MyHomeWidget',
              );
              print("✅ 위젯 업데이트 성공");
            } catch (e) {
              print("⚠️ 위젯 업데이트 실패: $e");
            }
            
            // 새로운 일정이 있는지 확인하고 알림 발송
            try {
              print("🔄 새 일정 확인 시작");
              await _checkAndNotifyNewEvents();
              print("✅ 새 일정 확인 완료");
            } catch (e) {
              print("⚠️ 새 일정 확인 실패: $e");
            }
            
            print("✅ 백그라운드 작업 실행 완료: ${DateTime.now()}");
          } catch (e) {
            print("🚨 백그라운드 작업 콜백 오류: $e");
          }
          BackgroundFetch.finish(taskId);
        },
      ).timeout(Duration(seconds: 10));
    } catch (e) {
      print("⚠️ 백그라운드 작업 설정 실패: $e");
    }

    // 백그라운드 작업 상태 확인
    try {
      final status = await BackgroundFetch.status;
      print("📊 백그라운드 작업 상태: $status");
    } catch (e) {
      print("⚠️ 백그라운드 작업 상태 확인 실패: $e");
    }
    
    // 앱 테마 모드 설정을 SharedPreferences에 저장
    try {
      final prefs = await SharedPreferences.getInstance();
      String themeModeString;
      
      if (UserData.themeMode == ThemeMode.dark) {
        themeModeString = 'dark';
        appThemeMode = ThemeMode.dark;
      } else if (UserData.themeMode == ThemeMode.light) {
        themeModeString = 'light';
        appThemeMode = ThemeMode.light;
      } else {
        themeModeString = 'system';
        appThemeMode = ThemeMode.system;
      }
      
      await prefs.setString('app_theme_mode', themeModeString);
      print("✅ 앱 테마 저장: $themeModeString");
    } catch (e) {
      print("⚠️ 앱 테마 저장 실패: $e");
    }
    
  } catch (e) {
    print("🚨 initializeApp 오류: $e");
  }
}

void main() async {
  tz.initializeTimeZones();
  WidgetsFlutterBinding.ensureInitialized();

  // 과목 코드 초기화 (앱 실행 시 한 번만)
  await SubjectCodeManager.initialize();

  // 앱 테마 모드 로드
  await loadAppThemeMode();
  
  // 시스템 UI 스타일 설정
  final isDarkMode = appThemeMode == ThemeMode.dark || 
                    (appThemeMode == ThemeMode.system && 
                     WidgetsBinding.instance.window.platformBrightness == Brightness.dark);
  
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: isDarkMode ? Colors.grey[900] : Colors.white,
  ));
await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  print("앱 시작 - 테마 모드: ${isDarkMode ? '다크모드' : '라이트모드'}");
  
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late StreamSubscription<bool> themeSubscription;
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdReady = false;
  bool _isInitialized = false;
  bool _showAnnouncementDialog = false;
  bool _isDialogShowing = false;
  final _storage = FlutterSecureStorage();
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _textFadeAnimation;
  DateTime? _lastBackgroundTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _textFadeAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _initializeApp();
    MobileAds.instance.initialize().then((_) {
      _loadBannerAd();
      _loadInterstitialAd();
    }).catchError((e) {
      print("⚠️ 광고 초기화 실패: $e");
    });

    themeSubscription = pnuStream.stream.listen((bool event) {
      if (event && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    themeSubscription.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        // 앱이 백그라운드로 갈 때
        _lastBackgroundTime = DateTime.now();
        print("📱 앱 백그라운드 진입: ${DateTime.now()}");
        break;
        
      case AppLifecycleState.resumed:
        // 앱이 포그라운드로 돌아올 때
        if (_lastBackgroundTime != null) {
          final backgroundDuration = DateTime.now().difference(_lastBackgroundTime!);
          print("📱 앱 포그라운드 복귀: 백그라운드 시간 ${backgroundDuration.inMinutes}분");
          
          // 5분 이상 백그라운드에 있었다면 데이터 갱신
          if (backgroundDuration.inMinutes >= 1) {
            _refreshDataOnForeground();
          }
        }
        break;
        
      default:
        break;
    }
  }

  // 포그라운드 복귀 시 데이터 갱신
  Future<void> _refreshDataOnForeground() async {
    if (isRefreshingOnForeground) return; // 이미 갱신 중이면 스킵
    
    setState(() {
      isRefreshingOnForeground = true;
    });
    
    try {
      print("🔄 포그라운드 복귀 시 데이터 갱신 시작");
      await Loading.refresh();
      await Calendar.saveAppointmentCounts();
      
      // 위젯 업데이트
      try {
        await HomeWidget.updateWidget(
          androidName: 'CalendarWidgetProvider',
          iOSName: 'MyHomeWidget',
        );
        print("✅ 포그라운드 복귀 시 위젯 업데이트 성공");
      } catch (e) {
        print("⚠️ 포그라운드 복귀 시 위젯 업데이트 실패: $e");
      }
      
      // 새로운 일정 확인
      try {
        await _checkAndNotifyNewEvents();
      } catch (e) {
        print("⚠️ 포그라운드 복귀 시 새 일정 확인 실패: $e");
      }
      
      print("✅ 포그라운드 복귀 시 데이터 갱신 완료");
    } catch (e) {
      print("⚠️ 포그라운드 복귀 시 데이터 갱신 실패: $e");
    } finally {
      if (mounted) {
        setState(() {
          isRefreshingOnForeground = false;
        });
      }
    }
  }

  Future<void> _initializeApp() async {
    
    try {
      await initializeApp().timeout(Duration(seconds: 60), onTimeout: () {
        throw TimeoutException("앱 초기화 시간 초과");
      });

      LoadingStatus.updateStatus("알림 초기화 중...");
      try {
        print("알림 초기화 시도");
        final notificationInitialized = await Notify.notificationInit()
            .timeout(Duration(seconds: 10), onTimeout: () {
          throw TimeoutException("알림 초기화 시간 초과");
        });
        if (notificationInitialized) {
          print("✅ 알림 초기화 성공");
          try {
            await Notify.scheduleEventReminderNotifications()
                .timeout(Duration(seconds: 10));
                
            print("✅ 알림 예약 성공");
          } catch (e) {
            print("⚠️ 알림 예약 실패: $e");
          }
        } else {
          print("⚠️ 알림 초기화 실패");
          // 알림 권한 다이얼로그 표시 제거
        }
      } catch (e) {
        print("⚠️ 알림 초기화 실패: $e");
      }

      try {
        print("ℹ️ 텍스트 및 이미지 가져오기 시작");
        final docContent = await fetchGoogleDocAsTextAndImages().timeout(Duration(seconds: 10));
        print("✅ 텍스트 및 이미지 가져오기 성공");

        // Check if announcement is empty
        final isEmptyAnnouncement = docContent['text'].isEmpty && docContent['imageUrls'].isEmpty;
        print("ℹ️ 공지사항 상태: text=${docContent['text']}, imageUrls=${docContent['imageUrls']}, isEmpty=$isEmptyAnnouncement");

        if (!isEmptyAnnouncement) {
          // Preload images using cached_network_image
          for (var url in docContent['imageUrls']) {
            await precacheImage(CachedNetworkImageProvider(url), context);
          }
          print("✅ 이미지 프리로딩 성공");

          String? savedText = await _storage.read(key: 'announcement_text');
          print("ℹ️ 저장된 텍스트: $savedText");

          if (mounted) {
            setState(() {
              text = docContent['text'];
              imageUrls = docContent['imageUrls'];
              if (savedText == null || savedText != text) {
                _showAnnouncementDialog = true;
              }
            });
          }
        } else {
          print("ℹ️ 빈 공지사항: 다이얼로그 표시 안 함");
        }
      } catch (e) {
        print("⚠️ 텍스트 및 이미지 가져오기 실패: $e");
      }

      // Update system UI after initialization
      try {
        final isDarkMode = UserData.themeMode == ThemeMode.dark;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: isDarkMode ? Colors.grey[900] : Colors.white,
        ));
        
        // 앱 테마 모드 업데이트
        final prefs = await SharedPreferences.getInstance();
        String themeModeString;
        
        if (UserData.themeMode == ThemeMode.dark) {
          themeModeString = 'dark';
          appThemeMode = ThemeMode.dark;
        } else if (UserData.themeMode == ThemeMode.light) {
          themeModeString = 'light';
          appThemeMode = ThemeMode.light;
        } else {
          themeModeString = 'system';
          appThemeMode = ThemeMode.system;
        }
        
        await prefs.setString('app_theme_mode', themeModeString);
        print("✅ 앱 테마 업데이트: $themeModeString");
      } catch (e) {
        print("⚠️ 시스템 UI 설정 실패: $e");
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print("🚨 초기화 오류: $e");
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
    Calendar.saveAppointmentCounts(); 
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-7809866335486017/6875245552',
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() {
              _isBannerAdReady = true;
            });
          }
        },
        onAdFailedToLoad: (ad, err) {
          _isBannerAdReady = false;
          ad.dispose();
          Future.delayed(Duration(seconds: 5), () {
            if (mounted) _loadBannerAd();
          });
        },
      ),
    );
    _bannerAd!.load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-7809866335486017/8459107773',
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          if (mounted) {
            setState(() {
              _interstitialAd = ad;
              _isInterstitialAdReady = true;
            });
          }
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              ad.dispose();
              if (mounted) {
                setState(() {
                  _interstitialAd = null;
                  _isInterstitialAdReady = false;
                });
              }
              _loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
              ad.dispose();
              if (mounted) {
                setState(() {
                  _interstitialAd = null;
                  _isInterstitialAdReady = false;
                });
              }
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (mounted) {
            setState(() {
              _interstitialAd = null;
              _isInterstitialAdReady = false;
            });
          }
          Future.delayed(Duration(seconds: 5), () {
            if (mounted) _loadInterstitialAd();
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      // 앱 테마 모드 사용
      bool isDarkMode = appThemeMode == ThemeMode.dark || 
                        (appThemeMode == ThemeMode.system && 
                         WidgetsBinding.instance.window.platformBrightness == Brightness.dark);
      
      print("로딩 화면 렌더링 - 앱 테마: ${appThemeMode.toString()}, 다크모드: $isDarkMode");

      return MaterialApp(
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          SfGlobalLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          const Locale('en'),
          const Locale('ko'),
        ],
        locale: const Locale('ko'),
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.white,
          dialogBackgroundColor: Colors.white,
          textTheme: TextTheme(
            bodyLarge: TextStyle(color: Colors.black87),
          ),
        ),
        darkTheme: ThemeData(
          scaffoldBackgroundColor: Colors.grey[900],
          dialogBackgroundColor: Colors.grey[800],
          textTheme: TextTheme(
            bodyLarge: TextStyle(color: Colors.white),
          ),
          brightness: Brightness.dark,
        ),
        themeMode: appThemeMode,
        home: Container(
          color: isDarkMode ? _darkBackgroundColor : Colors.white,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulse effect
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 150 * _pulseAnimation.value,
                      height: 150 * _pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (isDarkMode ? _darkPrimaryColor : _primaryAppColor)
                            .withOpacity(0.2 * (1 - _pulseAnimation.value)),
                      ),
                    );
                  },
                ),
                // Logo with scale animation
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 100,
                    height: 100,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.calendar_today,
                      size: 100,
                      color: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
                    ),
                  ),
                ),
                // Status text below
                Positioned(
                  bottom: MediaQuery.of(context).size.height * 0.25,
                  child: AnimatedOpacity(
                    opacity: _textFadeAnimation.value,
                    duration: Duration(milliseconds: 500),
                    child: StreamBuilder<bool>(
                      stream: pnuStream.stream,
                      builder: (context, snapshot) {
                        return Text(
                          LoadingStatus.currentStatus,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w300,
                            color: isDarkMode ? Colors.white : Colors.black87,
                            letterSpacing: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        SfGlobalLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('en'),
        const Locale('ko'),
      ],
      locale: const Locale('ko'),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return CupertinoTheme(
          data: CupertinoThemeData(
            primaryColor: _primaryAppColor,
          ),
          child: child!,
        );
      },
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        dialogBackgroundColor: Colors.white,
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: _primaryAppColor,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: Color.fromARGB(77, 59, 113, 208),
        ),
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: Colors.black87),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[900],
        dialogBackgroundColor: Colors.grey[800],
        brightness: Brightness.dark,
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
        ),
      ),
      themeMode: UserData.themeMode,
      home: Builder(
        builder: (context) {
          if (_showAnnouncementDialog && text != null && !_isDialogShowing) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_isDialogShowing && mounted) {
                setState(() {
                  _isDialogShowing = true;
                  _showAnnouncementDialog = false;
                });
                
                final isDarkMode = Theme.of(context).brightness == Brightness.dark;
                
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 8,
                    backgroundColor: isDarkMode ? Color(0xFF252525) : Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 헤더
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: Color.fromARGB(255, 59, 113, 208),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start, // 왼쪽 정렬로 변경
                            children: [
                              SizedBox(width: 20), // 왼쪽 여백 추가
                              Icon(
                                Icons.campaign_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              SizedBox(width: 10),
                              Text(
                                '공지사항',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // 내용
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.5, // 최대 높이 제한
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
                              mainAxisSize: MainAxisSize.min, // 내용에 맞게 크기 조절
                              children: [
                                // 텍스트 내용
                                if (text != null && text!.isNotEmpty)
                                  Container(
                                    width: double.infinity, // 너비를 최대로 설정
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? Color(0xFF2A2A2A) : Color(0xFFF5F5F5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      text!,
                                      style: TextStyle(
                                        fontSize: 16,
                                        height: 1.5,
                                        color: isDarkMode ? Colors.white : Colors.black87,
                                      ),
                                      textAlign: TextAlign.left, // 텍스트 왼쪽 정렬
                                    ),
                                  ),
                                
                                // 이미지 내용
                                if (imageUrls.isNotEmpty) ...[
                                  SizedBox(height: 20),
                                  ...imageUrls.map((url) => Container(
                                    width: double.infinity, // 너비를 최대로 설정
                                    margin: EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 10,
                                          offset: Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: CachedNetworkImage(
                                        imageUrl: url,
                                        fit: BoxFit.contain,
                                        placeholder: (context, url) => Container(
                                          height: 150,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              color: _primaryAppColor,
                                            ),
                                          ),
                                        ),
                                        errorWidget: (context, url, error) => Container(
                                          padding: EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.error_outline, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text(
                                                '이미지 로드 실패',
                                                style: TextStyle(color: Colors.red),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  )).toList(),
                                ],
                              ],
                            ),
                          ),
                        ),
                        
                        // 버튼
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Color(0xFF1E1E1E) : Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    if (text != null) {
                                      await _storage.write(key: 'announcement_text', value: text!);
                                      print("ℹ️ 텍스트 저장됨: $text");
                                    }
                                    Navigator.pop(context);
                                    if (mounted) {
                                      setState(() {
                                        _isDialogShowing = false;
                                      });
                                    }
                                  },
                                  icon: Icon(Icons.check_circle_outline, size: 18),
                                  label: Text('다시 보지 않기'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primaryAppColor,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    if (mounted) {
                                      setState(() {
                                        _isDialogShowing = false;
                                      });
                                    }
                                  },
                                  child: Text('닫기'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isDarkMode ? Color(0xFF3A3A3A) : Colors.white,
                                    foregroundColor: isDarkMode ? Colors.white : Colors.black87,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                                        width: 1,
                                      ),
                                    ),
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            });
          }

          return MyHomePage(
            bannerAd: _bannerAd,
            isBannerAdReady: _isBannerAdReady,
            interstitialAd: _interstitialAd,
            isInterstitialAdReady: _isInterstitialAdReady,
          );
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final BannerAd? bannerAd;
  final bool isBannerAdReady;
  final InterstitialAd? interstitialAd;
  final bool isInterstitialAdReady;

  MyHomePage({
    Key? key,
    this.bannerAd,
    required this.isBannerAdReady,
    this.interstitialAd,
    required this.isInterstitialAdReady,
  }) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  //home widget stuff..
  String appGroupId = "group.com.junseo.platoCalendar";
  String iOSWidgetName = "MyHomeWidget";
  String dateKey = "text_from_flutter_app";

  bool loading = false;
  late StreamSubscription<bool> timerSubScription;
  late StreamSubscription<bool> pnuSubscription;

  List<Widget> get _widgets => [
        Calendar(
          bannerAd: widget.bannerAd,
          isBannerAdReady: widget.isBannerAdReady,
        ),
        ToDoList(),
        Food(),
        Setting(
          interstitialAd: widget.interstitialAd,
          isInterstitialAdReady: widget.isInterstitialAdReady,
        ),
      ];

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    HomeWidget.setAppGroupId(appGroupId);
    timerSubScription = timer(10).listen((event) async {
      try {
        await UserData.writeDatabase.updateTime();
      } catch (e) {
        print("⚠️ 타이머 업데이트 오류: $e");
      }
    });
    pnuSubscription = pnuStream.stream.listen((bool event) {
      if (event && mounted) {
        setState(() {});
      }
    });
    try {
      UserData.googleCalendar.openStream();
      UserData.googleCalendar.updateCalendarFull();
    } catch (e) {
      print("⚠️ 구글 캘린더 초기화 오류: $e");
    }
    update();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      UserData.googleCalendar.closeStream();
    } catch (e) {
      print("⚠️ 구글 캘린더 스트림 종료 오류: $e");
    }
    timerSubScription.cancel();
    pnuSubscription.cancel;
    super.dispose();
  }

  Future<void> _triggerVibration() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (e) {
      print("⚠️ 진동 오류: $e");
    }
  }

  void update() {}

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return AbsorbPointer(
      absorbing: loading,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            AnimatedSwitcher(
              duration: Duration(milliseconds: 350),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(UserData.tapIndex),
                child: _widgets[UserData.tapIndex],
              ),
              layoutBuilder: (currentChild, previousChildren) => Stack(
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
            ),
            // 포그라운드 복귀 시 갱신 로딩 오버레이
            if (isRefreshingOnForeground)
              Center(
                child: Material(
                  color: Colors.transparent,
                  elevation: 16,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 320,
                    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 32,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: Lottie.asset('assets/lottie/loading.json'),
                        ),
                        SizedBox(height: 24),
                        Text(
                          '데이터 동기화 중...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          '최신 정보를 불러오고 있습니다',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDarkMode ? Color(0xFF121212) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: isDarkMode ? Color(0xFF121212) : Colors.white,
            selectedItemColor: _primaryAppColor,
            unselectedItemColor: isDarkMode ? Colors.grey[500] : Colors.grey[400],
            currentIndex: UserData.tapIndex,
            elevation: 0,
            onTap: (int i) {
              _triggerVibration();
              if (mounted) {
                setState(() {
                  UserData.tapIndex = i;
                });
              }
            },
            items: [
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_today),
                label: "달력",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.my_library_books_outlined),
                label: "할일",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.restaurant),
                label: "학식",
              ),
             BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: "설정",
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        if (mounted) {
          setState(() {
            loading = true;
          });
        }
        try {
          UserData.readDatabase = BackgroundDatabase();
          await UserData.readDatabase.lock().timeout(Duration(seconds: 5));
          await UserData.readDatabase.release();
          DateTime beforeSync = await UserData.writeDatabase.getTime();
          DateTime nowSync = await UserData.readDatabase.getTime();

          if (nowSync.difference(beforeSync).inSeconds > 0) {
            showToastMessageCenter("데이터를 불러오고 있습니다.");

            await UserData.readDatabase.lock().timeout(Duration(seconds: 5));
            await UserData.readDatabase
                .loadDatabase()
                .timeout(Duration(seconds: 10));

            UserData.readDatabase.calendarDataLoad();
            UserData.readDatabase.userDataLoad();

            await Future.wait([
              UserData.writeDatabase
                  .subjectCodeThisSemesterSave()
                  .timeout(Duration(seconds: 5)),
              UserData.writeDatabase
                  .defaultColorSave()
                  .timeout(Duration(seconds: 5)),
              UserData.writeDatabase.uidSetSave().timeout(Duration(seconds: 5)),
              UserData.writeDatabase
                  .calendarDataFullSave()
                  .timeout(Duration(seconds: 10)),
            ]);

            await UserData.readDatabase
                .closeDatabase()
                .timeout(Duration(seconds: 5));
            UserData.readDatabase.release();
            pnuStream.sink.add(true);
            closeToastMessage();
          }
          
          // 앱 테마 모드 업데이트
          try {
            final prefs = await SharedPreferences.getInstance();
            String themeModeString;
            
            if (UserData.themeMode == ThemeMode.dark) {
              themeModeString = 'dark';
              appThemeMode = ThemeMode.dark;
            } else if (UserData.themeMode == ThemeMode.light) {
              themeModeString = 'light';
              appThemeMode = ThemeMode.light;
            } else {
              themeModeString = 'system';
              appThemeMode = ThemeMode.system;
            }
            
            await prefs.setString('app_theme_mode', themeModeString);
            print("✅ 앱 테마 업데이트(라이프사이클): $themeModeString");
          } catch (e) {
            print("⚠️ 앱 테마 업데이트 실패: $e");
          }
          
        } catch (e) {
          print("⚠️ 앱 라이프사이클 복구 오류: $e");
        }
        if (mounted) {
          setState(() {
            loading = false;
          });
        }

        timerSubScription.resume();
        break;
      case AppLifecycleState.inactive:
        timerSubScription.pause();
        break;
      case AppLifecycleState.paused:
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }
}