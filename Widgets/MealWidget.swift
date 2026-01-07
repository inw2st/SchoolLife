import WidgetKit
import SwiftUI

// MARK: - 위젯 데이터 모델
struct MealEntry: TimelineEntry {
    let date: Date
    let meals: [SimpleMeal]
    let schoolName: String
}

struct SimpleMeal {
    let type: String // 조식, 중식, 석식
    let menu: String
    let calories: String
}

// MARK: - 위젯 Provider
struct MealProvider: TimelineProvider {
    private let apiKey = "b22e0d13ad8e49179c4d37cff6aed382"

    func placeholder(in context: Context) -> MealEntry {
        MealEntry(
            date: Date(),
            meals: [SimpleMeal(type: "중식", menu: "불고기\n김치찌개\n밥", calories: "800 Kcal")],
            schoolName: "학교 검색 필요"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MealEntry) -> Void) {
        fetchMealData { entry in completion(entry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MealEntry>) -> Void) {
        fetchMealData { entry in
            // 1시간마다 업데이트
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func fetchMealData(completion: @escaping (MealEntry) -> Void) {
        // ✅ 동적으로 App Group 감지
        guard let defaults = AppGroupManager.shared.sharedDefaults else {
            completion(MealEntry(date: Date(), meals: [], schoolName: "App Group 오류"))
            return
        }
        
        let schoolCode = defaults.string(forKey: "savedSchoolCode") ?? ""
        let officeCode = defaults.string(forKey: "savedOfficeCode") ?? ""
        let schoolName = defaults.string(forKey: "savedSchoolName") ?? "학교를 선택하세요"

        guard !schoolCode.isEmpty else {
            completion(MealEntry(date: Date(), meals: [], schoolName: "앱에서 학교를 먼저 설정하세요"))
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let today = dateFormatter.string(from: Date())

        let urlString =
        "https://open.neis.go.kr/hub/mealServiceDietInfo?KEY=\(apiKey)&Type=json&ATPT_OFCDC_SC_CODE=\(officeCode)&SD_SCHUL_CODE=\(schoolCode)&MLSV_YMD=\(today)"

        guard let url = URL(string: urlString) else {
            completion(MealEntry(date: Date(), meals: [], schoolName: schoolName))
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            var meals: [SimpleMeal] = []

            if let data,
               let json = try? JSONDecoder().decode(MealResponse.self, from: data) {

                let rows = json.mealServiceDietInfo?
                    .compactMap { $0.row }      // [[MealRowWidget]?]
                    .compactMap { $0 }          // [MealRowWidget]
                    .first(where: { !$0.isEmpty }) ?? []

                meals = rows.map { meal in
                    let cleanMenu = meal.DDISH_NM
                        .replacingOccurrences(of: "<br/>", with: "\n")
                        .replacingOccurrences(of: #"\([0-9\.]+\)"#, with: "", options: .regularExpression)

                    return SimpleMeal(
                        type: meal.MMEAL_SC_NM,
                        menu: cleanMenu,
                        calories: meal.CAL_INFO
                    )
                }
            }

            completion(MealEntry(date: Date(), meals: meals, schoolName: schoolName))
        }.resume()
    }
}

// MARK: - 위젯 뷰 (Small만 표시 + 다크모드 연동)
struct MealWidgetView: View {
    var entry: MealEntry
    @Environment(\.widgetFamily) private var family

    @AppStorage("isDarkMode", store: AppGroupManager.shared.sharedDefaults)
    private var isDarkMode: Bool = false

    var body: some View {
        Group {
            switch family {
            case .systemLarge:
                LargeWidgetView(entry: entry)
            default:
                SmallWidgetView(entry: entry)
            }
        }
        .widgetURL(URL(string: "schoollife://meal"))
        .containerBackground(for: .widget) {
            if isDarkMode {
                Color(red: 0.1, green: 0.1, blue: 0.12)
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.18),
                        Color.white
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .environment(\.colorScheme, isDarkMode ? .dark : .light)
    }
}

// MARK: - Small Widget
struct SmallWidgetView: View {
    let entry: MealEntry

    var body: some View {
        GeometryReader { geometry in
            if let lunch = entry.meals.first(where: { $0.type.contains("중식") }) {

                let menus = lunch.menu.split(separator: "\n")
                let count = CGFloat(menus.count)

                let headerHeight: CGFloat = 18
                let usableHeight = geometry.size.height - headerHeight - 8
                let rowHeight = usableHeight / max(count, 1)
                let fontSize = rowHeight * 0.75

                VStack(spacing: 0) {
                    HStack {
                        Text("오늘 중식")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.blue)

                        Spacer()

                        Text(lunch.calories)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(height: headerHeight)

                    VStack(spacing: 0) {
                        ForEach(menus.indices, id: \.self) { index in
                            Text(String(menus[index]))
                                .font(.system(size: fontSize, weight: .bold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: rowHeight)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 12)

            } else {
                VStack {
                    Spacer()
                    Text("No Meal Information")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: -Large Widget
struct LargeWidgetView: View {
    let entry: MealEntry

    var body: some View {
        GeometryReader { geometry in
            if let lunch = entry.meals.first(where: { $0.type.contains("중식") }) {

                // 라지에서는 너무 많으면 글자가 작아지니까 적당히 컷
                let menusAll = lunch.menu.split(separator: "\n").map(String.init)
                let menus = Array(menusAll.prefix(9)) // 필요하면 8~10으로 조절

                let count = CGFloat(max(menus.count, 1))

                // 라지용 비율(헤더/패딩만 살짝 키움)
                let headerHeight: CGFloat = 22
                let verticalPadding: CGFloat = 12

                let usableHeight = geometry.size.height - headerHeight - (verticalPadding * 2)
                let rowHeight = usableHeight / count

                // 행높이에 비례하되 너무 커/작아지지 않게 제한
                let rawFont = rowHeight * 0.78
                let fontSize = min(max(rawFont, 14), 26)

                VStack(spacing: 0) {

                    // 헤더(Small 스타일 유지 + 살짝 업)
                    HStack {
                        Text("오늘 중식")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.blue)

                        Spacer()

                        Text(lunch.calories)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(height: headerHeight)

                    // 메뉴(줄 단위, 동일한 방식)
                    VStack(spacing: 0) {
                        ForEach(menus.indices, id: \.self) { index in
                            Text(menus[index])
                                .font(.system(size: fontSize, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: rowHeight)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, verticalPadding)

            } else {
                VStack {
                    Spacer()
                    Text("No Meal Information")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - 위젯 Entry Point (Small만 지원)
struct MealWidget: Widget {
    let kind: String = "MealWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MealProvider()) { entry in
            MealWidgetView(entry: entry)
        }
        .configurationDisplayName("오늘의 급식")
        .description("학교 급식 정보를 확인하세요")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

// MARK: - API Response 모델
struct MealResponse: Codable {
    let mealServiceDietInfo: [MealInfoWidget]?
}
struct MealInfoWidget: Codable {
    let row: [MealRowWidget]?
}
struct MealRowWidget: Codable {
    let MMEAL_SC_NM: String
    let DDISH_NM: String
    let CAL_INFO: String
}
