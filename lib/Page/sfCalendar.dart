import 'dart:async';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../page/settings.dart';
import '../Data/userData.dart';
import 'widget/appointmentEditor.dart';
import '../utility.dart';
import 'package:flutter/cupertino.dart';
import 'package:vibration/vibration.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:plato_calendar/notify.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'dart:ui' show lerpDouble;

class Calendar extends StatefulWidget {
  final BannerAd? bannerAd;
  final bool isBannerAdReady;

  Calendar({this.bannerAd, required this.isBannerAdReady});

  @override
  State<StatefulWidget> createState() => _CalendarState();

  // Static method that can be called from other files
  static Future<void> saveAppointmentCounts() async {
    try {
      // Hive 초기화 확인
      if (!Hive.isBoxOpen('userData')) {
        await Hive.openBox('userData');
        print('[Flutter] Hive box opened for userData');
      }

      Map<String, int> appointmentCounts = {};
      for (var appointment in UserData.data) {
        if (!appointment.disable && (!appointment.finished || UserData.showFinished)) {
          String dateKey = DateFormat('yyyy-MM-dd').format(appointment.end.toLocal());
          appointmentCounts[dateKey] = (appointmentCounts[dateKey] ?? 0) + 1;
        }
      }

      print('[Flutter] Preparing to save appointment counts: ${appointmentCounts.toString()}');
      
      const platform = MethodChannel('com.junseo.platoCalendar/userdefaults');
      final result = await platform.invokeMethod('saveAppointmentCounts', {
        'counts': appointmentCounts,
      });
      
      print('[Flutter] Save result: $result');
    } catch (e, stackTrace) {
      print('[Flutter] Error saving appointment counts: $e');
      print('[Flutter] Stack trace: $stackTrace');
    }
  }
}

class _CalendarState extends State<Calendar> {
  CalendarView viewType = CalendarView.month;
  CalendarController _calendarController = CalendarController();
  late StreamSubscription<dynamic> listener;
  DateTime _currentDate = DateTime.now();
  DateTime? _selectedDate;
  DateTime? _lastSelectedDate;
  Appointment? _tappedAppointment;

