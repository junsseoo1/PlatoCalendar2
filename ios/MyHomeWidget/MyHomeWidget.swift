import WidgetKit
import SwiftUI
import os.log

// MARK: - 데이터 모델
struct CalendarEntry: TimelineEntry {
    let date: Date
    let counts: [String: Int]  // ["2023-05-20": 3]
    var month: MonthData
}

struct MonthData {
    let year: Int
    let month: Int
    let weeks: [[Int?]]
    let dayCount: Int
}

// MARK: - 프로바이더
struct Provider: TimelineProvider {
    private let calendar = Calendar.current
    private let logger = OSLog(subsystem: "group.com.junseo.platoCalendar", category: "Widget")
    
    func placeholder(in context: Context) -> CalendarEntry {
        generateEntry(for: Date(), counts: [:], context: context)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        let counts = loadCounts()
        completion(generateEntry(for: Date(), counts: counts, context: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let counts = loadCounts()
        let currentDate = Date()
        let entry = generateEntry(for: currentDate, counts: counts, context: context)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadCounts() -> [String: Int] {
    guard let groupURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.junseo.platoCalendar"
    ) else {
        os_log("🔴 App Group 접근 실패", log: logger)
        return UserDefaults.standard.dictionary(forKey: "cachedCounts") as? [String: Int] ?? [:]
    }
    
    let fileURL = groupURL.appendingPathComponent("appointmentCounts.json")
    
    do {
        let data = try Data(contentsOf: fileURL)
        let counts = try JSONDecoder().decode([String: Int].self, from: data)
        os_log("✅ 로드된 데이터: %d개", log: logger, counts.count)
        UserDefaults.standard.set(counts, forKey: "cachedCounts")
        return counts
    } catch {
        os_log("🔴 파일 로드 실패: %@", log: logger, error.localizedDescription)
        return UserDefaults.standard.dictionary(forKey: "cachedCounts") as? [String: Int] ?? [:]
    }
}
    
    private func generateEntry(for date: Date, counts: [String: Int], context: Context) -> CalendarEntry {
        let components = calendar.dateComponents([.year, .month], from: date)
        let monthData = generateMonthData(
            year: components.year!,
            month: components.month!,
            widgetFamily: context.family
        )
        return CalendarEntry(date: date, counts: counts, month: monthData)
    }
    
    func generateMonthData(year: Int, month: Int, widgetFamily: WidgetFamily) -> MonthData {
        var weeks = [[Int?]]()
        var currentWeek = [Int?]()
        
        // 사용자 지정 캘린더 생성: 월요일을 첫 번째 요일로 설정
        var customCalendar = Calendar.current
        customCalendar.firstWeekday = 2 // 1: 일요일, 2: 월요일
        
        guard let firstDay = customCalendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = customCalendar.range(of: .day, in: .month, for: firstDay) else {
            return MonthData(year: year, month: month, weeks: [], dayCount: 0)
        }
        
        // 첫 번째 날의 요일 인덱스 (월요일=1, 일요일=7)
        let weekday = customCalendar.component(.weekday, from: firstDay)
        // 월요일 기준으로 빈 칸 추가 (weekday가 2(월요일)일 때 0, 3(화요일)일 때 1, ..., 1(일요일)일 때 6)
        let offset = (weekday - customCalendar.firstWeekday + 7) % 7
        for _ in 0..<offset {
            currentWeek.append(nil)
        }
        
        // 날짜 채우기
        for day in range.lowerBound..<range.upperBound {
            currentWeek.append(day)
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }
        
        // 마지막 주가 비어 있으면 채우기
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            weeks.append(currentWeek)
        }
        
        // 모든 위젯에서 6주 표시
        let displayedWeeks: [[Int?]]
        if weeks.count < 5 {
            var additionalDays = [Int?]()
            if let nextMonthStart = customCalendar.date(byAdding: .month, value: 1, to: firstDay),
               let nextRange = customCalendar.range(of: .day, in: .month, for: nextMonthStart) {
                let neededDays = (6 - weeks.count) * 7
                additionalDays = (1...neededDays).map { $0 }
                var additionalWeeks = [[Int?]]()
                var tempWeek = [Int?]()
                for day in additionalDays {
                    tempWeek.append(day)
                    if tempWeek.count == 7 {
                        additionalWeeks.append(tempWeek)
                        tempWeek = []
                    }
                }
                if !tempWeek.isEmpty {
                    while tempWeek.count < 7 {
                        tempWeek.append(nil)
                    }
                    additionalWeeks.append(tempWeek)
                }
                displayedWeeks = weeks + additionalWeeks
            } else {
                displayedWeeks = weeks
            }
        } else {
            displayedWeeks = Array(weeks.prefix(6))
        }
        
        return MonthData(year: year, month: month, weeks: displayedWeeks, dayCount: displayedWeeks.flatMap { $0 }.compactMap { $0 }.count)
    }
}

// MARK: - 위젯 뷰
struct CalendarWidgetView: View {
    var entry: CalendarEntry
    @Environment(\.widgetFamily) var family
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)  // 7 days a week
    private let weekdaySymbols = ["월", "화", "수", "목", "금", "토", "일"] // 월요일부터 시작
    
