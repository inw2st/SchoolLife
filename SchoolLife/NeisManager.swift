import Foundation
import SwiftUI
import WidgetKit
import WatchConnectivity

enum TimetableSource: String, CaseIterable, Identifiable {
    case neis
    case comci

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neis: return "교육청 API"
        case .comci: return "컴시간"
        }
    }
}

enum TimetableEditResetTarget: String, CaseIterable, Identifiable {
    case todayOnly
    case weekly
    case replaceSubject
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todayOnly: return "오늘만 수정 초기화"
        case .weekly: return "매주 수정 초기화"
        case .replaceSubject: return "동일 이름 전체 교체 초기화"
        case .all: return "현재 반 수정 전체 초기화"
        }
    }

    var summary: String {
        switch self {
        case .todayOnly: return "현재 학교/학년/반의 날짜별 수정만 삭제합니다."
        case .weekly: return "현재 학교/학년/반의 요일 반복 수정만 삭제합니다."
        case .replaceSubject: return "현재 학교/학년/반의 동일 이름 전체 교체만 삭제합니다."
        case .all: return "현재 학교/학년/반의 모든 시간표 수정사항을 삭제합니다."
        }
    }
}

final class NeisManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var schools: [SchoolRow] = []
    @Published var meals: [MealRow] = []
    @Published var timetables: [TimetableRow] = []
    @Published var selectedDate: Date = Date()
    @Published var timetableRawJSON: String = ""
    @Published var timetableMessage: String? = nil

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

    @AppStorage("timetableSource", store: AppGroupManager.shared.sharedDefaults)
    private var timetableSourceRawValue: String = TimetableSource.neis.rawValue

    @AppStorage("isDarkMode", store: AppGroupManager.shared.sharedDefaults)
    var isDarkMode: Bool = false

    @AppStorage("timetableDateEditsJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableDateEditsJSON: String = "{}"

    @AppStorage("timetableWeeklyEditsJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableWeeklyEditsJSON: String = "{}"
    
    @AppStorage("timetableReplaceRulesJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableReplaceRulesJSON: String = "{}"

    @AppStorage("savedComciSchoolCode", store: AppGroupManager.shared.sharedDefaults)
    private var comciSchoolCode: String = ""

    @AppStorage("savedComciMappedSchoolName", store: AppGroupManager.shared.sharedDefaults)
    private var comciMappedSchoolName: String = ""

    @AppStorage("savedComciRegionName", store: AppGroupManager.shared.sharedDefaults)
    private var comciRegionName: String = ""

    @AppStorage("comciWeeklyTimetableCacheJSON", store: AppGroupManager.shared.sharedDefaults)
    private var comciWeeklyTimetableCacheJSON: String = "{}"

    @Published private(set) var replaceRules: [String: String] = [:]


    @Published private(set) var timetableDateEdits: [String: String] = [:]
    @Published private(set) var timetableWeeklyEdits: [String: String] = [:]

    private let apiKey = "b22e0d13ad8e49179c4d37cff6aed382"
    private let comciRelayBaseURL = "https://comci-direct-server.vercel.app"
    private var watchSession: WCSession?
    private var comciWeeklyCache: [String: ComciWeeklyCacheEntry] = [:]

    private let replaceRuleMarker = "|SUBJECT|"
    private let comciWeeklyCacheMaxEntries = 24
    private let comciWeeklyCacheFreshHours: TimeInterval = 6 * 60 * 60

    var timetableSource: TimetableSource {
        get { TimetableSource(rawValue: timetableSourceRawValue) ?? .neis }
        set {
            timetableSourceRawValue = newValue.rawValue
            WidgetCenter.shared.reloadTimelines(ofKind: "TimetableWidget")
            objectWillChange.send()
        }
    }

    override init() {
        super.init()
        configureWatchSession()
        loadTimetableEditsIfNeeded()
        loadComciWeeklyCacheIfNeeded()
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

        migrateLegacyReplaceRulesIfNeeded()
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

    private func loadComciWeeklyCacheIfNeeded() {
        guard let data = comciWeeklyTimetableCacheJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: ComciWeeklyCacheEntry].self, from: data) else {
            comciWeeklyCache = [:]
            return
        }
        comciWeeklyCache = decoded
    }

    private func saveComciWeeklyCache() {
        pruneComciWeeklyCacheIfNeeded()
        if let data = try? JSONEncoder().encode(comciWeeklyCache),
           let json = String(data: data, encoding: .utf8) {
            comciWeeklyTimetableCacheJSON = json
        }
    }

    private func pruneComciWeeklyCacheIfNeeded() {
        guard comciWeeklyCache.count > comciWeeklyCacheMaxEntries else { return }
        let sortedKeys = comciWeeklyCache
            .sorted { $0.value.fetchedAt > $1.value.fetchedAt }
            .map(\.key)
        let keepKeys = Set(sortedKeys.prefix(comciWeeklyCacheMaxEntries))
        comciWeeklyCache = comciWeeklyCache.filter { keepKeys.contains($0.key) }
    }

    private func migrateLegacyReplaceRulesIfNeeded() {
        var migrated = replaceRules
        var didChange = false

        for (key, value) in replaceRules {
            guard parsedReplaceRuleKey(key) == nil else { continue }
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }

            if timetableSource == .comci, key.hasPrefix("comci|") {
                let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3 else { continue }
                let schoolIdentifier = parts.dropLast(1).joined(separator: "|")
                let subject = parts.last ?? ""
                guard schoolIdentifier == currentDateWeeklySchoolIdentifier() else { continue }

                let scopedKey = "\(currentReplaceRuleScopeIdentifier())\(replaceRuleMarker)\(subject)"
                if migrated[scopedKey] == nil {
                    migrated[scopedKey] = trimmedValue
                }
                migrated.removeValue(forKey: key)
                didChange = true
                continue
            }

            if timetableSource == .neis, !key.contains("|") {
                let scopedKey = "\(currentReplaceRuleScopeIdentifier())\(replaceRuleMarker)\(key)"
                if migrated[scopedKey] == nil {
                    migrated[scopedKey] = trimmedValue
                }
                migrated.removeValue(forKey: key)
                didChange = true
            }
        }

        if didChange {
            replaceRules = migrated
            saveTimetableEdits()
        }
    }


    func dateEditKey(for row: TimetableRow) -> String {
        let d = row.ALL_TI_YMD ?? getApiDateString()
        let g = row.GRADE ?? grade
        let c = row.CLASS_NM ?? classNum
        let p = row.PERIO ?? ""
        return "\(rowSchoolIdentifier(for: row))|\(d)|\(g)|\(c)|\(p)"
    }

    func weeklyEditKey(for row: TimetableRow) -> String {
        let weekday = Calendar.current.component(.weekday, from: selectedDate)
        let perio = row.PERIO ?? ""
        return "\(rowSchoolIdentifier(for: row))|G\(grade)|C\(classNum)|W\(weekday)|P\(perio)"
    }

    private func rowSchoolIdentifier(for row: TimetableRow) -> String {
        if row.SOURCE_KIND == TimetableSource.comci.rawValue {
            let sourceID = row.SOURCE_SCHOOL_ID ?? currentTimetableSchoolIdentifier()
            return "\(TimetableSource.comci.rawValue)|\(sourceID)"
        }
        return schoolCode
    }

    private func currentTimetableSchoolIdentifier() -> String {
        switch timetableSource {
        case .neis:
            return schoolCode
        case .comci:
            return comciSchoolCode.isEmpty ? schoolName : comciSchoolCode
        }
    }

    private func replaceRuleKey(for row: TimetableRow) -> String {
        let original = (row.ITRT_CNTNT ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return "" }
        return "\(replaceRuleScopeIdentifier(for: row))\(replaceRuleMarker)\(original)"
    }

    private func replaceRuleScopeIdentifier(for row: TimetableRow) -> String {
        let rowGrade = row.GRADE ?? grade
        let rowClass = row.CLASS_NM ?? classNum
        let schoolIdentifier: String
        let sourceIdentifier: String

        if row.SOURCE_KIND == TimetableSource.comci.rawValue {
            sourceIdentifier = TimetableSource.comci.rawValue
            schoolIdentifier = row.SOURCE_SCHOOL_ID ?? currentTimetableSchoolIdentifier()
        } else {
            sourceIdentifier = TimetableSource.neis.rawValue
            schoolIdentifier = schoolCode
        }

        return "\(sourceIdentifier)|\(schoolIdentifier)|G\(rowGrade)|C\(rowClass)"
    }

    private func currentReplaceRuleScopeIdentifier() -> String {
        let sourceIdentifier = timetableSource.rawValue
        let schoolIdentifier = timetableSource == .comci ? currentTimetableSchoolIdentifier() : schoolCode
        return "\(sourceIdentifier)|\(schoolIdentifier)|G\(grade)|C\(classNum)"
    }

    func displayText(for row: TimetableRow) -> String {
        let dk = dateEditKey(for: row)
        if let edited = timetableDateEdits[dk], !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return edited
        }

        let wk = weeklyEditKey(for: row)
        if let edited = timetableWeeklyEdits[wk], !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return edited
        }

        let replaceKey = replaceRuleKey(for: row)
        if let replaced = replaceRules[replaceKey], !replaced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return replaced
        }

        return row.ITRT_CNTNT ?? "-"
    }

    func hasAnyEditedText(for row: TimetableRow) -> Bool {
        return timetableDateEdits[dateEditKey(for: row)] != nil
            || timetableWeeklyEdits[weeklyEditKey(for: row)] != nil
            || replaceRules[replaceRuleKey(for: row)] != nil
    }



    func setEditedTextDate(_ text: String, for row: TimetableRow) {
        timetableDateEdits[dateEditKey(for: row)] = text
        saveTimetableEdits()
        objectWillChange.send()
    }

    func setEditedTextWeekly(_ text: String, for row: TimetableRow) {
        timetableWeeklyEdits[weeklyEditKey(for: row)] = text
        saveTimetableEdits()
        objectWillChange.send()
    }

    func clearEditedTextDate(for row: TimetableRow) {
        timetableDateEdits.removeValue(forKey: dateEditKey(for: row))
        saveTimetableEdits()
        objectWillChange.send()
    }

    func clearEditedTextWeekly(for row: TimetableRow) {
        timetableWeeklyEdits.removeValue(forKey: weeklyEditKey(for: row))
        saveTimetableEdits()
        objectWillChange.send()
    }

    func clearAllEdits(for row: TimetableRow) {
        clearEditedTextDate(for: row)
        clearEditedTextWeekly(for: row)

        clearReplaceRule(for: row)
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

    func setReplaceRule(for row: TimetableRow, to: String) {
        let key = replaceRuleKey(for: row)
        guard !key.isEmpty else { return }
        replaceRules[key] = to
        saveTimetableEdits()
        objectWillChange.send()
    }

    func clearReplaceRule(for row: TimetableRow) {
        let key = replaceRuleKey(for: row)
        replaceRules.removeValue(forKey: key)
        saveTimetableEdits()
        objectWillChange.send()
    }

    private func currentDateWeeklySchoolIdentifier() -> String {
        switch timetableSource {
        case .neis:
            return schoolCode
        case .comci:
            return "comci|\(currentTimetableSchoolIdentifier())"
        }
    }

    private func parsedDateEditKey(_ key: String) -> (schoolIdentifier: String, grade: String, classNum: String)? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        return (
            schoolIdentifier: parts.dropLast(4).joined(separator: "|"),
            grade: parts[parts.count - 3],
            classNum: parts[parts.count - 2]
        )
    }

    private func parsedWeeklyEditKey(_ key: String) -> (schoolIdentifier: String, grade: String, classNum: String)? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        let rawGrade = parts[parts.count - 4]
        let rawClass = parts[parts.count - 3]
        return (
            schoolIdentifier: parts.dropLast(4).joined(separator: "|"),
            grade: rawGrade.hasPrefix("G") ? String(rawGrade.dropFirst()) : rawGrade,
            classNum: rawClass.hasPrefix("C") ? String(rawClass.dropFirst()) : rawClass
        )
    }

    private func parsedReplaceRuleKey(_ key: String) -> (scopeIdentifier: String, original: String)? {
        guard let range = key.range(of: replaceRuleMarker, options: .backwards) else { return nil }
        return (
            scopeIdentifier: String(key[..<range.lowerBound]),
            original: String(key[range.upperBound...])
        )
    }

    private func currentScopedDateEdits() -> [String: String] {
        let expectedSchoolIdentifier = currentDateWeeklySchoolIdentifier()
        return timetableDateEdits.filter { entry in
            guard let parsed = parsedDateEditKey(entry.key) else { return false }
            return parsed.schoolIdentifier == expectedSchoolIdentifier
                && parsed.grade == grade
                && parsed.classNum == classNum
        }
    }

    private func currentScopedWeeklyEdits() -> [String: String] {
        let expectedSchoolIdentifier = currentDateWeeklySchoolIdentifier()
        return timetableWeeklyEdits.filter { entry in
            guard let parsed = parsedWeeklyEditKey(entry.key) else { return false }
            return parsed.schoolIdentifier == expectedSchoolIdentifier
                && parsed.grade == grade
                && parsed.classNum == classNum
        }
    }

    private func currentScopedReplaceRules() -> [String: String] {
        let expectedScope = currentReplaceRuleScopeIdentifier()
        return replaceRules.filter { entry in
            guard let parsed = parsedReplaceRuleKey(entry.key) else { return false }
            return parsed.scopeIdentifier == expectedScope
        }
    }

    private func currentTimetableEditExportScope() -> TimetableEditExportScope {
        TimetableEditExportScope(
            source: timetableSource.rawValue,
            schoolIdentifier: timetableSource == .comci ? currentTimetableSchoolIdentifier() : schoolCode,
            schoolName: schoolName,
            grade: grade,
            classNum: classNum
        )
    }

    func currentTimetableEditExportFileName() -> String {
        let safeSchoolName = schoolName.isEmpty ? "school" : schoolName.replacingOccurrences(of: " ", with: "")
        return "timetable-edits-\(safeSchoolName)-\(grade)-\(classNum)-\(timetableSource.rawValue).json"
    }

    func exportCurrentTimetableEditsData() throws -> Data {
        let dateEdits = currentScopedDateEdits()
        let weeklyEdits = currentScopedWeeklyEdits()
        let replaceRules = currentScopedReplaceRules()

        guard !dateEdits.isEmpty || !weeklyEdits.isEmpty || !replaceRules.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "내보낼 수정사항이 없습니다."])
        }

        let payload = TimetableEditExportPayload(
            version: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            scope: currentTimetableEditExportScope(),
            dateEdits: dateEdits,
            weeklyEdits: weeklyEdits,
            replaceRules: replaceRules
        )

        return try JSONEncoder.prettyPrinted.encode(payload)
    }

    func importTimetableEdits(from data: Data) throws {
        let payload = try JSONDecoder().decode(TimetableEditExportPayload.self, from: data)
        let currentScope = currentTimetableEditExportScope()

        guard payload.scope.source == currentScope.source else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "시간표 소스가 달라 불러올 수 없습니다."])
        }
        guard payload.scope.grade == currentScope.grade, payload.scope.classNum == currentScope.classNum else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "학년 또는 반이 달라 불러올 수 없습니다."])
        }

        let sameSchool = payload.scope.schoolIdentifier == currentScope.schoolIdentifier
            || (!payload.scope.schoolName.isEmpty && payload.scope.schoolName == currentScope.schoolName)
        guard sameSchool else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "현재 선택된 학교와 수정사항 파일의 학교가 다릅니다."])
        }

        for (key, value) in payload.dateEdits { timetableDateEdits[key] = value }
        for (key, value) in payload.weeklyEdits { timetableWeeklyEdits[key] = value }
        for (key, value) in payload.replaceRules { replaceRules[key] = value }

        saveTimetableEdits()
        fetchTimetable()
        objectWillChange.send()
    }

    func clearCurrentTimetableEdits(_ target: TimetableEditResetTarget) {
        switch target {
        case .todayOnly:
            timetableDateEdits = timetableDateEdits.filter { !currentScopedDateEdits().keys.contains($0.key) }
        case .weekly:
            timetableWeeklyEdits = timetableWeeklyEdits.filter { !currentScopedWeeklyEdits().keys.contains($0.key) }
        case .replaceSubject:
            replaceRules = replaceRules.filter { !currentScopedReplaceRules().keys.contains($0.key) }
        case .all:
            let dateKeys = Set(currentScopedDateEdits().keys)
            let weeklyKeys = Set(currentScopedWeeklyEdits().keys)
            let replaceKeys = Set(currentScopedReplaceRules().keys)
            timetableDateEdits = timetableDateEdits.filter { !dateKeys.contains($0.key) }
            timetableWeeklyEdits = timetableWeeklyEdits.filter { !weeklyKeys.contains($0.key) }
            replaceRules = replaceRules.filter { !replaceKeys.contains($0.key) }
        }

        saveTimetableEdits()
        fetchTimetable()
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
                defaults.removeObject(forKey: "savedComciSchoolCode")
                defaults.removeObject(forKey: "savedComciMappedSchoolName")
                defaults.removeObject(forKey: "savedComciRegionName")
                defaults.synchronize()
            }

            self.comciSchoolCode = ""
            self.comciMappedSchoolName = ""
            self.comciRegionName = ""

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
        switch timetableSource {
        case .neis:
            fetchNeisTimetable()
        case .comci:
            fetchComciTimetable()
        }
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
            if error != nil {
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

    var timetableSourceDescription: String {
        timetableSource.title
    }

    private func fetchNeisTimetable() {
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
                DispatchQueue.main.async {
                    self.timetableMessage = nil
                    self.timetables = []
                }
                return
            }

            if let raw = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.timetableRawJSON = raw
                    self.timetableMessage = nil
                }
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
                DispatchQueue.main.async {
                    self.timetableMessage = "교육청 시간표를 불러오지 못했습니다."
                    self.timetables = []
                }
            }
        }.resume()
    }

    private func fetchComciTimetable() {
        guard !schoolName.isEmpty else { return }

        resolveComciSchoolMapping { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.timetableMessage = error.localizedDescription
                    self.timetableRawJSON = error.localizedDescription
                    self.timetables = []
                }
            case .success(let school):
                let cacheKey = self.comciWeeklyCacheKey(for: school, grade: self.grade, classNum: self.classNum, date: self.selectedDate)
                if let cached = self.comciWeeklyCache[cacheKey] {
                    DispatchQueue.main.async {
                        self.applyComciWeeklyCache(cached, school: school)
                    }

                    if Date().timeIntervalSince(cached.fetchedAtDate) < self.comciWeeklyCacheFreshHours {
                        return
                    }
                }
                self.requestComciTimetable(for: school)
            }
        }
    }

    private func requestComciTimetable(for school: ComciResolvedSchool) {
        guard var components = URLComponents(string: "\(comciRelayBaseURL)/timetable/verify") else { return }

        let targetDate = isoDateString(from: selectedDate)
        components.queryItems = [
            URLQueryItem(name: "school_name", value: school.schoolName),
            URLQueryItem(name: "region_name", value: school.regionName),
            URLQueryItem(name: "school_code", value: school.schoolCode),
            URLQueryItem(name: "grade", value: grade),
            URLQueryItem(name: "class_num", value: classNum),
            URLQueryItem(name: "target_date", value: targetDate)
        ]

        guard let url = components.url else { return }
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let data else {
                DispatchQueue.main.async {
                    self.timetableMessage = "컴시간 시간표를 불러오지 못했습니다."
                    self.timetableRawJSON = ""
                    self.timetables = []
                }
                return
            }

            let raw = String(data: data, encoding: .utf8) ?? ""
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200

            do {
                if statusCode >= 400 {
                    let errorResponse = try JSONDecoder().decode(ComciErrorResponse.self, from: data)
                    DispatchQueue.main.async {
                        self.timetableRawJSON = raw
                        self.timetableMessage = errorResponse.message
                        self.timetables = []
                    }
                    return
                }

                let decoded = try JSONDecoder().decode(ComciVerifyResponse.self, from: data)
                let weekStart = self.startOfWeekISODate(for: self.selectedDate)
                let cacheKey = self.comciWeeklyCacheKey(for: school, grade: self.grade, classNum: self.classNum, date: self.selectedDate)
                let cacheEntry = ComciWeeklyCacheEntry(
                    schoolCode: school.schoolCode,
                    schoolName: school.schoolName,
                    regionName: school.regionName,
                    grade: self.grade,
                    classNum: self.classNum,
                    weekStart: weekStart,
                    fetchedAt: ISO8601DateFormatter().string(from: Date()),
                    weeklyGrid: decoded.weekly_grid
                )

                DispatchQueue.main.async {
                    self.comciWeeklyCache[cacheKey] = cacheEntry
                    self.saveComciWeeklyCache()
                    self.timetableRawJSON = raw
                    self.applyComciWeeklyCache(cacheEntry, school: school)
                }
            } catch {
                DispatchQueue.main.async {
                    self.timetableRawJSON = raw
                    self.timetableMessage = "컴시간 시간표를 해석하지 못했습니다."
                    self.timetables = []
                }
            }
        }.resume()
    }

    private func resolveComciSchoolMapping(completion: @escaping (Result<ComciResolvedSchool, Error>) -> Void) {
        let resolvedSchoolName = comciMappedSchoolName.isEmpty ? schoolName : comciMappedSchoolName

        if !comciSchoolCode.isEmpty {
            completion(.success(ComciResolvedSchool(
                schoolCode: comciSchoolCode,
                schoolName: resolvedSchoolName,
                regionName: comciRegionName.isEmpty ? fallbackComciRegionName() : comciRegionName
            )))
            return
        }

        guard var components = URLComponents(string: "\(comciRelayBaseURL)/schools/search") else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "컴시간 학교 검색 URL을 만들지 못했습니다."])))
            return
        }
        components.queryItems = [URLQueryItem(name: "q", value: resolvedSchoolName)]

        guard let url = components.url else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "컴시간 학교 검색 URL을 만들지 못했습니다."])))
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "컴시간 학교 검색 응답이 없습니다."])))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ComciSchoolSearchResponse.self, from: data)
                let region = self.fallbackComciRegionName()
                guard let match = self.findBestComciSchoolMatch(
                    schools: decoded.schools,
                    requestedSchoolName: self.schoolName,
                    resolvedSchoolName: resolvedSchoolName,
                    region: region
                ) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "컴시간에서 현재 학교를 찾지 못했습니다."])
                }

                DispatchQueue.main.async {
                    self.comciSchoolCode = match.school_code
                    self.comciMappedSchoolName = match.school_name
                    self.comciRegionName = match.region_name
                }

                completion(.success(ComciResolvedSchool(
                    schoolCode: match.school_code,
                    schoolName: match.school_name,
                    regionName: match.region_name
                )))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func normalizeComciSubject(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return trimmed.replacingOccurrences(of: "_", with: ".")
    }

    private func comciWeeklyCacheKey(for school: ComciResolvedSchool, grade: String, classNum: String, date: Date) -> String {
        let weekStart = startOfWeekISODate(for: date)
        return "comci|\(school.schoolCode)|G\(grade)|C\(classNum)|W\(weekStart)"
    }

    private func startOfWeekISODate(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.firstWeekday = 2
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return isoDateString(from: weekStart)
    }

    private func weekdayIndexForSelectedDate() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return max(0, calendar.component(.weekday, from: selectedDate) - 2)
    }

    private func applyComciWeeklyCache(_ cacheEntry: ComciWeeklyCacheEntry, school: ComciResolvedSchool) {
        let weekdayIndex = weekdayIndexForSelectedDate()
        let periods = cacheEntry.weeklyGrid.first(where: { $0.weekday_index == weekdayIndex })?.periods ?? []
        let rows = periods.compactMap { period -> TimetableRow? in
            let subject = normalizeComciSubject(period.subject)
            guard !subject.isEmpty else { return nil }
            return TimetableRow(
                ALL_TI_YMD: getApiDateString(),
                GRADE: cacheEntry.grade,
                CLASS_NM: cacheEntry.classNum,
                PERIO: String(period.period),
                ITRT_CNTNT: subject,
                SOURCE_KIND: TimetableSource.comci.rawValue,
                SOURCE_SCHOOL_ID: school.schoolCode
            )
        }

        timetableMessage = rows.isEmpty ? "컴시간 시간표 데이터가 비어 있습니다." : nil
        timetables = rows.sorted {
            (Int($0.PERIO ?? "0") ?? 0) < (Int($1.PERIO ?? "0") ?? 0)
        }
    }

    private func findBestComciSchoolMatch(
        schools: [ComciSchool],
        requestedSchoolName: String,
        resolvedSchoolName: String,
        region: String
    ) -> ComciSchool? {
        let exactRegionMatchers = [
            resolvedSchoolName,
            requestedSchoolName
        ]

        for name in exactRegionMatchers {
            if let match = schools.first(where: { $0.school_name == name && ($0.region_name == region || region.isEmpty) }) {
                return match
            }
        }

        for name in exactRegionMatchers {
            if let match = schools.first(where: { $0.school_name == name }) {
                return match
            }
        }

        let normalizedRequested = normalizeSchoolNameForComciMatch(requestedSchoolName)
        let normalizedResolved = normalizeSchoolNameForComciMatch(resolvedSchoolName)

        if let match = schools.first(where: {
            let normalizedCandidate = normalizeSchoolNameForComciMatch($0.school_name)
            let sameRegion = $0.region_name == region || region.isEmpty
            return sameRegion && (
                normalizedCandidate == normalizedRequested ||
                normalizedCandidate == normalizedResolved ||
                normalizedCandidate.contains(normalizedRequested) ||
                normalizedCandidate.contains(normalizedResolved) ||
                normalizedRequested.contains(normalizedCandidate) ||
                normalizedResolved.contains(normalizedCandidate)
            )
        }) {
            return match
        }

        if schools.count == 1 {
            return schools.first
        }

        return nil
    }

    private func normalizeSchoolNameForComciMatch(_ name: String) -> String {
        name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "중학교", with: "중")
            .replacingOccurrences(of: "고등학교", with: "고")
            .replacingOccurrences(of: "초등학교", with: "초")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func fallbackComciRegionName() -> String {
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
        "\(SOURCE_KIND ?? TimetableSource.neis.rawValue)|\(SOURCE_SCHOOL_ID ?? "")|\(ALL_TI_YMD ?? "")\(GRADE ?? "")\(CLASS_NM ?? "")\(PERIO ?? "")"
    }
    let ALL_TI_YMD: String?
    let GRADE: String?
    let CLASS_NM: String?
    let PERIO: String?
    let ITRT_CNTNT: String?
    let SOURCE_KIND: String?
    let SOURCE_SCHOOL_ID: String?
}

