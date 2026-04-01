import Foundation
import SwiftUI
import WidgetKit
import WatchConnectivity
import UserNotifications
import UIKit

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

    @AppStorage("timetableExtraPeriodsJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableExtraPeriodsJSON: String = "{}"

    @AppStorage("timetableCommentsJSON", store: AppGroupManager.shared.sharedDefaults)
    private var timetableCommentsJSON: String = "{}"

    @AppStorage("commentReminderHour", store: AppGroupManager.shared.sharedDefaults)
    var commentReminderHour: Int = 19

    @AppStorage("commentReminderMinute", store: AppGroupManager.shared.sharedDefaults)
    var commentReminderMinute: Int = 0

    @AppStorage("savedComciSchoolCode", store: AppGroupManager.shared.sharedDefaults)
    private var comciSchoolCode: String = ""

    @AppStorage("savedComciMappedSchoolName", store: AppGroupManager.shared.sharedDefaults)
    private var comciMappedSchoolName: String = ""

    @AppStorage("savedComciRegionName", store: AppGroupManager.shared.sharedDefaults)
    private var comciRegionName: String = ""

    @AppStorage("comciWeeklyTimetableCacheJSON", store: AppGroupManager.shared.sharedDefaults)
    private var comciWeeklyTimetableCacheJSON: String = "{}"

    @AppStorage("syncServerURL", store: AppGroupManager.shared.sharedDefaults)
    var syncServerURL: String = ""

    @AppStorage("syncSpaceKey", store: AppGroupManager.shared.sharedDefaults)
    var syncSpaceKey: String = ""

    @AppStorage("syncServerVersion", store: AppGroupManager.shared.sharedDefaults)
    private var syncServerVersion: Int = 0

    @AppStorage("syncLocalModifiedAt", store: AppGroupManager.shared.sharedDefaults)
    private var syncLocalModifiedAt: String = ""

    @AppStorage("syncLastSyncedAt", store: AppGroupManager.shared.sharedDefaults)
    private var syncLastSyncedAt: String = ""

    @AppStorage("syncBootstrapCreatorDeviceName", store: AppGroupManager.shared.sharedDefaults)
    private var syncBootstrapCreatorDeviceNameStorage: String = ""

    @AppStorage("syncBootstrapCreatedAt", store: AppGroupManager.shared.sharedDefaults)
    private var syncBootstrapCreatedAtStorage: String = ""

    @Published private(set) var replaceRules: [String: String] = [:]


    @Published private(set) var timetableDateEdits: [String: String] = [:]
    @Published private(set) var timetableWeeklyEdits: [String: String] = [:]
    @Published private(set) var timetableExtraPeriods: [String: Int] = [:]
    @Published private(set) var timetableComments: [String: TimetableComment] = [:]
    @Published var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var syncStatusMessage: String? = nil
    @Published var syncInProgress: Bool = false

    private let apiKey = "b22e0d13ad8e49179c4d37cff6aed382"
    private let comciRelayBaseURL = "https://comci-direct-server.vercel.app"
    private let embeddedSyncServerURL = "https://schoollife-sync.minwestt.workers.dev"
    private var watchSession: WCSession?
    private var comciWeeklyCache: [String: ComciWeeklyCacheEntry] = [:]
    private var syncTimer: Timer?
    private var pendingSyncWorkItem: DispatchWorkItem?
    private var lastObservedSyncSignature: String = ""
    private var isApplyingRemoteSyncPayload = false
    private var fastSyncUntil: Date?

    private let replaceRuleMarker = "|SUBJECT|"
    private let comciWeeklyCacheMaxEntries = 24
    private let comciWeeklyCacheFreshHours: TimeInterval = 6 * 60 * 60
    private let normalSyncInterval: TimeInterval = 20
    private let fastSyncInterval: TimeInterval = 3
    private let fastSyncWindow: TimeInterval = 10
    var timetableSource: TimetableSource {
        get { TimetableSource(rawValue: timetableSourceRawValue) ?? .neis }
        set {
            timetableSourceRawValue = newValue.rawValue
            WidgetCenter.shared.reloadTimelines(ofKind: "TimetableWidget")
            objectWillChange.send()
            noteLocalSyncMutation()
        }
    }

    override init() {
        super.init()
        configureWatchSession()
        loadTimetableEditsIfNeeded()
        loadTimetableExtrasIfNeeded()
        loadTimetableCommentsIfNeeded()
        loadComciWeeklyCacheIfNeeded()
        refreshNotificationAuthorizationStatus()
        configureSyncLifecycleObservers()
        lastObservedSyncSignature = currentSyncPayloadSignature()
        startSyncLoopIfNeeded()
        queueSyncCycle(delay: 1.5)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        invalidateSyncLoop()
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

    func apiDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
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

    private func loadTimetableExtrasIfNeeded() {
        if let d = timetableExtraPeriodsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: d) {
            timetableExtraPeriods = decoded
        } else {
            timetableExtraPeriods = [:]
        }
    }

    private func loadTimetableCommentsIfNeeded() {
        if let d = timetableCommentsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: TimetableComment].self, from: d) {
            timetableComments = decoded
        } else {
            timetableComments = [:]
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
        noteLocalSyncMutation()
    }

    private func saveTimetableExtras() {
        if let data = try? JSONEncoder().encode(timetableExtraPeriods),
           let json = String(data: data, encoding: .utf8) {
            timetableExtraPeriodsJSON = json
        }
        objectWillChange.send()
        noteLocalSyncMutation()
    }

    private func saveTimetableComments() {
        if let data = try? JSONEncoder().encode(timetableComments),
           let json = String(data: data, encoding: .utf8) {
            timetableCommentsJSON = json
        }
        objectWillChange.send()
        // applyRemoteSyncEnvelope 실행 중에는 mutation으로 처리하지 않음.
        // (서버 데이터 적용 도중 loadTimetableCommentsIfNeeded가 호출되면서
        //  이 함수가 간접적으로 불릴 경우를 방어)
        guard !isApplyingRemoteSyncPayload else { return }
        noteLocalSyncMutation()
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

        let original = (row.ITRT_CNTNT ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return original.isEmpty ? "빈 시간표" : original
    }

    func editableText(for row: TimetableRow) -> String {
        let dk = dateEditKey(for: row)
        if let edited = timetableDateEdits[dk] {
            return edited
        }

        let wk = weeklyEditKey(for: row)
        if let edited = timetableWeeklyEdits[wk] {
            return edited
        }

        let replaceKey = replaceRuleKey(for: row)
        if let replaced = replaceRules[replaceKey] {
            return replaced
        }

        return row.ITRT_CNTNT ?? ""
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

    private func timetableSlotScopeKey(for date: String, grade: String, classNum: String) -> String {
        "\(currentDateWeeklySchoolIdentifier())|\(date)|\(grade)|\(classNum)"
    }

    private func timetableSlotScopeKey(for row: TimetableRow) -> String {
        let date = row.ALL_TI_YMD ?? getApiDateString()
        let rowGrade = row.GRADE ?? grade
        let rowClass = row.CLASS_NM ?? classNum
        return "\(rowSchoolIdentifier(for: row))|\(date)|\(rowGrade)|\(rowClass)"
    }

    private func timetableCommentKey(for row: TimetableRow) -> String {
        "\(timetableSlotScopeKey(for: row))|\(row.PERIO ?? "0")"
    }

    func timetableComment(for row: TimetableRow) -> TimetableComment? {
        timetableComments[timetableCommentKey(for: row)]
    }

    func setTimetableComment(text: String, reminderEnabled: Bool, for row: TimetableRow) {
        let key = timetableCommentKey(for: row)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            clearTimetableComment(for: row)
            return
        }

        let comment = TimetableComment(
            text: trimmed,
            reminderEnabled: reminderEnabled,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        timetableComments[key] = comment
        saveTimetableComments()
        scheduleCommentNotificationIfNeeded(for: row, comment: comment)
    }

    func clearTimetableComment(for row: TimetableRow) {
        let key = timetableCommentKey(for: row)
        timetableComments.removeValue(forKey: key)
        saveTimetableComments()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [commentNotificationIdentifier(for: key)])
    }

    func addEmptyTimetablePeriodIfPossible() {
        guard canAddEmptyTimetablePeriod else { return }
        let key = timetableSlotScopeKey(for: getApiDateString(), grade: grade, classNum: classNum)
        timetableExtraPeriods[key] = 7
        saveTimetableExtras()
    }

    var canAddEmptyTimetablePeriod: Bool {
        guard !isWeekend(selectedDate) else { return false }
        guard timetables.isEmpty else { return false }
        return timetableSlots().count == 6
    }

    func timetableSlots() -> [TimetableSlot] {
        guard !isWeekend(selectedDate) else { return [] }

        let selectedDateString = getApiDateString()
        let scopeKey = timetableSlotScopeKey(for: selectedDateString, grade: grade, classNum: classNum)
        let apiRowsByPeriod = Dictionary(grouping: timetables) { Int($0.PERIO ?? "0") ?? 0 }
        let maxAPI = apiRowsByPeriod.keys.max() ?? 0
        let maxExtra = timetableExtraPeriods[scopeKey] ?? 0
        let slotCount = max(6, maxAPI, maxExtra)

        return (1...slotCount).map { period in
            let row = apiRowsByPeriod[period]?.first ?? placeholderRow(for: period)
            let key = timetableCommentKey(for: row)
            return TimetableSlot(
                row: row,
                displayText: displayText(for: row),
                comment: timetableComments[key],
                isPlaceholder: (row.ITRT_CNTNT ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private func placeholderRow(for period: Int) -> TimetableRow {
        TimetableRow(
            ALL_TI_YMD: getApiDateString(),
            GRADE: grade,
            CLASS_NM: classNum,
            PERIO: String(period),
            ITRT_CNTNT: nil,
            SOURCE_KIND: timetableSource.rawValue,
            SOURCE_SCHOOL_ID: timetableSource == .comci ? currentTimetableSchoolIdentifier() : nil
        )
    }

    func commentReminderTimeText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: reminderTimeDate())
    }

    func reminderTimeDate() -> Date {
        var components = DateComponents()
        components.hour = commentReminderHour
        components.minute = commentReminderMinute
        return Calendar.current.date(from: components) ?? Date()
    }

    func updateCommentReminderTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        commentReminderHour = components.hour ?? 19
        commentReminderMinute = components.minute ?? 0
        rescheduleAllCommentNotifications()
        noteLocalSyncMutation()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            self.refreshNotificationAuthorizationStatus()
            self.rescheduleAllCommentNotifications()
        }
    }

    func refreshNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationAuthorizationStatus = settings.authorizationStatus
            }
        }
    }

    func rescheduleAllCommentNotifications() {
        for (key, comment) in timetableComments {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [commentNotificationIdentifier(for: key)])
            guard comment.reminderEnabled else { continue }
            guard let row = rowFromCommentKey(key) else { continue }
            scheduleCommentNotificationIfNeeded(for: row, comment: comment)
        }
    }

    private func rowFromCommentKey(_ key: String) -> TimetableRow? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        let period = parts.last ?? ""
        let rowClass = parts[parts.count - 2]
        let rowGrade = parts[parts.count - 3]
        let date = parts[parts.count - 4]
        let schoolIdentifier = parts.dropLast(4).joined(separator: "|")

        let sourceKind: String
        let sourceSchoolID: String?
        if schoolIdentifier.hasPrefix("comci|") {
            sourceKind = TimetableSource.comci.rawValue
            sourceSchoolID = String(schoolIdentifier.dropFirst("comci|".count))
        } else {
            sourceKind = TimetableSource.neis.rawValue
            sourceSchoolID = nil
        }

        let subject = timetables.first(where: { $0.PERIO == period })?.ITRT_CNTNT

        return TimetableRow(
            ALL_TI_YMD: date,
            GRADE: rowGrade,
            CLASS_NM: rowClass,
            PERIO: period,
            ITRT_CNTNT: subject,
            SOURCE_KIND: sourceKind,
            SOURCE_SCHOOL_ID: sourceSchoolID
        )
    }

    private func scheduleCommentNotificationIfNeeded(for row: TimetableRow, comment: TimetableComment) {
        let key = timetableCommentKey(for: row)
        let identifier = commentNotificationIdentifier(for: key)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard comment.reminderEnabled else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            guard let triggerDate = self.commentNotificationDate(for: row), triggerDate > Date() else { return }

            let content = UNMutableNotificationContent()
            let subject = self.displayText(for: row)
            let dateText = self.notificationDateText(for: row.ALL_TI_YMD ?? self.getApiDateString())
            content.title = "\(dateText) \(row.PERIO ?? "?")교시 알림"
            content.body = "\(subject)\n\(comment.text)"
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func commentNotificationIdentifier(for key: String) -> String {
        "timetable-comment-\(key)"
    }

    private func commentNotificationDate(for row: TimetableRow) -> Date? {
        guard let dateString = row.ALL_TI_YMD,
              let eventDate = dateFromAPIString(dateString),
              let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: eventDate) else {
            return nil
        }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: previousDay)
        components.hour = commentReminderHour
        components.minute = commentReminderMinute
        return Calendar.current.date(from: components)
    }

    private func notificationDateText(for dateString: String) -> String {
        guard let date = dateFromAPIString(dateString) else { return dateString }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

    private func dateFromAPIString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: dateString)
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
            self.noteLocalSyncMutation()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private func configureSyncLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func handleSyncDidBecomeActive() {
        startSyncLoopIfNeeded()
        queueSyncCycle(delay: 0.5)
    }

    @objc private func handleSyncDidEnterBackground() {
        invalidateSyncLoop()
    }

    private func startSyncLoopIfNeeded() {
        guard syncTimer == nil else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: currentSyncInterval, repeats: true) { [weak self] _ in
            self?.performAutomaticSyncIfNeeded()
        }
        if let syncTimer {
            RunLoop.main.add(syncTimer, forMode: .common)
        }
    }

    private func invalidateSyncLoop() {
        syncTimer?.invalidate()
        syncTimer = nil
        pendingSyncWorkItem?.cancel()
        pendingSyncWorkItem = nil
    }

    private func queueSyncCycle(delay: TimeInterval = 0.8) {
        guard hasSyncConfiguration else { return }
        pendingSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performAutomaticSyncIfNeeded()
        }
        pendingSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func noteLocalSyncMutation() {
        guard !isApplyingRemoteSyncPayload else { return }
        syncLocalModifiedAt = isoTimestamp()
        activateFastSyncWindow()
        if syncInProgress {
            queueSyncCycle()
        } else {
            performAutomaticSyncIfNeeded()
        }
    }

    private var currentSyncInterval: TimeInterval {
        guard let fastSyncUntil else { return normalSyncInterval }
        return fastSyncUntil > Date() ? fastSyncInterval : normalSyncInterval
    }

    private func activateFastSyncWindow() {
        fastSyncUntil = Date().addingTimeInterval(fastSyncWindow)
        restartSyncLoop()
    }

    private func refreshSyncLoopIfNeeded() {
        guard syncTimer != nil else { return }
        if currentSyncInterval != syncTimer?.timeInterval {
            restartSyncLoop()
        }
    }

    private func restartSyncLoop() {
        invalidateSyncLoop()
        startSyncLoopIfNeeded()
    }

    var hasSyncConfiguration: Bool {
        !effectiveSyncServerURL.isEmpty && !effectiveSyncSpaceKey.isEmpty
    }

    var effectiveSyncServerURL: String {
        let configured = normalizedSyncServerURL(syncServerURL)
        return configured.isEmpty ? embeddedSyncServerURL : configured
    }

    var effectiveSyncSpaceKey: String {
        syncSpaceKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var bootstrapCreatorDescription: String {
        guard !syncBootstrapCreatorDeviceNameStorage.isEmpty else { return "아직 없음" }
        if let date = ISO8601DateFormatter().date(from: syncBootstrapCreatedAtStorage) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "M/d a h:mm"
            return "\(syncBootstrapCreatorDeviceNameStorage) · \(formatter.string(from: date))"
        }
        return syncBootstrapCreatorDeviceNameStorage
    }

    var syncLastSyncedDescription: String {
        guard !syncLastSyncedAt.isEmpty,
              let date = ISO8601DateFormatter().date(from: syncLastSyncedAt) else {
            return "아직 없음"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d a h:mm:ss"
        return formatter.string(from: date)
    }

    func disconnectSync() {
        syncSpaceKey = ""
        syncServerVersion = 0
        syncLastSyncedAt = ""
        syncStatusMessage = "저장된 동기화 키를 지웠습니다."
    }

    func createOrGetBootstrapSyncSpace(completion: @escaping (Result<String, Error>) -> Void) {
        let serverURL = effectiveSyncServerURL
        let body = SyncCreateRequest(
            deviceName: currentDeviceName(),
            clientModifiedAt: currentSyncModifiedAt(),
            payload: currentSyncPayload()
        )

        requestSync(
            path: "/api/bootstrap/create-or-get",
            serverURL: serverURL,
            body: body,
            expecting: SyncBootstrapResponse.self
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.applyBootstrapResponse(response, serverURL: serverURL)
                    self.pullLatestSync(forceApply: true) { pullResult in
                        switch pullResult {
                        case .success:
                            completion(.success(response.syncKey))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                case .failure(let error):
                    self.syncStatusMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    func fetchBootstrapSyncSpace(completion: @escaping (Result<String, Error>) -> Void) {
        let serverURL = effectiveSyncServerURL
        requestSync(
            path: "/api/bootstrap/current",
            serverURL: serverURL,
            expecting: SyncBootstrapResponse.self
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.applyBootstrapResponse(response, serverURL: serverURL)
                    self.pullLatestSync(forceApply: true) { pullResult in
                        switch pullResult {
                        case .success:
                            completion(.success(response.syncKey))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                case .failure(let error):
                    self.syncStatusMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    func createSyncSpace(completion: @escaping (Result<String, Error>) -> Void) {
        let serverURL = normalizedSyncServerURL(syncServerURL)
        guard !serverURL.isEmpty else {
            completion(.failure(syncError("서버 URL을 먼저 입력하세요.")))
            return
        }

        let payload = currentSyncPayload()
        let body = SyncCreateRequest(
            deviceName: currentDeviceName(),
            clientModifiedAt: currentSyncModifiedAt(),
            payload: payload
        )

        requestSync(
            path: "/api/sync/create",
            serverURL: serverURL,
            body: body,
            expecting: SyncCreateResponse.self
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.syncServerURL = serverURL
                    self.syncSpaceKey = response.syncKey
                    self.syncServerVersion = response.version
                    self.syncLastSyncedAt = response.updatedAt
                    self.lastObservedSyncSignature = self.currentSyncPayloadSignature()
                    self.syncStatusMessage = "새 동기화 키를 만들었습니다."
                    completion(.success(response.syncKey))
                case .failure(let error):
                    self.syncStatusMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    func connectSyncSpace(completion: @escaping (Result<String, Error>) -> Void) {
        let serverURL = normalizedSyncServerURL(syncServerURL)
        let key = syncSpaceKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !serverURL.isEmpty else {
            completion(.failure(syncError("서버 URL을 입력하세요.")))
            return
        }
        guard !key.isEmpty else {
            completion(.failure(syncError("동기화 키를 입력하세요.")))
            return
        }

        syncServerURL = serverURL
        syncSpaceKey = key
        pullLatestSync(forceApply: true) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.syncStatusMessage = "동기화 서버에 연결했습니다."
                    completion(.success("연결 완료"))
                case .failure(let error):
                    self.syncStatusMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    func syncNow(completion: @escaping (Result<String, Error>) -> Void) {
        performAutomaticSyncIfNeeded(manual: true, completion: completion)
    }

    func markSyncRelevantSettingChanged() {
        noteLocalSyncMutation()
    }

    @MainActor
    func refreshTimetableManually() async {
        await withCheckedContinuation { continuation in
            syncNow { _ in
                continuation.resume()
            }
        }
        fetchAll()
    }

    private func performAutomaticSyncIfNeeded(manual: Bool = false, completion: ((Result<String, Error>) -> Void)? = nil) {
        if let fastSyncUntil, fastSyncUntil <= Date() {
            self.fastSyncUntil = nil
            refreshSyncLoopIfNeeded()
        }

        if effectiveSyncSpaceKey.isEmpty {
            fetchBootstrapSyncSpace { result in
                switch result {
                case .success:
                    self.performAutomaticSyncIfNeeded(manual: manual, completion: completion)
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
            return
        }
        guard !syncInProgress else {
            completion?(.success("동기화 진행 중"))
            return
        }

        if hasPendingLocalSyncChange {
            // 단, 서버 버전을 모르는(= 처음 연결) 경우는 pull 먼저
            if syncServerVersion == 0 {
                pullLatestSync(forceApply: true, completion: completion)
            } else {
                pushCurrentSyncPayload(completion: completion)
            }
        } else {
            pullLatestSync(forceApply: manual, completion: completion)
        }
    }

    private func pushCurrentSyncPayload(completion: ((Result<String, Error>) -> Void)? = nil) {
        let serverURL = effectiveSyncServerURL
        let key = effectiveSyncSpaceKey
        guard !serverURL.isEmpty, !key.isEmpty else {
            completion?(.failure(syncError("동기화 설정이 비어 있습니다.")))
            return
        }

        syncInProgress = true
        let body = SyncPushRequest(
            syncKey: key,
            clientKnownVersion: syncServerVersion,
            clientModifiedAt: currentSyncModifiedAt(),
            deviceName: currentDeviceName(),
            payload: currentSyncPayload()
        )

        requestSync(
            path: "/api/sync/push",
            serverURL: serverURL,
            body: body,
            expecting: SyncEnvelope.self
        ) { result in
            DispatchQueue.main.async {
                self.syncInProgress = false
                switch result {
                case .success(let envelope):
                    self.applyPushEnvelope(envelope)
                    completion?(.success("업로드 완료"))
                case .failure(let error):
                    self.syncStatusMessage = error.localizedDescription
                    completion?(.failure(error))
                }
            }
        }
    }

    private func pullLatestSync(forceApply: Bool = false, completion: ((Result<String, Error>) -> Void)? = nil) {
        let serverURL = effectiveSyncServerURL
        let key = effectiveSyncSpaceKey
        guard !serverURL.isEmpty, !key.isEmpty else {
            completion?(.failure(syncError("동기화 설정이 비어 있습니다.")))
            return
        }

        syncInProgress = true
        let body = SyncPullRequest(syncKey: key, knownVersion: syncServerVersion)

        requestSync(
            path: "/api/sync/pull",
            serverURL: serverURL,
            body: body,
            expecting: SyncEnvelope.self
        ) { result in
            DispatchQueue.main.async {
                self.syncInProgress = false
                switch result {
                case .success(let envelope):
                    let remoteSignature = self.signature(for: envelope.payload)
                    let remoteIsNewerThanLocal = self.isTimestamp(envelope.updatedAt, newerThan: self.currentSyncModifiedAt())
                    let payloadDiffers = remoteSignature != self.currentSyncPayloadSignature()
                    let shouldApply = forceApply
                        || envelope.version != self.syncServerVersion
                        || (payloadDiffers && !self.hasPendingLocalSyncChange)


                    if shouldApply {
                        self.applyRemoteSyncEnvelope(envelope)
                    } else if payloadDiffers && self.hasPendingLocalSyncChange {
                        self.pushCurrentSyncPayload(completion: completion)
                        return
                    } else {
                        self.syncServerVersion = envelope.version
                        self.syncLastSyncedAt = envelope.updatedAt
                        self.syncStatusMessage = "최신 상태입니다."
                    }
                    completion?(.success("가져오기 완료"))
                case .failure(let error):
                    self.syncStatusMessage = error.localizedDescription
                    completion?(.failure(error))
                }
            }
        }
    }

    private func applyPushEnvelope(_ envelope: SyncEnvelope) {
        let remoteSignature = signature(for: envelope.payload)
        if remoteSignature != currentSyncPayloadSignature() {
            applyRemoteSyncEnvelope(envelope)
            return
        }
        syncLocalModifiedAt = envelope.updatedAt
        syncServerVersion = envelope.version
        syncLastSyncedAt = envelope.updatedAt
        syncStatusMessage = "동기화를 완료했습니다."
        lastObservedSyncSignature = remoteSignature
    }

    private func applyRemoteSyncEnvelope(_ envelope: SyncEnvelope) {
        isApplyingRemoteSyncPayload = true
        let payload = envelope.payload

        officeCode = payload.officeCode
        schoolCode = payload.schoolCode
        schoolName = payload.schoolName
        grade = payload.grade
        classNum = payload.classNum
        timetableSourceRawValue = payload.timetableSourceRawValue
        comciSchoolCode = payload.comciSchoolCode
        comciMappedSchoolName = payload.comciMappedSchoolName
        comciRegionName = payload.comciRegionName
        timetableDateEditsJSON = payload.timetableDateEditsJSON
        timetableWeeklyEditsJSON = payload.timetableWeeklyEditsJSON
        timetableReplaceRulesJSON = payload.timetableReplaceRulesJSON
        timetableExtraPeriodsJSON = payload.timetableExtraPeriodsJSON
        timetableCommentsJSON = payload.timetableCommentsJSON
        commentReminderHour = payload.commentReminderHour
        commentReminderMinute = payload.commentReminderMinute
        syncLocalModifiedAt = envelope.updatedAt
        syncServerVersion = envelope.version
        syncLastSyncedAt = envelope.updatedAt

        loadTimetableEditsIfNeeded()
        loadTimetableExtrasIfNeeded()
        loadTimetableCommentsIfNeeded()
        rescheduleAllCommentNotifications()
        syncWatchContext()
        fetchAll()
        WidgetCenter.shared.reloadAllTimelines()

        syncStatusMessage = "다른 기기의 변경사항을 가져왔습니다."
        isApplyingRemoteSyncPayload = false
        objectWillChange.send()

        // @AppStorage 쓰기가 UserDefaults에 완전히 커밋된 뒤
        // signature를 재계산해야 hasPendingLocalSyncChange가 오탐되지 않음.
        // 즉시 activateFastSyncWindow를 호출하면 @AppStorage 커밋 전에
        // currentSyncPayload()가 이전 값을 읽어 불필요한 push가 발생함.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastObservedSyncSignature = self.currentSyncPayloadSignature()
            self.activateFastSyncWindow()
        }
    }

    private func currentSyncPayload() -> TimetableSyncPayload {
        TimetableSyncPayload(
            officeCode: officeCode,
            schoolCode: schoolCode,
            schoolName: schoolName,
            grade: grade,
            classNum: classNum,
            timetableSourceRawValue: timetableSourceRawValue,
            comciSchoolCode: comciSchoolCode,
            comciMappedSchoolName: comciMappedSchoolName,
            comciRegionName: comciRegionName,
            timetableDateEditsJSON: timetableDateEditsJSON,
            timetableWeeklyEditsJSON: timetableWeeklyEditsJSON,
            timetableReplaceRulesJSON: timetableReplaceRulesJSON,
            timetableExtraPeriodsJSON: timetableExtraPeriodsJSON,
            timetableCommentsJSON: timetableCommentsJSON,
            commentReminderHour: commentReminderHour,
            commentReminderMinute: commentReminderMinute
        )
    }

    private func currentSyncPayloadSignature() -> String {
        signature(for: currentSyncPayload())
    }

    private var hasPendingLocalSyncChange: Bool {
        guard !isApplyingRemoteSyncPayload else { return false }

        return currentSyncPayloadSignature() != lastObservedSyncSignature
    }

    private func signature(for payload: TimetableSyncPayload) -> String {
        let encoder = JSONEncoder.prettyPrinted
        guard let data = try? encoder.encode(payload) else { return "" }
        return data.base64EncodedString()
    }

    private func currentSyncModifiedAt() -> String {
        if syncLocalModifiedAt.isEmpty {
            syncLocalModifiedAt = isoTimestamp()
        }
        return syncLocalModifiedAt
    }

    private func currentDeviceName() -> String {
        UIDevice.current.name
    }

    private func applyBootstrapResponse(_ response: SyncBootstrapResponse, serverURL: String) {
        syncServerURL = serverURL
        syncSpaceKey = response.syncKey
        syncBootstrapCreatorDeviceNameStorage = response.creatorDeviceName
        syncBootstrapCreatedAtStorage = response.createdAt
        syncStatusMessage = "동기화 키를 불러왔습니다."
    }

    private func normalizedSyncServerURL(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func isTimestamp(_ lhs: String, newerThan rhs: String) -> Bool {
        guard let lhsDate = parseSyncTimestamp(lhs) else { return false }
        guard let rhsDate = parseSyncTimestamp(rhs) else { return true }
        return lhsDate > rhsDate
    }

    private func parseSyncTimestamp(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func syncError(_ message: String) -> NSError {
        NSError(domain: "SchoolLifeSync", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func requestSync<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        serverURL: String,
        body: RequestBody,
        expecting: ResponseBody.Type,
        completion: @escaping (Result<ResponseBody, Error>) -> Void
    ) {
        guard let url = URL(string: serverURL + path) else {
            completion(.failure(syncError("서버 URL 형식이 올바르지 않습니다.")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data else {
                completion(.failure(self.syncError("서버 응답을 읽지 못했습니다.")))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let errorResponse = try? JSONDecoder().decode(SyncErrorResponse.self, from: data) {
                    completion(.failure(self.syncError(errorResponse.error)))
                } else {
                    completion(.failure(self.syncError("동기화 서버 오류 (\(httpResponse.statusCode))")))
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func requestSync<ResponseBody: Decodable>(
        path: String,
        serverURL: String,
        expecting: ResponseBody.Type,
        completion: @escaping (Result<ResponseBody, Error>) -> Void
    ) {
        guard let url = URL(string: serverURL + path) else {
            completion(.failure(syncError("서버 URL 형식이 올바르지 않습니다.")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data else {
                completion(.failure(self.syncError("서버 응답을 읽지 못했습니다.")))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let errorResponse = try? JSONDecoder().decode(SyncErrorResponse.self, from: data) {
                    completion(.failure(self.syncError(errorResponse.error)))
                } else {
                    completion(.failure(self.syncError("동기화 서버 오류 (\(httpResponse.statusCode))")))
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func fetchAll() {
        fetchMeal()
        fetchTimetable()
        fetchSchedule()          // ▶ 학사일정도 함께 불러옴
    }

    func fetchMeal() {
        guard !schoolCode.isEmpty else { return }

        let today = Calendar.current.startOfDay(for: Date())
        guard let endDate = Calendar.current.date(byAdding: .day, value: 3, to: today) else { return }

        let urlString =
        "https://open.neis.go.kr/hub/mealServiceDietInfo?KEY=\(apiKey)&Type=json&ATPT_OFCDC_SC_CODE=\(officeCode)&SD_SCHUL_CODE=\(schoolCode)&MLSV_FROM_YMD=\(apiDateString(from: today))&MLSV_TO_YMD=\(apiDateString(from: endDate))"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let decoded = try? JSONDecoder().decode(NeisResponse.self, from: data),
               let rows = decoded.mealServiceDietInfo?
                .compactMap({ $0.row })
                .first(where: { !$0.isEmpty }) {
                let sortedRows = rows.sorted {
                    if $0.MLSV_YMD == $1.MLSV_YMD {
                        return ($0.MMEAL_SC_CODE) < ($1.MMEAL_SC_CODE)
                    }
                    return $0.MLSV_YMD < $1.MLSV_YMD
                }
                DispatchQueue.main.async { self.meals = sortedRows }
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
                    self.rescheduleAllCommentNotifications()
                }
            } catch {
                DispatchQueue.main.async {
                    self.timetableMessage = "교육청 시간표를 불러오지 못했습니다."
                    self.timetables = []
                    self.rescheduleAllCommentNotifications()
                }
            }
        }.resume()
    }

    private func fetchComciTimetable() {
        guard !schoolName.isEmpty else { return }
        guard !isWeekend(selectedDate) else {
            DispatchQueue.main.async {
                self.timetableMessage = "주말에는 시간표가 없습니다."
                self.timetableRawJSON = ""
                self.timetables = []
                self.rescheduleAllCommentNotifications()
            }
            return
        }

        resolveComciSchoolMapping { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.timetableMessage = error.localizedDescription
                    self.timetableRawJSON = error.localizedDescription
                    self.timetables = []
                    self.rescheduleAllCommentNotifications()
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
                    self.rescheduleAllCommentNotifications()
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
                        self.rescheduleAllCommentNotifications()
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
                    self.rescheduleAllCommentNotifications()
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
        guard !isWeekend(selectedDate) else {
            timetableMessage = "주말에는 시간표가 없습니다."
            timetables = []
            rescheduleAllCommentNotifications()
            return
        }

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
        rescheduleAllCommentNotifications()
    }

    private func isWeekend(_ date: Date) -> Bool {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
        return weekday == 1 || weekday == 7
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
    var id: String { "\(MLSV_YMD)-\(MMEAL_SC_CODE)" }
    let MMEAL_SC_NM, DDISH_NM, CAL_INFO, MMEAL_SC_CODE, MLSV_YMD: String
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

struct TimetableComment: Codable {
    let text: String
    let reminderEnabled: Bool
    let updatedAt: String
}

struct TimetableSlot: Identifiable {
    var id: String { row.id }
    let row: TimetableRow
    let displayText: String
    let comment: TimetableComment?
    let isPlaceholder: Bool
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

struct TimetableSyncPayload: Codable {
    let officeCode: String
    let schoolCode: String
    let schoolName: String
    let grade: String
    let classNum: String
    let timetableSourceRawValue: String
    let comciSchoolCode: String
    let comciMappedSchoolName: String
    let comciRegionName: String
    let timetableDateEditsJSON: String
    let timetableWeeklyEditsJSON: String
    let timetableReplaceRulesJSON: String
    let timetableExtraPeriodsJSON: String
    let timetableCommentsJSON: String
    let commentReminderHour: Int
    let commentReminderMinute: Int
}

struct SyncCreateRequest: Codable {
    let deviceName: String
    let clientModifiedAt: String
    let payload: TimetableSyncPayload
}

struct SyncPullRequest: Codable {
    let syncKey: String
    let knownVersion: Int
}

struct SyncPushRequest: Codable {
    let syncKey: String
    let clientKnownVersion: Int
    let clientModifiedAt: String
    let deviceName: String
    let payload: TimetableSyncPayload
}

struct SyncCreateResponse: Codable {
    let syncKey: String
    let version: Int
    let updatedAt: String
}

struct SyncBootstrapResponse: Codable {
    let syncKey: String
    let creatorDeviceName: String
    let createdAt: String
    let version: Int
    let updatedAt: String
}

struct SyncEnvelope: Codable {
    let spaceId: String
    let version: Int
    let updatedAt: String
    let lastModifiedBy: String
    let payload: TimetableSyncPayload
}

struct SyncErrorResponse: Codable {
    let error: String
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
