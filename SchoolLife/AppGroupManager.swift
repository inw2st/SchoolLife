import Foundation

/// 일반적인 앱 배포(앱 스토어 / TestFlight 등)에서 쓰기 좋게
/// 고정 App Group ID만 사용하는 단순한 매니저입니다.
///
/// - 더 이상 ESign/사이드로딩용 App Group 자동 감지/추측 로직은 사용하지 않습니다.
/// - `appGroupID`에 설정된 값만 사용하며,
///   만약 해당 그룹이 설정돼 있지 않으면 자동으로 `UserDefaults.standard`로 fallback 됩니다.
final class AppGroupManager {
    static let shared = AppGroupManager()
    
    /// 사용하려는 App Group ID
    /// - NOTE: Xcode > Signing & Capabilities > App Groups 에
    ///   동일한 ID를 추가해 두어야 합니다.
    private(set) var appGroupID: String?
    
    /// App Group용 UserDefaults (없으면 standard 로 fallback)
    let sharedDefaults: UserDefaults?
    
    private init() {
        // ✅ 일반 배포용: 고정 App Group ID 사용
        // 필요 없다면 `nil`로 두면 되고, 그 경우에는 `UserDefaults.standard`를 사용합니다.
        let fixedGroupID = "group.com.minwestt.slife.widget"
        self.appGroupID = fixedGroupID
        
        if let defaults = UserDefaults(suiteName: fixedGroupID) {
            self.sharedDefaults = defaults
        } else {
            // App Group 설정이 없거나 suiteName 생성 실패 시에도
            // 앱이 정상 동작하도록 standard 로 fallbackimport Foundation
            
            /// 일반적인 앱 배포(앱 스토어 / TestFlight 등)에서 쓰기 좋게
            /// 고정 App Group ID만 사용하는 단순한 매니저입니다.
            ///
            /// - 더 이상 ESign/사이드로딩용 App Group 자동 감지/추측 로직은 사용하지 않습니다.
            /// - `appGroupID`에 설정된 값만 사용하며,
            ///   만약 해당 그룹이 설정돼 있지 않으면 자동으로 `UserDefaults.standard`로 fallback 됩니다.
            final class AppGroupManager {
                static let shared = AppGroupManager()
                
                /// 사용하려는 App Group ID
                /// - NOTE: Xcode > Signing & Capabilities > App Groups 에
                ///   동일한 ID를 추가해 두어야 합니다.
                private(set) var appGroupID: String?
                
                /// App Group용 UserDefaults (없으면 standard 로 fallback)
                let sharedDefaults: UserDefaults?
                
                private init() {
                    // ✅ 일반 배포용: 고정 App Group ID 사용
                    // 필요 없다면 `nil`로 두면 되고, 그 경우에는 `UserDefaults.standard`를 사용합니다.
                    let fixedGroupID = "group.com.minwestt.slife.widget"
                    self.appGroupID = fixedGroupID
                    
                    if let defaults = UserDefaults(suiteName: fixedGroupID) {
                        self.sharedDefaults = defaults
                    } else {
                        // App Group 설정이 없거나 suiteName 생성 실패 시에도
                        // 앱이 정상 동작하도록 standard 로 fallback
                        self.sharedDefaults = UserDefaults.standard
                    }
                }
                
                /// 디버깅용: 현재 사용 중인 정보를 출력
                func printDebugInfo() {
                    print("=== App Group Debug Info ===")
                    print("Configured App Group: \(appGroupID ?? "nil (using standard)")")
                    print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
                    
                    if let groupID = appGroupID,
                       let containerURL = FileManager.default.containerURL(
                        forSecurityApplicationGroupIdentifier: groupID
                       ) {
                        print("Container Path: \(containerURL.path)")
                    }
                    
                    if let defaults = sharedDefaults {
                        print("Saved Keys (sample):")
                        print("  - savedSchoolCode: \(defaults.string(forKey: "savedSchoolCode") ?? "nil")")
                        print("  - savedSchoolName: \(defaults.string(forKey: "savedSchoolName") ?? "nil")")
                    }
                    print("===========================")
                }
            }

            self.sharedDefaults = UserDefaults.standard
        }
    }
    
    /// 디버깅용: 현재 사용 중인 정보를 출력
    func printDebugInfo() {
        print("=== App Group Debug Info ===")
        print("Configured App Group: \(appGroupID ?? "nil (using standard)")")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        
        if let groupID = appGroupID,
           let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
           ) {
            print("Container Path: \(containerURL.path)")
        }
        
        if let defaults = sharedDefaults {
            print("Saved Keys (sample):")
            print("  - savedSchoolCode: \(defaults.string(forKey: "savedSchoolCode") ?? "nil")")
            print("  - savedSchoolName: \(defaults.string(forKey: "savedSchoolName") ?? "nil")")
        }
        print("===========================")
    }
}