struct ComciResolvedSchool {
    let schoolCode: String
    let schoolName: String
    let regionName: String
}

struct ComciSchoolSearchResponse: Decodable {
    let schools: [ComciSchool]
}

struct ComciSchool: Decodable {
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
}

struct ComciVerifyResponse: Decodable {
    let request: ComciVerifyRequest
    let daily_subjects: [ComciPeriod]
    let weekly_grid: [ComciWeeklyDay]
}

struct ComciVerifyRequest: Decodable {
    let target_date: String
}

struct ComciPeriod: Codable {
    let period: Int
    let subject: String
}

struct ComciWeeklyDay: Codable {
    let weekday_index: Int
    let weekday_name_ko: String
    let periods: [ComciPeriod]
}

struct ComciWeeklyCacheEntry: Codable {
    let schoolCode: String
    let schoolName: String
    let regionName: String
    let grade: String
    let classNum: String
    let weekStart: String
    let fetchedAt: String
    let weeklyGrid: [ComciWeeklyDay]

    var fetchedAtDate: Date {
        ISO8601DateFormatter().date(from: fetchedAt) ?? .distantPast
    }
}

struct ComciErrorResponse: Decodable {
    let message: String
}

struct TimetableEditExportPayload: Codable {
    let version: Int
    let exportedAt: String
    let scope: TimetableEditExportScope
    let dateEdits: [String: String]
    let weeklyEdits: [String: String]
    let replaceRules: [String: String]
}

struct TimetableEditExportScope: Codable {
    let source: String
    let schoolIdentifier: String
    let schoolName: String
    let grade: String
    let classNum: String
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

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
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
