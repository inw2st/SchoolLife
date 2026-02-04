import SwiftUI

// ─────────────────────────────────────────────
// MARK: - CalendarView  (학사일정 달력)
// ─────────────────────────────────────────────
struct CalendarView: View {
    @ObservedObject var neisManager: NeisManager
    
    // 현재 보고 있는 월의 offset (0 = 오늘이 속한 월)
    @State private var monthOffset: Int = 0
    
    // 선택된 날짜
    @State private var selectedDate: Date? = nil
    
    // 연월 설정 시트
    @State private var showYearMonthPicker = false
    
    // ─── computed ───
    private var cal: Calendar { Calendar.current }
    
    /// 현재 표시 중인 월 (1일 기준)
    private var displayedMonth: Date {
        let today = Date()
        let comps = cal.dateComponents([.year, .month], from: today)
        let thisMonth = cal.date(from: comps)!
        return cal.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }
    
    /// 선택된 날짜의 이벤트 목록
    private var selectedEvents: [ScheduleEventRow] {
        guard let sel = selectedDate else { return [] }
        return neisManager.events(on: sel)
    }
    
    // 월 표시 포맷
    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy년 M월"
        f.locale = Locale(identifier: "ko_KR")
        return f.string(from: displayedMonth)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let isIPad = geometry.size.width > 600
            let maxWidth: CGFloat = isIPad ? 700 : .infinity
            // iPad에서 셀 크기가 커지면서 6주차까지 안전하게 보이도록 높이 여유를 넉넉히 줌
            let calendarHeight: CGFloat = isIPad ? 660 : 380
            
