import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

enum AppTab: String {
    case meal
    case timetable
    case schedule      // ▶ 학사일정 탭 추가
    case settings
}

struct ContentView: View {
    @StateObject var neisManager = NeisManager()
    @State private var selectedTab: AppTab = .meal
    @State private var showSearchSheet = false
    @State private var showDatePicker = false

    var body: some View {
        ZStack {
            if neisManager.isDarkMode {
                Color(.systemBackground).ignoresSafeArea()
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.15), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                headerSection

                TabView(selection: $selectedTab) {
                    MealView(neisManager: neisManager)
                        .tabItem { Label("급식", systemImage: "fork.knife") }
                        .tag(AppTab.meal)

                    TimetableView(neisManager: neisManager)
                        .tabItem { Label("시간표", systemImage: "clock.fill") }
                        .tag(AppTab.timetable)

                    CalendarView(neisManager: neisManager)
                        .tabItem { Label("학사일정", systemImage: "calendar.badge.plus") }
                        .tag(AppTab.schedule)

                    SettingsView(neisManager: neisManager)
                        .tabItem { Label("설정", systemImage: "gearshape.fill") }
                        .tag(AppTab.settings)
                }
            }
        }
        .preferredColorScheme(neisManager.isDarkMode ? .dark : .light)
        .sheet(isPresented: $showSearchSheet) {
            SchoolSearchView(neisManager: neisManager)
        }
        .onAppear {
            if neisManager.schoolCode.isEmpty { showSearchSheet = true }
            else { neisManager.fetchAll() }
            neisManager.debugWriteForWatch()
        }
        .onChange(of: neisManager.selectedDate) { _, _ in
            neisManager.fetchAll()
        }
        .onOpenURL { url in
            guard url.scheme == "schoollife" else { return }

            switch url.host {
            case "meal":
                selectedTab = .meal
            case "timetable":
                selectedTab = .timetable
            case "schedule":
                selectedTab = .schedule
            case "settings":
                selectedTab = .settings
            default:
                break
            }
        }
    }

    var headerSection: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("My School Life")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.blue)

                Text(neisManager.schoolName.isEmpty ? "학교 검색" : neisManager.schoolName)
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(.primary)
                    .onTapGesture { showSearchSheet = true }
            }

            Spacer()

            Button(action: { showDatePicker.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(formattedDate(neisManager.selectedDate))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .foregroundColor(.primary)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.1), radius: 4)
            }
            .popover(isPresented: $showDatePicker, arrowEdge: .top) {
                VStack {
                    DatePicker("", selection: $neisManager.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: neisManager.selectedDate) { _, _ in
                            showDatePicker = false
                        }
                }
                .frame(width: 320, height: 350)
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 25)
        .padding(.top, 20)
        .padding(.bottom, 15)
    }

    func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM.dd"
        return f.string(from: date)
    }
}

// MARK: - 시간표 뷰
struct TimetableView: View {
    @ObservedObject var neisManager: NeisManager

    @State private var editingRow: TimetableRow? = nil
    @State private var editText: String = ""
    @State private var mode: EditApplyMode = .weekly

    // 편집 적용 방식
    private enum EditApplyMode: String, CaseIterable, Identifiable {
        case todayOnly
        case weekly
        case replaceSubject

        var id: String { rawValue }

        var title: String {
            switch self {
            case .todayOnly: return "오늘만"
            case .weekly: return "매주"
            case .replaceSubject: return "과목명 전체치환"
            }
        }

        var subtitle: String {
            switch self {
            case .todayOnly: return "이 날짜의 이 교시만 변경"
            case .weekly: return "같은 요일/교시 전부 변경"
            case .replaceSubject: return "현재 학교/학년/반에서 같은 과목명 전부 변경"
            }
        }

