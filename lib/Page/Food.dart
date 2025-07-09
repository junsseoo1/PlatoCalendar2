import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:ui' show lerpDouble;

class Food extends StatefulWidget {
  const Food({Key? key}) : super(key: key);

  @override
  _FoodScreenState createState() => _FoodScreenState();
}

class _FoodScreenState extends State<Food> with TickerProviderStateMixin {
  Map<String, List<DayMeal>> restaurantMeals = {};
  bool isLoading = true;
  bool isRefreshing = false;
  String errorMessage = '';
  String weekRange = '';
  int currentDayIndex = 0;
  List<String> availableDates = [];
  final now = tz.TZDateTime.now(tz.getLocation('Asia/Seoul'));
  final dateFormat = DateFormat('yyyy.MM.dd');
  final dayFormat = DateFormat('EEEE', 'ko_KR');
  late AnimationController _refreshController;

  // 사용자 지정 식당 순서 관련 변수
  List<Map<String, String>> customRestaurantOrder = [];
  static const String restaurantOrderKey = 'restaurant_order';
  bool isDragging = false; // 드래그 중인지 상태

  // 각 식당 섹션의 확장/축소 상태 관리
  Map<String, bool> expandedSections = {};
  static const String expandedSectionsKey = 'expanded_sections';

  // 애니메이션 컨트롤러와 애니메이션 리스트
  final List<AnimationController> _sectionControllers = [];
  final List<Animation<double>> _sectionSizeAnimations = [];

  // Theme colors
  final Color primaryColor = const Color(0xFF3B71D0);
  final Color breakfastColor = const Color(0xFFFF7043);
  final Color lunchColor = const Color(0xFF42A5F5);
  final Color dinnerColor = const Color(0xFF66BB6A);

  // Dark mode colors
  final Color darkPrimaryColor = const Color(0xFF5B8DEF);
  final Color darkBreakfastColor = const Color(0xFFFF9066);
  final Color darkLunchColor = const Color(0xFF64B5F6);
  final Color darkDinnerColor = const Color(0xFF81C784);
  final Color darkBackgroundColor = const Color(0xFF121212);
  final Color darkCardColor = const Color(0xFF1E1E1E);
  final Color darkSurfaceColor = const Color(0xFF2C2C2C);

  // Cache keys
  static const String cacheKey = 'restaurant_meals_cache';
  static const String cacheTimestampKey = 'restaurant_meals_timestamp';

  final List<Map<String, String>> restaurants = [
    {'name': '금정회관 교직원식당', 'code': 'PG001', 'building': 'R001', 'icon': 'restaurant'},
    {'name': '금정회관 학생식당', 'code': 'PG002', 'building': 'R001', 'icon': 'local_dining'},
    {'name': '문창회관 식당', 'code': 'PM002', 'building': 'R002', 'icon': 'dinner_dining'},
    {'name': '샛벌회관 식당', 'code': 'PS001', 'building': 'R003', 'icon': 'lunch_dining'},
    {'name': '학생회관 학생식당', 'code': 'PH002', 'building': 'R004', 'icon': 'fastfood'},
  ];

  // ... (rest of the code remains unchanged)

