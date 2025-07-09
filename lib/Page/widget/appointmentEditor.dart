import 'dart:math';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:plato_calendar/Data/etc.dart';
import 'package:plato_calendar/utility.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:intl/intl.dart';
import '../../Data/subjectCode.dart';
import '../../Data/userData.dart';
import '../../Data/ics.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';


const Color _primaryAppColor = Color.fromARGB(255, 59, 113, 208);
const Color _darkBackgroundColor = Color(0xFF121212);
const Color _darkCardColor = Color(0xFF1E1E1E);

class PopUpAppointmentEditor extends StatefulWidget {
  bool newData = false;
  late CalendarData calendarData;
  final BannerAd? bannerAd;
  final bool isBannerAdReady;

  CalendarData get scalendarData => calendarData;

  PopUpAppointmentEditor.appointment(Appointment data)
      : bannerAd = null,
        isBannerAdReady = false {
    calendarData = UserData.data.firstWhere((value) {
      return value.hashCode == data.resourceIds![0];
    });
  }

  PopUpAppointmentEditor.appointmentWithAd(
    Appointment data, {
    required this.bannerAd,
    required this.isBannerAdReady,
  }) {
    calendarData = UserData.data.firstWhere((value) {
      return value.hashCode == data.resourceIds![0];
    });
  }

  PopUpAppointmentEditor(this.calendarData)
      : bannerAd = null,
        isBannerAdReady = false;

  PopUpAppointmentEditor.newAppointment()
      : bannerAd = null,
        isBannerAdReady = false {
    DateTime time = DateTime.now();
    time = time.subtract(Duration(
        seconds: time.second,
        milliseconds: time.millisecond,
        microseconds: time.microsecond));
    calendarData = CalendarData.newIcs();
    newData = true;
  }

  PopUpAppointmentEditor.newAppointmentWithAd({
    required this.bannerAd,
    required this.isBannerAdReady,
  }) {
    DateTime time = DateTime.now();
    time = time.subtract(Duration(
        seconds: time.second,
        milliseconds: time.millisecond,
        microseconds: time.microsecond));
    calendarData = CalendarData.newIcs();
    newData = true;
  }

  @override
  _PopUpAppointmentEditorState createState() => _PopUpAppointmentEditorState();
}

Future<void> _triggerVibration() async {
  HapticFeedback.lightImpact();
}

