import WidgetKit
import SwiftUI

// MARK: - Entry
struct WatchMealEntry: TimelineEntry {
    let date: Date
    let menu: String
    let calories: String
}

// MARK: - Provider
struct WatchMealProvider: TimelineProvider {
    private let apiKey = "b22e0d13ad8e49179c4d37cff6aed382"
    
    func placeholder(in context: Context) -> WatchMealEntry {
        WatchMealEntry(
            date: Date(),
            menu: "불고기\n김치찌개\n밥",
            calories: "800 Kcal"
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WatchMealEntry) -> Void) {
        fetchMeal { entry in
            completion(entry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchMealEntry>) -> Void) {
        fetchMeal { entry in
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }
    
    private func fetchMeal(completion: @escaping (WatchMealEntry) -> Void) {
        guard let defaults = AppGroupManager.shared.sharedDefaults else {
            completion(WatchMealEntry(date: Date(), menu: "설정 필요", calories: ""))
            return
        }
        
        let schoolCode = defaults.string(forKey: "savedSchoolCode") ?? ""
        let officeCode = defaults.string(forKey: "savedOfficeCode") ?? ""
        
        guard !schoolCode.isEmpty else {
            completion(WatchMealEntry(date: Date(), menu: "앱에서 학교 설정", calories: ""))
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let today = dateFormatter.string(from: Date())
        
        let urlString = "https://open.neis.go.kr/hub/mealServiceDietInfo?KEY=\(apiKey)&Type=json&ATPT_OFCDC_SC_CODE=\(officeCode)&SD_SCHUL_CODE=\(schoolCode)&MLSV_YMD=\(today)"
        
        guard let url = URL(string: urlString) else {
            completion(WatchMealEntry(date: Date(), menu: "오류", calories: ""))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var menu = "급식 정보 없음"
            var calories = ""
            
            if let data,
               let json = try? JSONDecoder().decode(WatchMealWidgetResponse.self, from: data),
               let rows = json.mealServiceDietInfo?.compactMap({ $0.row }).first(where: { !($0?.isEmpty ?? true) }),
               let lunch = rows?.first(where: { $0.MMEAL_SC_NM.contains("중식") }) {
                
                menu = lunch.DDISH_NM
                    .replacingOccurrences(of: "<br/>", with: "\n")
                    .replacingOccurrences(of: #"\([0-9\.]+\)"#, with: "", options: .regularExpression)
                
                calories = lunch.CAL_INFO
            }
            
            completion(WatchMealEntry(date: Date(), menu: menu, calories: calories))
        }.resume()
    }
}

// MARK: - Widget View
struct WatchMealWidgetView: View {
    var entry: WatchMealEntry
    @Environment(\.widgetFamily) private var family
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("중식")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.blue)
                
                Spacer()
                
                if !entry.calories.isEmpty {
                    Text(entry.calories)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            
            let menus = entry.menu.split(separator: "\n").prefix(family == .accessoryRectangular ? 3 : 6)
            
            ForEach(Array(menus.enumerated()), id: \.offset) { _, menu in
                Text(String(menu))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
        }
        .padding(8)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

// MARK: - Widget
struct WatchMealWidget: Widget {
    let kind: String = "WatchMealWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchMealProvider()) { entry in
            WatchMealWidgetView(entry: entry)
        }
        .configurationDisplayName("급식")
        .description("오늘의 급식 메뉴")
        .supportedFamilies([.accessoryRectangular, .accessoryCorner])
    }
}

// MARK: - API Models
struct WatchMealWidgetResponse: Codable {
    let mealServiceDietInfo: [WatchMealWidgetInfo]?
}

struct WatchMealWidgetInfo: Codable {
    let row: [WatchMealWidgetRow]?
}

struct WatchMealWidgetRow: Codable {
    let MMEAL_SC_NM: String
    let DDISH_NM: String
    let CAL_INFO: String
}
