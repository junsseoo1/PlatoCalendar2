import 'dart:async';
import 'dart:io';
import 'dart:math' as Math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:plato_calendar/Page/sfCalendar.dart';
import 'package:plato_calendar/Page/widget/Loading.dart';
import 'package:plato_calendar/Page/widget/Loading2.dart';
import 'package:plato_calendar/Page/widget/LoginPage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../Data/etc.dart';
import '../Data/subjectCode.dart';
import '../Data/subjectCodeManager.dart';
import '../main.dart' show pnuStream;
import '../Data/userData.dart';
import '../utility.dart';
import 'widget/appointmentEditor.dart';
import '../notify.dart';

// Primary color palette
const Color _primaryAppColor = Color(0xFF3B71CA);
const Color _secondaryAppColor = Color(0xFF9ECE6A);
const double _leadingIconSize = 24.0;

// Dark mode colors
const Color _darkPrimaryColor = Color(0xFF3B71CA);
const Color _darkBackgroundColor = Color(0xFF121212);
const Color _darkCardColor = Color(0xFF1A1A1A);
const Color _darkSurfaceColor = Color(0xFF2A2A2A);
const Color _darkTextColor = Color(0xFFF5F5F5);
const Color _darkSecondaryTextColor = Color(0xFFA0A0A0);
const Color _darkDividerColor = Color(0xFF404040);
const Color _darkSelectedColor = Color(0xFF2A3A50);
String _buildNotificationSubtitle(int totalMinutes) {
  final totalHours = totalMinutes ~/ 60;
  final days = totalHours ~/ 24;
  final hours = totalHours % 24;

  final parts = <String>[];
  if (days > 0) parts.add('$days일');
  if (hours > 0) parts.add('$hours시간');
  if (parts.isEmpty) parts.add('0시간');

  return '일정 ${parts.join(' ')} 전 알림';
}
class _InlineNotificationTimePicker extends StatefulWidget {
  final int initialMinutes;
  final ValueChanged<int> onChanged;

  const _InlineNotificationTimePicker({
    super.key,
    required this.initialMinutes,
    required this.onChanged,
  });

  @override
  State<_InlineNotificationTimePicker> createState() => _InlineNotificationTimePickerState();
}

class _InlineNotificationTimePickerState extends State<_InlineNotificationTimePicker> {
  late int selectedDays;
  late int selectedHours;

  @override
  void initState() {
    super.initState();
    final totalHours = widget.initialMinutes ~/ 60;
    selectedDays = totalHours ~/ 24;
    selectedHours = totalHours % 24;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return SizedBox(
      height: 160,
      child: Row(
        children: [
          Expanded(
            child: CupertinoPicker(
              itemExtent: 32,
              scrollController: FixedExtentScrollController(initialItem: selectedDays),
              onSelectedItemChanged: (index) {
                setState(() {
                  selectedDays = index;
                  widget.onChanged((selectedDays * 24 + selectedHours) * 60);
                });
              },
              children: List.generate(8, (i) => Center(
                child: Text('$i일 전', style: TextStyle(color: textColor)),
              )),
            ),
          ),
          Expanded(
            child: CupertinoPicker(
              itemExtent: 32,
              scrollController: FixedExtentScrollController(initialItem: selectedHours),
              onSelectedItemChanged: (index) {
                setState(() {
                  selectedHours = index;
                  widget.onChanged((selectedDays * 24 + selectedHours) * 60);
                });
              },
              children: List.generate(24, (i) => Center(
                child: Text('$i시간 전', style: TextStyle(color: textColor)),
              )),
            ),
          ),
        ],
      ),
    );
  }
}
class Setting extends StatefulWidget {
  final InterstitialAd? interstitialAd;
  final bool isInterstitialAdReady;
  