class _PopUpAppointmentEditorState extends State<PopUpAppointmentEditor>
    with SingleTickerProviderStateMixin {
  TextEditingController summaryController = TextEditingController();
  TextEditingController descriptionController = TextEditingController();
  TextEditingController memoController = TextEditingController();
  TextEditingController _newSubjectController = TextEditingController();
  late String _classCode;
  late DateTime _start;
  late DateTime _end;
  late int _color;
  late bool _isPlato;
  double _bottomPadding = 16.0;
  FocusNode _titleFocusNode = FocusNode();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _showStartTimePicker = false;
  bool _showEndTimePicker = false;
  bool _isSwitchingPicker = false;
  bool _isEditingSubjects = false;
  bool _hasText = false;
  bool _refreshDropdown = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    )..forward();
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mediaQuery = MediaQuery.of(context);
      if (mediaQuery.viewInsets.bottom > 0) {
        setState(() {
          _bottomPadding = mediaQuery.viewInsets.bottom + 16.0;
        });
      }
    });
    summaryController.text = widget.calendarData.summary;
    descriptionController.text = widget.calendarData.description;
    memoController.text = widget.calendarData.memo;
    _classCode =
        UserData.subjectCodeThisSemester.contains(widget.calendarData.classCode)
            ? widget.calendarData.classCode
            : UserData.subjectCodeThisSemester.first;
    _start = widget.calendarData.start;
    _end = widget.calendarData.end;
    _color = widget.calendarData.color % colorCollection.length;
    _isPlato = widget.calendarData.isPlato;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (summaryController.text.trim().isEmpty) {
        FocusScope.of(context).requestFocus(_titleFocusNode);
      }
    });

    _newSubjectController.addListener(() {
      setState(() {
        _hasText = _newSubjectController.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    summaryController.dispose();
    descriptionController.dispose();
    memoController.dispose();
    _newSubjectController.dispose();
    _titleFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _addNewSubject() {
    String newSubject = _newSubjectController.text.trim();
    if (newSubject.isEmpty) {
      showToastMessageCenter("과목 이름을 입력하세요.");
      return;
    }
    Set<String> existingSubjects = UserData.subjectCodeThisSemester
        .map((s) => s.trim())
        .toSet();
    if (existingSubjects.contains(newSubject)) {
      showToastMessageCenter("이미 존재하는 과목입니다.");
      return;
    }
    setState(() {
      UserData.subjectCodeThisSemester.add(newSubject);
      Set usedColors = UserData.defaultColor.values.toSet();
      int newColorIndex = 0;
      while (usedColors.contains(newColorIndex)) {
        newColorIndex++;
        if (newColorIndex >= colorCollection.length) {
          newColorIndex = Random().nextInt(colorCollection.length);
          break;
        }
      }
      UserData.defaultColor[newSubject] = newColorIndex;
      _classCode = newSubject;
      _color = newColorIndex;
      UserData.writeDatabase.subjectCodeThisSemesterSave();
      UserData.writeDatabase.defaultColorSave();
      _newSubjectController.clear();
      _isEditingSubjects = false;
    });
  }

  void _deleteSubject(String subject) {
    if (subject == '전체') {
      showToastMessageCenter("전체 과목은 삭제할 수 없습니다.");
      return;
    }
    bool hasPlato = UserData.data.any((data) => data.classCode == subject && data.isPlato);
    if (hasPlato) {
      showToastMessageCenter("이 과목에는 Plato 일정이 있어 삭제할 수 없습니다.");
      return;
    }
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColorPrimary = isDarkMode ? Colors.white : Colors.black87;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: isDarkMode ? _darkCardColor : Colors.white,
          title: Text(
            '삭제',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: textColorPrimary,
            ),
          ),
          content: Text(
            '"$subject" 과목을 삭제하시겠습니까?',
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode ? Colors.white70 : Colors.grey[700]!,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  UserData.subjectCodeThisSemester.remove(subject);
                  UserData.defaultColor.remove(subject);
                  for (var data in UserData.data) {
                    if (data.classCode == subject) {
                      data.classCode = '과목 분류 없음';
                      data.className = '';
                      UserData.writeDatabase.calendarDataSave(data);
                    }
                  }
                  if (_classCode == subject) {
                    _classCode = '전체';
                  }
                  UserData.writeDatabase.subjectCodeThisSemesterSave();
                  UserData.writeDatabase.defaultColorSave();
                  _refreshDropdown = !_refreshDropdown;
                });
                Navigator.pop(context, true);
              },
              child: Text(
                '확인',
                style: TextStyle(
                  color: textColorPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                '취소',
                style: TextStyle(
                  color: textColorPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColorPrimary = isDarkMode ? Colors.white : Colors.black87;
    final Color textColorSecondary = isDarkMode ? Colors.white70 : Colors.grey[700]!;
    final Color textColorHint = isDarkMode ? Colors.white54 : Colors.grey[500]!;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorCollection[_color],
        elevation: 0,
        actions: [
          if (!widget.newData && !widget.calendarData.finished)
            Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: Icon(Icons.task_alt, size: 22),
                color: Colors.white,
                onPressed: () {
                  _triggerVibration();
                  setState(() {
                    widget.calendarData.finished = true;
                  });
                  UserData.writeDatabase.calendarDataSave(widget.calendarData);
                  showToastMessageCenter("완료된 일정으로 변경했습니다.");
                  Navigator.pop(context);
                },
                tooltip: "완료",
              ),
            ),
          if (!widget.newData)
            Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: IconButton(
                icon: Icon(Icons.delete_rounded, size: 22),
                color: Colors.white,
                onPressed: () {
                  _triggerVibration();
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: isDarkMode ? _darkCardColor : Colors.white,
                        title: Text(
                          "삭제",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: textColorPrimary,
                          ),
                        ),
                        content: Text(
                          "정말 삭제하시겠습니까?",
                          style: TextStyle(
                            fontSize: 16,
                            color: textColorSecondary,
                          ),
                        ),
                        actions: [
                          TextButton(
                            child: Text(
                              "확인",
                              style: TextStyle(
                                color: textColorPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, true),
                          ),
                          TextButton(
                            child: Text(
                              "취소",
                              style: TextStyle(
                                color: textColorPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, false),
                          ),
                        ],
                      );
                    },
                  ).then((value) {
                    if (value != null && value) {
                      widget.calendarData.disable = true;
                      Navigator.pop(context);
                      UserData.writeDatabase.calendarDataSave(widget.calendarData);
                    }
                  });
                },
                tooltip: "삭제",
              ),
            ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 18,
                    color: textColorSecondary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: _isEditingSubjects
                        ? Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  cursorColor: _primaryAppColor,
                                  controller: _newSubjectController,
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: '새 과목 이름',
                                    hintStyle: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: textColorHint,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textColorPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _hasText ? Icons.save : Icons.close,
                                  color: textColorSecondary,
                                ),
                                onPressed: () {
                                  _triggerVibration();
                                  if (_hasText) {
                                    _addNewSubject();
                                  } else {
                                    setState(() {
                                      _isEditingSubjects = false;
                                      _newSubjectController.clear();
                                    });
                                  }
                                },
                              ),
                            ],
                          )
                        : DropdownButton<String>(
                            key: Key(_refreshDropdown.toString()),
                            value: _classCode,
                            icon: Icon(
                              Icons.arrow_drop_down,
                              size: 20,
                              color: textColorSecondary,
                            ),
                            isExpanded: true,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textColorPrimary,
                            ),
                            underline: SizedBox(),
                            dropdownColor: isDarkMode ? _darkCardColor : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            onChanged: (String? newValue) {
                              setState(() {
                                _classCode = newValue!;
                                if (UserData.defaultColor.containsKey(_classCode)) {
                                  _color = UserData.defaultColor[_classCode] % colorCollection.length;
                                }
                              });
                            },
                            items: UserData.subjectCodeThisSemester
                                .map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: GestureDetector(
                                  onLongPress: () {
                                    if (value != '전체') {
                                      _deleteSubject(value);
                                    }
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                    child: Text(
                                      subjectCode[value] ?? value,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: textColorPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                  if (!_isEditingSubjects)
                    IconButton(
                      icon: Icon(Icons.edit, size: 18, color: textColorSecondary),
                      onPressed: () {
                        _triggerVibration();
                        setState(() {
                          _isEditingSubjects = true;
                        });
                      },
                    ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: isDarkMode ? _darkCardColor : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.12),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colorCollection[_color],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      cursorColor: _primaryAppColor,
                      controller: summaryController,
                      focusNode: _titleFocusNode,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: "제목",
                        hintStyle: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: textColorHint,
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                      ),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: textColorPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDarkMode ? _darkCardColor : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.12),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 18,
                        color: textColorSecondary,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          descriptionController.text.isEmpty
                              ? "내용 없음"
                              : descriptionController.text,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: descriptionController.text.isEmpty
                                ? textColorHint
                                : textColorPrimary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 18,
                        color: textColorSecondary,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isPlato
                              ? () {
                                  _triggerVibration();
                                  showToastMessageCenter("Plato 일정은 시간 변경이 불가합니다.");
                                }
                              : () {
                                  _triggerVibration();
                                  setState(() {
                                    _isSwitchingPicker = _showEndTimePicker;
                                    _showStartTimePicker = !_showStartTimePicker;
                                    _showEndTimePicker = false;
                                  });
                                },
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.black12 : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "시작",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: textColorHint,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  DateFormat('M월 dd일 (EEE)', 'ko_KR').format(_start),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textColorPrimary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  DateFormat('HH:mm').format(_start),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: textColorPrimary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: textColorSecondary,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isPlato
                              ? () {
                                  _triggerVibration();
                                  showToastMessageCenter("Plato 일정은 시간 변경이 불가합니다.");
                                }
                              : () {
                                  _triggerVibration();
                                  setState(() {
                                    _isSwitchingPicker = _showStartTimePicker;
                                    _showEndTimePicker = !_showEndTimePicker;
                                    _showStartTimePicker = false;
                                  });
                                },
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.black12 : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "종료",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: textColorHint,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  DateFormat('M월 dd일 (EEE)', 'ko_KR').format(_end),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textColorPrimary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  DateFormat('HH:mm').format(_end),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: textColorPrimary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  AnimatedContainer(
                    duration: _isSwitchingPicker ? Duration.zero : Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: _showStartTimePicker ? 200.0 : 0.0,
                    child: _showStartTimePicker
                        ? CupertinoTheme(
                            data: CupertinoTheme.of(context).copyWith(
                              textTheme: CupertinoTheme.of(context).textTheme.copyWith(
                                    dateTimePickerTextStyle: CupertinoTheme.of(context)
                                        .textTheme
                                        .dateTimePickerTextStyle
                                        .copyWith(
                                          color: isDarkMode ? Colors.white : Colors.black,
                                        ),
                                  ),
                            ),
                            child: CupertinoDatePicker(
                              mode: CupertinoDatePickerMode.dateAndTime,
                              initialDateTime: _start,
                              onDateTimeChanged: (DateTime newDateTime) {
                                setState(() {
                                  _start = newDateTime;
                                  if (_start.difference(_end).inSeconds > 0) {
                                    _end = _start.add(Duration(hours: 1));
                                  }
                                });
                              },
                              use24hFormat: true,
                              minuteInterval: 1,
                            ),
                          )
                        : SizedBox.shrink(),
                  ),
                  AnimatedContainer(
                    duration: _isSwitchingPicker ? Duration.zero : Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: _showEndTimePicker ? 200.0 : 0.0,
                    child: _showEndTimePicker
                        ? CupertinoTheme(
                            data: CupertinoTheme.of(context).copyWith(
                              textTheme: CupertinoTheme.of(context).textTheme.copyWith(
                                    dateTimePickerTextStyle: CupertinoTheme.of(context)
                                        .textTheme
                                        .dateTimePickerTextStyle
                                        .copyWith(
                                          color: isDarkMode ? Colors.white : Colors.black,
                                        ),
                                  ),
                            ),
                            child: CupertinoDatePicker(
                              mode: CupertinoDatePickerMode.dateAndTime,
                              initialDateTime: _end,
                              onDateTimeChanged: (DateTime newDateTime) {
                                setState(() {
                                  _end = newDateTime;
                                  if (_start.difference(_end).inSeconds > 0) {
                                    _start = _end.subtract(Duration(hours: 1));
                                  }
                                });
                              },
                              use24hFormat: true,
                              minuteInterval: 1,
                            ),
                          )
                        : SizedBox.shrink(),
                  ),
                  SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notes_outlined,
                        size: 18,
                        color: textColorSecondary,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.multiline,
                          maxLines: null,
                          minLines: 1,
                          cursorColor: _primaryAppColor,
                          controller: memoController,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: "메모",
                            hintStyle: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textColorHint,
                            ),
                            contentPadding: EdgeInsets.symmetric(vertical: 6),
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textColorPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  TextButton(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "달력에 표시되는 색깔 : ",
                          style: TextStyle(
                            color: textColorPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(Icons.lens, color: colorCollection[_color]),
                      ],
                    ),
                    onPressed: () {
                      _triggerVibration();
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return CalendarColorPicker(_color);
                        },
                      ).then((value) => setState(() {
                            if (value != null) _color = value;
                          }));
                    },
                  ),
                ],
              ),
            ),
            if (widget.isBannerAdReady == true &&
                widget.bannerAd != null &&
                widget.bannerAd!.responseInfo != null)
              Container(
                width: double.infinity,
                height: 50,
                margin: EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                alignment: Alignment.center,
                child: AdWidget(ad: widget.bannerAd!),
              )
            else
              SizedBox.shrink(),
          ],
        ),
      ),
      floatingActionButton: AnimatedPadding(
        duration: Duration(milliseconds: 300),
        padding: EdgeInsets.only(bottom: _bottomPadding),
        child: FloatingActionButton(
          shape: CircleBorder(),
          onPressed: () {
            _triggerVibration();
            if (summaryController.text.trim().isEmpty) {
              setState(() {
                summaryController.text = "제목 없음";
              });
            }
            widget.calendarData.summary = summaryController.text;
            widget.calendarData.description = descriptionController.text;
            widget.calendarData.memo = memoController.text;
            if (_classCode != "전체") {
              widget.calendarData.classCode = _classCode;
              widget.calendarData.className = subjectCode[_classCode] ?? _classCode;
            } else {
              widget.calendarData.classCode = "과목 분류 없음";
              widget.calendarData.className = "";
            }
            widget.calendarData.start = _start;
            widget.calendarData.end = _end;
            widget.calendarData.color = _color;
            widget.calendarData.isPeriod = (_start != _end);
            if (widget.newData)
              Navigator.pop(context, widget.calendarData);
            else
              Navigator.pop(context);
            UserData.writeDatabase.calendarDataSave(widget.calendarData);
          },
          child: Icon(
            Icons.save,
            color: Colors.white,
            size: 22,
          ),
          backgroundColor: colorCollection[_color],
          elevation: 5,
        ),
      ),
    );
  }
}

