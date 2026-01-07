import WidgetKit
import SwiftUI

// MARK: - Entry
struct TimetableEntry: TimelineEntry {
    let date: Date
    let schoolName: String
    let grade: String
    let classNum: String
    let items: [TTItem]
}

struct TTItem: Identifiable {
    let id = UUID()
    let perio: String
    let subject: String
}

// MARK: - Provider
struct TimetableProvider: TimelineProvider {
    private let apiKey = "b22e0d13ad8e49179c4d37cff6aed382"

    func placeholder(in context: Context) -> TimetableEntry {
        TimetableEntry(
            date: Date(),
            schoolName: "학교명",
            grade: "2",
            classNum: "7",
            items: [
                TTItem(perio: "1", subject: "생명과학Ⅰ"),
                TTItem(perio: "2", subject: "기하"),
                TTItem(perio: "3", subject: "영어Ⅱ")
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TimetableEntry) -> Void) {
        fetchTimetable { completion($0) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableEntry>) -> Void) {
        fetchTimetable { entry in
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchTimetable(completion: @escaping (TimetableEntry) -> Void) {
        // ✅ 동적으로 App Group 감지
        guard let defaults = AppGroupManager.shared.sharedDefaults else {
            completion(TimetableEntry(date: Date(), schoolName: "설정 오류", grade: "1", classNum: "1", items: []))
            return
        }

        let officeCode = defaults.string(forKey: "savedOfficeCode") ?? ""
        let schoolCode = defaults.string(forKey: "savedSchoolCode") ?? ""
        let schoolName = defaults.string(forKey: "savedSchoolName") ?? "학교를 선택하세요"
        let grade = defaults.string(forKey: "savedGrade") ?? "1"
        let classNum = defaults.string(forKey: "savedClass") ?? "1"

        #if DEBUG
        print("🔵 TimetableWidget fetchTimetable called")
        print("   App Group: \(AppGroupManager.shared.appGroupID ?? "nil")")
        print("   schoolCode: \(schoolCode)")
        print("   schoolName: \(schoolName)")
        print("   grade: \(grade), class: \(classNum)")
        #endif

        guard !schoolCode.isEmpty else {
            completion(TimetableEntry(date: Date(), schoolName: "앱에서 학교를 먼저 설정하세요", grade: grade, classNum: classNum, items: []))
            return
        }

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let ymd = df.string(from: Date())

        let dateEdits = decodeDict(defaults.string(forKey: "timetableDateEditsJSON"))
        let weeklyEdits = decodeDict(defaults.string(forKey: "timetableWeeklyEditsJSON"))
        let replaceRules = decodeDict(defaults.string(forKey: "timetableReplaceRulesJSON"))

        let urlString =
        "https://open.neis.go.kr/hub/hisTimetable?KEY=\(apiKey)&Type=json&pIndex=1&pSize=100&ATPT_OFCDC_SC_CODE=\(officeCode)&SD_SCHUL_CODE=\(schoolCode)&ALL_TI_YMD=\(ymd)&GRADE=\(grade)&CLASS_NM=\(classNum)"

        guard let url = URL(string: urlString) else {
            completion(TimetableEntry(date: Date(), schoolName: schoolName, grade: grade, classNum: classNum, items: []))
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            var items: [TTItem] = []

            if let data,
               let decoded = try? JSONDecoder().decode(NeisTimetableResponseWidget.self, from: data),
               let rows = decoded.hisTimetable?.compactMap({ $0.row }).first(where: { !($0?.isEmpty ?? true) }) ?? nil {

                let sorted = rows.sorted { (Int($0.PERIO ?? "0") ?? 0) < (Int($1.PERIO ?? "0") ?? 0) }

                items = sorted.map { r in
                    let perio = r.PERIO ?? ""
                    let original = (r.ITRT_CNTNT ?? "-").trimmingCharacters(in: .whitespacesAndNewlines)

                    let dateKey = "\(schoolCode)|\(ymd)|\(grade)|\(classNum)|\(perio)"
                    let weekday = Calendar.current.component(.weekday, from: Date())
                    let weeklyKey = "\(schoolCode)|G\(grade)|C\(classNum)|W\(weekday)|P\(perio)"

                    let subject: String
                    if let v = dateEdits[dateKey], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        subject = v
                    } else if let v = weeklyEdits[weeklyKey], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        subject = v
                    } else if let v = replaceRules[original], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        subject = v
                    } else {
                        subject = original.isEmpty ? "-" : original
                    }

                    return TTItem(perio: perio, subject: subject)
                }
            }

            completion(TimetableEntry(date: Date(), schoolName: schoolName, grade: grade, classNum: classNum, items: items))
        }.resume()
    }

