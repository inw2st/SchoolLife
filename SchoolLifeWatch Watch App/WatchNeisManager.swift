import Foundation
import SwiftUI
import Combine
import WatchConnectivity
import WidgetKit

final class WatchNeisManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var meals: [WatchMealRow] = []
    @Published var timetables: [WatchTimetableRow] = []
    @Published var schoolName: String = ""
    
    private let apiKey = "b22e0d13ad8e49179c4d37cff6aed382"
    private var session: WCSession?
    
    override init() {
        super.init()
        configureSession()
        schoolName = schoolNameFromStore
    }
    
    // App Group에서 설정 읽기
    private var appGroupStore: UserDefaults? {
        AppGroupManager.shared.sharedDefaults
    }
    
    private var officeCode: String {
        appGroupStore?.string(forKey: "savedOfficeCode") ?? ""
    }
    
    private var schoolCode: String {
        appGroupStore?.string(forKey: "savedSchoolCode") ?? ""
    }
    
    private var schoolNameFromStore: String {
        appGroupStore?.string(forKey: "savedSchoolName") ?? ""
    }
    
    private var grade: String {
        appGroupStore?.string(forKey: "savedGrade") ?? "1"
    }
    
    private var classNum: String {
        appGroupStore?.string(forKey: "savedClass") ?? "1"
    }
    
    private var timetableDateEdits: [String: String] {
        guard let json = appGroupStore?.string(forKey: "timetableDateEditsJSON"),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private var timetableWeeklyEdits: [String: String] {
        guard let json = appGroupStore?.string(forKey: "timetableWeeklyEditsJSON"),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private var replaceRules: [String: String] {
        guard let json = appGroupStore?.string(forKey: "timetableReplaceRulesJSON"),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private func configureSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }
    
    func fetchAll() {
        schoolName = schoolNameFromStore
        fetchMeal()
        fetchTimetable()
    }
    
    // MARK: - 급식
    func fetchMeal() {
        guard !schoolCode.isEmpty else { return }
        
        let today = getApiDateString()
        let urlString = "https://open.neis.go.kr/hub/mealServiceDietInfo?KEY=\(apiKey)&Type=json&ATPT_OFCDC_SC_CODE=\(officeCode)&SD_SCHUL_CODE=\(schoolCode)&MLSV_YMD=\(today)"
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data,
               let decoded = try? JSONDecoder().decode(WatchMealResponse.self, from: data),
               let rows = decoded.mealServiceDietInfo?.compactMap({ $0.row }).first(where: { !($0?.isEmpty ?? true) }) {
                DispatchQueue.main.async {
                    self.meals = rows ?? []
                }
            } else {
                DispatchQueue.main.async {
                    self.meals = []
                }
            }
        }.resume()
    }
    
    // MARK: - 시간표
    func fetchTimetable() {
        guard !schoolCode.isEmpty else { return }
        
        let today = getApiDateString()
        let urlString = "https://open.neis.go.kr/hub/hisTimetable?KEY=\(apiKey)&Type=json&pIndex=1&pSize=100&ATPT_OFCDC_SC_CODE=\(officeCode)&SD_SCHUL_CODE=\(schoolCode)&ALL_TI_YMD=\(today)&GRADE=\(grade)&CLASS_NM=\(classNum)"
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data,
               let decoded = try? JSONDecoder().decode(WatchTimetableResponse.self, from: data),
               let rows = decoded.hisTimetable?.compactMap({ $0.row }).first(where: { !($0?.isEmpty ?? true) }) {
                DispatchQueue.main.async {
                    self.timetables = (rows ?? []).sorted {
                        (Int($0.PERIO ?? "0") ?? 0) < (Int($1.PERIO ?? "0") ?? 0)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.timetables = []
                }
            }
        }.resume()
    }
    
    // MARK: - Helpers
    func getApiDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
    
    func cleanMealText(_ text: String) -> String {
        return text.replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: #"\([0-9\.]+\)"#, with: "", options: .regularExpression)
    }
    
    func displayText(for row: WatchTimetableRow) -> String {
        let perio = row.PERIO ?? ""
        let today = getApiDateString()
        
        // 1) 날짜 고정 편집
        let dateKey = "\(schoolCode)|\(today)|\(grade)|\(classNum)|\(perio)"
        if let edited = timetableDateEdits[dateKey], !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return edited
        }
        
        // 2) 요일 반복 편집
        let weekday = Calendar.current.component(.weekday, from: Date())
        let weeklyKey = "\(schoolCode)|G\(grade)|C\(classNum)|W\(weekday)|P\(perio)"
        if let edited = timetableWeeklyEdits[weeklyKey], !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return edited
        }
        
        // 3) 과목명 치환
        let original = (row.ITRT_CNTNT ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let replaced = replaceRules[original], !replaced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return replaced
        }
        
        // 4) 원본
        return row.ITRT_CNTNT ?? "-"
    }
    
    private func storeUserInfo(_ userInfo: [String: Any]) {
        guard let defaults = AppGroupManager.shared.sharedDefaults else { return }
        if let value = userInfo["savedOfficeCode"] as? String { defaults.set(value, forKey: "savedOfficeCode") }
        if let value = userInfo["savedSchoolCode"] as? String { defaults.set(value, forKey: "savedSchoolCode") }
        if let value = userInfo["savedSchoolName"] as? String { defaults.set(value, forKey: "savedSchoolName") }
        if let value = userInfo["savedGrade"] as? String { defaults.set(value, forKey: "savedGrade") }
        if let value = userInfo["savedClass"] as? String { defaults.set(value, forKey: "savedClass") }
        if let value = userInfo["timetableDateEditsJSON"] as? String { defaults.set(value, forKey: "timetableDateEditsJSON") }
        if let value = userInfo["timetableWeeklyEditsJSON"] as? String { defaults.set(value, forKey: "timetableWeeklyEditsJSON") }
        if let value = userInfo["timetableReplaceRulesJSON"] as? String { defaults.set(value, forKey: "timetableReplaceRulesJSON") }
        defaults.synchronize()
        DispatchQueue.main.async {
            self.schoolName = self.schoolNameFromStore
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated {
            DispatchQueue.main.async {
                self.schoolName = self.schoolNameFromStore
                self.fetchAll()
            }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        storeUserInfo(userInfo)
        DispatchQueue.main.async {
            self.schoolName = self.schoolNameFromStore
            self.fetchAll()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // 🔧 아이폰 → 워치 App Group 통신 테스트
    func debugReadFromPhone() {
        let v = UserDefaults(
            suiteName: AppGroupManager.shared.appGroupID ?? ""
        )?.string(forKey: "watch_test")

        print("⌚️ watch_test =", v ?? "nil")
    }

}

// MARK: - Models
struct WatchMealResponse: Codable {
    let mealServiceDietInfo: [WatchMealInfo]?
}

struct WatchMealInfo: Codable {
    let row: [WatchMealRow]?
}

struct WatchMealRow: Codable, Identifiable {
    var id: String { MMEAL_SC_CODE }
    let MMEAL_SC_NM, DDISH_NM, CAL_INFO, MMEAL_SC_CODE: String
}

struct WatchTimetableResponse: Codable {
    let hisTimetable: [WatchTimetableInfo]?
}

struct WatchTimetableInfo: Codable {
    let row: [WatchTimetableRow]?
}

struct WatchTimetableRow: Codable, Identifiable {
    var id: String {
        "\(GRADE ?? "")\(CLASS_NM ?? "")\(PERIO ?? "")"
    }
    let GRADE: String?
    let CLASS_NM: String?
    let PERIO: String?
    let ITRT_CNTNT: String?
}
