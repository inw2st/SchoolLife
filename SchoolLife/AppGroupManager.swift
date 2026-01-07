import Foundation

/// App Group ID를 동적으로 감지하는 매니저
final class AppGroupManager {
    static let shared = AppGroupManager()
    
    /// 감지된 App Group ID
    private(set) var appGroupID: String?
    
    /// App Group용 UserDefaults
    var sharedDefaults: UserDefaults? {
        guard let appGroupID = appGroupID else { return nil }
        return UserDefaults(suiteName: appGroupID)
    }
    
    private init() {
        detectAppGroup()
    }
    
    /// 앱의 Entitlements에서 실제 App Group ID를 읽어옴
    private func detectAppGroup() {
        // 방법 1: Entitlements에서 직접 읽기 (개발 환경용)
        #if DEBUG
        // 개발 환경에서는 하드코딩된 개발용 App Group 먼저 시도
        let developmentGroup = "group.com.minwestt.slife.widget" // ← 실제 개발용 App Group
        if validateAppGroup(developmentGroup) {
            self.appGroupID = developmentGroup
            print("✅ 개발 환경 App Group 감지: \(developmentGroup)")
            return
        }
        #endif
        
        // 방법 2: Entitlements에서 직접 읽기 (가장 정확)
        if let appGroups = Bundle.main.object(forInfoDictionaryKey: "com.apple.security.application-groups") as? [String],
           let firstGroup = appGroups.first {
            // Entitlements에 등록된 첫 번째 App Group 사용
            if validateAppGroup(firstGroup) {
                self.appGroupID = firstGroup
                print("✅ Entitlements에서 App Group 감지: \(firstGroup)")
                return
            }
        }
        
        // 방법 2: Entitlements가 Info.plist에 없는 경우, 실제 접근 가능한 것 찾기
        // 모든 가능한 패턴 시도
        let possiblePrefixes = [
            "group.",
            "group.6e88432fd066d72e.",
            "group.com.",
        ]
        
        // FileManager로 실제 App Group 컨테이너 찾기
        for prefix in possiblePrefixes {
            // 일반적인 패턴들 시도
            for suffix in ["1", "2", "3", "schoollife", "SchoolLife"] {
                let candidate = "\(prefix)\(suffix)"
                if validateAppGroup(candidate) {
                    self.appGroupID = candidate
                    print("✅ 패턴 매칭으로 App Group 감지: \(candidate)")
                    return
                }
            }
        }
        
        // 방법 3: Bundle Identifier 기반으로 추측
        if let bundleID = Bundle.main.bundleIdentifier {
            // ESign 패턴: bundle ID의 해시를 사용하는 경우
            let candidates = [
                "group.\(bundleID)",
                "group.\(bundleID).shared",
            ]
            
            for candidate in candidates {
                if validateAppGroup(candidate) {
                    self.appGroupID = candidate
                    print("✅ Bundle ID 기반으로 App Group 감지: \(candidate)")
                    return
                }
            }
        }
        
        // 감지 실패 시 경고
        print("⚠️ 유효한 App Group을 찾을 수 없습니다.")
        print("   Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        print("   위젯이 작동하지 않을 수 있습니다.")
    }
    
    /// App Group이 실제로 접근 가능한지 확인
    private func validateAppGroup(_ groupID: String) -> Bool {
        // 컨테이너 URL 확인
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else {
            return false
        }
        
        // 실제 파일 시스템에 존재하는지 확인
        return FileManager.default.fileExists(atPath: containerURL.path)
    }
    
    /// 디버깅용: 현재 감지된 정보 출력
    func printDebugInfo() {
        print("=== App Group Debug Info ===")
        print("Detected App Group: \(appGroupID ?? "nil")")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        
        if let groupID = appGroupID,
           let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
           ) {
            print("Container Path: \(containerURL.path)")
            
            // UserDefaults에 저장된 키들 출력
            if let defaults = sharedDefaults {
                print("Saved Keys:")
                print("  - savedSchoolCode: \(defaults.string(forKey: "savedSchoolCode") ?? "nil")")
                print("  - savedSchoolName: \(defaults.string(forKey: "savedSchoolName") ?? "nil")")
            }
        }
        print("===========================")
    }
}
