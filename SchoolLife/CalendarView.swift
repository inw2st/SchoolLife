import SwiftUI

// ─────────────────────────────────────────────
// MARK: - CalendarView  (학사일정 달력)
// ─────────────────────────────────────────────
/// 기존 ContentView의 TabView에 추가되는 새 탭
/// - 월간 달력 그리드로 학사일정 이벤트를 표시
/// - 날짜 셀을 탭하면 해당 날의 이벤트 목록이 아래로 전개
/// - 휴업일(방학·휴일)은 색상으로 구분
/// - 월 이동 시 자동 re-fetch

struct CalendarView: View {
    @ObservedObject var neisManager: NeisManager

    // 현재 달력이 보여주는 월 (1일 기준)
    @State private var displayedMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps)!
    }()

    // 선택된 날짜
    @State private var selectedDate: Date? = nil

    // ─── computed ───
    private var cal: Calendar { Calendar.current }

    /// displayedMonth 기준 해당 월의 모든 날짜 (1일 ~ 마지막 날)
    private var daysInMonth: [Date] {
        guard let range = cal.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        return range.map { cal.date(byAdding: .day, value: $0 - 1, to: displayedMonth)! }
    }

    /// 1일이 몇 번째 요일인지 (0=일, 1=월 … 6=토)  → iOS Calendar weekday는 1=일
    private var startWeekdayIndex: Int {
        cal.component(.weekday, from: displayedMonth) - 1   // 0-based
    }

    /// 달력 그리드 총 셀 수 (앞 빈칸 포함)
    private var totalCells: Int {
        startWeekdayIndex + daysInMonth.count
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
        VStack(spacing: 0) {
            monthNavigationHeader
            weekdayLabels
            calendarGrid
            Divider().padding(.horizontal)
            eventListSection
        }
        .onChange(of: displayedMonth) { _, newMonth in
            updateCalendarRange(for: newMonth)
            neisManager.fetchSchedule()
        }
        .onAppear {
            updateCalendarRange(for: displayedMonth)
            neisManager.fetchSchedule()
        }
        // grade가 바뀌면 학사일정도 다시 불러옴
        .onChange(of: neisManager.grade) { _, _ in
            neisManager.fetchSchedule()
        }
    }

    // ─────────────────────────────────────────
    // MARK: - 월 이동 헤더
    // ─────────────────────────────────────────
    private var monthNavigationHeader: some View {
        HStack {
            Button {
                displayedMonth = cal.date(byAdding: .month, value: -1, to: displayedMonth)!
                selectedDate = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)

            Spacer()

            Text(monthTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            Spacer()

            Button {
                displayedMonth = cal.date(byAdding: .month, value: 1, to: displayedMonth)!
                selectedDate = nil
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
    // MARK: - 요일 라벨 (일~토)
    // ─────────────────────────────────────────
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

    // ─────────────────────────────────────────
    // MARK: - 달력 그리드
    // ─────────────────────────────────────────
    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<totalCells, id: \.self) { idx in
                if idx < startWeekdayIndex {
                    // 앞쪽 빈 셀
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    let dayIdx = idx - startWeekdayIndex
                    let date   = daysInMonth[dayIdx]
                    DayCellView(
                        date: date,
                        events: neisManager.events(on: date),
                        isSelected: selectedDate.map { cal.isDate($0, equalTo: date, toGranularity: .day) } ?? false,
                        isToday: cal.isDate(date, equalTo: Date(), toGranularity: .day),
                        isWeekend: isWeekend(date)
                    ) {
                        // 탭 핸들러: 같은 날짜를 다시 탭하면 선택 해제
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

    // ─────────────────────────────────────────
    // MARK: - 이벤트 목록 섹션 (선택 날짜)
    // ─────────────────────────────────────────
    private var eventListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let sel = selectedDate {
                // 날짜 헤더
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
                .padding(.top, 10)
                .padding(.bottom, 6)

                if !selectedEvents.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(selectedEvents) { event in
                                EventCardView(event: event)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                } else {
                    // 빈 상태 패딩
                    Spacer(minLength: 40)
                }
            } else {
                // 날짜를 선택하지 않은 상태
                HStack {
                    Spacer()
                    Text("날짜를 선택하세요")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 16)
                Spacer(minLength: 40)
            }
        }
    }

    // ─── helpers ───
    private func isWeekend(_ date: Date) -> Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7   // 일=1, 토=7
    }

    private func updateCalendarRange(for month: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let firstDay = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstDay),
              let lastDay = cal.date(byAdding: .day, value: range.count - 1, to: firstDay) else { return }
        neisManager.calendarMonthStart = firstDay
        neisManager.calendarMonthEnd   = lastDay
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M월 d일 (EEE)"
        f.locale = Locale(identifier: "ko_KR")
        return f.string(from: date)
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

    /// 휴업일 이벤트가 있는지 (SBTR_DD_SC_NM == "휴업일")
    private var hasHoliday: Bool {
        events.contains { $0.SBTR_DD_SC_NM == "휴업일" }
    }

    /// 일반 이벤트(휴업일 아닌)가 있는지
    private var hasNormalEvent: Bool {
        events.contains { $0.SBTR_DD_SC_NM != "휴업일" }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // 배경
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
                    .aspectRatio(1, contentMode: .fit)

                VStack(spacing: 2) {
                    // 날짜 숫자
                    Text("\(dayNumber)")
                        .font(.system(size: 13, weight: isToday ? .bold : .medium))
                        .foregroundColor(textColor)

                    // 이벤트 닷 표시 (최대 3개)
                    HStack(spacing: 3) {
                        if hasHoliday {
                            Circle().fill(Color.red.opacity(0.7)).frame(width: 5, height: 5)
                        }
                        if hasNormalEvent {
                            Circle().fill(Color.blue.opacity(0.7)).frame(width: 5, height: 5)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // 배경색 결정
    private var backgroundColor: Color {
        if isSelected {
            return .blue.opacity(0.18)
        } else if hasHoliday {
            return .red.opacity(0.08)
        } else {
            return .clear
        }
    }

    // 텍스트 색 결정
    private var textColor: Color {
        if isSelected {
            return .blue
        } else if isToday {
            return .blue
        } else if isWeekend {
            return hasHoliday ? .red : (Calendar.current.component(.weekday, from: date) == 1 ? .red : .blue)
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

    /// 휴업일 여부
    private var isHoliday: Bool {
        event.SBTR_DD_SC_NM == "휴업일"
    }

    var body: some View {
        HStack(alignment: .leading, spacing: 12) {
            // 왼쪽 색 바
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

                // 행사 내용이 있으면 표시
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
