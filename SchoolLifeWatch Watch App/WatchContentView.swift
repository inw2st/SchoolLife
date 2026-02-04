import SwiftUI

enum WatchTab {
    case meal
    case timetable
}

struct WatchContentView: View {
    @StateObject private var neisManager = WatchNeisManager()
    @State private var selectedTab: WatchTab = .meal
    
    var body: some View {
        TabView(selection: $selectedTab) {
            WatchMealView(neisManager: neisManager)
                .tag(WatchTab.meal)
            
            WatchTimetableView(neisManager: neisManager)
                .tag(WatchTab.timetable)
        }
        .tabViewStyle(.page)
        .onAppear {
            neisManager.fetchAll()
            neisManager.debugReadFromPhone()
        }
    }
}

struct WatchMealView: View {
    @ObservedObject var neisManager: WatchNeisManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !neisManager.schoolName.isEmpty {
                    Text(neisManager.schoolName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("오늘의 급식")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                if neisManager.meals.isEmpty {
                    Text("급식 정보 없음")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else {
                    ForEach(neisManager.meals) { meal in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meal.MMEAL_SC_NM)
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            
                            Text(neisManager.cleanMealText(meal.DDISH_NM))
                                .font(.caption2)
                                .lineSpacing(2)
                            
                            Text(meal.CAL_INFO)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding()
        }
    }
}

struct WatchTimetableView: View {
    @ObservedObject var neisManager: WatchNeisManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if !neisManager.schoolName.isEmpty {
                    Text(neisManager.schoolName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("오늘의 시간표")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                if neisManager.timetables.isEmpty {
                    Text("시간표 정보 없음")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else {
                    ForEach(neisManager.timetables) { time in
                        HStack(spacing: 6) {
                            Text("\(time.PERIO ?? "")교시")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.blue)
                                .frame(width: 40, alignment: .leading)
                            
                            Text(neisManager.displayText(for: time))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
        }
    }
}