  @override
  void initState() {
    super.initState();
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    // 애니메이션 컨트롤러 초기화
    for (var restaurant in restaurants) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 450),
        vsync: this,
      );
      _sectionControllers.add(controller);
      _sectionSizeAnimations.add(CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutQuart,
      ));
    }
    _loadCustomRestaurantOrder();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    for (var controller in _sectionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // 사용자 지정 식당 순서 및 확장 상태 로드
  Future<void> _loadCustomRestaurantOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final orderJson = prefs.getString(restaurantOrderKey);
    final expandedJson = prefs.getString(expandedSectionsKey);

    if (orderJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(orderJson);
        final List<Map<String, String>> order = decoded
            .map((item) => Map<String, String>.from(item))
            .toList();

        // 새로운 식당이 추가되었는지 확인
        final existingNames = order.map((r) => r['name']).toSet();
        final newRestaurants = restaurants
            .where((r) => !existingNames.contains(r['name']))
            .toList();

        // 새 식당을 순서 목록에 추가
        order.addAll(newRestaurants);

        if (!mounted) return;
        setState(() {
          customRestaurantOrder = order;
          // 확장 상태 및 애니메이션 초기화
          for (int i = 0; i < order.length; i++) {
            final restaurantName = order[i]['name']!;
            expandedSections[restaurantName] = expandedSections[restaurantName] ?? false;
            if (expandedSections[restaurantName]!) {
              _sectionControllers[i].forward();
            }
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          customRestaurantOrder = List.from(restaurants);
          for (var restaurant in customRestaurantOrder) {
            expandedSections[restaurant['name']!] = false;
          }
        });
      }
    } else {
      if (!mounted) return;
      setState(() {
        customRestaurantOrder = List.from(restaurants);
        for (var restaurant in customRestaurantOrder) {
          expandedSections[restaurant['name']!] = false;
        }
      });
    }

    // 확장 상태 로드
    if (expandedJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(expandedJson);
        if (!mounted) return;
        setState(() {
          expandedSections = decoded.map((key, value) => MapEntry(key, value as bool));
          // 애니메이션 상태 동기화
          for (int i = 0; i < customRestaurantOrder.length; i++) {
            final restaurantName = customRestaurantOrder[i]['name']!;
            if (expandedSections[restaurantName] ?? false) {
              _sectionControllers[i].forward();
            }
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          for (var restaurant in customRestaurantOrder) {
            expandedSections[restaurant['name']!] = false;
          }
        });
      }
    }

    _loadCachedData();
  }

  // 사용자 지정 식당 순서 및 확장 상태 저장
  Future<void> _saveCustomRestaurantOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final orderJson = jsonEncode(customRestaurantOrder);
    await prefs.setString(restaurantOrderKey, orderJson);
  }

  Future<void> _saveExpandedSections() async {
    final prefs = await SharedPreferences.getInstance();
    final expandedJson = jsonEncode(expandedSections);
    await prefs.setString(expandedSectionsKey, expandedJson);
  }

  // 캐시된 데이터 로드
  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString(cacheKey);
    final timestamp = prefs.getString(cacheTimestampKey);

    if (cachedData != null && timestamp != null) {
      final cacheDate = DateTime.parse(timestamp);
      final now = DateTime.now();

      if (now.difference(cacheDate).inDays < 3) {
        final decodedData = jsonDecode(cachedData) as Map<String, dynamic>;
        final cachedMeals = decodedData.map((key, value) => MapEntry(
              key,
              (value as List).map((e) => DayMeal.fromJson(e)).toList(),
            ));

        if (!mounted) return;
        setState(() {
          restaurantMeals = cachedMeals;
          availableDates = _extractDates(cachedMeals);
          currentDayIndex = _getCurrentDayIndex();
          isLoading = false;
        });
      }
    }

    if (restaurantMeals.isEmpty || cachedData == null || timestamp == null ||
        DateTime.now().difference(DateTime.parse(timestamp)).inDays >= 3) {
      await _fetchMealData();
    }
  }

  // 캐시에 데이터 저장
  Future<void> _saveToCache(Map<String, List<DayMeal>> meals) async {
    final prefs = await SharedPreferences.getInstance();
    final encodedData = jsonEncode(
      meals.map((key, value) => MapEntry(
            key,
            value.map((e) => e.toJson()).toList(),
          )),
    );
    await prefs.setString(cacheKey, encodedData);
    await prefs.setString(cacheTimestampKey, DateTime.now().toIso8601String());
  }

  // 날짜 추출
  List<String> _extractDates(Map<String, List<DayMeal>> meals) {
    Set<String> dateSet = {};
    meals.forEach((_, mealList) {
      for (var meal in mealList) {
        dateSet.add(meal.date);
      }
    });
    final dates = dateSet.toList()..sort();
    return dates;
  }

  // 현재 날짜 인덱스 계산
  int _getCurrentDayIndex() {
    final todayStr = dateFormat.format(now);
    final index = availableDates.indexOf(todayStr);
    return index == -1 && availableDates.isNotEmpty ? 0 : index;
  }

  Future<void> _fetchMealData({bool isRefresh = false}) async {
    if (isRefresh) {
      if (!mounted) return;
      setState(() {
        isRefreshing = true;
        errorMessage = '';
      });
      _refreshController.repeat();
    } else {
      if (!mounted) return;
      setState(() {
        isLoading = true;
        errorMessage = '';
      });
    }

    try {
      Map<String, List<DayMeal>> allMeals = {};
      for (var restaurant in restaurants) {
        try {
          final url =
              'https://www.pusan.ac.kr/kor/CMS/MenuMgr/menuListOnBuilding.do?mCode=MN202&campus_gb=PUSAN&building_gb=${restaurant['building']}&restaurant_code=${restaurant['code']}';
          final response = await http.get(Uri.parse(url));

          if (response.statusCode == 200) {
            if (response.body.isEmpty) {
              continue;
            }
            final meals = _parseHtml(response.body, restaurant['name']!);
            allMeals[restaurant['name']!] = meals;
          } else {
            continue;
          }
        } catch (e) {
          continue;
        }
      }

      await _saveToCache(allMeals);

      if (!mounted) return;
      setState(() {
        restaurantMeals = allMeals;
        availableDates = _extractDates(allMeals);
        currentDayIndex = _getCurrentDayIndex();
        isLoading = false;
        isRefreshing = false;
      });
      _refreshController.stop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = '학식 정보를 불러오지 못했습니다.';
        isLoading = false;
        isRefreshing = false;
      });
      _refreshController.stop();
    }
  }

  List<DayMeal> _parseHtml(String html, String restaurantName) {
    final document = parser.parse(html);
    var menuTable = document.querySelector('.menu-tbl.type-day') ??
        document.querySelector('.menu-tbl') ??
        document.querySelector('table');
    final weekInfo = document.querySelector('.menu-navi .loca')?.text.trim() ?? '';

    List<DayMeal> parsedMeals = [];

    if (menuTable == null) {
      final rawText = document.body?.text.trim() ?? '';
      if (rawText.isNotEmpty) {
        parsedMeals.add(DayMeal(
          restaurant: restaurantName,
          day: '알 수 없음',
          date: dateFormat.format(now),
          mealType: '알 수 없음',
          title: '데이터 없음',
          menu: rawText,
        ));
      }
      return parsedMeals;
    }

    final headers = menuTable.querySelectorAll('thead th');
    final days = headers.isNotEmpty
        ? headers.sublist(1).map((e) {
            return {
              'day': e.querySelector('.day')?.text.trim() ?? '알 수 없음',
              'date': e.querySelector('.date')?.text.trim() ?? dateFormat.format(now),
            };
          }).toList()
        : [
            {
              'day': '알 수 없음',
              'date': dateFormat.format(now),
            }
          ];

    final rows = menuTable.querySelectorAll('tbody tr');
    if (rows.isEmpty) {
      final cells = menuTable.querySelectorAll('td');
      if (cells.isNotEmpty) {
        parsedMeals.add(DayMeal(
          restaurant: restaurantName,
          day: days[0]['day'] as String,
          date: days[0]['date'] as String,
          mealType: '알 수 없음',
          title: '',
          menu: cells.map((cell) => cell.text.trim()).join('\n'),
        ));
      }
      return parsedMeals;
    }

    for (final row in rows) {
      final mealType = row.querySelector('th')?.text.trim() ?? '알 수 없음';
      final meals = row.querySelectorAll('td').asMap().entries.map((entry) {
        final index = entry.key;
        final cell = entry.value;
        final menuItems = cell.querySelectorAll('li').isNotEmpty
            ? cell.querySelectorAll('li').map((li) {
                final liText = li.text.trim().split('\n');
                String title = '';
                String menu = '';

                if (liText.isNotEmpty) {
                  title = liText[0].trim();
                  menu = liText.sublist(1).join('\n').trim();
                } else {
                  menu = li.text.trim();
                }

                return {
                  'title': title,
                  'menu': menu,
                };
              }).toList()
            : [
                {
                  'title': '',
                  'menu': cell.text.trim(),
                }
              ];

        return {
          'day': days[index]['day'] as String,
          'date': days[index]['date'] as String,
          'mealType': mealType,
          'menuItems': menuItems,
        };
      }).toList();

      for (final meal in meals) {
        final menuItems = meal['menuItems'] as List<Map<String, String>>;
        for (var item in menuItems) {
          parsedMeals.add(DayMeal(
            restaurant: restaurantName,
            day: meal['day'] as String,
            date: meal['date'] as String,
            mealType: meal['mealType'] as String,
            title: item['title'] ?? '',
            menu: item['menu'] ?? '',
          ));
        }
      }
    }

    setState(() {
      weekRange = weekInfo;
    });

    return parsedMeals;
  }

  void _changeDay(int direction) {
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      currentDayIndex = (currentDayIndex + direction).clamp(0, availableDates.length - 1);
    });
  }

  IconData _getRestaurantIcon(String restaurantName) {
    final restaurant = restaurants.firstWhere(
      (r) => r['name'] == restaurantName,
      orElse: () => {'icon': 'restaurant'},
    );

    switch (restaurant['icon']) {
      case 'local_dining':
        return Icons.local_dining;
      case 'dinner_dining':
        return Icons.dinner_dining;
      case 'lunch_dining':
        return Icons.lunch_dining;
      case 'fastfood':
        return Icons.fastfood;
      default:
        return Icons.restaurant;
    }
  }

  Color _getMealTypeColor(String mealType, bool isDarkMode) {
    switch (mealType) {
      case '조식':
        return isDarkMode ? darkBreakfastColor : breakfastColor;
      case '중식':
        return isDarkMode ? darkLunchColor : lunchColor;
      case '석식':
        return isDarkMode ? darkDinnerColor : dinnerColor;
      default:
        return isDarkMode ? darkPrimaryColor : primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final currentDate = availableDates.isNotEmpty ? availableDates[currentDayIndex] : '';
    final currentDay = currentDate.isNotEmpty
        ? dayFormat.format(dateFormat.parse(currentDate))
        : '오늘';
    final accentColor = isDarkMode ? darkPrimaryColor : primaryColor;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: isDarkMode ? darkBackgroundColor : Colors.white,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: isDarkMode ? darkBackgroundColor : Colors.white,
          leading: IconButton(
            onPressed: currentDayIndex > 0 ? () => _changeDay(-1) : null,
            icon: Icon(
              Icons.chevron_left_rounded,
              color: currentDayIndex > 0 ? accentColor : (isDarkMode ? Colors.grey[700] : Colors.grey.withOpacity(0.5)),
              size: 28,
            ),
          ),
          title: GestureDetector(
            onTap: () {
              // Reset to today
              if (availableDates.isNotEmpty) {
                final todayIndex = _getCurrentDayIndex();
                if (todayIndex >= 0 && todayIndex < availableDates.length) {
                  if (!mounted) return;
                  setState(() {
                    currentDayIndex = todayIndex;
                  });
                }
              }
            },
            child: Column(
              children: [
                Text(
                  '학식',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: accentColor.withOpacity(0.8),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '$currentDate ($currentDay)',
                      style: TextStyle(
                        color: accentColor.withOpacity(0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: () => _fetchMealData(isRefresh: true),
              icon: isRefreshing
                  ? RotationTransition(
                      turns: _refreshController,
                      child: Icon(
                        Icons.refresh_rounded,
                        color: accentColor,
                        size: 24,
                      ),
                    )
                  : Icon(
                      Icons.refresh_rounded,
                      color: accentColor,
                      size: 24,
                    ),
            ),
            IconButton(
              onPressed: currentDayIndex < availableDates.length - 1 ? () => _changeDay(1) : null,
              icon: Icon(
                Icons.chevron_right_rounded,
                color: currentDayIndex < availableDates.length - 1
                    ? accentColor
                    : (isDarkMode ? Colors.grey[700] : Colors.grey.withOpacity(0.5)),
                size: 28,
              ),
            ),
          ],
        ),
        body: Container(
          color: isDarkMode ? darkBackgroundColor : Colors.white,
          child: _buildBody(isDarkMode),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDarkMode) {
    final accentColor = isDarkMode ? darkPrimaryColor : primaryColor;

    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: accentColor,
              strokeWidth: 3,
            ),
            SizedBox(height: 16),
            Text(
              '학식 정보를 불러오는 중...',
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : Colors.black54,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final currentDate = availableDates.isNotEmpty ? availableDates[currentDayIndex] : '';

    return Column(
      children: [
        SizedBox(height: 5),
        if (errorMessage.isNotEmpty)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.red.withOpacity(0.2) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode ? Colors.red.withOpacity(0.4) : Colors.red.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: TextStyle(
                      color: isDarkMode ? Colors.red[300] : Colors.red,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: restaurantMeals.isEmpty
              ? _buildEmptyState(isDarkMode)
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: customRestaurantOrder.length,
                  buildDefaultDragHandles: false,
                  onReorderStart: (index) {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      isDragging = true;
                    });
                  },
                  onReorderEnd: (index) {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      isDragging = false;
                    });
                    
                    // 드래그가 끝난 후 애니메이션 상태를 복구
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      for (int i = 0; i < customRestaurantOrder.length; i++) {
                        final restaurantName = customRestaurantOrder[i]['name']!;
                        if (expandedSections[restaurantName] ?? false) {
                          _sectionControllers[i].forward();
                        } else {
                          _sectionControllers[i].reverse();
                        }
                      }
                    });
                  },
                  proxyDecorator: (child, index, animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (BuildContext context, Widget? child) {
                        final double animValue = Curves.easeInOut.transform(animation.value);
                        final double elevation = lerpDouble(0, 8, animValue)!;
                        final double scale = lerpDouble(1, 0.95, animValue)!;
                        final restaurant = customRestaurantOrder[index]['name']!;
                        final restaurantIcon = _getRestaurantIcon(restaurant);
                        final headerColor = isDarkMode
                            ? Color.lerp(darkPrimaryColor, Colors.black, 0.2)!
                            : primaryColor;
                        final isExpanded = expandedSections[restaurant] ?? false;

                        return Material(
                          elevation: elevation,
                          color: Colors.transparent,
                          shadowColor: isDarkMode
                              ? Colors.black.withOpacity(0.5)
                              : Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: headerColor,
                                borderRadius: const BorderRadius.all(Radius.circular(12)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      restaurantIcon,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      restaurant,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      softWrap: true,
                                    ),
                                  ),
                                  Icon(
                                    isExpanded ? Icons.expand_less : Icons.expand_more,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      child: child,
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final item = customRestaurantOrder.removeAt(oldIndex);
                      customRestaurantOrder.insert(newIndex, item);
                      // 애니메이션 컨트롤러도 재정렬
                      final controller = _sectionControllers.removeAt(oldIndex);
                      final animation = _sectionSizeAnimations.removeAt(oldIndex);
                      _sectionControllers.insert(newIndex, controller);
                      _sectionSizeAnimations.insert(newIndex, animation);
                      HapticFeedback.mediumImpact();
                      _saveCustomRestaurantOrder();
                    });
                    
                    // 재정렬 후 애니메이션 상태 동기화
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      for (int i = 0; i < customRestaurantOrder.length; i++) {
                        final restaurantName = customRestaurantOrder[i]['name']!;
                        if (expandedSections[restaurantName] ?? false) {
                          _sectionControllers[i].forward();
                        } else {
                          _sectionControllers[i].reverse();
                        }
                      }
                    });
                  },
                  itemBuilder: (context, index) {
                    final restaurant = customRestaurantOrder[index]['name']!;
                    final meals = restaurantMeals[restaurant]
                            ?.where((meal) => meal.date == currentDate)
                            .toList() ??
                        [];
                    if (meals.isNotEmpty) {
                      meals.sort((a, b) => _mealTypeOrder(a.mealType).compareTo(_mealTypeOrder(b.mealType)));
                    }
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(restaurant),
                      index: index,
                      enabled: !(expandedSections[restaurant] ?? false),
                      child: _buildRestaurantSection(context, restaurant, meals, isDarkMode, index),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    final accentColor = isDarkMode ? darkPrimaryColor : primaryColor;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor = isDarkMode ? Colors.white70 : Colors.black54;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.no_food_rounded, size: 64, color: accentColor.withOpacity(0.7)),
          ),
          const SizedBox(height: 24),
          Text('학식 정보가 없습니다', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 8),
          Text('새로고침을 눌러 다시 시도해보세요', style: TextStyle(fontSize: 14, color: subtitleColor)),
        ],
      ),
    );
  }

  int _mealTypeOrder(String mealType) {
    switch (mealType) {
      case '조식':
        return 1;
      case '중식':
        return 2;
      case '석식':
        return 3;
      default:
        return 4;
    }
  }

  Widget _buildRestaurantSection(BuildContext context, String restaurant, List<DayMeal> meals, bool isDarkMode, int index) {
    final mealTypes = ['조식', '중식', '석식'];
    final restaurantIcon = _getRestaurantIcon(restaurant);
    final accentColor = isDarkMode ? darkPrimaryColor : primaryColor;
    final cardColor = isDarkMode ? darkCardColor : Colors.white;
    final headerColor = isDarkMode ? Color.lerp(darkPrimaryColor, Colors.black, 0.2)! : primaryColor;
    final isExpanded = expandedSections[restaurant] ?? false;

    // 드래그 중일 때는 헤더만 표시하되, 펼쳐진 상태라면 내용도 표시
    if (isDragging) {
      if (isExpanded) {
        // 드래그 중이지만 펼쳐진 상태라면 전체 내용을 표시
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: headerColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.zero,
                      bottomRight: Radius.zero,
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: isDarkMode ? Colors.grey[700]!.withOpacity(0.5) : Colors.grey[300]!.withOpacity(0.7),
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              restaurantIcon,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            restaurant,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        Icons.expand_less,
                        color: Colors.white,
                        size: 24,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: meals.isEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Icon(
                                Icons.no_food,
                                size: 36,
                                color: isDarkMode ? Colors.white12 : Colors.black12,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '해당 날짜의 식단 정보가 없습니다',
                                style: TextStyle(
                                  color: isDarkMode ? Colors.white38 : Colors.black45,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Row(
                                children: mealTypes.map((type) {
                                  final mealItems = meals.where((meal) => meal.mealType.contains(type)).toList();
                                  if (mealItems.isEmpty) return const SizedBox.shrink();

                                  final typeColor = _getMealTypeColor(type, isDarkMode);

                                  return Expanded(
                                    child: Container(
                                      margin: EdgeInsets.only(right: type != '석식' ? 8 : 0),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: typeColor.withOpacity(isDarkMode ? 0.2 : 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: isDarkMode
                                            ? Border.all(color: typeColor.withOpacity(0.3), width: 1)
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            type == '조식'
                                                ? Icons.wb_sunny_outlined
                                                : type == '중식'
                                                    ? Icons.wb_sunny
                                                    : Icons.nightlight_round,
                                            size: 16,
                                            color: typeColor,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            type,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: typeColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: mealTypes.map((type) {
                                final mealItems = meals.where((meal) => meal.mealType.contains(type)).toList();
                                if (mealItems.isEmpty) return const SizedBox.shrink();

                                return Expanded(
                                  child: Container(
                                    margin: EdgeInsets.only(right: type != '석식' ? 8 : 0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: mealItems.map((meal) => _buildMealItem(context, meal, isDarkMode)).toList(),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      } else {
        // 드래그 중이고 접힌 상태라면 헤더만 표시
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              boxShadow: [
                BoxShadow(
                  color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    restaurantIcon,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    restaurant,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        );
      }
    }

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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                if (!mounted) return;
                setState(() {
                  expandedSections[restaurant] = !isExpanded;
                  if (expandedSections[restaurant]!) {
                    _sectionControllers[index].forward();
                  } else {
                    _sectionControllers[index].reverse();
                  }
                  _saveExpandedSections();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: headerColor,
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            restaurantIcon,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          restaurant,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
            SizeTransition(
              sizeFactor: _sectionSizeAnimations[index],
              axis: Axis.vertical,
              child: AnimatedOpacity(
                opacity: isExpanded ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutQuart,
                child: AnimatedScale(
                  scale: isExpanded ? 1.0 : 0.9,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutQuart,
                  child: isExpanded
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: meals.isEmpty
                              ? Container(
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  alignment: Alignment.center,
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.no_food,
                                        size: 36,
                                        color: isDarkMode ? Colors.white12 : Colors.black12,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '해당 날짜의 식단 정보가 없습니다',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.white38 : Colors.black45,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Column(
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      child: Row(
                                        children: mealTypes.map((type) {
                                          final mealItems = meals.where((meal) => meal.mealType.contains(type)).toList();
                                          if (mealItems.isEmpty) return const SizedBox.shrink();

                                          final typeColor = _getMealTypeColor(type, isDarkMode);

                                          return Expanded(
                                            child: Container(
                                              margin: EdgeInsets.only(right: type != '석식' ? 8 : 0),
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              decoration: BoxDecoration(
                                                color: typeColor.withOpacity(isDarkMode ? 0.2 : 0.15),
                                                borderRadius: BorderRadius.circular(8),
                                                border: isDarkMode
                                                    ? Border.all(color: typeColor.withOpacity(0.3), width: 1)
                                                    : null,
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    type == '조식'
                                                        ? Icons.wb_sunny_outlined
                                                        : type == '중식'
                                                            ? Icons.wb_sunny
                                                            : Icons.nightlight_round,
                                                    size: 16,
                                                    color: typeColor,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    type,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: typeColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: mealTypes.map((type) {
                                        final mealItems = meals.where((meal) => meal.mealType.contains(type)).toList();
                                        if (mealItems.isEmpty) return const SizedBox.shrink();

                                        return Expanded(
                                          child: Container(
                                            margin: EdgeInsets.only(right: type != '석식' ? 8 : 0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: mealItems.map((meal) => _buildMealItem(context, meal, isDarkMode)).toList(),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
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

  Widget _buildMealItem(BuildContext context, DayMeal meal, bool isDarkMode) {
    final menuLines = meal.menu.split('\n');
    final accentColor = isDarkMode ? darkPrimaryColor : primaryColor;
    final surfaceColor = isDarkMode ? darkSurfaceColor : Colors.grey[50]!;
    final borderColor = isDarkMode ? const Color(0xFF3A3A3A) : Colors.grey[200]!;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkMode ? Colors.white70 : Colors.black54;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: isDarkMode
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meal.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                meal.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ),
          if (meal.menu.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: menuLines.map((line) {
                if (line.trim().isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryTextColor,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          line.trim(),
                          style: TextStyle(
                            fontSize: 13,
                            color: textColor,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          if (meal.title.isEmpty && meal.menu.isEmpty)
            Text(
              '식단 정보 없음',
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode ? Colors.white38 : Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

class DayMeal {
  final String restaurant;
  final String day;
  final String date;
  final String mealType;
  final String title;
  final String menu;

  DayMeal({
    required this.restaurant,
    required this.day,
    required this.date,
    required this.mealType,
    required this.title,
    required this.menu,
  });

  Map<String, dynamic> toJson() => {
        'restaurant': restaurant,
        'day': day,
        'date': date,
        'mealType': mealType,
        'title': title,
        'menu': menu,
      };

  static DayMeal fromJson(Map<String, dynamic> json) => DayMeal(
        restaurant: json['restaurant'],
        day: json['day'],
        date: json['date'],
        mealType: json['mealType'],
        title: json['title'],
        menu: json['menu'],
      );
}