        var icon: String {
            switch self {
            case .todayOnly: return "calendar"
            case .weekly: return "arrow.triangle.2.circlepath"
            case .replaceSubject: return "arrow.left.arrow.right"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            VStack(spacing: 12) {
                HStack {
                    Label(neisManager.timetableSourceDescription, systemImage: "rectangle.2.swap")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Picker("학년", selection: $neisManager.grade) {
                    Text("1학년").tag("1")
                    Text("2학년").tag("2")
                    Text("3학년").tag("3")
                }
                .pickerStyle(.segmented)
                .onChange(of: neisManager.grade) { _, _ in
                    neisManager.fetchTimetable()
                    neisManager.syncWatchContext()
                    WidgetCenter.shared.reloadTimelines(ofKind: "TimetableWidget")
                }

                HStack {
                    Text("반")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.primary)

                    Picker("반", selection: $neisManager.classNum) {
                        ForEach(1...15, id: \.self) { i in
                            Text("\(i)반").tag("\(i)")
                        }
                    }
                    .onChange(of: neisManager.classNum) { _, _ in
                        neisManager.fetchTimetable()
                        neisManager.syncWatchContext()
                        WidgetCenter.shared.reloadTimelines(ofKind: "TimetableWidget")
                    }

                    Spacer()
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(15)
            .padding()

            // 시간표 목록
            ScrollView {
                VStack(spacing: 10) {
                    if neisManager.timetables.isEmpty {
                        Text("시간표 데이터가 없습니다.")
                            .foregroundColor(.secondary)
                            .padding(.top, 50)
                        if let message = neisManager.timetableMessage {
                            Text(message)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    } else {
                        ForEach(neisManager.timetables) { time in
                            Button {
                                editingRow = time
                                editText = neisManager.displayText(for: time)
                                mode = .weekly // 기본 선택
                            } label: {
                                HStack {
                                    Text("\(time.PERIO ?? "")교시")
                                        .bold()
                                        .foregroundColor(.blue)
                                        .frame(width: 60, alignment: .leading)

                                    Text(neisManager.displayText(for: time))
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if neisManager.hasAnyEditedText(for: time) {
                                        Image(systemName: "pencil.circle.fill")
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding()
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }

                        if neisManager.timetables.count > 0 && neisManager.timetables.count < 7 {
                            Text("나머지 교시 정보는 학교에서 등록하지 않았습니다.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 10)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
        .sheet(item: $editingRow) { row in
            NavigationStack {
                Form {
                    // 편집 적용 방식 선택
                    Section("적용 방식") {
                        ForEach(EditApplyMode.allCases) { m in
                            Button {
                                mode = m
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: m.icon)
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.title)
                                            .foregroundColor(.primary)
                                        Text(m.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if mode == m {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }

                        if mode == .replaceSubject {
                            let original = (row.ITRT_CNTNT ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            Text(original.isEmpty
                                 ? "원본 과목명이 없어 치환 규칙을 만들 수 없어요."
                                 : "'\(original)'이(가) 시간표에 나오면 항상 아래 값으로 표시돼요.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }

                    Section("변경할 표시") {
                        TextField("예: 한국지리 / A_한국지리", text: $editText, axis: .vertical)
                            .lineLimit(2...5)
                    }

                    Section("원본 과목") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.ITRT_CNTNT ?? "-")
                                .foregroundColor(.secondary)

                            HStack(spacing: 10) {
                                Text("\(row.PERIO ?? "?")교시")
                                Text("학년 \(neisManager.grade)")
                                Text("반 \(neisManager.classNum)")
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }
                    }

                    // 삭제 버튼을 Form 내부 섹션으로 이동
                    Section("삭제") {
                        Button(role: .destructive) {
                            deleteByCurrentMode(row: row)
                            editingRow = nil
                        } label: {
                            Text("현재 방식 편집값 삭제")
                        }

                        Button(role: .destructive) {
                            deleteAllForRow(row: row)
                            editingRow = nil
                        } label: {
                            Text("이 교시 관련 편집값 전체 삭제")
                        }
                    }
                }
                .navigationTitle("시간표 편집")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { editingRow = nil }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            saveEdit(row: row)
                            editingRow = nil
                        }
                        .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func saveEdit(row: TimetableRow) {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .todayOnly:
            neisManager.setEditedTextDate(trimmed, for: row)

        case .weekly:
            neisManager.setEditedTextWeekly(trimmed, for: row)

        case .replaceSubject:
            neisManager.setReplaceRule(for: row, to: trimmed)
        }
    }

    private func deleteByCurrentMode(row: TimetableRow) {
        switch mode {
        case .todayOnly:
            neisManager.clearEditedTextDate(for: row)

        case .weekly:
            neisManager.clearEditedTextWeekly(for: row)

        case .replaceSubject:
            neisManager.clearReplaceRule(for: row)
        }
    }

    private func deleteAllForRow(row: TimetableRow) {
        neisManager.clearEditedTextDate(for: row)
        neisManager.clearEditedTextWeekly(for: row)
        neisManager.clearReplaceRule(for: row)
    }
}


// MARK: - 급식 뷰
struct MealView: View {
    @ObservedObject var neisManager: NeisManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if neisManager.meals.isEmpty {
                    Text("급식 정보가 없습니다")
                        .padding(.top, 50)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(neisManager.meals) { meal in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(meal.MMEAL_SC_NM)
                                .font(.caption)
                                .bold()
                                .padding(6)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(6)

                            Text(neisManager.cleanMealText(meal.DDISH_NM))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.primary)
                                .lineSpacing(6)

                            Text(meal.CAL_INFO)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(24)
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - 설정 뷰
struct SettingsView: View {
    @ObservedObject var neisManager: NeisManager
    @State private var showDebugInfo = false
    @State private var showSchoolSearch = false
    @State private var showGradeClassEdit = false
    @State private var exportDocument: TimetableEditsDocument?
    @State private var exportFileName: String = "timetable-edits.json"
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var notice: SettingsNotice?
    @State private var showResetTargetDialog = false
    @State private var pendingResetTarget: TimetableEditResetTarget?
    @State private var showResetConfirmation = false

    var body: some View {
        List {
            Section(header: Text("화면 설정")) {
                Toggle(isOn: $neisManager.isDarkMode) {
                    HStack {
                        Image(systemName: neisManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                            .foregroundColor(neisManager.isDarkMode ? .purple : .orange)
                        Text("다크모드")
                    }
                }
            }

            Section(header: Text("시간표 소스")) {
                Picker(
                    "시간표 소스",
                    selection: Binding(
                        get: { neisManager.timetableSource },
                        set: { newValue in
                            neisManager.timetableSource = newValue
                            neisManager.fetchTimetable()
                        }
                    )
                ) {
                    ForEach(TimetableSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                Text("급식과 학사일정은 기존처럼 교육청 API를 사용하고, 시간표만 선택한 소스로 불러옵니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("현재 정보")) {
                Button {
                    showSchoolSearch = true
                } label: {
                    HStack {
                        Text("학교명")
                        Spacer()
                        Text(neisManager.schoolName.isEmpty ? "설정 안 됨" : neisManager.schoolName)
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    showGradeClassEdit = true
                } label: {
                    HStack {
                        Text("학년 / 반")
                        Spacer()
                        Text("\(neisManager.grade)학년 \(neisManager.classNum)반")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("시간표 수정사항")) {
                Button {
                    do {
                        let data = try neisManager.exportCurrentTimetableEditsData()
                        exportFileName = neisManager.currentTimetableEditExportFileName()
                        exportDocument = TimetableEditsDocument(data: data)
                        showExporter = true
                    } catch {
                        notice = SettingsNotice(message: error.localizedDescription)
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.blue)
                        Text("수정사항 내보내기")
                    }
                }

                Button {
                    showImporter = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(.green)
                        Text("수정사항 불러오기")
                    }
                }

                Button(role: .destructive) {
                    showResetTargetDialog = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("변경사항 초기화")
                    }
                }

                Text("현재 선택된 학교, 학년, 반, 시간표 소스에 맞는 수정사항만 내보내고 불러옵니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("개발자 정보")) {
                Button {
                    showDebugInfo = true
                } label: {
                    HStack {
                        Image(systemName: "ant.fill")
                            .foregroundColor(.green)
                        Text("App Group & 서명 정보")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showDebugInfo) {
            DebugInfoView()
        }
        .sheet(isPresented: $showSchoolSearch) {
            SchoolSearchView(neisManager: neisManager)
        }
        .sheet(isPresented: $showGradeClassEdit) {
            GradeClassEditView(neisManager: neisManager)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success:
                notice = SettingsNotice(message: "수정사항을 내보냈습니다.")
            case .failure(let error):
                notice = SettingsNotice(message: "내보내기에 실패했습니다: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .failure(let error):
                notice = SettingsNotice(message: "불러오기에 실패했습니다: \(error.localizedDescription)")
            case .success(let url):
                let started = url.startAccessingSecurityScopedResource()
                defer {
                    if started { url.stopAccessingSecurityScopedResource() }
                }

                do {
                    let data = try Data(contentsOf: url)
                    try neisManager.importTimetableEdits(from: data)
                    notice = SettingsNotice(message: "수정사항을 불러왔습니다.")
                } catch {
                    notice = SettingsNotice(message: error.localizedDescription)
                }
            }
        }
        .confirmationDialog(
            "어떤 변경사항을 초기화할까요?",
            isPresented: $showResetTargetDialog,
            titleVisibility: .visible
        ) {
            ForEach(TimetableEditResetTarget.allCases) { target in
                Button(target.title, role: .destructive) {
                    pendingResetTarget = target
                    showResetConfirmation = true
                }
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("현재 학교, 학년, 반에 귀속된 수정사항만 대상으로 합니다.")
        }
        .alert(
            pendingResetTarget?.title ?? "변경사항 초기화",
            isPresented: $showResetConfirmation,
            presenting: pendingResetTarget
        ) { target in
            Button("취소", role: .cancel) {
                pendingResetTarget = nil
            }
            Button("초기화", role: .destructive) {
                neisManager.clearCurrentTimetableEdits(target)
                notice = SettingsNotice(message: "\(target.title)을 완료했습니다.")
                pendingResetTarget = nil
            }
        } message: { target in
            Text("초기화하시겠습니까?\n\(target.summary)\n되돌릴 수 없습니다.")
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text("시간표 수정사항"),
                message: Text(notice.message),
                dismissButton: .default(Text("확인"))
            )
        }
    }
}

struct SettingsNotice: Identifiable {
    let id = UUID()
    let message: String
}

struct TimetableEditsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 학년/반 수정 뷰
struct GradeClassEditView: View {
    @ObservedObject var neisManager: NeisManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("학년")) {
                    Picker("학년", selection: $neisManager.grade) {
                        Text("1학년").tag("1")
                        Text("2학년").tag("2")
                        Text("3학년").tag("3")
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("반")) {
                    Picker("반", selection: $neisManager.classNum) {
                        ForEach(1...15, id: \.self) { i in
                            Text("\(i)반").tag("\(i)")
                        }
                    }
                }
            }
            .navigationTitle("학년/반 변경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 디버그 정보 뷰
struct DebugInfoView: View {
    @Environment(\.dismiss) var dismiss
    @State private var copiedMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            List {
                // App Group 정보 섹션
                Section(header: Text("📦 App Group")) {
                    if let appGroupID = AppGroupManager.shared.appGroupID {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("감지된 App Group")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(appGroupID)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                
                                Spacer()
                                
                                Button {
                                    UIPasteboard.general.string = appGroupID
                                    copiedMessage = "App Group ID 복사됨"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copiedMessage = nil
                                    }
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            if let containerURL = FileManager.default.containerURL(
                                forSecurityApplicationGroupIdentifier: appGroupID
                            ) {
                                Text("컨테이너 경로:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                                
                                Text(containerURL.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            // 상태 표시
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("정상 작동")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding(.top, 4)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("App Group 감지 실패")
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }
                            
                            Text("위젯이 작동하지 않을 수 있습니다. ESign 서명 설정을 확인하세요.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 앱 정보
                Section(header: Text("📱 앱 정보")) {
                    if let bundleID = Bundle.main.bundleIdentifier {
                        LabeledContent("Bundle ID", value: bundleID)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        LabeledContent("버전", value: version)
                    }
                    
                    if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        LabeledContent("빌드", value: build)
                    }
                }
                
                // 서명 정보
                Section(header: Text("✍️ 서명 정보")) {
                    if let provisioningPath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.blue)
                                Text("Provisioning Profile 존재")
                                    .foregroundColor(.primary)
                            }
                            
                            if let data = try? Data(contentsOf: URL(fileURLWithPath: provisioningPath)),
                               let profile = parseProvisioningProfile(data) {
                                
                                if let name = profile["Name"] as? String {
                                    Text("프로필: \(name)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let teamID = profile["TeamIdentifier"] as? [String], let id = teamID.first {
                                    Text("Team ID: \(id)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let creationDate = profile["CreationDate"] as? Date {
                                    Text("생성일: \(formatDate(creationDate))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let expirationDate = profile["ExpirationDate"] as? Date {
                                    let isExpired = expirationDate < Date()
                                    HStack {
                                        Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "clock")
                                            .foregroundColor(isExpired ? .red : .green)
                                        Text("만료일: \(formatDate(expirationDate))")
                                            .font(.caption)
                                            .foregroundColor(isExpired ? .red : .secondary)
                                    }
                                }
                                
                                if let entitlements = profile["Entitlements"] as? [String: Any],
                                   let groups = entitlements["com.apple.security.application-groups"] as? [String] {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Entitlements App Groups:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.top, 4)
                                        
                                        ForEach(groups, id: \.self) { group in
                                            Text("• \(group)")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.orange)
                            Text("Provisioning Profile 정보 없음")
                                .foregroundColor(.secondary)
                        }
                        Text("개발 빌드이거나 시뮬레이터에서 실행 중입니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // UserDefaults 저장 데이터
                Section(header: Text("💾 저장된 데이터")) {
                    if let defaults = AppGroupManager.shared.sharedDefaults {
                        Group {
                            if let schoolCode = defaults.string(forKey: "savedSchoolCode"), !schoolCode.isEmpty {
                                LabeledContent("학교 코드", value: schoolCode)
                            } else {
                                Text("학교 코드: 없음")
                                    .foregroundColor(.secondary)
                            }
                            
                            if let schoolName = defaults.string(forKey: "savedSchoolName"), !schoolName.isEmpty {
                                LabeledContent("학교명", value: schoolName)
                            } else {
                                Text("학교명: 없음")
                                    .foregroundColor(.secondary)
                            }
                            
                            LabeledContent("학년", value: defaults.string(forKey: "savedGrade") ?? "없음")
                            LabeledContent("반", value: defaults.string(forKey: "savedClass") ?? "없음")
                        }
                        
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("위젯과 데이터 공유 가능")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(.top, 4)
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("App Group UserDefaults 접근 불가")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // 복사 완료 메시지
                if let message = copiedMessage {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(message)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .navigationTitle("디버그 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
    
    // Provisioning Profile에서 plist 추출
    private func parseProvisioningProfile(_ data: Data) -> [String: Any]? {
        guard let dataString = String(data: data, encoding: .isoLatin1) else { return nil }
        
        // plist XML 범위 확인
        guard let startRange = dataString.range(of: "<?xml"),
              let endRange = dataString.range(of: "</plist>") else {
            return nil
        }
        
        let xmlString = String(dataString[startRange.lowerBound...endRange.upperBound])
        guard let xmlData = xmlString.data(using: .utf8) else { return nil }
        
        do {
            if let plist = try PropertyListSerialization.propertyList(from: xmlData, format: nil) as? [String: Any] {
                return plist
            }
        } catch {
            print("Provisioning profile 파싱 에러: \(error)")
        }
        
        return nil
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
