import 'dart:async';
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../Data/etc.dart';
import '../Data/subjectCode.dart';
import '../Data/userData.dart';
import 'widget/adBanner.dart';
import 'widget/appointmentEditor.dart';
import '../Data/ics.dart';
import '../main.dart';
import '../utility.dart';

class ToDoList extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _ToDoList();
}

class _ToDoList extends State<ToDoList> with TickerProviderStateMixin {
  String dropdownValue = UserData.subjectCodeThisSemester.isNotEmpty
      ? UserData.subjectCodeThisSemester.first
      : '전체';
  List<Widget> toDoListNodate = [];
  List<Widget> toDoListPassed = [];
  List<Widget> toDoListLongTime = [];
  List<Widget> toDoListWeek = [];
  List<Widget> toDoListTomorrow = [];
  List<Widget> toDoListToday = [];
  List<Widget> toDoList12Hour = [];
  List<Widget> toDoList6Hour = [];
  List<Widget> toDoListFinished = [];

  TextEditingController searchController = TextEditingController();
  bool isSearching = false;
  String searchQuery = '';

  late StreamSubscription<dynamic> listener;

  // Animation controllers for category sections
  final List<AnimationController> _categoryControllers = [];
  final List<Animation<double>> _categorySizeAnimations = [];

  @override
  void initState() {
    super.initState();
    if (UserData.subjectCodeThisSemester.isEmpty) {
      UserData.subjectCodeThisSemester.add('전체');
    }

    listener = pnuStream.stream.listen((event) {
      if (mounted && event) {
        setState(() {});
      }
    });

    searchController.addListener(() {
      if (mounted) {
        setState(() {
          searchQuery = searchController.text;
        });
      }
    });

    // Initialize animations for 9 categories
    for (int i = 0; i < 9; i++) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 450),
        vsync: this,
      );
      _categoryControllers.add(controller);
      _categorySizeAnimations.add(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutQuart,
      ));

      // Start animation if category is already expanded
      if (UserData.showToDoList[i]) {
        controller.forward();
      }
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    listener.cancel();
    for (var controller in _categoryControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _toggleSearch() {
    if (!mounted) return;
    setState(() {
      isSearching = !isSearching;
      if (!isSearching) {
        searchController.clear();
      }
    });
    _triggerVibration();
  }

  Future<void> _triggerVibration() async {
    HapticFeedback.lightImpact();
  }

  bool _matchesSearchQuery(CalendarData task) {
    if (searchQuery.isEmpty) return true;
    final query = searchQuery.toLowerCase();
    return task.summary.toLowerCase().contains(query) ||
        task.description.toLowerCase().contains(query) ||
        task.className.toLowerCase().contains(query) ||
        task.classCode.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = Color.fromARGB(255, 59, 113, 202);
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? Color(0xFF121212) : Colors.white;
    final cardColor = isDarkMode ? Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor = isDarkMode ? Colors.white70 : Colors.black54;

    toDoListNodate.clear();
    toDoListPassed.clear();
    toDoListLongTime.clear();
    toDoListWeek.clear();
    toDoListTomorrow.clear();
    toDoListToday.clear();
    toDoList12Hour.clear();
    toDoList6Hour.clear();
    toDoListFinished.clear();

    DateTime now = DateTime.now();
    List<CalendarData> icsList = UserData.data.toList();
    icsList.sort((CalendarData a, CalendarData b) {
      if (a.end != b.end) {
        if (a.end == null && b.end == null) return 0;
        if (a.end == null) return -1;
        if (b.end == null) return 1;
        return a.end!.compareTo(b.end!);
      } else {
        return a.summary.compareTo(b.summary);
      }
    });

    icsList.forEach((element) {
      if (!_matchesSearchQuery(element)) return;

      if (dropdownValue == '전체' || element.classCode == dropdownValue) {
        if (!element.disable) {
          if (element.finished) {
            if (element.end == null || element.end!.difference(now).inDays > -5) {
              toDoListFinished.add(_getTodoWidget(element, isDarkMode, textColor, primaryColor, cardColor));
            }
          } else {
            if (element.end == null) {
              toDoListNodate.add(_getTodoWidget(element, isDarkMode, textColor, primaryColor, cardColor));
            } else {
              Duration diff = element.end!.difference(now);
              if (diff.inSeconds < 0) {
                toDoListPassed.add(_getTodoWidget(element, isDarkMode, textColor, primaryColor, cardColor));
              } else if (diff.inDays > 7) {
                toDoListLongTime.add(_getTodoWidget(element, isDarkMode, textColor, primaryColor, cardColor));
              } else if (element.end!.year == now.year &&
                         element.end!.month == now.month &&
                         element.end!.day == now.day) {
                if (diff.inHours < 6) {
                  toDoList6Hour.add(_getTodoWidget(element, isDarkMode, textColor, primaryColor, cardColor));
                } else if (diff.inHours < 12) {
                  toDoList12Hour.add(_getTodoWidget(element, isDarkMode, textColor, primaryColor, cardColor));
                } else {
                  toDoListToday.add(_getTodoWidget(element, isDarkMode, textColor, primaryColor, cardColor));
                }
              } else {
                DateTime tomorrow = now.add(const Duration(days: 1));
                if (element.end!.year == tomorrow.year &&
                    element.end!.month == tomorrow.month &&
                    element.end!.day == tomorrow.day) {
                  toDoListTomorrow.add(_getTodoWidget(element, isDarkMode, textColor, primaryColor, cardColor));
                } else {
                  toDoListWeek.add(_getTodoWidget(element, isDarkMode, textColor, primaryColor, cardColor));
                }
              }
            }
          }
        }
      }
    });

    bool hasAnyResults = toDoListNodate.isNotEmpty ||
        toDoListPassed.isNotEmpty ||
        toDoListLongTime.isNotEmpty ||
        toDoListWeek.isNotEmpty ||
        toDoListTomorrow.isNotEmpty ||
        toDoListToday.isNotEmpty ||
        toDoList12Hour.isNotEmpty ||
        toDoList6Hour.isNotEmpty ||
        toDoListFinished.isNotEmpty;

    bool showNoSearchResultsMessage = searchQuery.isNotEmpty && !hasAnyResults;
    bool showNoTodoListMessage = searchQuery.isEmpty && !hasAnyResults;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: backgroundColor,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: isDarkMode ? Color(0xFF121212) : Colors.white,
          title: isSearching
              ? _buildSearchField(primaryColor, isDarkMode)
              : (UserData.subjectCodeThisSemester.isNotEmpty
                  ? Row(
                      children: [
                        const SizedBox(width: 5),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: DropdownButton<String>(
                              value: dropdownValue,
                              icon: Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor),
                              isExpanded: true,
                              iconSize: 24,
                              elevation: 16,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                              underline: Container(height: 0),
                              onChanged: (String? newValue) {
                                _triggerVibration();
                                if (mounted && newValue != null) {
                                  setState(() {
                                    dropdownValue = newValue;
                                  });
                                }
                              },
                              items: UserData.subjectCodeThisSemester
                                  .map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(
                                    (subjectCode[value] ?? value),
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text('To-Do List', style: TextStyle(color: textColor, fontWeight: FontWeight.bold))),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Icon(
                  isSearching ? Icons.close : Icons.search,
                  color: primaryColor,
                  size: 22,
                ),
                onPressed: _toggleSearch,
              ),
            ),
          ],
        ),
        body: showNoSearchResultsMessage
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.search_off_rounded, size: 64, color: primaryColor.withOpacity(0.7)),
                    ),
                    const SizedBox(height: 24),
                    Text('검색 결과가 없습니다', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 8),
                    Text('다른 검색어를 입력해보세요', style: TextStyle(fontSize: 14, color: subtitleColor)),
                  ],
                ),
              )
            : showNoTodoListMessage
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.event_note_rounded, size: 64, color: primaryColor.withOpacity(0.7)),
                        ),
                        const SizedBox(height: 24),
                        Text('일정이 없습니다', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                        const SizedBox(height: 8),
                        Text('새로운 일정을 추가해보세요', style: TextStyle(fontSize: 14, color: subtitleColor)),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      if (searchQuery.isNotEmpty && hasAnyResults)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded, color: primaryColor, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '"$searchQuery" 검색 결과',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${toDoListNodate.length + toDoListPassed.length + toDoListLongTime.length + toDoListWeek.length + toDoListTomorrow.length + toDoListToday.length + toDoList12Hour.length + toDoList6Hour.length + toDoListFinished.length}개',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildCategorySection(toDoListPassed, "지난 할일", 0, primaryColor, cardColor, isDarkMode),
                      _buildCategorySection(toDoList6Hour, "6시간 이내", 1, primaryColor, cardColor, isDarkMode),
                      _buildCategorySection(toDoList12Hour, "12시간 남음", 2, primaryColor, cardColor, isDarkMode),
                      _buildCategorySection(toDoListToday, "오늘", 3, primaryColor, cardColor, isDarkMode),
                      _buildCategorySection(toDoListTomorrow, "내일", 4, primaryColor, cardColor, isDarkMode),
                      _buildCategorySection(toDoListWeek, "7일 이내", 5, primaryColor, cardColor, isDarkMode),
                      _buildCategorySection(toDoListLongTime, "7일 이상", 6, primaryColor, cardColor, isDarkMode),
                      _buildCategorySection(toDoListNodate, "기한 없음", 7, primaryColor, cardColor, isDarkMode),
                      _buildCategorySection(toDoListFinished, "완료", 8, primaryColor, cardColor, isDarkMode),
                      if (isSearching)
                        SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? MediaQuery.of(context).viewInsets.bottom : 0),
                    ],
                  ),
      ),
    );
  }

  Widget _buildCategorySection(List<Widget> items, String title, int index, Color primaryColor, Color cardColor, bool isDarkMode) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _getDurationWidget(title, index, primaryColor, isDarkMode),
            SizeTransition(
              sizeFactor: _categorySizeAnimations[index],
              axis: Axis.vertical,
              child: AnimatedOpacity(
                opacity: UserData.showToDoList[index] ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutQuart,
                child: AnimatedScale(
                  scale: UserData.showToDoList[index] ? 1.0 : 0.9,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutQuart,
                  child: UserData.showToDoList[index]
                      ? Column(
                          children: [
                            for (int i = 0; i < items.length; i++) ...[
                              items[i],
                              if (i < items.length - 1)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: isDarkMode ? Colors.grey[700]!.withOpacity(0.5) : Colors.grey[300]!.withOpacity(0.7),
                                  indent: 16,
                                  endIndent: 16,
                                ),
                            ],
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(Color primaryColor, bool isDarkMode) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2C) : const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: searchController,
        autofocus: true,
        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87, fontSize: 15),
        decoration: InputDecoration(
          hintText: '할 일 검색...',
          hintStyle: TextStyle(color: isDarkMode ? Colors.white54 : Colors.black38),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          prefixIcon: Icon(Icons.search_rounded, color: primaryColor, size: 20),
        ),
        onSubmitted: (_) {
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }

  Widget _getDurationWidget(String str, int index, Color primaryColor, bool isDarkMode) {
    Color headerBackgroundColor = isDarkMode ? const Color(0xFF333333) : const Color(0xFFFFFFFF);

    bool isExpanded = UserData.showToDoList[index];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: headerBackgroundColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(12),
          topRight: const Radius.circular(12),
          bottomLeft: isExpanded ? Radius.zero : const Radius.circular(12),
          bottomRight: isExpanded ? Radius.zero : const Radius.circular(12),
        ),
        border: isExpanded
            ? Border(
                bottom: BorderSide(
                  color: isDarkMode ? Colors.grey[700]!.withOpacity(0.5) : Colors.grey[300]!.withOpacity(0.7),
                  width: 1.0,
                ),
              )
            : null,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _triggerVibration();
          if (mounted) {
            setState(() {
              UserData.showToDoList[index] = !UserData.showToDoList[index];
              if (UserData.showToDoList[index]) {
                _categoryControllers[index].forward();
              } else {
                _categoryControllers[index].reverse();
              }
            });
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _getCategoryIcon(str, primaryColor),
                const SizedBox(width: 12),
                Text(
                  str,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            Icon(
              UserData.showToDoList[index] ? Icons.expand_less : Icons.expand_more,
              color: primaryColor,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _getCategoryIcon(String category, Color primaryColor) {
    IconData iconData;
    switch (category) {
      case "지난 할일":
        iconData = Icons.history_rounded;
        break;
      case "6시간 이내":
        iconData = Icons.timer_rounded;
        break;
      case "12시간 남음":
        iconData = Icons.hourglass_bottom_rounded;
        break;
      case "오늘":
        iconData = Icons.today_rounded;
        break;
      case "내일":
        iconData = Icons.event_rounded;
        break;
      case "7일 이내":
        iconData = Icons.date_range_rounded;
        break;
      case "7일 이상":
        iconData = Icons.calendar_month_rounded;
        break;
      case "기한 없음":
        iconData = Icons.calendar_today_rounded;
        break;
      case "완료":
        iconData = Icons.check_circle_rounded;
        break;
      default:
        iconData = Icons.list_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        color: primaryColor,
        size: 18,
      ),
    );
  }

  Widget _getTodoWidget(CalendarData data, bool isDarkMode, Color textColor, Color primaryColor, Color itemBackgroundColor) {
    Widget buildTitleText(String text) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold),
        );
    Widget buildDescriptionText(String text) => Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w400),
        );

    Widget buildHighlightedText(String text, String query, bool isTitle) {
      if (query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) {
        return isTitle ? buildTitleText(text) : buildDescriptionText(text);
      }
      List<TextSpan> spans = [];
      final String lowercaseText = text.toLowerCase();
      final String lowercaseQuery = query.toLowerCase();
      int start = 0;
      int indexOfMatch;
      while (true) {
        indexOfMatch = lowercaseText.indexOf(lowercaseQuery, start);
        if (indexOfMatch < 0) {
          if (start < text.length) {
            spans.add(TextSpan(
              text: text.substring(start),
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: isTitle ? FontWeight.bold : FontWeight.w400,
              ),
            ));
          }
          break;
        }
        if (indexOfMatch > start) {
          spans.add(TextSpan(
            text: text.substring(start, indexOfMatch),
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: isTitle ? FontWeight.bold : FontWeight.w400,
            ),
          ));
        }
        spans.add(TextSpan(
          text: text.substring(indexOfMatch, indexOfMatch + query.length),
          style: TextStyle(
            color: primaryColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            backgroundColor: primaryColor.withOpacity(0.15),
          ),
        ));
        start = indexOfMatch + query.length;
      }
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(children: spans),
      );
    }

    Widget getRemainingTime(DateTime? date) {
      if (date == null) return const SizedBox.shrink();
      DateTime now = DateTime.now();
      Duration diff = date.difference(now);
      String text;
      if (diff.isNegative) {
        text = "기한 지남";
      } else if (diff.inHours < 6) {
        text = "${diff.inHours}시간 ${diff.inMinutes % 60}분 남음";
      } else if (diff.inHours < 24) {
        text = "${diff.inHours}시간 남음";
      } else if (diff.inDays < 7) {
        text = "${diff.inDays}일 ${diff.inHours % 24}시간 남음";
      } else {
        text = "${diff.inDays}일 남음";
      }
      return Text(
        text,
        style: TextStyle(
          color: isDarkMode ? Colors.white : Colors.black87,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return InkWell(
      onTap: () {
        _triggerVibration();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (BuildContext context) => Container(
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: PopUpAppointmentEditor(data),
            ),
          ),
        ).then((_) {
          if (mounted) setState(() {});
        });
      },
      child: Container(
        color: itemBackgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 40,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: colorCollection[data.color],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  buildHighlightedText(data.summary, searchQuery, true),
                  if (data.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    buildHighlightedText(data.description, searchQuery, false),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          data.className.isNotEmpty ? data.className : data.classCode,
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (!data.finished && data.end != null) getRemainingTime(data.end),
                    ],
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.9,
              child: Container(
                margin: const EdgeInsets.only(left: 8, right: 4),
                child: Checkbox(
                  value: data.finished,
                  activeColor: primaryColor.withOpacity(0.2),
                  checkColor: primaryColor,
                  shape: const CircleBorder(),
                  side: BorderSide(
                    color: isDarkMode ? Colors.grey[600]! : Colors.grey[400]!,
                    width: 1.5,
                  ),
                  onChanged: (value) {
                    _triggerVibration();
                    if (mounted && value != null) {
                      setState(() {
                        data.finished = value;
                      });
                      UserData.writeDatabase.calendarDataSave(data);
                      if (value) showMessage(context, "완료된 일정으로 변경했습니다.");
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}