    private var titleFont: Font {
        switch family {
        case .systemSmall: return .system(size: 12, weight: .bold)
        case .systemMedium: return .system(size: 14, weight: .bold)
        default: return .system(size: 16, weight: .bold)
        }
    }
    
    private var dayFont: Font {
        switch family {
        case .systemSmall: return .system(size: 8)
        case .systemMedium: return .system(size: 10)
        default: return .system(size: 12)
        }
    }
    
    private func backgroundColor(for count: Int) -> Color {
        let maxCount = 3  // 3개 이상 최대 색상
        let normalizedCount = min(count, maxCount)
        let opacity: Double = {
            switch normalizedCount {
            case 0: return 0.0
            case 1: return 0.33
            case 2: return 0.66
            default: return 1.0
            }
        }()
        return Color.blue.opacity(opacity)
    }
    
    private func isToday(year: Int, month: Int, day: Int) -> Bool {
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return today.year == year && today.month == month && today.day == day
    }
    
    var body: some View {
        GeometryReader { geometry in
            let minDimension = min(geometry.size.width, geometry.size.height) // Use the smallest dimension
            let cellSize = minDimension / 7 // Divide by 7 to fit 7 columns
            
            VStack(spacing: 0) {
                // 헤더
                HStack {
                    Text("\(entry.month.month)월")
                        .font(titleFont)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("갱신: \(entry.date.formatted(.dateTime.day().hour().minute()))")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .padding(.top, 2)
                }
                .padding(.bottom, 4)
                
                // 요일 표시
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { day in
                        Text(day)
                            .font(dayFont)
                            .foregroundColor(day == "일" ? .red :  .gray)
                            .frame(width: cellSize, height: cellSize, alignment: .center)
                    }
                }
                .padding(.bottom, 4)
                
                // 달력 그리드
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(entry.month.weeks, id: \.self) { week in
                        ForEach(week.indices, id: \.self) { index in
                            if let day = week[index] {
                                let dateKey = String(format: "%04d-%02d-%02d", entry.month.year, entry.month.month, day)
                                let count = entry.counts[dateKey] ?? 0
                                let isToday = isToday(year: entry.month.year, month: entry.month.month, day: day)
                                
                                ZStack {
                                    Rectangle()
                                        .fill(backgroundColor(for: count))
                                        .cornerRadius(4) // 날짜 셀 모서리 둥글게
                                        .overlay(
                                            isToday ?
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.gray, lineWidth: 1.3) // 오늘 날짜에 테두리 추가
                                            : nil
                                        )
                                    
                                    Text("\(day)")
                                        .font(dayFont)
                                        .foregroundColor(index == 6 ? .red :  .primary)// 일요일: 빨강, 토요일: 파랑
                                        .frame(width: cellSize, height: cellSize, alignment: .center)
                                }
                                .frame(width: cellSize, height: cellSize)
                            } else {
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .containerBackground(for: .widget) {
            Color.clear  // 라이트/다크 테마에 맞게 자동 변경
        }
    }
}

// MARK: - 위젯 설정
struct MyHomeWidget: Widget {
    let kind: String = "MyHomeWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: Provider()
        ) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("달력 위젯")
        .description("일정 개수에 따라 색상이 변하는 달력")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - 프리뷰
struct CalendarWidget_Previews: PreviewProvider {
    static var sampleEntry: CalendarEntry {
        let counts = [
            "2023-05-15": 1,
            "2023-05-20": 3,
            "2023-05-21": 2,
            "2023-05-28": 1,
            "2023-06-01": 5,
            "2023-06-10": 2
        ]
        let provider = Provider()
        let date = Date()
        return CalendarEntry(
            date: date,
            counts: counts,
            month: provider.generateMonthData(
                year: 2023,
                month: 5,
                widgetFamily: .systemLarge
            )
        )
    }
    
    static var previews: some View {
        Group {
            // 2x2 (systemSmall)
            CalendarWidgetView(entry: sampleEntry)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("2x2")
            
            // 2x4 (systemMedium)
            CalendarWidgetView(entry: sampleEntry)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("2x4")
            
            // 4x4 (systemLarge)
            CalendarWidgetView(entry: sampleEntry)
                .previewContext(WidgetPreviewContext(family: .systemLarge))
                .previewDisplayName("4x4")
        }
    }
}