class CalendarColorPicker extends StatefulWidget {
  CalendarColorPicker(this.calendarColor);
  final int calendarColor;

  @override
  State<StatefulWidget> createState() =>
      _CalendarColorPickerState(calendarColor);
}

class _CalendarColorPickerState extends State<CalendarColorPicker> {
  int _calendarColor;
  _CalendarColorPickerState(this._calendarColor);

  @override
  Widget build(context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColorPrimary = isDarkMode ? Colors.white : Colors.black87;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20.0, 10.0, 20.0, 24.0),
      backgroundColor: isDarkMode ? _darkCardColor : Colors.white,
      content: Container(
        alignment: Alignment.center,
        width: (colorCollection.length * 100).toDouble(),
        height: 50.0,
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.all(0),
          leading: Text(
            '색상',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: textColorPrimary,
            ),
          ),
          title: ListView.builder(
            padding: EdgeInsets.all(0),
            scrollDirection: Axis.horizontal,
            itemCount: colorCollection.length,
            itemBuilder: (context, i) {
              return TextButton(
                style: TextButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.all(2.2),
                ),
                onPressed: () {
                  _triggerVibration();
                  setState(() {
                    _calendarColor = i;
                  });
                  Future.delayed(const Duration(milliseconds: 200), () {
                    Navigator.pop(context, _calendarColor);
                  });
                },
                child: Icon(
                  i == _calendarColor ? Icons.lens : Icons.trip_origin,
                  color: colorCollection[i],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class SimplePopUpAppointmentEditor extends StatefulWidget {
  final CalendarData calendarData;

  SimplePopUpAppointmentEditor(Appointment data)
      : calendarData = UserData.data.firstWhere((value) {
          return value.hashCode == data.resourceIds![0];
        });

  @override
  State<StatefulWidget> createState() =>
      _SimplePopUpAppointmentEditorState(calendarData);
}

class _SimplePopUpAppointmentEditorState
    extends State<SimplePopUpAppointmentEditor> {
  CalendarData calendarData;

  _SimplePopUpAppointmentEditorState(this.calendarData);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColorPrimary = isDarkMode ? Colors.white : Colors.black87;

    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      backgroundColor: isDarkMode ? _darkCardColor : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Container(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () {
                _triggerVibration();
                calendarData.finished = true;
                UserData.writeDatabase.calendarDataSave(calendarData);
                Navigator.pop(context, true);
              },
              child: Text(
                "일정 완료처리 하기",
                style: TextStyle(
                  color: textColorPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _triggerVibration();
                calendarData.disable = true;
                UserData.writeDatabase.calendarDataSave(calendarData);
                Navigator.pop(context, false);
              },
              child: Text(
                "일정 삭제",
                style: TextStyle(
                  color: textColorPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _triggerVibration();
                Navigator.pop(context);
              },
              child: Text(
                "취소",
                style: TextStyle(
                  color: textColorPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}