  const Setting({
    Key? key,
    this.interstitialAd,
    required this.isInterstitialAdReady,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SettingsState();
}

Future<void> _launchURL(String url) async {
  final Uri uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    showToastMessageCenter('Could not launch $url');
  }
}

Future<void> _triggerVibration() async {
  HapticFeedback.lightImpact();
}

class _SettingsState extends State<Setting> with TickerProviderStateMixin {
  Set<String> _subjectCodeThisSemester =
      Set<String>.from(UserData.subjectCodeThisSemester);
  late StreamSubscription<dynamic> _listener;
  late AnimationController _platoSyncController;
  late AnimationController _googleSyncController;
  late Animation<double> _platoSyncAnimation;
  late Animation<double> _googleSyncAnimation;

  bool _isThemeButtonsVisible = false;
  bool _isCalendarTypeButtonsVisible = false;
  bool _isFirstDayButtonsVisible = false;
  bool _isHelpButtonsVisible = false;
  bool _isNotificationTimeButtonsVisible = false;

  // Animation controllers for expandable sections
  late AnimationController _themeAnimationController;
  late AnimationController _calendarTypeAnimationController;
  late AnimationController _firstDayAnimationController;
  late AnimationController _helpAnimationController;
  late AnimationController _notificationTimeAnimationController;

  late Animation<double> _themeSizeAnimation;
  late Animation<double> _calendarTypeSizeAnimation;
  late Animation<double> _firstDaySizeAnimation;
  late Animation<double> _helpSizeAnimation;
  late Animation<double> _notificationTimeSizeAnimation;

  @override
  void initState() {
    super.initState();
    _subjectCodeThisSemester.remove("전체");
    _listener = pnuStream.stream.listen((event) {
      if (event && mounted) setState(() {});
    });

    _platoSyncController = AnimationController(
      duration: const Duration(seconds: 1, milliseconds: 500),
      vsync: this,
    );
    _platoSyncAnimation = Tween<double>(
      begin: 0,
      end: 2 * Math.pi,
    ).animate(CurvedAnimation(parent: _platoSyncController, curve: Curves.easeInOutCubic));

    _googleSyncController = AnimationController(
      duration: const Duration(seconds: 1, milliseconds: 500),
      vsync: this,
    );
    _googleSyncAnimation = Tween<double>(
      begin: 0,
      end: 2 * Math.pi,
    ).animate(CurvedAnimation(parent: _googleSyncController, curve: Curves.easeInOutCubic));

    // Initialize animations for expandable sections
    _themeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _themeSizeAnimation = CurvedAnimation(
      parent: _themeAnimationController,
      curve: Curves.easeOutQuart,
    );

    _calendarTypeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _calendarTypeSizeAnimation = CurvedAnimation(
      parent: _calendarTypeAnimationController,
      curve: Curves.easeOutQuart,
    );

    _firstDayAnimationController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _firstDaySizeAnimation = CurvedAnimation(
      parent: _firstDayAnimationController,
      curve: Curves.easeOutQuart,
    );

    _helpAnimationController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _helpSizeAnimation = CurvedAnimation(
      parent: _helpAnimationController,
      curve: Curves.easeOutQuart,
    );

    _notificationTimeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _notificationTimeSizeAnimation = CurvedAnimation(
      parent: _notificationTimeAnimationController,
      curve: Curves.easeOutQuart,
    );
  }

  @override
  void dispose() {
    _platoSyncController.dispose();
    _googleSyncController.dispose();
    _themeAnimationController.dispose();
    _calendarTypeAnimationController.dispose();
    _firstDayAnimationController.dispose();
    _helpAnimationController.dispose();
    _notificationTimeAnimationController.dispose();
    _listener.cancel();
    super.dispose();
  }

  void _showColorSettingsDialog() {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  final AnimationController animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  final Animation<double> fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
    CurvedAnimation(parent: animationController, curve: Curves.easeInOut),
  );

  // 과목 수에 따른 동적 높이 계산
  final int subjectCount = _subjectCodeThisSemester.length;
  const double itemHeight = 48.0; // 각 과목 항목의 높이
  const double headerHeight = 64.0; // 헤더(제목 및 닫기 버튼)의 높이
  const double maxHeight = 400.0; // 최대 다이얼로그 높이

