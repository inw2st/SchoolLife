import WidgetKit
import SwiftUI

// MARK: - Entry
struct WatchTimetableEntry: TimelineEntry {
    let date: Date
    let items: [WatchTTItem]
}

struct WatchTTItem: Identifiable {
    let id = UUID()
    let perio: String
    let subject: String
}

// MARK: - Provider
struct WatchTimetableProvider: TimelineProvider {
    private let apiKey = "b22e0d13ad8e49179c4d37cff6aed382"
    
    func placeholder(in context: Context) -> WatchTimetableEntry {
        WatchTimetableEntry(
            date: Date(),
            items: [
                WatchTTItem(perio: "1", subject: "국어"),
                WatchTTItem(perio: "2", subject: "수학"),
                WatchTTItem(perio: "3", subject: "영어")
            ]
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WatchTimetableEntry) -> Void) {
        fetchTimetable { entry in
            completion(entry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchTimetableEntry>) -> Void) {
        fetchTimetable { entry in
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }
    
    private func fetchTimetable(completion: @escaping (WatchTimetableEntry) -> Void) {
        guard let defaults = AppGroupManager.shared.sharedDefaults else {
            completion(WatchTimetableEntry(date: Date(), items: []))
            return
        }
        
        let officeCode = defaults.string(forKey: "savedOfficeCode") ?? ""
        let schoolCode = defaults.string(forKey: "savedSchoolCode") ?? ""
        let grade = defaults.string(forKey: "savedGrade") ?? "1"
        let classNum = defaults.string(forKey: "savedClass") ?? "1"
        
        guard !schoolCode.isEmpty else {
            completion(WatchTimetableEntry(date: Date(), items: []))
            return
        }
        
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        let ymd = df.string(from: Date())
        
        let dateEdits = decodeDict(defaults.string(forKey: "timetableDateEditsJSON"))
        let weeklyEdits = decodeDict(defaults.string(forKey: "timetableWeeklyEditsJSON"))
        let replaceRules = decodeDict(defaults.string(forKey: "timetableReplaceRulesJSON"))
        
        let urlString = "https://open.neis.go.kr/hub/hisTimetable?KEY=\(apiKey)&Type=json&pIndex=1&pSize=100&ATPT_OFCDC_SC_CODE=\(officeCode)&SD_SCHUL_CODE=\(schoolCode)&ALL_TI_YMD=\(ymd)&GRADE=\(grade)&CLASS_NM=\(classNum)"
        
        guard let url = URL(string: urlString) else {
            completion(WatchTimetableEntry(date: Date(), items: []))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var items: [WatchTTItem] = []
            
            if let data,
               let decoded = try? JSONDecoder().decode(WatchTimetableWidgetResponse.self, from: data),
               let rows = decoded.hisTimetable?.compactMap({ $0.row }).first(where: { !($0?.isEmpty ?? true) }) {
                
                let sorted = rows?.sorted { (Int($0.PERIO ?? "0") ?? 0) < (Int($1.PERIO ?? "0") ?? 0) } ?? []
                
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
                    
                    return WatchTTItem(perio: perio, subject: subject)
                }
            }
            
            completion(WatchTimetableEntry(date: Date(), items: items))
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
struct WatchTimetableWidgetView: View {
    var entry: WatchTimetableEntry
    @Environment(\.widgetFamily) private var family
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("시간표")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.blue)
            
            let maxItems = family == .accessoryRectangular ? 3 : 5
            let items = Array(entry.items.prefix(maxItems))
            
            if items.isEmpty {
                Text("시간표 없음")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        Text(item.perio)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 12, alignment: .leading)
                        
                        Text(item.subject)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

// MARK: - Widget
struct WatchTimetableWidget: Widget {
    let kind: String = "WatchTimetableWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchTimetableProvider()) { entry in
            WatchTimetableWidgetView(entry: entry)
        }
        .configurationDisplayName("시간표")
        .description("오늘의 시간표")
        .supportedFamilies([.accessoryRectangular, .accessoryCorner])
    }
}

// MARK: - API Models
struct WatchTimetableWidgetResponse: Codable {
    let hisTimetable: [WatchTimetableWidgetInfo]?
}

struct WatchTimetableWidgetInfo: Codable {
    let row: [WatchTimetableWidgetRow]?
}

struct WatchTimetableWidgetRow: Codable {
    let PERIO: String?
    let ITRT_CNTNT: String?
}