  @override
  void initState() {
    super.initState();
    
    Intl.defaultLocale = 'ko_KR';
    _calendarController.view = CalendarView.month;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _calendarController.selectedDate = DateTime.now();
          _lastSelectedDate = DateTime.now();
        });
      }
    });
    listener = pnuStream.stream.listen((event) {
      if (event) setState(() {});
    });
  }

  @override
  void dispose() {
    listener.cancel();
    super.dispose();
  }

  Future<void> _triggerVibration() async {
    HapticFeedback.lightImpact();
  }

  // Reschedule notifications
  Future<void> _rescheduleNotifications() async {
    await Notify.scheduleEventReminderNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: isDarkMode ? Color(0xFF121212) : null, 
      appBar: AppBar(
        title: GestureDetector(
          onTap: () async {
            await _triggerVibration();
            showModalBottomSheet(
              context: context,
              builder: (BuildContext context) {
                return Container(
                  height: 300,
                  color: isDarkMode ? Colors.grey[900] : Colors.white,
                  child: Column(
                    children: [
                      Container(
                        height: 50,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: Text(
                                '취소',
                                style: TextStyle(color: Colors.red, fontSize: 16),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _currentDate = _selectedDate ?? _currentDate;
                                  _calendarController.displayDate = _currentDate;
                                  _lastSelectedDate = _currentDate;
                                  UserData.selectedDate = _currentDate; // Update UserData.selectedDate
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    _calendarController.selectedDate = _currentDate;
                                  });
                                });
                                Navigator.pop(context);
                              },
                              child: Text(
                                '완료',
                                style: TextStyle(color: Colors.blue, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: CupertinoTheme(
                          data: CupertinoThemeData(
                            textTheme: CupertinoTextThemeData(
                              dateTimePickerTextStyle: TextStyle(
                                color: isDarkMode ? Colors.white : Colors.black,
                                fontSize: 21,
                              ),
                            ),
                          ),
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.date,
                            initialDateTime: UserData.selectedDate ?? _currentDate,
                            minimumDate: DateTime(2000),
                            maximumDate: DateTime(2100),
                            onDateTimeChanged: (DateTime date) {
                              _selectedDate = date;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              DateFormat('yyyy년 M월').format(_currentDate),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        backgroundColor: const Color.fromARGB(255, 59, 113, 208),
        foregroundColor: Colors.white,
        actions: [
          AnimatedSwitcher(
            duration: Duration(milliseconds: 150),
            child: (UserData.selectedDate != null &&
                    (UserData.selectedDate!.year != DateTime.now().year ||
                        UserData.selectedDate!.month != DateTime.now().month ||
                        UserData.selectedDate!.day != DateTime.now().day))
                ? TextButton(
                    key: ValueKey("todayButton"),
                    onPressed: () async {
                      await _triggerVibration();
                      setState(() {
                        _currentDate = DateTime.now();
                        _calendarController.displayDate = DateTime.now();
                        _lastSelectedDate = DateTime.now();
                        UserData.selectedDate = DateTime.now(); // Update UserData.selectedDate
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _calendarController.selectedDate = DateTime.now();
                        });
                      });
                    },
                    style: TextButton.styleFrom(
                      side: BorderSide(color: Colors.white, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      foregroundColor: Colors.white,
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: Text(
                      "TODAY",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  )
                : SizedBox.shrink(),
          ),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () async {
              await _triggerVibration();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  side: BorderSide.none,
                ),
                clipBehavior: Clip.antiAlias,
                builder: (BuildContext context) {
                  return Container(
                    height: MediaQuery.of(context).size.height * 0.8,
                    color: Colors.transparent,
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                      child: PopUpAppointmentEditor.newAppointmentWithAd(
                        bannerAd: widget.bannerAd,
                        isBannerAdReady: widget.isBannerAdReady,
                      ),
                    ),
                  );
                },
              ).then((value) async {
                if (value != null) {
                  setState(() {
                    UserData.uidSet.add(value.uid);
                    UserData.data.add(value);
                    _rescheduleNotifications();
                  });
                  UserData.writeDatabase.uidSetSave();
                  await Calendar.saveAppointmentCounts(); // Update widget
                }
              });
            },
          ),
        ],
      ),
      body: WillPopScope(
        child: FutureBuilder(
          future: _getCalendarDataSource(),
          builder: (BuildContext context, AsyncSnapshot snapshot) {
            return SafeArea(
              child: SfCalendar(
                onSelectionChanged: (CalendarSelectionDetails details) {
                  if (_selectedDate == null || _selectedDate != details.date) {
                    setState(() {
                      _selectedDate = details.date;
                      UserData.selectedDate = details.date ?? DateTime.now();
                    });
                  }
                },
                selectionDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
                controller: _calendarController,
                headerHeight: 0,
                todayHighlightColor: const Color.fromARGB(255, 59, 113, 208),
                firstDayOfWeek: UserData.firstDayOfWeek,
                monthViewSettings: MonthViewSettings(
                  dayFormat: 'EEE',
                  appointmentDisplayCount: 4,
                  appointmentDisplayMode:
                      UserData.calendarType == CalendarType.split
                          ? MonthAppointmentDisplayMode.appointment
                          : MonthAppointmentDisplayMode.indicator,
                  showAgenda: UserData.calendarType == CalendarType.split
                      ? false
                      : true,
                ),
                viewHeaderStyle: ViewHeaderStyle(
                  dayTextStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.grey[900],
                  ),
                ),
                cellBorderColor: Colors.transparent,
                scheduleViewSettings: ScheduleViewSettings(
                  monthHeaderSettings: MonthHeaderSettings(
                    height: 100,
                    monthFormat: 'yyyy년 M월',
                  ),
                ),
                dataSource: snapshot.hasData ? snapshot.data : DataSource([]),
                appointmentBuilder: (UserData.calendarType ==
                        CalendarType.integrated)
                    ? (BuildContext context,
                        CalendarAppointmentDetails details) {
                        final Appointment appointment =
                            details.appointments!.first;
                        final bool isTapped = _tappedAppointment == appointment;
                        return AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          transform: Matrix4.identity()
                            ..scale(isTapped ? 0.7 : 1.0),
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: appointment.color,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '  ' + appointment.subject,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                TextSpan(
                                  text:
                                      '\n${DateFormat('  a hh:mm', 'ko_KR').format(appointment.endTime)} 까지',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    : null,
                monthCellBuilder:
                    (BuildContext context, MonthCellDetails details) {
                  final bool isSunday =
                      DateFormat('EEE', 'ko_KR').format(details.date) == '일';
                  final bool isCurrentMonth =
                      details.date.month == _currentDate.month;
                  final bool isSelected = _selectedDate != null &&
                      details.date.year == _selectedDate!.year &&
                      details.date.month == _selectedDate!.month &&
                      details.date.day == _selectedDate!.day;
                  final bool isToday =
                      details.date.year == DateTime.now().year &&
                          details.date.month == DateTime.now().month &&
                          details.date.day == DateTime.now().day;

                  return AnimatedContainer(
                    duration: Duration(milliseconds: 230),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blueGrey.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Align(
                      alignment: FractionalOffset(0.5, 0.10),
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isToday
                              ? Color.fromARGB(255, 59, 113, 208)
                              : Colors.transparent,
                        ),
                        child: Text(
                          details.date.day.toString(),
                          style: TextStyle(
                            color: isToday
                                ? Colors.white
                                : isSunday
                                    ? Colors.red
                                    : isCurrentMonth
                                        ? Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                            : Colors.black
                                        : Colors.grey,
                            fontWeight: isCurrentMonth
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                onTap: (data) async {
                  if (UserData.calendarType == CalendarType.split) {
                    if (_calendarController.view == CalendarView.month &&
                        data.targetElement == CalendarElement.calendarCell) {
                      await _triggerVibration();
                      setState(() {
                        _calendarController.view = CalendarView.schedule;
                      });
                    } else if (_calendarController.view ==
                            CalendarView.schedule &&
                        data.targetElement == CalendarElement.appointment) {
                      await _triggerVibration();
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                          side: BorderSide.none,
                        ),
                        clipBehavior: Clip.antiAlias,
                        builder: (BuildContext context) {
                          return Container(
                            height: MediaQuery.of(context).size.height * 0.8,
                            color: Colors.transparent,
                            child: ClipRRect(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20)),
                              child: PopUpAppointmentEditor.appointmentWithAd(
                                data.appointments![0],
                                bannerAd: widget.bannerAd,
                                isBannerAdReady: widget.isBannerAdReady,
                              ),
                            ),
                          );
                        },
                      ).then((value) => setState(() {
                            _rescheduleNotifications();
                            Calendar.saveAppointmentCounts(); // Update widget
                          }));
                    }
                  } else if (UserData.calendarType == CalendarType.integrated) {
                    if (data.targetElement == CalendarElement.appointment) {
                      await _triggerVibration();
                      setState(() {
                        _tappedAppointment = data.appointments![0];
                      });
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                          side: BorderSide.none,
                        ),
                        clipBehavior: Clip.antiAlias,
                        builder: (BuildContext context) {
                          return Container(
                            height: MediaQuery.of(context).size.height * 0.8,
                            color: Colors.transparent,
                            child: ClipRRect(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20)),
                              child: PopUpAppointmentEditor.appointmentWithAd(
                                data.appointments![0],
                                bannerAd: widget.bannerAd,
                                isBannerAdReady: widget.isBannerAdReady,
                              ),
                            ),
                          );
                        },
                      ).then((value) => setState(() {
                            _tappedAppointment = null;
                            _rescheduleNotifications();
                            Calendar.saveAppointmentCounts(); // Update widget
                          }));
                    } else if (data.targetElement ==
                        CalendarElement.calendarCell) {
                      await _triggerVibration();
                      final tappedDate = data.date!;
                      if (_selectedDate != null &&
                          _selectedDate!.year == tappedDate.year &&
                          _selectedDate!.month == tappedDate.month &&
                          _selectedDate!.day == tappedDate.day) {
                        if (_lastSelectedDate != null &&
                            _lastSelectedDate!.year == tappedDate.year &&
                            _lastSelectedDate!.month == tappedDate.month &&
                            _lastSelectedDate!.day == tappedDate.day) {
                          await _triggerVibration();
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20)),
                              side: BorderSide.none,
                            ),
                            clipBehavior: Clip.antiAlias,
                            builder: (BuildContext context) {
                              return Container(
                                height:
                                    MediaQuery.of(context).size.height * 0.8,
                                color: Colors.transparent,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20)),
                                  child: PopUpAppointmentEditor
                                      .newAppointmentWithAd(
                                    bannerAd: widget.bannerAd,
                                    isBannerAdReady: widget.isBannerAdReady,
                                  ),
                                ),
                              );
                            },
                          ).then((value) async {
                            if (value != null) {
                              setState(() {
                                UserData.uidSet.add(value.uid);
                                UserData.data.add(value);
                                _rescheduleNotifications();
                              });
                              UserData.writeDatabase.uidSetSave();
                              await Calendar.saveAppointmentCounts(); // Update widget
                            }
                          });
                        }
                      }
                      setState(() {
                        _selectedDate = tappedDate;
                        _lastSelectedDate = tappedDate;
                        UserData.selectedDate = tappedDate; // Update UserData.selectedDate
                      });
                    }
                  }
                },
                onLongPress: (data) async {
                  if (data.targetElement == CalendarElement.appointment) {
                    await _triggerVibration();
                    setState(() {
                      _tappedAppointment = data.appointments![0];
                    });
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return SimplePopUpAppointmentEditor(
                            data.appointments![0]);
                      },
                    ).then((value) => setState(() {
                          _tappedAppointment = null;
                          if (value == true) {
                            showMessage(context, "완료된 일정으로 변경했습니다.");
                          } else if (value == false) {
                            showMessage(context, "일정을 삭제 했습니다.");
                          }
                          _rescheduleNotifications();
                          Calendar.saveAppointmentCounts(); // Update widget
                        }));
                  }
                },
                onViewChanged: (ViewChangedDetails details) {
                  final List<DateTime> visibleDates = details.visibleDates;
                  final DateTime middleDate =
                      visibleDates[visibleDates.length ~/ 2];
                  if (_currentDate.month != middleDate.month) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _currentDate = middleDate;
                          UserData.selectedDate = middleDate; // Update UserData.selectedDate
                        });
                      }
                    });
                  }
                },
              ),
            );
          },
        ),
        onWillPop: () async {
          if (_calendarController.view == CalendarView.schedule) {
            setState(() {
              _calendarController.view = CalendarView.month;
            });
            return false;
          }
          return true;
        },
      ),
    );
  }
}

class DataSource extends CalendarDataSource {
  DataSource(List<Appointment> source) {
    appointments = source;
  }

  @override
  DateTime getStartTime(int index) => appointments![index].from;

  @override
  DateTime getEndTime(int index) => appointments![index].to;

  @override
  String getSubject(int index) => appointments![index].eventName;

  @override
  Color getColor(int index) => appointments![index].background;

  @override
  bool isAllDay(int index) => appointments![index].isAllDay;
}

Future<DataSource> _getCalendarDataSource() async {
  List<Appointment> appointments = <Appointment>[];
  for (var iter in UserData.data) {
    if (!iter.disable && (!iter.finished || UserData.showFinished)) {
      appointments.add(iter.toAppointment());
    }
  }
  return DataSource(appointments);
}