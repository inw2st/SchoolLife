import WidgetKit
import SwiftUI

private enum WidgetTimetableSource: String {
    case neis
    case comci
}

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
    private let comciRelayBaseURL = "https://comci-direct-server.vercel.app"

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
        let timetableSource = defaults.string(forKey: "timetableSource") ?? WidgetTimetableSource.neis.rawValue
        let savedComciSchoolCode = defaults.string(forKey: "savedComciSchoolCode") ?? ""
        let savedComciMappedSchoolName = defaults.string(forKey: "savedComciMappedSchoolName") ?? ""
        let savedComciRegionName = defaults.string(forKey: "savedComciRegionName") ?? ""

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

        if timetableSource == WidgetTimetableSource.comci.rawValue {
            fetchComciTimetable(
                schoolName: schoolName,
                officeCode: officeCode,
                grade: grade,
                classNum: classNum,
                ymd: ymd,
                savedComciSchoolCode: savedComciSchoolCode,
                savedComciMappedSchoolName: savedComciMappedSchoolName,
                savedComciRegionName: savedComciRegionName,
                dateEdits: dateEdits,
                weeklyEdits: weeklyEdits,
                replaceRules: replaceRules,
                completion: completion
            )
            return
        }

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
                    let replaceScope = "\(WidgetTimetableSource.neis.rawValue)|\(schoolCode)|G\(grade)|C\(classNum)"
                    let replaceKey = "\(replaceScope)|SUBJECT|\(original)"

                    let subject: String
                    if let v = dateEdits[dateKey], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        subject = v
                    } else if let v = weeklyEdits[weeklyKey], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        subject = v
                    } else if let v = replaceRules[replaceKey], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    private func fetchComciTimetable(
        schoolName: String,
        officeCode: String,
        grade: String,
        classNum: String,
        ymd: String,
        savedComciSchoolCode: String,
        savedComciMappedSchoolName: String,
        savedComciRegionName: String,
        dateEdits: [String: String],
        weeklyEdits: [String: String],
        replaceRules: [String: String],
        completion: @escaping (TimetableEntry) -> Void
    ) {
        let targetDate = "\(String(ymd.prefix(4)))-\(String(ymd.dropFirst(4).prefix(2)))-\(String(ymd.suffix(2)))"

        resolveComciSchool(
            schoolName: schoolName,
            officeCode: officeCode,
            savedComciSchoolCode: savedComciSchoolCode,
            savedComciMappedSchoolName: savedComciMappedSchoolName,
            savedComciRegionName: savedComciRegionName
        ) { result in
            switch result {
            case .failure:
                completion(TimetableEntry(date: Date(), schoolName: schoolName, grade: grade, classNum: classNum, items: []))
            case .success(let school):
                guard var components = URLComponents(string: "\(comciRelayBaseURL)/timetable/verify") else {
                    completion(TimetableEntry(date: Date(), schoolName: schoolName, grade: grade, classNum: classNum, items: []))
                    return
                }
                components.queryItems = [
                    URLQueryItem(name: "school_name", value: school.schoolName),
                    URLQueryItem(name: "region_name", value: school.regionName),
                    URLQueryItem(name: "school_code", value: school.schoolCode),
                    URLQueryItem(name: "grade", value: grade),
                    URLQueryItem(name: "class_num", value: classNum),
                    URLQueryItem(name: "target_date", value: targetDate)
                ]

                guard let url = components.url else {
                    completion(TimetableEntry(date: Date(), schoolName: schoolName, grade: grade, classNum: classNum, items: []))
                    return
                }

                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data,
                          let decoded = try? JSONDecoder().decode(ComciVerifyResponseWidget.self, from: data) else {
                        completion(TimetableEntry(date: Date(), schoolName: schoolName, grade: grade, classNum: classNum, items: []))
                        return
                    }

                    let items = decoded.daily_subjects.compactMap { period -> TTItem? in
                        let original = normalizeComciSubject(period.subject)
                        guard !original.isEmpty else { return nil }

                        let sourceID = "comci|\(school.schoolCode)"
                        let dateKey = "\(sourceID)|\(ymd)|\(grade)|\(classNum)|\(period.period)"
                        let weekday = Calendar.current.component(.weekday, from: Date())
                        let weeklyKey = "\(sourceID)|G\(grade)|C\(classNum)|W\(weekday)|P\(period.period)"
                        let replaceScope = "\(WidgetTimetableSource.comci.rawValue)|\(school.schoolCode)|G\(grade)|C\(classNum)"
                        let replaceKey = "\(replaceScope)|SUBJECT|\(original)"

                        let subject: String
                        if let value = dateEdits[dateKey], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            subject = value
                        } else if let value = weeklyEdits[weeklyKey], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            subject = value
                        } else if let value = replaceRules[replaceKey], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            subject = value
                        } else {
                            subject = original
                        }

                        return TTItem(perio: String(period.period), subject: subject)
                    }

                    completion(TimetableEntry(
                        date: Date(),
                        schoolName: schoolName,
                        grade: grade,
                        classNum: classNum,
                        items: items
                    ))
                }.resume()
            }
        }
    }

    private func resolveComciSchool(
        schoolName: String,
        officeCode: String,
        savedComciSchoolCode: String,
        savedComciMappedSchoolName: String,
        savedComciRegionName: String,
        completion: @escaping (Result<ComciSchoolWidget, Error>) -> Void
    ) {
        let resolvedSchoolName = savedComciMappedSchoolName.isEmpty ? schoolName : savedComciMappedSchoolName

        if !savedComciSchoolCode.isEmpty {
            completion(.success(ComciSchoolWidget(
                school_code: savedComciSchoolCode,
                region_name: savedComciRegionName.isEmpty ? fallbackComciRegionName(officeCode) : savedComciRegionName,
                school_name: resolvedSchoolName
            )))
            return
        }

        guard var components = URLComponents(string: "\(comciRelayBaseURL)/schools/search") else {
            completion(.failure(NSError(domain: "", code: -1)))
            return
        }
        components.queryItems = [URLQueryItem(name: "q", value: resolvedSchoolName)]

        guard let url = components.url else {
            completion(.failure(NSError(domain: "", code: -1)))
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data,
                  let decoded = try? JSONDecoder().decode(ComciSchoolSearchResponseWidget.self, from: data) else {
                completion(.failure(NSError(domain: "", code: -1)))
                return
            }

            let region = fallbackComciRegionName(officeCode)
            if let match = decoded.schools.first(where: { $0.school_name == resolvedSchoolName && ($0.region_name == region || region.isEmpty) })
                ?? decoded.schools.first(where: { $0.school_name == resolvedSchoolName })
                ?? decoded.schools.first(where: { $0.school_name == schoolName && ($0.region_name == region || region.isEmpty) })
                ?? decoded.schools.first(where: { $0.school_name == schoolName }) {
                completion(.success(match))
            } else {
                completion(.failure(NSError(domain: "", code: -1)))
            }
        }.resume()
    }

    private func normalizeComciSubject(_ subject: String) -> String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: ".")
    }

    private func fallbackComciRegionName(_ officeCode: String) -> String {
        switch officeCode {
        case "B10": return "서울"
        case "C10": return "부산"
        case "D10": return "대구"
        case "E10": return "인천"
        case "F10": return "광주"
        case "G10": return "대전"
        case "H10": return "울산"
        case "I10": return "세종"
        case "J10": return "경기"
        case "K10": return "강원"
        case "M10": return "충북"
        case "N10": return "충남"
        case "P10": return "전북"
        case "Q10": return "전남"
        case "R10": return "경북"
        case "S10": return "경남"
        case "T10": return "제주"
        default: return ""
        }
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

struct ComciSchoolSearchResponseWidget: Decodable {
    let schools: [ComciSchoolWidget]
}

struct ComciSchoolWidget: Decodable {
    let school_code: String
    let region_name: String
    let school_name: String

    private enum CodingKeys: String, CodingKey {
        case school_code, region_name, school_name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        school_code = try container.decodeLossyString(forKey: .school_code)
        region_name = try container.decodeLossyString(forKey: .region_name)
        school_name = try container.decodeLossyString(forKey: .school_name)
    }

    init(school_code: String, region_name: String, school_name: String) {
        self.school_code = school_code
        self.region_name = region_name
        self.school_name = school_name
    }

    var schoolCode: String { school_code }
    var regionName: String { region_name }
    var schoolName: String { school_name }
}

struct ComciVerifyResponseWidget: Decodable {
    let daily_subjects: [ComciPeriodWidget]
}

struct ComciPeriodWidget: Decodable {
    let period: Int
    let subject: String
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) throws -> String {
        if let stringValue = try decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
            if doubleValue.rounded() == doubleValue {
                return String(Int(doubleValue))
            }
            return String(doubleValue)
        }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Value missing for key \(key.stringValue)"))
    }
}