    private func decodeDict(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

// MARK: - Widget View
struct TimetableWidgetView: View {
    let entry: TimetableEntry
    @Environment(\.widgetFamily) private var family

    @AppStorage("isDarkMode", store: AppGroupManager.shared.sharedDefaults)
    private var isDarkMode: Bool = false

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                TimetableSmallView(entry: entry)
            default:
                TimetableLargeView(entry: entry)
            }
        }
        .widgetURL(URL(string: "schoollife://timetable"))
        .containerBackground(for: .widget) {
            if isDarkMode {
                Color(red: 0.1, green: 0.1, blue: 0.12)
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.18), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .environment(\.colorScheme, isDarkMode ? .dark : .light)
    }
}

// MARK: - Small
struct TimetableSmallView: View {
    let entry: TimetableEntry

    var body: some View {
        GeometryReader { geo in
            let headerH: CGFloat = 14
            let verticalPad: CGFloat = 6
            let horizontalPad: CGFloat = 8

            let maxRows = 9
            let rows = Array(entry.items.prefix(maxRows))
            let count = CGFloat(max(rows.count, 1))

            let usable = geo.size.height - headerH - (verticalPad * 2)
            let rowH = usable / count
            
            // 더 많은 공간 활용 → 폰트 크기 증가
            let font = min(max(rowH * 0.88, 13), 22)

            VStack(spacing: 0) {
                // 헤더 (제목만)
                HStack {
                    Text("오늘 시간표")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(.blue)
                    Spacer()
                }
                .frame(height: headerH)

                if rows.isEmpty {
                    Spacer()
                    Text("No Timetable")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows) { it in
                            HStack(spacing: 4) {
                                // 교시 번호만 (파란색 숫자) - 왼쪽 정렬 유지
                                Text(it.perio)
                                    .font(.system(size: min(font, 20), weight: .heavy))
                                    .foregroundColor(.blue)
                                    .frame(width: 18, alignment: .leading)

                                // 과목명 - 왼쪽으로 붙음
                                Text(it.subject)
                                    .font(.system(size: font, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: rowH, alignment: .leading)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, horizontalPad)
            .padding(.vertical, verticalPad)
        }
    }
}

// MARK: - Large
struct TimetableLargeView: View {
    let entry: TimetableEntry

    var body: some View {
        GeometryReader { geo in
            let headerH: CGFloat = 22
            let verticalPad: CGFloat = 12

            let maxRows = 9
            let rows = Array(entry.items.prefix(maxRows))
            let count = CGFloat(max(rows.count, 1))

            let usable = geo.size.height - headerH - (verticalPad * 2)
            let rowH = usable / count
            let font = min(max(rowH * 0.78, 14), 24)

            VStack(spacing: 0) {

                // 헤더(Small 스타일 유지 + 살짝 업)
                HStack {
                    Text("오늘 시간표")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.blue)
                    Spacer()
                    Text("\(entry.schoolName)  \(entry.grade)학년 \(entry.classNum)반")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(height: headerH)

                if rows.isEmpty {
                    Spacer()
                    Text("No Timetable")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows) { it in
                            HStack(spacing: 10) {
                                HStack(spacing: 2) {
                                    Text(it.perio)
                                        .font(.system(size: min(font, 22), weight: .heavy))
                                        .foregroundColor(.blue)

                                    Text("교시")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.blue.opacity(0.9))
                                }
                                .frame(width: 64, alignment: .leading)

                                Text(it.subject)
                                    .font(.system(size: font, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Spacer(minLength: 0)
                            }
                            .frame(height: rowH)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPad)
        }
    }
}

// MARK: - Widget Entry Point
struct TimetableWidget: Widget {
    let kind: String = "TimetableWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimetableProvider()) { entry in
            TimetableWidgetView(entry: entry)
        }
        .configurationDisplayName("오늘의 시간표")
        .description("오늘의 시간표를 확인하세요")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

// MARK: - Timetable API Models (Widget용 최소)
struct NeisTimetableResponseWidget: Codable {
    let hisTimetable: [TimetableInfoWidget]?
}

struct TimetableInfoWidget: Codable {
    let row: [TimetableRowWidget]?
}

struct TimetableRowWidget: Codable {
    let PERIO: String?
    let ITRT_CNTNT: String?
}