            VStack(spacing: 0) {
                // 헤더
                monthNavigationHeader
                
                // 달력 + 이벤트 영역을 ScrollView로 감싸서 iPad에서 스크롤 가능
                ScrollView {
                    VStack(spacing: 0) {
                        // 달력 영역 (TabView로 페이지 스와이프)
                        calendarSection(calendarHeight: calendarHeight)
                            .frame(maxWidth: maxWidth)
                        
                        Divider()
                            .padding(.horizontal)
                            .padding(.top, 12)
                        
                        // 이벤트 목록
                        eventListSection
                            .frame(maxWidth: maxWidth)
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity) // 중앙 정렬
                    // 하단 탭 바 / 홈 인디케이터에 가려지지 않도록 안전 영역만큼 여유
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                }
            }
        }
        .onChange(of: monthOffset) { _, _ in
            updateCalendarData()
        }
        .onAppear {
            updateCalendarData()
        }
        .onChange(of: neisManager.grade) { _, _ in
            neisManager.fetchSchedule()
        }
        .sheet(isPresented: $showYearMonthPicker) {
            YearMonthPickerSheet(monthOffset: $monthOffset)
        }
    }
    
    // ─────────────────────────────────────────
    // MARK: - 월 이동 헤더
    // ─────────────────────────────────────────
    private var monthNavigationHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    monthOffset -= 1
                    selectedDate = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            
            Spacer()
            
            Button {
                showYearMonthPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(monthTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    monthOffset += 1
                    selectedDate = nil
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
    }
    
    // ─────────────────────────────────────────
    // MARK: - 달력 섹션 (TabView 기반 스와이프)
    // ─────────────────────────────────────────
    private func calendarSection(calendarHeight: CGFloat) -> some View {
        TabView(selection: $monthOffset) {
            ForEach(-12...12, id: \.self) { offset in
                let month = getMonthDate(offset: offset)
                VStack(spacing: 0) {
                    // 달력은 항상 상단에 붙어 있도록 하고,
                    // 남는 공간은 아래쪽으로만 빠지게 Spacer로 처리
                    MonthCalendarGrid(
                        month: month,
                        selectedDate: $selectedDate,
                        neisManager: neisManager
                    )
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: calendarHeight)
    }
    
    // ─────────────────────────────────────────
    // MARK: - 이벤트 목록 섹션
    // ─────────────────────────────────────────
    private var eventListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let sel = selectedDate {
                let dateStr = formatDate(sel)
                HStack {
                    Text(dateStr)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    if selectedEvents.isEmpty {
                        Text("이벤트 없음")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                if !selectedEvents.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(selectedEvents) { event in
                            EventCardView(event: event)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            } else {
                HStack {
                    Spacer()
                    Text("날짜를 선택하세요")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        }
    }
    
    // ─── helpers ───
    private func getMonthDate(offset: Int) -> Date {
        let today = Date()
        let comps = cal.dateComponents([.year, .month], from: today)
        let thisMonth = cal.date(from: comps)!
        return cal.date(byAdding: .month, value: offset, to: thisMonth) ?? thisMonth
    }
    
    private func updateCalendarData() {
        let month = displayedMonth
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let firstDay = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstDay),
              let lastDay = cal.date(byAdding: .day, value: range.count - 1, to: firstDay) else { return }
        
        neisManager.calendarMonthStart = firstDay
        neisManager.calendarMonthEnd   = lastDay
        neisManager.fetchSchedule()
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M월 d일 (EEE)"
        f.locale = Locale(identifier: "ko_KR")
        return f.string(from: date)
    }
}

// ─────────────────────────────────────────────
// MARK: - MonthCalendarGrid  (개별 월 달력)
// ─────────────────────────────────────────────
private struct MonthCalendarGrid: View {
    let month: Date
    @Binding var selectedDate: Date?
    @ObservedObject var neisManager: NeisManager
    
    private var cal: Calendar { Calendar.current }
    
    private var daysInMonth: [Date] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        return range.map { cal.date(byAdding: .day, value: $0 - 1, to: month)! }
    }
    
    private var startWeekdayIndex: Int {
        cal.component(.weekday, from: month) - 1
    }
    
    private var totalCells: Int {
        startWeekdayIndex + daysInMonth.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 요일 라벨
            weekdayLabels
            
            // 달력 그리드
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<totalCells, id: \.self) { idx in
                    if idx < startWeekdayIndex {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    } else {
                        let dayIdx = idx - startWeekdayIndex
                        let date = daysInMonth[dayIdx]
                        DayCellView(
                            date: date,
                            events: neisManager.events(on: date),
                            isSelected: selectedDate.map { cal.isDate($0, equalTo: date, toGranularity: .day) } ?? false,
                            isToday: cal.isDate(date, equalTo: Date(), toGranularity: .day),
                            isWeekend: isWeekend(date)
                        ) {
                            if let sel = selectedDate, cal.isDate(sel, equalTo: date, toGranularity: .day) {
                                selectedDate = nil
                            } else {
                                selectedDate = date
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
    
    private var weekdayLabels: some View {
        let labels = ["일", "월", "화", "수", "목", "금", "토"]
        return HStack(spacing: 0) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(label == "일" ? .red : label == "토" ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
    
    private func isWeekend(_ date: Date) -> Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }
}

// ─────────────────────────────────────────────
// MARK: - DayCellView  (달력 한 칸)
// ─────────────────────────────────────────────
private struct DayCellView: View {
    let date: Date
    let events: [ScheduleEventRow]
    let isSelected: Bool
    let isToday: Bool
    let isWeekend: Bool
    let onTap: () -> Void
    
    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
                    .aspectRatio(1, contentMode: .fit)
                
                VStack(spacing: 2) {
                    Text("\(dayNumber)")
                        .font(.system(size: 13, weight: isToday ? .bold : .medium))
                        .foregroundColor(textColor)
                    
                    if !events.isEmpty {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue.opacity(0.18)
        } else if events.contains(where: { $0.SBTR_DD_SC_NM == "휴업일" }) {
            return .red.opacity(0.08)
        } else {
            return .clear
        }
    }
    
    private var textColor: Color {
        if isSelected {
            return .blue
        } else if isToday {
            return .blue
        } else if isWeekend {
            return Calendar.current.component(.weekday, from: date) == 1 ? .red : .blue
        } else {
            return .primary
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - EventCardView  (이벤트 카드)
// ─────────────────────────────────────────────
private struct EventCardView: View {
    let event: ScheduleEventRow
    
    private var isHoliday: Bool {
        event.SBTR_DD_SC_NM == "휴업일"
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isHoliday ? Color.red : Color.blue)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(event.EVENT_NM ?? "행사")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if isHoliday {
                        Text("휴업일")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(4)
                    }
                }
                
                if let content = event.EVENT_CNTNT, !content.isEmpty {
                    Text(content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// ─────────────────────────────────────────────
// MARK: - YearMonthPickerSheet  (연월 설정 시트)
// ─────────────────────────────────────────────
private struct YearMonthPickerSheet: View {
    @Binding var monthOffset: Int
    @Environment(\.dismiss) var dismiss
    
    @State private var pickedYear: Int
    @State private var pickedMonth: Int
    @State private var showYearPicker: Bool = false
    
    private static let yearRange = 2020...2030
    
    init(monthOffset: Binding<Int>) {
        self._monthOffset = monthOffset
        
        let cal = Calendar.current
        let today = Date()
        let comps = cal.dateComponents([.year, .month], from: today)
        let thisMonth = cal.date(from: comps)!
        let targetMonth = cal.date(byAdding: .month, value: monthOffset.wrappedValue, to: thisMonth)!
        
        self._pickedYear = State(initialValue: cal.component(.year, from: targetMonth))
        self._pickedMonth = State(initialValue: cal.component(.month, from: targetMonth))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 연도 표시 + 좌우 이동/탭을 한 줄로 통합
                HStack(spacing: 16) {
                    Button {
                        if let first = Self.yearRange.first, pickedYear > first {
                            pickedYear -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .foregroundColor(.primary)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    
                    Button {
                        showYearPicker = true
                    } label: {
                        // LocalizedStringKey로 인한 2,024 형식 방지용으로 verbatim 사용
                        Text(verbatim: "\(pickedYear)년")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    
                    Button {
                        if let last = Self.yearRange.last, pickedYear < last {
                            pickedYear += 1
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .foregroundColor(.primary)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 8)
                
                // 월 선택 그리드 (3 x 4)
                VStack(alignment: .leading, spacing: 12) {
                    Text("월 선택")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(1...12, id: \.self) { m in
                            Button {
                                pickedMonth = m
                            } label: {
                                Text("\(m)월")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(monthBackground(isSelected: pickedMonth == m))
                                    .foregroundColor(monthForeground(isSelected: pickedMonth == m))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .navigationTitle("연월 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        applySelection()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showYearPicker) {
                NavigationStack {
                    List {
                        ForEach(Self.yearRange, id: \.self) { y in
                            Button {
                                pickedYear = y
                                showYearPicker = false
                            } label: {
                                HStack {
                                    // LocalizedStringKey가 숫자에 콤마 넣지 않도록 verbatim 사용
                                    Text(verbatim: "\(y)년")
                                        .foregroundColor(.primary)
                                    if y == pickedYear {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("연도 선택")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
    
    private func monthBackground(isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        } else {
            return Color(.secondarySystemBackground)
        }
    }
    
    private func monthForeground(isSelected: Bool) -> Color {
        if isSelected {
            return Color.white
        } else {
            return Color.primary
        }
    }
    
    private func applySelection() {
        let cal = Calendar.current
        let today = Date()
        let todayComps = cal.dateComponents([.year, .month], from: today)
        let thisMonth = cal.date(from: todayComps)!
        
        var targetComps = DateComponents()
        targetComps.year = pickedYear
        targetComps.month = pickedMonth
        targetComps.day = 1
        
        if let targetMonth = cal.date(from: targetComps) {
            let offset = cal.dateComponents([.month], from: thisMonth, to: targetMonth).month ?? 0
            monthOffset = offset
        }
    }
}
