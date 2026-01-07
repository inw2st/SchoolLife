import Foundation
import SwiftUI
import WidgetKit

final class NeisManager: ObservableObject {

    // MARK: - Published
    @Published var schools: [SchoolRow] = []
    @Published var meals: [MealRow] = []
    @Published var timetables: [TimetableRow] = []
    @Published var selectedDate: Date = Date()
    @Published var timetableRawJSON: String = ""

    // MARK: - App Group Storage (위젯 공유)
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

    // 특정 날짜만 덮어쓰기(override) 편집
    @AppStorage("timetableDateEditsJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableDateEditsJSON: String = "{}"

    // 매주 반복되는 요일/교시 템플릿 편집
    @AppStorage("timetableWeeklyEditsJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableWeeklyEditsJSON: String = "{}"
    
    @AppStorage("timetableReplaceRulesJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableReplaceRulesJSON: String = "{}"

    @Published private(set) var replaceRules: [String: String] = [:]   // 원본 -> 치환


    /// key: editedText
    @Published private(set) var timetableDateEdits: [String: String] = [:]
    @Published private(set) var timetableWeeklyEdits: [String: String] = [:]

    // MARK: - NEIS API
    private let apiKey = "b22e0d13ad8e49179c4d37cff6aed382"

    init() {
        loadTimetableEditsIfNeeded()
    }

    // MARK: - Date
    func getApiDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: selectedDate)
    }

    // MARK: - Timetable Edit Persistence
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
    }

    /// 특정 날짜용 키: 학교 + 날짜 + 학년 + 반 + 교시
    func dateEditKey(for row: TimetableRow) -> String {
        let d = row.ALL_TI_YMD ?? getApiDateString()
        let g = row.GRADE ?? grade
        let c = row.CLASS_NM ?? classNum
        let p = row.PERIO ?? ""
        return "\(schoolCode)|\(d)|\(g)|\(c)|\(p)"
    }

    /// 매주 반복 키: 학교 + 학년 + 반 + 요일 + 교시
    /// weekday: 1=일 ... 7=토 (Calendar 기준)
    func weeklyEditKey(perio: String) -> String {
        let weekday = Calendar.current.component(.weekday, from: selectedDate)
        return "\(schoolCode)|G\(grade)|C\(classNum)|W\(weekday)|P\(perio)"
    }

    /// 화면 표시용 텍스트 (우선순위: 날짜 고정 > 요일 반복 > NEIS)
    func displayText(for row: TimetableRow) -> String {
        let perio = row.PERIO ?? ""

        // 1) 날짜 고정
        let dk = dateEditKey(for: row)
        if let edited = timetableDateEdits[dk], !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return edited
        }

        // 2) 요일 반복
        let wk = weeklyEditKey(perio: perio)
        if let edited = timetableWeeklyEdits[wk], !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return edited
        }

        // 3) 과목명 자동 치환
        let original = (row.ITRT_CNTNT ?? "-").trimmingCharacters(in: .whitespacesAndNewlines)
        if let replaced = replaceRules[original], !replaced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return replaced
        }

        // 4) 원문
        return row.ITRT_CNTNT ?? "-"
    }

    func hasAnyEditedText(for row: TimetableRow) -> Bool {
        let perio = row.PERIO ?? ""
        let original = (row.ITRT_CNTNT ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return timetableDateEdits[dateEditKey(for: row)] != nil
            || timetableWeeklyEdits[weeklyEditKey(perio: perio)] != nil
            || (!original.isEmpty && replaceRules[original] != nil)
    }



    // 편집 저장/삭제 API
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


    // MARK: - School Search
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
            // 1) UI가 참조하는 @AppStorage 값을 먼저 초기화
            self.grade = "1"
            self.classNum = "1"
            self.selectedDate = Date()

            self.officeCode = school.ATPT_OFCDC_SC_CODE
            self.schoolCode = school.SD_SCHUL_CODE
            self.schoolName = school.SCHUL_NM

            // 2) App Group defaults에도 동일하게 저장
            if let defaults = AppGroupManager.shared.sharedDefaults {
                defaults.set(self.officeCode, forKey: "savedOfficeCode")
                defaults.set(self.schoolCode, forKey: "savedSchoolCode")
                defaults.set(self.schoolName, forKey: "savedSchoolName")
                defaults.set(self.grade, forKey: "savedGrade")
                defaults.set(self.classNum, forKey: "savedClass")
                defaults.synchronize()
            }

            // 3) 데이터 다시 불러오기
            self.fetchAll()

            // 4) UserDefaults 동기화 시간을 확보한 뒤 위젯 새로고침
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
    
    // MARK: - Fetch All
    func fetchAll() {
        fetchMeal()
        fetchTimetable()
    }

    // MARK: - Meal
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

    // MARK: - Timetable
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

            // 디버그용 원본 JSON 저장
            if let raw = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { self.timetableRawJSON = raw }
                
                #if DEBUG
                // print("NEIS RAW JSON:\n\(raw)")
                #endif
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

    // MARK: - Helpers
    func cleanMealText(_ text: String) -> String {
        return text.replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: #"\([0-9\.]+\)"#, with: "", options: .regularExpression)
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
