import Foundation
import SwiftUI
import WidgetKit
import WatchConnectivity

final class NeisManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var schools: [SchoolRow] = []
    @Published var meals: [MealRow] = []
    @Published var timetables: [TimetableRow] = []
    @Published var selectedDate: Date = Date()
    @Published var timetableRawJSON: String = ""

    @Published var scheduleEvents: [ScheduleEventRow] = []
    @Published var calendarMonthStart: Date = Date()
    @Published var calendarMonthEnd: Date   = Date()

    private var appGroupStore: UserDefaults? {
        AppGroupManager.shared.sharedDefaults
    }

    @AppStorage("savedOfficeCode", store: AppGroupManager.shared.sharedDefaults)
    var officeCode: String = ""

    @AppStorage("savedSchoolCode", store: AppGroupManager.shared.sharedDefaults)
    var schoolCode: String = ""

    @AppStorage("savedSchoolName", store: AppGroupManager.shared.sharedDefaults)
    var schoolName: String = ""

    @AppStorage("savedGrade", store: AppGroupManager.shared.sharedDefaults)
    var grade: String = "1"

    @AppStorage("savedClass", store: AppGroupManager.shared.sharedDefaults)
    var classNum: String = "1"

    @AppStorage("isDarkMode", store: AppGroupManager.shared.sharedDefaults)
    var isDarkMode: Bool = false

    @AppStorage("timetableDateEditsJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableDateEditsJSON: String = "{}"

    @AppStorage("timetableWeeklyEditsJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableWeeklyEditsJSON: String = "{}"
    
    @AppStorage("timetableReplaceRulesJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableReplaceRulesJSON: String = "{}"

    @Published private(set) var replaceRules: [String: String] = [:]


    @Published private(set) var timetableDateEdits: [String: String] = [:]
    @Published private(set) var timetableWeeklyEdits: [String: String] = [:]

    private let apiKey = "b22e0d13ad8e49179c4d37cff6aed382"
    private var watchSession: WCSession?

    override init() {
        super.init()
        configureWatchSession()
        loadTimetableEditsIfNeeded()
    }

    private func configureWatchSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        watchSession = session
    }

    func syncWatchContext() {
        guard let session = watchSession, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "savedOfficeCode": officeCode,
            "savedSchoolCode": schoolCode,
            "savedSchoolName": schoolName,
            "savedGrade": grade,
            "savedClass": classNum,
            "timetableDateEditsJSON": timetableDateEditsJSON,
            "timetableWeeklyEditsJSON": timetableWeeklyEditsJSON,
            "timetableReplaceRulesJSON": timetableReplaceRulesJSON
        ]
        session.transferUserInfo(payload)
    }

    func getApiDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: selectedDate)
    }

    func loadTimetableEditsIfNeeded() {
        if let d = timetableDateEditsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: d) {
            timetableDateEdits = decoded
        } else {
            timetableDateEdits = [:]
        }

        if let d = timetableWeeklyEditsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: d) {
            timetableWeeklyEdits = decoded
        } else {
            timetableWeeklyEdits = [:]
        }
        if let d = timetableReplaceRulesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: d) {
            replaceRules = decoded
        } else {
            replaceRules = [:]
        }
    }

    private func saveTimetableEdits() {
        if let data = try? JSONEncoder().encode(timetableDateEdits),
           let json = String(data: data, encoding: .utf8) {
            timetableDateEditsJSON = json
        }

        if let data = try? JSONEncoder().encode(timetableWeeklyEdits),
           let json = String(data: data, encoding: .utf8) {
            timetableWeeklyEditsJSON = json
        }
        
        if let data = try? JSONEncoder().encode(replaceRules),
            let json = String(data: data, encoding: .utf8) {
            timetableReplaceRulesJSON = json
        }

        WidgetCenter.shared.reloadAllTimelines()
        syncWatchContext()
    }


    func dateEditKey(for row: TimetableRow) -> String {
        let d = row.ALL_TI_YMD ?? getApiDateString()
        let g = row.GRADE ?? grade
        let c = row.CLASS_NM ?? classNum
        let p = row.PERIO ?? ""
        return "\(schoolCode)|\(d)|\(g)|\(c)|\(p)"
    }

    func weeklyEditKey(perio: String) -> String {
        let weekday = Calendar.current.component(.weekday, from: selectedDate)
        return "\(schoolCode)|G\(grade)|C\(classNum)|W\(weekday)|P\(perio)"
    }

    func displayText(for row: TimetableRow) -> String {
        let perio = row.PERIO ?? ""

        let dk = dateEditKey(for: row)
        if let edited = timetableDateEdits[dk], !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return edited
        }

        let wk = weeklyEditKey(perio: perio)
        if let edited = timetableWeeklyEdits[wk], !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return edited
        }

        let original = (row.ITRT_CNTNT ?? "-").trimmingCharacters(in: .whitespacesAndNewlines)
        if let replaced = replaceRules[original], !replaced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return replaced
        }

        return row.ITRT_CNTNT ?? "-"
    }

    func hasAnyEditedText(for row: TimetableRow) -> Bool {
        let perio = row.PERIO ?? ""
        let original = (row.ITRT_CNTNT ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return timetableDateEdits[dateEditKey(for: row)] != nil
            || timetableWeeklyEdits[weeklyEditKey(perio: perio)] != nil
            || (!original.isEmpty && replaceRules[original] != nil)
    }



    func setEditedTextDate(_ text: String, for row: TimetableRow) {
        timetableDateEdits[dateEditKey(for: row)] = text
        saveTimetableEdits()
        objectWillChange.send()
    }

    func setEditedTextWeekly(_ text: String, for row: TimetableRow) {
        let perio = row.PERIO ?? ""
        timetableWeeklyEdits[weeklyEditKey(perio: perio)] = text
        saveTimetableEdits()
        objectWillChange.send()
    }

    func clearEditedTextDate(for row: TimetableRow) {
        timetableDateEdits.removeValue(forKey: dateEditKey(for: row))
        saveTimetableEdits()
        objectWillChange.send()
    }

    func clearEditedTextWeekly(for row: TimetableRow) {
        let perio = row.PERIO ?? ""
        timetableWeeklyEdits.removeValue(forKey: weeklyEditKey(perio: perio))
        saveTimetableEdits()
        objectWillChange.send()
    }

    func clearAllEdits(for row: TimetableRow) {
        clearEditedTextDate(for: row)
        clearEditedTextWeekly(for: row)

        let original = (row.ITRT_CNTNT ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !original.isEmpty {
            clearReplaceRule(for: original)
        }
    }

    func setReplaceRule(from: String, to: String) {
        let key = from.trimmingCharacters(in: .whitespacesAndNewlines)
        replaceRules[key] = to
        saveTimetableEdits()
        objectWillChange.send()
    }

    func clearReplaceRule(for from: String) {
        let key = from.trimmingCharacters(in: .whitespacesAndNewlines)
        replaceRules.removeValue(forKey: key)
        saveTimetableEdits()
        objectWillChange.send()
    }


    func searchSchool(query: String) {
        guard !query.isEmpty,
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return }

        let urlString = "https://open.neis.go.kr/hub/schoolInfo?KEY=\(apiKey)&Type=json&SCHUL_NM=\(encodedQuery)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let decoded = try? JSONDecoder().decode(SchoolResponse.self, from: data),
               let rows = decoded.schoolInfo?[1].row {
                DispatchQueue.main.async { self.schools = rows }
            }
        }.resume()
    }

    func saveSchool(school: SchoolRow) {
        DispatchQueue.main.async {
            self.grade = "1"
            self.classNum = "1"
            self.selectedDate = Date()

            self.officeCode = school.ATPT_OFCDC_SC_CODE
            self.schoolCode = school.SD_SCHUL_CODE
            self.schoolName = school.SCHUL_NM

            if let defaults = AppGroupManager.shared.sharedDefaults {
                defaults.set(self.officeCode, forKey: "savedOfficeCode")
                defaults.set(self.schoolCode, forKey: "savedSchoolCode")
                defaults.set(self.schoolName, forKey: "savedSchoolName")
                defaults.set(self.grade, forKey: "savedGrade")
                defaults.set(self.classNum, forKey: "savedClass")
                defaults.synchronize()
            }

            self.syncWatchContext()

            self.fetchAll()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
    
    func fetchAll() {
        fetchMeal()
        fetchTimetable()
        fetchSchedule()          // ▶ 학사일정도 함께 불러옴
    }

    func fetchMeal() {
        guard !schoolCode.isEmpty else { return }

        let urlString =
        "https://open.neis.go.kr/hub/mealServiceDietInfo?KEY=\(apiKey)&Type=json&ATPT_OFCDC_SC_CODE=\(officeCode)&SD_SCHUL_CODE=\(schoolCode)&MLSV_YMD=\(getApiDateString())"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let decoded = try? JSONDecoder().decode(NeisResponse.self, from: data),
               let rows = decoded.mealServiceDietInfo?[1].row {
                DispatchQueue.main.async { self.meals = rows }
            } else {
                DispatchQueue.main.async { self.meals = [] }
            }
        }.resume()
    }

    func fetchTimetable() {
        guard !schoolCode.isEmpty else { return }

        let currentOfficeCode = officeCode
        let currentSchoolCode = schoolCode
        let currentDate = getApiDateString()
        let currentGrade = grade
        let currentClass = classNum

        let urlString =
        "https://open.neis.go.kr/hub/hisTimetable?KEY=\(apiKey)&Type=json&pIndex=1&pSize=100&ATPT_OFCDC_SC_CODE=\(currentOfficeCode)&SD_SCHUL_CODE=\(currentSchoolCode)&ALL_TI_YMD=\(currentDate)&GRADE=\(currentGrade)&CLASS_NM=\(currentClass)"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { self.timetables = [] }
                return
            }

            if let raw = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { self.timetableRawJSON = raw }
                
            }

            do {
                let decoded = try JSONDecoder().decode(NeisResponse.self, from: data)

                let rows = decoded.hisTimetable?
                    .compactMap { $0.row }
                    .first(where: { !$0.isEmpty })

                DispatchQueue.main.async {
                    if let rows {
                        self.timetables = rows.sorted {
                            (Int($0.PERIO ?? "0") ?? 0) < (Int($1.PERIO ?? "0") ?? 0)
                        }
                    } else {
                        self.timetables = []
                    }
                }
            } catch {
                DispatchQueue.main.async { self.timetables = [] }
            }
        }.resume()
    }

    // MARK: 학사일정 (SchoolSchedule)

    func fetchSchedule(from monthStart: Date? = nil, to monthEnd: Date? = nil) {
        guard !schoolCode.isEmpty else { return }

        let start = monthStart ?? calendarMonthStart
        let end   = monthEnd   ?? calendarMonthEnd

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let fromYMD = formatter.string(from: start)
        let toYMD   = formatter.string(from: end)

        let urlString =
            "https://open.neis.go.kr/hub/SchoolSchedule" +
            "?KEY=\(apiKey)" +
            "&Type=json" +
            "&pIndex=1&pSize=100" +
            "&ATPT_OFCDC_SC_CODE=\(officeCode)" +
            "&SD_SCHUL_CODE=\(schoolCode)" +
            "&AA_FROM_YMD=\(fromYMD)" +
            "&AA_TO_YMD=\(toYMD)"

        print("📡 fetchSchedule URL:\n\(urlString)")

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { [self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { self.scheduleEvents = [] }
                return
            }
            print("📡 fetchSchedule HTTP status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")

            guard let data = data else {
                DispatchQueue.main.async { self.scheduleEvents = [] }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ScheduleResponse.self, from: data)
                print("✅ schoolSchedule 배열 수: \(decoded.schoolSchedule?.count ?? -1)")

                let rows = decoded.schoolSchedule?[1].row ?? []
                print("✅ row 수 (필터 전): \(rows.count)")

                let filtered = rows.filter { self.isEventForCurrentGrade($0) }
                print("✅ row 수 (필터 후, grade=\(self.grade)): \(filtered.count)")

                DispatchQueue.main.async {
                    self.scheduleEvents = filtered
                }
            } catch {
                print("🚫 fetchSchedule 파싱 오류: \(error)")
                DispatchQueue.main.async { self.scheduleEvents = [] }
            }
        }.resume()
    }

    /// 현재 학년(grade)에 해당하는 이벤트인지 판단
    /// NEIS 응답 필드:
    ///   ONE_GRADE_EVENT_YN   → 1학년
    ///   TW_GRADE_EVENT_YN    → 2학년
    ///   THREE_GRADE_EVENT_YN → 3학년
    ///   FR_GRADE_EVENT_YN    → 4학년 (초등)
    ///   FIV_GRADE_EVENT_YN   → 5학년 (초등)
    ///   SIX_GRADE_EVENT_YN   → 6학년 (초등)
    /// 값이 "Y"이면 해당 학년에 적용, "*"이면 해당 학년 없음
    private func isEventForCurrentGrade(_ event: ScheduleEventRow) -> Bool {
        let flag: String?
        switch grade {
        case "1": flag = event.ONE_GRADE_EVENT_YN
        case "2": flag = event.TW_GRADE_EVENT_YN
        case "3": flag = event.THREE_GRADE_EVENT_YN
        case "4": flag = event.FR_GRADE_EVENT_YN
        case "5": flag = event.FIV_GRADE_EVENT_YN
        case "6": flag = event.SIX_GRADE_EVENT_YN
        default:  flag = nil
        }
        // "Y" 또는 해당 필드가 없는 경우(전체 학년 공통 이벤트) 포함
        return flag == nil || flag == "Y"
    }

    /// 특정 날짜에 해당하는 학사일정 이벤트 목록 반환
    func events(on date: Date) -> [ScheduleEventRow] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateStr = formatter.string(from: date)
        return scheduleEvents.filter { $0.AA_YMD == dateStr }
    }

    /// MARK: - Helpers
    func cleanMealText(_ text: String) -> String {
        return text.replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: #"\([0-9\.]+\)"#, with: "", options: .regularExpression)
    }
    
    // 🔧 워치 통신 테스트용 (아이폰 → 워치)
    func debugWriteForWatch() {
        if let defaults = AppGroupManager.shared.sharedDefaults {
            defaults.set("HELLO_FROM_IPHONE", forKey: "watch_test")
            print("📱 wrote watch_test")
        } else {
            print("📱 App Group 접근 실패")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated {
            syncWatchContext()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

// MARK: - Models
struct SchoolResponse: Codable { let schoolInfo: [SchoolInfoHeader]? }
struct SchoolInfoHeader: Codable { let row: [SchoolRow]? }
struct SchoolRow: Codable, Identifiable {
    var id: String { SD_SCHUL_CODE }
    let ATPT_OFCDC_SC_CODE, SD_SCHUL_CODE, SCHUL_NM: String
    let ORG_RDNMA: String?
}

struct NeisResponse: Codable {
    let mealServiceDietInfo: [MealInfo]?
    let hisTimetable: [TimetableInfo]?
}

struct MealInfo: Codable { let row: [MealRow]? }
struct MealRow: Codable, Identifiable {
    var id: String { MMEAL_SC_CODE }
    let MMEAL_SC_NM, DDISH_NM, CAL_INFO, MMEAL_SC_CODE: String
}

struct TimetableInfo: Codable {
    let head: [HeadInfo]?
    let row: [TimetableRow]?
}

struct HeadInfo: Codable {
    let list_total_count: Int?
    let RESULT: ResultInfo?
}

struct ResultInfo: Codable {
    let CODE: String?
    let MESSAGE: String?
}

struct TimetableRow: Codable, Identifiable {
    var id: String {
        "\(ALL_TI_YMD ?? "")\(GRADE ?? "")\(CLASS_NM ?? "")\(PERIO ?? "")"
    }
    let ALL_TI_YMD: String?
    let GRADE: String?
    let CLASS_NM: String?
    let PERIO: String?
    let ITRT_CNTNT: String?
}

// ─────────────────────────────────────────────
// MARK: - 학사일정 모델
// ─────────────────────────────────────────────

/// NEIS SchoolSchedule API 최상위 응답
/// 기존 NeisResponse와 동일한 패턴: 배열[0] = head, 배열[1] = row
struct ScheduleResponse: Codable {
    let schoolSchedule: [ScheduleInfo]?

    enum CodingKeys: String, CodingKey {
        case schoolSchedule = "SchoolSchedule"
    }
}

struct ScheduleInfo: Codable {
    let head: [HeadInfo]?
    let row: [ScheduleEventRow]?
}

/// 학사일정 단일 행사 데이터
struct ScheduleEventRow: Codable, Identifiable {
    /// 고유 ID: 날짜 + 행사명으로 조합 (같은 날 여러 행사 가능)
    var id: String {
        "\(AA_YMD ?? "")|\(EVENT_NM ?? "")"
    }

    let ATPT_OFCDC_SC_CODE: String?   // 시도교육청코드
    let SD_SCHUL_CODE: String?        // 학교코드
    let SCHUL_NM: String?             // 학교명
    let AY: String?                   // 학년도
    let SBTR_DD_SC_NM: String?        // 휴업일 구분 (예: "휴업일", "평일")
    let AA_YMD: String?               // 행사일자  yyyyMMdd
    let EVENT_NM: String?             // 행사명
    let EVENT_CNTNT: String?          // 행사내용 (상세 설명)

    // 학년별 행사 여부 ("Y" = 해당, "*" = 해당 없음)
    let ONE_GRADE_EVENT_YN: String?   // 1학년
    let TW_GRADE_EVENT_YN: String?    // 2학년
    let THREE_GRADE_EVENT_YN: String? // 3학년
    let FR_GRADE_EVENT_YN: String?    // 4학년
    let FIV_GRADE_EVENT_YN: String?   // 5학년
    let SIX_GRADE_EVENT_YN: String?   // 6학년
}