  // 6개 이하일 때는 모든 과목이 보이도록, 6개 초과 시 스크롤 활성화
  final double desiredHeight = subjectCount <= 6
      ? headerHeight + (subjectCount * itemHeight)
      : maxHeight;
void updateExistingEventsColor(String subjectCode, int newColor) {
  for (var event in UserData.data) {
    if (event.classCode == subjectCode) {
      event.color = newColor; // 기존 일정의 색상 업데이트
      UserData.writeDatabase.calendarDataSave(event); // 변경된 일정 데이터베이스에 저장
    }
  }
  if (mounted) {
    setState(() {}); // UI 갱신
  }
}
  showDialog(
    context: context,
    builder: (BuildContext context) {
      animationController.forward();
      return Dialog(
        backgroundColor: isDarkMode ? _darkCardColor : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: desiredHeight,
            minHeight: Math.min(desiredHeight, 150.0),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return FadeTransition(
                opacity: fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '과목별 기본 색상',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? _darkTextColor : Colors.black87,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 20,
                              color: isDarkMode ? _darkSecondaryTextColor : Colors.grey[600],
                            ),
                            onPressed: () {
                              _triggerVibration();
                              animationController.reverse().then((_) => Navigator.pop(context));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: _subjectCodeThisSemester.map((String data) {
                              return SizedBox(
                                height: itemHeight,
                                child: GestureDetector(
                                  onTap: () {
                                    _triggerVibration();
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return CalendarColorPicker(UserData.defaultColor[data] ?? 1);
                                      },
                                    ).then((value) {
                                      if (value != null) {
                                        // 즉시 색상 적용
                                        setDialogState(() {
                                          UserData.defaultColor[data] = value;
                                        });
                                        UserData.writeDatabase.defaultColorSave();
                                        updateExistingEventsColor(data, value);
                                        if (mounted) setState(() {});
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    margin: const EdgeInsets.only(bottom: 6),
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? _darkSurfaceColor : Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            subjectCode[data] ?? data,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: isDarkMode ? _darkTextColor : Colors.black87,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: colorCollection[UserData.defaultColor[data] ?? 1],
                                            border: Border.all(
                                              color: isDarkMode ? _darkDividerColor : Colors.grey[300]!,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  ).whenComplete(() {
    animationController.dispose();
  });
}

  Widget _buildModernCard({required List<Widget> children, EdgeInsetsGeometry? margin}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: isDarkMode ? 4 : 3,
      shadowColor: isDarkMode ? Colors.black.withOpacity(0.4) : Colors.grey.withOpacity(0.3),
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDarkMode ? _darkCardColor : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildAnimatedCard({required Widget card, required int index}) {
    return card; // Return the card directly without animations
  }

  Widget _buildAccountSection() {
    final bool isPlatoLoggedIn = UserData.id != "";
    final bool hasError = UserData.lastSyncInfo != null && UserData.lastSyncInfo!.contains("오류");
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return _buildModernCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.account_circle_rounded,
                color: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
                size: _leadingIconSize,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPlatoLoggedIn ? UserData.id : "PLATO 계정",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? _darkTextColor : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      UserData.lastSyncInfo ?? "최근 동기화 정보 없음",
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? _darkSecondaryTextColor : Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isPlatoLoggedIn && !hasError)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Loading(
                      animation: _platoSyncAnimation,
                      control: _platoSyncController,
                      interstitialAd: widget.interstitialAd,
                      isInterstitialAdReady: widget.isInterstitialAdReady,
                    ),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                ),
                onPressed: () {
                  _triggerVibration();
                  if (isPlatoLoggedIn) {
                    setState(() {
                      UserData.id = "";
                      UserData.pw = "";
                      UserData.lastSyncInfo = "로그인이 필요합니다.";
                      UserData.subjectCodeThisSemester.clear();
                      UserData.subjectCodeThisSemester.add("전체");
                      _subjectCodeThisSemester = Set<String>.from(UserData.subjectCodeThisSemester);
                      _subjectCodeThisSemester.remove("전체");
                    });
                  } else {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return LoginPage();
                      },
                    ).then((value) {
                      if (mounted) {
                        setState(() {
                          Calendar.saveAppointmentCounts();
                          _subjectCodeThisSemester = Set<String>.from(UserData.subjectCodeThisSemester);
                          _subjectCodeThisSemester.remove("전체");
                        });
                      }
                    });
                  }
                },
                child: Text(
                  isPlatoLoggedIn ? "로그아웃" : "로그인",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2A1B1B) : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDarkMode ? const Color(0xFF4A2B2B) : Colors.red.shade100,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '동기화 오류',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? const Color(0xFFFF8A80) : Colors.red.shade600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• ID/PW 오류: 로그아웃 후 다시 시도하세요.\n'
                    '• 로그인 오류: 네트워크 연결을 확인 후 앱을 재시작하세요.\n'
                    '• 동기화 오류: 데이터 분석 중 오류가 발생했습니다. 지속적인 오류 시 앱스토어를 통해 문의하세요.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode ? const Color(0xFFE57373) : Colors.red.shade500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGoogleCalendarSection() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return _buildModernCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                color: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
                size: _leadingIconSize,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google 캘린더',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? _darkTextColor : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      UserData.isSaveGoogleToken ? '캘린더와 동기화 진행 중' : '로그인이 필요합니다.',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? _darkSecondaryTextColor : Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (UserData.isSaveGoogleToken) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Loading2(
                      animation: _googleSyncAnimation,
                      control: _googleSyncController,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    _triggerVibration();
                    await UserData.googleCalendar.logOutGoogleAccount();
                    if (mounted) setState(() {});
                  },
                  child: const Text(
                    "로그아웃",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ] else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    _triggerVibration();
                    if (UserData.id == "") {
                      showToastMessageCenter('먼저 PLATO 로그인을 진행해주세요.');
                    } else {
                      try {
                        await UserData.googleCalendar.authUsingGoogleAccount();
                      } catch (e) {
                        showToastMessageCenter('Google 연동 중 오류가 발생했습니다.');
                      }
                      if (mounted) setState(() {});
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GoogleLogo(size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "Google 연동",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralSettings() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return _buildModernCard(
      children: [
        _buildTapableTile(
          title: '앱 테마',
          subtitle: (() {
            switch (UserData.themeMode) {
              case ThemeMode.system:
                return "시스템 설정에 따라 적용";
              case ThemeMode.light:
                return "밝은 테마 적용";
              case ThemeMode.dark:
                return "어두운 테마 적용";
            }
          })(),
          icon: Icons.color_lens_rounded,
          onTap: () {
            _triggerVibration();
            setState(() {
              _isThemeButtonsVisible = !_isThemeButtonsVisible;
              if (_isThemeButtonsVisible) {
                _themeAnimationController.forward();
              } else {
                _themeAnimationController.reverse();
              }
            });
          },
        ),
        SizeTransition(
          sizeFactor: _themeSizeAnimation,
          axis: Axis.vertical,
          child: AnimatedOpacity(
            opacity: _isThemeButtonsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutQuart,
            child: AnimatedScale(
              scale: _isThemeButtonsVisible ? 1.0 : 0.9,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutQuart,
              child: _isThemeButtonsVisible
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildThemeButton(
                            title: '시스템',
                            icon: Icons.settings_suggest_rounded,
                            isSelected: UserData.themeMode == ThemeMode.system,
                            onTap: () {
                              _triggerVibration();
                              setState(() {
                                UserData.themeMode = ThemeMode.system;
                                pnuStream.sink.add(true);
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildThemeButton(
                            title: '라이트',
                            icon: Icons.light_mode_rounded,
                            isSelected: UserData.themeMode == ThemeMode.light,
                            onTap: () {
                              _triggerVibration();
                              setState(() {
                                UserData.themeMode = ThemeMode.light;
                                pnuStream.sink.add(true);
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildThemeButton(
                            title: '다크',
                            icon: Icons.dark_mode_rounded,
                            isSelected: UserData.themeMode == ThemeMode.dark,
                            onTap: () {
                              _triggerVibration();
                              setState(() {
                                UserData.themeMode = ThemeMode.dark;
                                pnuStream.sink.add(true);
                              });
                            },
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        _buildDivider(),
        _buildTapableTile(
          title: '달력 종류',
          subtitle: UserData.calendarType == CalendarType.split
              ? '달력과 일정 분리'
              : '달력과 일정 통합',
          icon: Icons.calendar_view_month_rounded,
          onTap: () {
            _triggerVibration();
            setState(() {
              _isCalendarTypeButtonsVisible = !_isCalendarTypeButtonsVisible;
              if (_isCalendarTypeButtonsVisible) {
                _calendarTypeAnimationController.forward();
              } else {
                _calendarTypeAnimationController.reverse();
              }
            });
          },
        ),
        SizeTransition(
          sizeFactor: _calendarTypeSizeAnimation,
          axis: Axis.vertical,
          child: AnimatedOpacity(
            opacity: _isCalendarTypeButtonsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutQuart,
            child: AnimatedScale(
              scale: _isCalendarTypeButtonsVisible ? 1.0 : 0.9,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutQuart,
              child: _isCalendarTypeButtonsVisible
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: SegmentedButton<CalendarType>(
                            style: SegmentedButton.styleFrom(
                              backgroundColor: isDarkMode ? _darkSurfaceColor : Colors.grey[100],
                              selectedBackgroundColor: isDarkMode ? _darkSelectedColor : _primaryAppColor.withOpacity(0.1),
                              selectedForegroundColor: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
                              foregroundColor: isDarkMode ? _darkSecondaryTextColor : Colors.grey[600],
                              side: BorderSide(
                                color: isDarkMode ? _darkDividerColor : Colors.grey[300]!,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            segments: const [
                              ButtonSegment<CalendarType>(
                                value: CalendarType.integrated,
                                label: Text('통합형'),
                              ),
                              ButtonSegment<CalendarType>(
                                value: CalendarType.split,
                                label: Text('분리형'),
                              ),
                            ],
                            selected: {UserData.calendarType},
                            onSelectionChanged: (newValue) {
                              _triggerVibration();
                              setState(() {
                                UserData.calendarType = newValue.first;
                              });
                            },
                            showSelectedIcon: false,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        _buildDivider(),
        _buildTapableTile(
          title: '한 주 시작 요일',
          subtitle: '${weekdayLocaleKR[UserData.firstDayOfWeek]}요일 시작',
          icon: Icons.event_rounded,
          onTap: () {
            _triggerVibration();
            setState(() {
              _isFirstDayButtonsVisible = !_isFirstDayButtonsVisible;
              if (_isFirstDayButtonsVisible) {
                _firstDayAnimationController.forward();
              } else {
                _firstDayAnimationController.reverse();
              }
            });
          },
        ),
        SizeTransition(
          sizeFactor: _firstDaySizeAnimation,
          axis: Axis.vertical,
          child: AnimatedOpacity(
            opacity: _isFirstDayButtonsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutQuart,
            child: AnimatedScale(
              scale: _isFirstDayButtonsVisible ? 1.0 : 0.9,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutQuart,
              child: _isFirstDayButtonsVisible
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: SegmentedButton<int>(
                            style: SegmentedButton.styleFrom(
                              backgroundColor: isDarkMode ? _darkSurfaceColor : Colors.grey[100],
                              selectedBackgroundColor: isDarkMode ? _darkSelectedColor : _primaryAppColor.withOpacity(0.1),
                              selectedForegroundColor: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
                              foregroundColor: isDarkMode ? _darkSecondaryTextColor : Colors.grey[600],
                              side: BorderSide(
                                color: isDarkMode ? _darkDividerColor : Colors.grey[300]!,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            segments: weekdayLocaleKR.entries
                                .map((entry) => ButtonSegment<int>(
                                      value: entry.key,
                                      label: Text(entry.value),
                                    ))
                                .toList(),
                            selected: {UserData.firstDayOfWeek},
                            onSelectionChanged: (newValue) {
                              _triggerVibration();
                              setState(() {
                                UserData.firstDayOfWeek = newValue.first;
                              });
                            },
                            showSelectedIcon: false,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppoint() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return _buildModernCard(
      children: [
        _buildSwitchTile(
          title: '완료된 일정 표시',
          subtitle: UserData.showFinished ? '완료된 일정 표시' : '완료된 일정 숨김',
          icon: Icons.check_circle_outline_rounded,
          value: UserData.showFinished,
          onChanged: (value) {
            _triggerVibration();
            setState(() {
              UserData.showFinished = value;
            });
            Calendar.saveAppointmentCounts();
          },
        ),
        _buildDivider(),
        _buildTapableTile(
  title: '알림 설정',
  subtitle: _buildNotificationSubtitle(UserData.notificationBeforeMinutes),
  icon: Icons.notifications_active,
  onTap: () {
    _triggerVibration();
    setState(() {
      _isNotificationTimeButtonsVisible = !_isNotificationTimeButtonsVisible;
      if (_isNotificationTimeButtonsVisible) {
        _notificationTimeAnimationController.forward();
      } else {
        _notificationTimeAnimationController.reverse();
      }
    });
  },
),
SizeTransition(
  sizeFactor: _notificationTimeSizeAnimation,
  axis: Axis.vertical,
  child: AnimatedOpacity(
    opacity: _isNotificationTimeButtonsVisible ? 1.0 : 0.0,
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOutQuart,
    child: AnimatedScale(
      scale: _isNotificationTimeButtonsVisible ? 1.0 : 0.9,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutQuart,
      child: _isNotificationTimeButtonsVisible
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: _InlineNotificationTimePicker(
                    initialMinutes: UserData.notificationBeforeMinutes,
                    onChanged: (newMinutes) {
                      _triggerVibration();
                      setState(() {
                        UserData.notificationBeforeMinutes = newMinutes;
                        Notify.updateEventReminderNotifications();
                      });
                    },
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    ),
  ),
),
        if (_subjectCodeThisSemester.isNotEmpty) ...[
          _buildDivider(),
          _buildTapableTile(
            title: '과목별 색상',
            subtitle: '원하는 과목 색상 변경',
            icon: Icons.palette_rounded,
            onTap: () {
              _triggerVibration();
              _showColorSettingsDialog();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildInfoAndFeedback() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return _buildModernCard(
      children: [
        _buildTapableTile(
          title: '도움말',
          subtitle: '이용 약관 & 방침 ',
          icon: Icons.help_outline_rounded,
          onTap: () {
            _triggerVibration();
            setState(() {
              _isHelpButtonsVisible = !_isHelpButtonsVisible;
              if (_isHelpButtonsVisible) {
                _helpAnimationController.forward();
              } else {
                _helpAnimationController.reverse();
              }
            });
          },
        ),
        SizeTransition(
          sizeFactor: _helpSizeAnimation,
          axis: Axis.vertical,
          child: AnimatedOpacity(
            opacity: _isHelpButtonsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutQuart,
            child: AnimatedScale(
              scale: _isHelpButtonsVisible ? 1.0 : 0.9,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutQuart,
              child: _isHelpButtonsVisible
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        children: [
                          _buildTapableTile(
                            title: '개인정보 처리방침',
                            subtitle: '개인정보 처리 정책 확인',
                            icon: Icons.privacy_tip_rounded,
                            onTap: () {
                              _triggerVibration();
                              _launchURL('https://junsseoo1.github.io/privacy/');
                            },
                          ),
                          _buildDivider(),
                          _buildTapableTile(
                            title: '서비스 이용 약관',
                            subtitle: '이용 약관 확인',
                            icon: Icons.description_rounded,
                            onTap: () {
                              _triggerVibration();
                              _launchURL('https://junsseoo1.github.io/service/');
                            },
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDarkMode ? _darkSelectedColor : _primaryAppColor.withOpacity(0.1))
                : (isDarkMode ? _darkSurfaceColor : Colors.grey[100]!),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? (isDarkMode ? _darkPrimaryColor : _primaryAppColor) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? (isDarkMode ? _darkPrimaryColor : _primaryAppColor)
                    : (isDarkMode ? _darkSecondaryTextColor : Colors.grey[600]),
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? (isDarkMode ? _darkPrimaryColor : _primaryAppColor)
                      : (isDarkMode ? _darkSecondaryTextColor : Colors.grey[600]),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(
        icon,
        color: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
        size: _leadingIconSize,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDarkMode ? _darkTextColor : Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 14,
          color: isDarkMode ? _darkSecondaryTextColor : Colors.grey[600],
        ),
      ),
      trailing: Switch(
        activeColor: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
        activeTrackColor: isDarkMode ? _darkPrimaryColor.withOpacity(0.3) : _primaryAppColor.withOpacity(0.3),
        inactiveThumbColor: isDarkMode ? Colors.grey[400] : Colors.grey[500],
        inactiveTrackColor: isDarkMode ? _darkSurfaceColor : Colors.grey[200],
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }

  Widget _buildTapableTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDarkMode ? _darkPrimaryColor : _primaryAppColor,
              size: _leadingIconSize,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? _darkTextColor : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? _darkSecondaryTextColor : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDarkMode ? _darkSecondaryTextColor : Colors.grey[500],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: isDarkMode ? _darkDividerColor : Colors.grey[200],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: isDarkMode ? _darkBackgroundColor : Colors.white,
        appBar: AppBar(
          title: const Text(
            '설정',
            style: TextStyle(
              color: const Color(0xFF5B8DEF),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: isDarkMode ? _darkBackgroundColor : Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 5),
              _buildAnimatedCard(card: _buildAccountSection(), index: 0),
              _buildAnimatedCard(card: _buildGoogleCalendarSection(), index: 1),
              _buildAnimatedCard(card: _buildGeneralSettings(), index: 2),
              _buildAnimatedCard(card: _buildAppoint(), index: 3),
              _buildAnimatedCard(card: _buildInfoAndFeedback(), index: 4),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({Key? key, this.size = 18.0}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: GoogleLogoPainter(),
      ),
    );
  }
}

class GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final Offset center = Offset(radius, radius);

    final Paint whitePaint = Paint()..color = Colors.white;
    final Paint redPaint = Paint()..color = const Color(0xFFEA4335);
    final Paint bluePaint = Paint()..color = const Color(0xFF4285F4);
    final Paint greenPaint = Paint()..color = const Color(0xFF34A853);
    final Paint yellowPaint = Paint()..color = const Color(0xFFFBBC05);

    canvas.drawCircle(center, radius, whitePaint);

    final double segmentWidth = radius * 0.35;

    Path redPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx + radius, center.dy - radius)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -Math.pi / 4,
        -Math.pi / 2,
        false,
      )
      ..close();
    canvas.drawPath(redPath, redPaint);

    Path bluePath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx + radius, center.dy + radius)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        Math.pi / 4,
        -Math.pi / 2,
        false,
      )
      ..close();
    canvas.drawPath(bluePath, bluePaint);

    Path greenPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - radius, center.dy + radius)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        3 * Math.pi / 4,
        -Math.pi / 2,
        false,
      )
      ..close();
    canvas.drawPath(greenPath, greenPaint);

    Path yellowPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - radius, center.dy - radius)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        5 * Math.pi / 4,
        -Math.pi / 2,
        false,
      )
      ..close();
    canvas.drawPath(yellowPath, yellowPaint);

    canvas.drawCircle(center, radius * 0.6, whitePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}